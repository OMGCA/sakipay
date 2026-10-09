/* (c) Copyright XiatStudio 2026~2026 */
import testNapi from 'libentry.so'
import { Log } from './Log'

/**
 * Typed Swift-free wrapper over the native `libentry.so` module, which forwards
 * to the shared Kotlin business logic (libsakipay.so).
 *
 * This is the single place the platform talks to the shared logic — the models
 * and view models call these helpers rather than reimplementing any rules.
 */

export interface TodayEarningsResult {
  amount: number
  progress: number
  status: string
  elapsedSeconds: number
  totalWorkSeconds: number
}

export interface MonthSummaryResult {
  workingDaysThisMonth: number
  workingDaysElapsed: number
  monthProgress: number
  monthEarnings: number
  totalMonthEarnings: number
  daysUntilPayday: number
  isPayday: boolean
  paydayCycleProgress: number
  paydayCycleTotal: number
  paydayCycleElapsed: number
}

export interface PruneBreaksResult {
  config: string
  removed: number
}

export interface VoluntaryOvertimeTotalResult {
  state: string
  seconds: number
}

export class NativeBridge {
  /** Minutes east of UTC (the Kotlin convention), derived from the JS offset. */
  public static tzOffsetMinutes(): number {
    return -new Date().getTimezoneOffset()
  }

  public static nowMillis(): number {
    return new Date().getTime()
  }

  public static defaultConfigJson(): string {
    return testNapi.defaultConfigJson()
  }

  public static defaultBreakJson(): string {
    return testNapi.defaultBreakJson()
  }

  public static composeConfigJson(
    monthlyPay: number,
    currency: string,
    payDay: number,
    taxRate: number,
    workingDaysPerMonth: number,
    workStartHour: number,
    workStartMinute: number,
    workEndHour: number,
    workEndMinute: number,
    breaksJson: string,
    dayOverridesJson: string,
    useCalibratedWorkDays: boolean
  ): string {
    return testNapi.composeConfigJson(
      monthlyPay, currency, payDay, taxRate, workingDaysPerMonth,
      workStartHour, workStartMinute, workEndHour, workEndMinute,
      breaksJson, dayOverridesJson, useCalibratedWorkDays
    )
  }

  public static todayEarnings(
    configJson: string,
    nowMillis: number,
    voluntaryOvertimeTotalSeconds: number,
    isPaused: boolean
  ): TodayEarningsResult {
    const raw: string = testNapi.todayEarningsJson(
      configJson, nowMillis, NativeBridge.tzOffsetMinutes(),
      voluntaryOvertimeTotalSeconds, isPaused
    )
    return JSON.parse(raw) as TodayEarningsResult
  }

  public static monthSummary(configJson: string, nowMillis: number, isPaused: boolean): MonthSummaryResult {
    const raw: string = testNapi.monthSummaryJson(
      configJson, nowMillis, NativeBridge.tzOffsetMinutes(), isPaused
    )
    return JSON.parse(raw) as MonthSummaryResult
  }

  public static calibratedWorkingDaysNow(configJson: string, nowMillis: number): number {
    return testNapi.calibratedWorkingDaysNow(configJson, nowMillis, NativeBridge.tzOffsetMinutes())
  }

  public static calibratedWorkingDays(configJson: string, year: number, month: number): number {
    return testNapi.calibratedWorkingDays(configJson, year, month)
  }

  public static holidayDataJson(year: number): string {
    return testNapi.holidayDataJson(year)
  }

  /** "normal" | "weekend" | "publicHoliday" | "adjustedWorkday" | "userHoliday" | "userOvertime". */
  public static resolveDayKind(year: number, month: number, day: number, dayOverridesJson: string): string {
    return testNapi.resolveDayKind(year, month, day, dayOverridesJson)
  }

  /** Raw clock minutes in a work window (breaks not subtracted, cross-midnight aware). */
  public static workWindowMinutes(workStartMinutes: number, workEndMinutes: number): number {
    return testNapi.workWindowMinutes(workStartMinutes, workEndMinutes)
  }

  /** Paid hours per day (window minus breaks). */
  public static workTotalHours(workStartMinutes: number, workEndMinutes: number, breaksJson: string): number {
    return testNapi.workScheduleTotalHours(workStartMinutes, workEndMinutes, breaksJson)
  }

  public static secondRate(configJson: string, nowMillis: number): number {
    return testNapi.secondRate(configJson, nowMillis, NativeBridge.tzOffsetMinutes())
  }

  public static pruneBreaks(configJson: string): PruneBreaksResult {
    const raw: string = testNapi.pruneBreaksJson(configJson)
    return JSON.parse(raw) as PruneBreaksResult
  }

  public static addBreak(configJson: string): string {
    return testNapi.addBreakJson(configJson)
  }

  /** Appends a break to a breaks array (JSON) using the shared placement rule. */
  public static addBreakToBreaks(workStartMinutes: number, workEndMinutes: number, breaksJson: string): string {
    return testNapi.addBreakToBreaks(workStartMinutes, workEndMinutes, breaksJson)
  }

  public static configBreaksJson(configJson: string): string {
    return testNapi.configBreaksJson(configJson)
  }

  public static configDayOverridesJson(configJson: string): string {
    return testNapi.configDayOverridesJson(configJson)
  }

  public static otTotalSeconds(stateJson: string, nowMillis: number, mutatesState: boolean): VoluntaryOvertimeTotalResult {
    const raw: string = testNapi.otTotalSecondsJson(
      stateJson, nowMillis, NativeBridge.tzOffsetMinutes(), mutatesState
    )
    return JSON.parse(raw) as VoluntaryOvertimeTotalResult
  }

  public static otStart(stateJson: string, nowMillis: number): string {
    return testNapi.otStartJson(stateJson, nowMillis, NativeBridge.tzOffsetMinutes())
  }

  public static otEnd(stateJson: string, nowMillis: number, secondRate: number): string {
    return testNapi.otEndJson(stateJson, nowMillis, NativeBridge.tzOffsetMinutes(), secondRate)
  }

  public static otBankDaily(stateJson: string, nowMillis: number, secondRate: number): string {
    return testNapi.otBankDailyJson(stateJson, nowMillis, NativeBridge.tzOffsetMinutes(), secondRate)
  }

  public static statusText(statusWire: string): string {
    return testNapi.statusText(statusWire)
  }

  public static paydayText(daysUntilPayday: number, isPayday: boolean): string {
    return testNapi.paydayText(daysUntilPayday, isPayday)
  }

  public static logError(message: string): void {
    Log.error(message)
  }
}
