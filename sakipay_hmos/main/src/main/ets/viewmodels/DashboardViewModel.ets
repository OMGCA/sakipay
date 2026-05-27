/* (c) Copyright XiatStudio 2026~2026 */
import {
  EarningsCalculator, WorkStatus, TodayEarnings, MonthSummary, BreakScheduleEntry
} from '../models/EarningsCalculator'
import { BreakSegment } from '../models/BreakSegment'
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

  private calculator: EarningsCalculator = new EarningsCalculator()
  private timerId: number = -1
  private store: PreferencesStore = new PreferencesStore()

  /** Callback invoked after privacy toggle — wired to widget refresh in Index. */
  public onPrivacyToggled: (() => void) | null = null

  public async initialise(context: Context): Promise<void> {
    await this.store.initialise(context)
    this.isPrivacyMode = await this.store.loadPrivacyMode()
  }

  public async togglePrivacy(): Promise<void> {
    this.isPrivacyMode = !this.isPrivacyMode
    await this.store.savePrivacyMode(this.isPrivacyMode)
    if (this.onPrivacyToggled !== null) {
      this.onPrivacyToggled()
    }
  }

  public configure(
    monthlyPay: number, workingDays: number, currency: string, taxRate: number, payDay: number,
    workStartH: number, workStartM: number, workEndH: number, workEndM: number,
    breaks: BreakSegment[]
  ): void {
    this.currency = currency
    this.isConfigured = monthlyPay > 0

    this.calculator.monthlyPay = monthlyPay
    this.calculator.workingDaysPerMonth = workingDays
    this.calculator.taxRate = taxRate
    this.calculator.payDay = payDay
    this.calculator.schedule.workStartMinutes = workStartH * 60 + workStartM
    this.calculator.schedule.workEndMinutes = workEndH * 60 + workEndM
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

  public refresh(): void {
    const today: TodayEarnings = this.calculator.calculateTodayEarnings()
    this.todayAmount = today.amount
    this.todayProgress = today.progress
    this.todayStatus = today.status
    this.monthSummary = this.calculator.calculateMonthSummary()
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
    switch (this.todayStatus) {
      case WorkStatus.NOT_STARTED:
        return '还没开始'
      case WorkStatus.WORKING:
        return '窝囊费积累中'
      case WorkStatus.ON_BREAK:
        return '休息中'
      case WorkStatus.COMPLETED:
        return '下班啦！'
      case WorkStatus.DAY_OFF:
        return '休息日'
      default:
        return ''
    }
  }

  public getPaydayText(): string {
    if (this.monthSummary.isPayday) {
      return '今天发工资!'
    }
    if (this.monthSummary.daysUntilPayday === 1) {
      return '明天发工资'
    }
    return `还有 ${this.monthSummary.daysUntilPayday} 天发工资`
  }
}
