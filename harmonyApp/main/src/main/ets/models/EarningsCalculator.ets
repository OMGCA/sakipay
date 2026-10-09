/* (c) Copyright XiatStudio 2026~2026 */
import { NativeBridge, TodayEarningsResult, MonthSummaryResult } from '../services/NativeBridge'
import { DayOverride } from './HolidayCalendar'

/**
 * Platform-facing calculator types.
 *
 * The business rules (rates, work-window maths, breaks, overtime, holidays,
 * payday cycles) all live in the shared Kotlin logic and are reached through
 * [NativeBridge]. This file only keeps the shape the ArkTS UI already consumes
 * so no view or view model needs rewriting — every method forwards to Kotlin.
 */

/** A single break entry in the work schedule. */
export class BreakScheduleEntry {
  public startMinutes: number = 0
  public endMinutes: number = 0
}

/**
 * Internal schedule representation used by the calculator. Cross-midnight
 * schedules (workEndMinutes <= workStartMinutes) are handled by the shared logic.
 */
class WorkSchedule {
  public workStartMinutes: number = 540 // 09:00
  public workEndMinutes: number = 1080  // 18:00
  public breaks: BreakScheduleEntry[] = []
}

/** Enum describing the current work status. Values match the shared wire names. */
export enum WorkStatus {
  NOT_STARTED = 'notStarted',
  WORKING = 'working',
  ON_BREAK = 'onBreak',
  COMPLETED = 'completed',
  OVERTIME = 'overtime',
  VOLUNTARY_OVERTIME = 'voluntaryOvertime',
  DAY_OFF = 'dayOff',
  /** User-armed pause: nothing accrues, regardless of day type or calendar. */
  PAUSED = 'paused'
}

function statusFromWire(wire: string): WorkStatus {
  switch (wire) {
    case 'working':
      return WorkStatus.WORKING
    case 'onBreak':
      return WorkStatus.ON_BREAK
    case 'completed':
      return WorkStatus.COMPLETED
    case 'overtime':
      return WorkStatus.OVERTIME
    case 'voluntaryOvertime':
      return WorkStatus.VOLUNTARY_OVERTIME
    case 'dayOff':
      return WorkStatus.DAY_OFF
    case 'paused':
      return WorkStatus.PAUSED
    default:
      return WorkStatus.NOT_STARTED
  }
}

/** Result of a today's earnings calculation. */
export class TodayEarnings {
  public amount: number = 0
  public progress: number = 0
  public status: WorkStatus = WorkStatus.NOT_STARTED
  public elapsedSeconds: number = 0
  public totalWorkSeconds: number = 0
}

/** Month-level summary data. */
export class MonthSummary {
  public workingDaysThisMonth: number = 0
  public workingDaysElapsed: number = 0
  public monthProgress: number = 0
  public monthEarnings: number = 0
  public totalMonthEarnings: number = 0
  public daysUntilPayday: number = 0
  public isPayday: boolean = false
  public paydayCycleProgress: number = 0
  public paydayCycleTotal: number = 0
  public paydayCycleElapsed: number = 0
}

/**
 * Facade over the shared calculator. Assign the configuration properties, then
 * call calculateTodayEarnings / calculateMonthSummary; each call rebuilds the
 * config document and asks the Kotlin engine.
 */
export class EarningsCalculator {
  public monthlyPay: number = 0
  public workingDaysPerMonth: number = 21.75
  public schedule: WorkSchedule = new WorkSchedule()
  public payDay: number = 15
  public taxRate: number = 0
  public dayOverrides: Map<string, DayOverride> = new Map()

  private presetConfigJson: string = ''

  /**
   * Configures directly from a canonical config document, skipping the
   * field-by-field marshalling. Used by the widget/form background paths, which
   * already hold the stored config.
   */
  public configureFromConfigJson(configJson: string): void {
    this.presetConfigJson = configJson
  }

  /** The config document to use: the preset if set, otherwise built from fields. */
  private configDocument(): string {
    return this.presetConfigJson.length > 0 ? this.presetConfigJson : this.buildConfigJson()
  }

  /** The base per-second rate, used to settle voluntary overtime. */
  public get secondRate(): number {
    return NativeBridge.secondRate(this.configDocument(), NativeBridge.nowMillis())
  }

  public calculateTodayEarnings(
    date: Date = new Date(),
    voluntaryOvertimeTotalSeconds: number = 0,
    isPaused: boolean = false
  ): TodayEarnings {
    const r: TodayEarningsResult = NativeBridge.todayEarnings(
      this.configDocument(), date.getTime(), voluntaryOvertimeTotalSeconds, isPaused
    )
    const out: TodayEarnings = new TodayEarnings()
    out.amount = r.amount
    out.progress = r.progress
    out.status = statusFromWire(r.status)
    out.elapsedSeconds = r.elapsedSeconds
    out.totalWorkSeconds = r.totalWorkSeconds
    return out
  }

  public calculateMonthSummary(date: Date = new Date(), isPaused: boolean = false): MonthSummary {
    const r: MonthSummaryResult = NativeBridge.monthSummary(
      this.configDocument(), date.getTime(), isPaused
    )
    const out: MonthSummary = new MonthSummary()
    out.workingDaysThisMonth = r.workingDaysThisMonth
    out.workingDaysElapsed = r.workingDaysElapsed
    out.monthProgress = r.monthProgress
    out.monthEarnings = r.monthEarnings
    out.totalMonthEarnings = r.totalMonthEarnings
    out.daysUntilPayday = r.daysUntilPayday
    out.isPayday = r.isPayday
    out.paydayCycleProgress = r.paydayCycleProgress
    out.paydayCycleTotal = r.paydayCycleTotal
    out.paydayCycleElapsed = r.paydayCycleElapsed
    return out
  }

  private overridesArray(): DayOverride[] {
    const arr: DayOverride[] = []
    this.dayOverrides.forEach((value: DayOverride): void => {
      arr.push(value)
    })
    return arr
  }

  /**
   * Builds the canonical config document from the current field values. Breaks
   * and overrides are passed as JSON arrays; the shared side fills defaults.
   * useCalibratedWorkDays is false because callers pass the already-resolved
   * working-day count in `workingDaysPerMonth`.
   */
  private buildConfigJson(): string {
    const ws: number = this.schedule.workStartMinutes
    const we: number = this.schedule.workEndMinutes
    return NativeBridge.composeConfigJson(
      this.monthlyPay, '¥', this.payDay, this.taxRate, this.workingDaysPerMonth,
      Math.floor(ws / 60), ws % 60, Math.floor(we / 60), we % 60,
      JSON.stringify(this.schedule.breaks),
      JSON.stringify(this.overridesArray()),
      false
    )
  }
}
