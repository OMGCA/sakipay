/* (c) Copyright XiatStudio 2026~2026 */
import {
  EarningsCalculator, WorkStatus, TodayEarnings, MonthSummary, BreakScheduleEntry
} from '../models/EarningsCalculator'
import { BreakSegment } from '../models/BreakSegment'
import { DayOverride } from '../models/HolidayCalendar'
import { NativeBridge } from '../services/NativeBridge'
import { PreferencesStore } from '../services/PreferencesStore'
import { Log } from '../services/Log'

/**
 * VM driving the dashboard — holds reactive state for the Today tab.
 */
@ObservedV2
export class DashboardViewModel {
  @Trace public todayAmount: number = 0
  @Trace public todayProgress: number = 0
  @Trace public todayStatus: WorkStatus = WorkStatus.NOT_STARTED
  @Trace public currency: string = '¥'
  @Trace public isConfigured: boolean = false
  @Trace public monthSummary: MonthSummary = new MonthSummary()
  @Trace public isPrivacyMode: boolean = false
  @Trace public isPaused: boolean = false
  @Trace public isVoluntaryOvertimeActive: boolean = false
  @Trace public voluntaryOTWeeklyEarnings: number = 0

  private calculator: EarningsCalculator = new EarningsCalculator()
  private timerId: number = -1
  private store: PreferencesStore = PreferencesStore.shared()
  private previousStatus: WorkStatus = WorkStatus.NOT_STARTED

  /** Callback invoked after privacy toggle — wired to widget refresh in Index. */
  public onPrivacyToggled: (() => void) | null = null
  /** Callback invoked after pause toggle — wired to widget refresh in Index. */
  public onPauseToggled: (() => void) | null = null
  /** Callback invoked after voluntary OT toggle — wired to widget refresh in Index. */
  public onVoluntaryOvertimeToggled: (() => void) | null = null

  public async initialise(context: Context): Promise<void> {
    await this.store.initialise(context)
    this.isPrivacyMode = await this.store.loadPrivacyMode()
    this.isPaused = await this.store.loadPauseMode()
    this.isVoluntaryOvertimeActive = await this.store.loadVoluntaryOTActive()
    this.voluntaryOTWeeklyEarnings = await this.store.loadVoluntaryOTWeeklyEarnings()
  }

  public async togglePrivacy(): Promise<void> {
    this.isPrivacyMode = !this.isPrivacyMode
    await this.store.savePrivacyMode(this.isPrivacyMode)
    if (this.onPrivacyToggled !== null) {
      this.onPrivacyToggled()
    }
  }

  /**
   * Arms or disarms pause mode. Pause is sticky — it overrides the calendar and every day type
   * until the user switches it off via this same control.
   */
  public async togglePause(): Promise<void> {
    this.isPaused = !this.isPaused
    await this.store.savePauseMode(this.isPaused)
    this.refresh()
    if (this.onPauseToggled !== null) {
      this.onPauseToggled()
    }
  }

  /**
   * Toggles voluntary overtime on/off. When starting, begins a new session counting from now.
   * When ending, accumulates the current session's elapsed time and settles it into the
   * weekly pool. Sessions accumulate across toggles within the same day and reset on the
   * next working day.
   */
  public async toggleVoluntaryOvertime(): Promise<void> {
    if (this.isVoluntaryOvertimeActive) {
      // endVoluntaryOTSession settles the day's total into the weekly pool, so the weekly
      // card reflects it immediately.
      await this.store.endVoluntaryOTSession(this.calculator.secondRate)
      this.voluntaryOTWeeklyEarnings = await this.store.loadVoluntaryOTWeeklyEarnings()
    } else {
      await this.store.startVoluntaryOTSession()
    }
    this.isVoluntaryOvertimeActive = await this.store.loadVoluntaryOTActive()
    this.refresh()
    if (this.onVoluntaryOvertimeToggled !== null) {
      this.onVoluntaryOvertimeToggled()
    }
  }

  public configure(
    monthlyPay: number, workingDays: number, currency: string, taxRate: number, payDay: number,
    workStartH: number, workStartM: number, workEndH: number, workEndM: number,
    breaks: BreakSegment[],
    dayOverrides: DayOverride[] = []
  ): void {
    this.currency = currency
    this.isConfigured = monthlyPay > 0

    this.calculator.monthlyPay = monthlyPay
    this.calculator.workingDaysPerMonth = workingDays
    this.calculator.taxRate = taxRate
    this.calculator.payDay = payDay
    this.calculator.schedule.workStartMinutes = workStartH * 60 + workStartM
    this.calculator.schedule.workEndMinutes = workEndH * 60 + workEndM
    const overrideMap: Map<string, DayOverride> = new Map()
    for (const ov of dayOverrides) {
      overrideMap.set(ov.dateString, ov)
    }
    this.calculator.dayOverrides = overrideMap

    const mapped: BreakScheduleEntry[] = []
    for (const b of breaks) {
      if (b.isValid) {
        const entry: BreakScheduleEntry = new BreakScheduleEntry()
        entry.startMinutes = b.startMinutes
        entry.endMinutes = b.endMinutes
        mapped.push(entry)
      }
    }
    this.calculator.schedule.breaks = mapped

    this.refresh()
    this.startTimer()
  }

  /**
   * Refreshes earnings data. Re-reads privacy, pause and voluntary OT state from
   * the store on every call so that toggles made on the widget are picked up by
   * the app (the widget writes from its own process).
   */
  public refresh(): void {
    this.store.loadPrivacyMode().then((privacy: boolean): void => {
      this.isPrivacyMode = privacy
      this.store.loadPauseMode().then((paused: boolean): void => {
        this.isPaused = paused
        this.store.loadVoluntaryOTActive().then((isActive: boolean): void => {
          this.isVoluntaryOvertimeActive = isActive
          this.store.voluntaryOvertimeTotalSeconds().then((totalOTSeconds: number): void => {
            const today: TodayEarnings = this.calculator.calculateTodayEarnings(new Date(),
              totalOTSeconds, paused)

            // Reset voluntary OT accumulation when a new work day begins
            // (transition from notStarted to working)
            if (today.status === WorkStatus.WORKING && this.previousStatus === WorkStatus.NOT_STARTED) {
              this.store.bankDailyVoluntaryOT(this.calculator.secondRate).then((): void => {
                this.store.loadVoluntaryOTWeeklyEarnings().then((val: number): void => {
                  this.voluntaryOTWeeklyEarnings = val
                })
              })
            }
            this.previousStatus = today.status

            this.todayAmount = today.amount
            this.todayProgress = today.progress
            this.todayStatus = today.status
            this.monthSummary = this.calculator.calculateMonthSummary(new Date(), paused)
          })
        })
      })
    })
  }

  /**
   * Re-reads every state the widget can toggle, after dropping the app process's
   * cached Preferences copy. Called when the app returns to the foreground —
   * without the reload the app would keep showing its own stale values and the
   * next flush would revert the widget's change.
   */
  public async reloadToggles(): Promise<void> {
    await this.store.reload()
    this.isPrivacyMode = await this.store.loadPrivacyMode()
    this.isPaused = await this.store.loadPauseMode()
    this.isVoluntaryOvertimeActive = await this.store.loadVoluntaryOTActive()
    this.voluntaryOTWeeklyEarnings = await this.store.loadVoluntaryOTWeeklyEarnings()
    this.refresh()
  }

  public startTimer(): void {
    this.stopTimer()
    this.timerId = setInterval(() => {
      this.refresh()
    }, 5000)
  }

  public stopTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  public getStatusText(): string {
    // Shared user-facing strings (SakipayCore.statusText).
    return NativeBridge.statusText(this.todayStatus as string)
  }

  public getPaydayText(): string {
    return NativeBridge.paydayText(this.monthSummary.daysUntilPayday, this.monthSummary.isPayday)
  }

  /**
   * Formatted weekly voluntary OT earnings string, or empty string if zero.
   */
  public getVoluntaryOTWeeklyText(): string {
    if (this.voluntaryOTWeeklyEarnings <= 0) {
      return ''
    }
    return this.voluntaryOTWeeklyEarnings.toFixed(2)
  }
}
