/* (c) Copyright XiatStudio 2026~2026 */
import { HolidayCalendarData, DayOverride, DayType } from './HolidayCalendar'

/**
 * A single break entry in the work schedule.
 */
export class BreakScheduleEntry {
  public startMinutes: number = 0
  public endMinutes: number = 0
}

/**
 * Internal schedule representation used by the calculator.
 * Supports cross-midnight schedules where workEndMinutes <= workStartMinutes
 * (e.g. 22:00–06:00 night shift).
 */
class WorkSchedule {
  public workStartMinutes: number = 540 // 09:00
  public workEndMinutes: number = 1080  // 18:00
  public breaks: BreakScheduleEntry[] = []

  /** True when the work day crosses midnight (e.g. 22:00–06:00). */
  public get isCrossMidnight(): boolean {
    return this.workEndMinutes <= this.workStartMinutes
  }

  /** Total clock minutes in the work window (before subtracting breaks). */
  public get workWindowMinutes(): number {
    const ws: number = this.workStartMinutes
    const we: number = this.workEndMinutes
    return this.isCrossMidnight ? (1440 - ws) + we : we - ws
  }

  public get totalBreakMinutes(): number {
    let total: number = 0
    for (const b of this.breaks) {
      total += (b.endMinutes - b.startMinutes)
    }
    return total
  }

  public get totalWorkMinutes(): number {
    return this.workWindowMinutes - this.totalBreakMinutes
  }

  public get totalWorkHours(): number {
    return this.totalWorkMinutes / 60
  }

  /**
   * Converts a clock-minute value to minutes elapsed since work start,
   * handling the cross-midnight wrap. Clamped to 0 for minutes before work start.
   */
  public elapsedSinceStart(clockMinute: number): number {
    if (!this.isCrossMidnight) {
      return Math.max(0, clockMinute - this.workStartMinutes)
    }
    if (clockMinute >= this.workStartMinutes) {
      return clockMinute - this.workStartMinutes
    }
    return (1440 - this.workStartMinutes) + clockMinute
  }

  /**
   * Converts a clock-second value to seconds elapsed since work start,
   * handling the cross-midnight wrap with second-level precision.
   */
  public elapsedSinceStartSeconds(clockSecond: number): number {
    const wsSec: number = this.workStartMinutes * 60
    if (!this.isCrossMidnight) {
      return Math.max(0, clockSecond - wsSec)
    }
    if (clockSecond >= wsSec) {
      return clockSecond - wsSec
    }
    return (1440 * 60 - wsSec) + clockSecond
  }

  /**
   * True when clockMinute falls within the active work window.
   */
  public isInWorkWindow(clockMinute: number): boolean {
    if (!this.isCrossMidnight) {
      return clockMinute >= this.workStartMinutes && clockMinute < this.workEndMinutes
    }
    return clockMinute >= this.workStartMinutes || clockMinute < this.workEndMinutes
  }

  /**
   * True when clockMinute is after the work window has ended for the day.
   */
  public isAfterWork(clockMinute: number): boolean {
    if (!this.isCrossMidnight) {
      return clockMinute >= this.workEndMinutes
    }
    return clockMinute >= this.workEndMinutes && clockMinute < this.workStartMinutes
  }

  public breakContaining(minute: number): BreakScheduleEntry | null {
    const sorted: BreakScheduleEntry[] = [...this.breaks].sort(
      (a: BreakScheduleEntry, b: BreakScheduleEntry) => a.startMinutes - b.startMinutes
    )
    if (!this.isCrossMidnight) {
      const found: BreakScheduleEntry | undefined = sorted.find(
        (b: BreakScheduleEntry) => minute >= b.startMinutes && minute < b.endMinutes
      )
      return found !== undefined ? found : null
    }
    // Cross-midnight: check both [ws, 1440) and [0, we] segments
    const found: BreakScheduleEntry | undefined = sorted.find(
      (b: BreakScheduleEntry) => minute >= b.startMinutes && minute < b.endMinutes
    )
    return found !== undefined ? found : null
  }

  /**
   * Returns total break seconds that have elapsed before the given clock second,
   * handling cross-midnight wrap.
   */
  public elapsedBreakSeconds(beforeClockSecond: number): number {
    const sorted: BreakScheduleEntry[] = [...this.breaks].sort(
      (a: BreakScheduleEntry, b: BreakScheduleEntry) => a.startMinutes - b.startMinutes
    )
    const beforeMinute: number = Math.floor(beforeClockSecond / 60)
    let total: number = 0
    for (const b of sorted) {
      const bEndElapsed: number = this.elapsedSinceStart(b.endMinutes)
      const beforeElapsed: number = this.elapsedSinceStart(beforeMinute)
      if (bEndElapsed <= beforeElapsed) {
        total += (b.endMinutes - b.startMinutes) * 60
      }
    }
    return total
  }
}

/**
 * Enum describing the current work status.
 */
export enum WorkStatus {
  NOT_STARTED = 'notStarted',
  WORKING = 'working',
  ON_BREAK = 'onBreak',
  COMPLETED = 'completed',
  OVERTIME = 'overtime',
  DAY_OFF = 'dayOff'
}

/**
 * Result of a today's earnings calculation.
 */
export class TodayEarnings {
  public amount: number = 0
  public progress: number = 0
  public status: WorkStatus = WorkStatus.NOT_STARTED
  public elapsedSeconds: number = 0
  public totalWorkSeconds: number = 0
}

/**
 * Month-level summary data.
 */
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
 * Pure calculation engine — takes config, returns earnings data.
 */
export class EarningsCalculator {
  public monthlyPay: number = 0
  public workingDaysPerMonth: number = 21.75
  public schedule: WorkSchedule = new WorkSchedule()
  public payDay: number = 15
  public taxRate: number = 0
  public holidayCalendar: HolidayCalendarData | null = null
  public dayOverrides: Map<string, DayOverride> = new Map()

  public get dailyRate(): number {
    if (this.workingDaysPerMonth <= 0) {
      return 0
    }
    return this.monthlyPay * (1 - this.taxRate) / this.workingDaysPerMonth
  }

  public get hourlyRate(): number {
    if (this.schedule.totalWorkHours <= 0) {
      return 0
    }
    return this.dailyRate / this.schedule.totalWorkHours
  }

  public get secondRate(): number {
    return this.hourlyRate / 3600
  }

  public get totalWorkSeconds(): number {
    return Math.max(0, this.schedule.totalWorkMinutes) * 60
  }

  public calculateTodayEarnings(date: Date = new Date()): TodayEarnings {
    const result = new TodayEarnings()
    result.totalWorkSeconds = this.totalWorkSeconds

    if (this.isDayOff(date)) {
      result.status = WorkStatus.DAY_OFF
      return result
    }

    const currentMinute: number = date.getHours() * 60 + date.getMinutes()
    const currentSec: number = date.getHours() * 3600 + date.getMinutes() * 60 + date.getSeconds()

    // Determine overtime config for today (if any)
    const ds: string = this.dateStringFromDate(date)
    const override: DayOverride | undefined = this.dayOverrides.get(ds)
    let isOvertime: boolean = false
    let multiplier: number = 1.0
    // When overtime has customWorkHours, it acts as the reference for the per-second rate
    // (snapshotted from the normal work schedule). The per-second rate stays anchored to
    // this reference regardless of the current schedule's totalWorkHours.
    let overtimeBaseSecondRate: number = this.secondRate

    if (override !== undefined && override.dayType === DayType.OVERTIME) {
      isOvertime = true
      multiplier = override.overtimeMultiplier

      const customHours: number | null = override.customWorkHours
      if (customHours !== null && customHours > 0) {
        // Derive per-second rate from the snapshotted reference hours
        overtimeBaseSecondRate = customHours > 0 ? this.dailyRate / customHours / 3600 : this.secondRate
      }
    }

    // Standard schedule path (regular day or overtime) — same window, same breaks.
    // Only the effective rate changes for overtime.
    const effectiveTotalSeconds: number = this.totalWorkSeconds
    const effectiveSecondRate: number = isOvertime ? overtimeBaseSecondRate : this.secondRate
    result.totalWorkSeconds = effectiveTotalSeconds

    // Not started: before work start (and not in cross-midnight's next-day portion)
    if (!this.schedule.isInWorkWindow(currentMinute) && !this.schedule.isAfterWork(currentMinute)) {
      result.status = WorkStatus.NOT_STARTED
      return result
    }

    // Completed: after work end
    if (this.schedule.isAfterWork(currentMinute)) {
      const fullAmount: number = isOvertime
        ? effectiveSecondRate * effectiveTotalSeconds * multiplier
        : this.dailyRate
      result.amount = fullAmount
      result.progress = 1
      result.status = isOvertime ? WorkStatus.OVERTIME : WorkStatus.COMPLETED
      result.elapsedSeconds = effectiveTotalSeconds
      return result
    }

    // In work window
    const activeBreak = this.schedule.breakContaining(currentMinute)
    if (activeBreak !== null) {
      // On break: work elapsed = time from work start to break start, minus prior breaks
      const breakStartSec: number = activeBreak.startMinutes * 60
      const breakStartElapsedSec: number = this.schedule.elapsedSinceStartSeconds(breakStartSec)
      const priorBreakSec: number = this.schedule.elapsedBreakSeconds(breakStartSec)
      let elapsedSec: number = Math.max(0, breakStartElapsedSec - priorBreakSec)
      elapsedSec = Math.min(elapsedSec, effectiveTotalSeconds)
      result.elapsedSeconds = elapsedSec
      result.amount = effectiveSecondRate * elapsedSec * multiplier
      result.progress = effectiveTotalSeconds > 0 ? elapsedSec / effectiveTotalSeconds : 0
      result.status = WorkStatus.ON_BREAK
      return result
    }

    // Working: work elapsed = time from work start to now, minus all completed breaks
    const nowElapsedSec: number = this.schedule.elapsedSinceStartSeconds(currentSec)
    const elapsedBreakSec: number = this.schedule.elapsedBreakSeconds(currentSec)
    let elapsedSec: number = Math.max(0, nowElapsedSec - elapsedBreakSec)
    elapsedSec = Math.min(elapsedSec, effectiveTotalSeconds)
    result.elapsedSeconds = elapsedSec
    result.amount = effectiveSecondRate * elapsedSec * multiplier
    result.progress = effectiveTotalSeconds > 0 ? elapsedSec / effectiveTotalSeconds : 0
    result.status = isOvertime ? WorkStatus.OVERTIME : WorkStatus.WORKING
    return result
  }

  public calculateMonthSummary(date: Date = new Date()): MonthSummary {
    const summary = new MonthSummary()
    const workingDays: number = this.countWorkingDaysInMonth(date)
    const elapsedDays: number = this.countElapsedWorkingDays(date)
    summary.workingDaysThisMonth = workingDays
    summary.workingDaysElapsed = elapsedDays
    summary.monthProgress = workingDays > 0 ? elapsedDays / workingDays : 0
    summary.monthEarnings = this.calculateElapsedMonthEarnings(date)
    summary.totalMonthEarnings = this.calculateTotalMonthEarnings(date)

    const paydayInfo = this.calculatePayday(date)
    summary.daysUntilPayday = paydayInfo[0]
    summary.isPayday = paydayInfo[1]

    const cycleInfo = this.calculatePaydayCycle(date)
    summary.paydayCycleProgress = cycleInfo[0]
    summary.paydayCycleTotal = cycleInfo[1]
    summary.paydayCycleElapsed = cycleInfo[2]

    return summary
  }

  private dateStringFromDate(date: Date): string {
    const y: number = date.getFullYear()
    const m: number = date.getMonth() + 1
    const d: number = date.getDate()
    return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`
  }

  /**
   * Three-tier day-off determination: user override > holiday calendar > weekend check.
   */
  private isDayOff(date: Date): boolean {
    const month: number = date.getMonth() + 1
    const day: number = date.getDate()

    // Tier 1: user override
    const ds: string = this.dateStringFromDate(date)
    const override: DayOverride | undefined = this.dayOverrides.get(ds)
    if (override !== undefined) {
      switch (override.dayType) {
        case DayType.NORMAL:
          break // fall through to calendar/weekend check
        case DayType.HOLIDAY:
          return true
        case DayType.OVERTIME:
          return false // overtime days are working days
      }
    }

    // Tier 2: Chinese holiday calendar
    if (this.holidayCalendar !== null) {
      if (this.holidayCalendar.isHoliday(month, day)) {
        return true
      }
      if (this.holidayCalendar.isAdjustedWorkday(month, day)) {
        return false
      }
    }

    // Tier 3: weekend fallback
    const wd: number = date.getDay()
    return wd === 0 || wd === 6
  }

  /**
   * Returns the per-day earnings for a given date, accounting for overtime.
   */
  private dailyEarningsForDate(date: Date): number {
    const ds: string = this.dateStringFromDate(date)
    const override: DayOverride | undefined = this.dayOverrides.get(ds)
    if (override !== undefined && override.dayType === DayType.OVERTIME) {
      const multiplier: number = override.overtimeMultiplier
      const customHours: number | null = override.customWorkHours
      // Use snapshotted reference hours for the per-second rate, schedule for the window
      const rateRefHours: number = (customHours !== null && customHours > 0)
        ? customHours : this.schedule.totalWorkHours
      const effSecondRate: number = this.dailyRate / rateRefHours / 3600
      return effSecondRate * this.schedule.totalWorkHours * 3600 * multiplier
    }
    if (this.isDayOff(date)) {
      return 0
    }
    return this.dailyRate
  }

  /**
   * Sums the earnings for every elapsed working day in the month (including today if working).
   */
  private calculateElapsedMonthEarnings(date: Date): number {
    const year: number = date.getFullYear()
    const month: number = date.getMonth()
    const today: number = date.getDate()
    let total: number = 0
    for (let d: number = 1; d <= today; d++) {
      const check: Date = new Date(year, month, d)
      total += this.dailyEarningsForDate(check)
    }
    return total
  }

  /**
   * Sums the earnings for every working day in the entire month.
   */
  private calculateTotalMonthEarnings(date: Date): number {
    const year: number = date.getFullYear()
    const month: number = date.getMonth()
    const daysInMonth: number = new Date(year, month + 1, 0).getDate()
    let total: number = 0
    for (let d: number = 1; d <= daysInMonth; d++) {
      const check: Date = new Date(year, month, d)
      total += this.dailyEarningsForDate(check)
    }
    return total
  }

  private countWorkingDaysInMonth(date: Date): number {
    const year: number = date.getFullYear()
    const month: number = date.getMonth()
    const daysInMonth: number = new Date(year, month + 1, 0).getDate()
    let count: number = 0
    for (let d: number = 1; d <= daysInMonth; d++) {
      const check: Date = new Date(year, month, d)
      if (!this.isDayOff(check)) {
        count++
      }
    }
    return count
  }

  private countElapsedWorkingDays(date: Date): number {
    const year: number = date.getFullYear()
    const month: number = date.getMonth()
    const today: number = date.getDate()
    let count: number = 0
    for (let d: number = 1; d <= today; d++) {
      const check: Date = new Date(year, month, d)
      if (!this.isDayOff(check)) {
        count++
      }
    }
    if (!this.isDayOff(date)) {
      count--
    }
    return Math.max(0, count)
  }

  private calculatePayday(date: Date): [number, boolean] {
    const todayDay: number = date.getDate()
    if (todayDay === this.payDay) {
      return [0, true]
    }
    const year: number = date.getFullYear()
    const month: number = date.getMonth()
    let paydayDate: Date = new Date(year, month, this.payDay)
    if (todayDay > this.payDay) {
      paydayDate = new Date(year, month + 1, this.payDay)
    }
    const todayStart: Date = new Date(year, month, todayDay)
    const diffMs: number = paydayDate.getTime() - todayStart.getTime()
    const days: number = Math.ceil(diffMs / (1000 * 60 * 60 * 24))
    return [days, false]
  }

  private calculatePaydayCycle(date: Date): [number, number, number] {
    const todayDay: number = date.getDate()
    const year: number = date.getFullYear()
    const month: number = date.getMonth()
    const todayStart: Date = new Date(year, month, todayDay)

    let cycleStart: Date = new Date(year, month, this.payDay)
    if (todayDay < this.payDay) {
      cycleStart = new Date(year, month - 1, this.payDay)
    }

    const cycleEnd: Date = new Date(cycleStart.getFullYear(), cycleStart.getMonth() + 1, this.payDay)
    const totalDays: number = Math.round((cycleEnd.getTime() - cycleStart.getTime()) / (1000 * 60 * 60 * 24))
    const elapsedDays: number = Math.round((todayStart.getTime() - cycleStart.getTime()) / (1000 * 60 * 60 * 24))
    const progress: number = totalDays > 0 ? Math.min(1, elapsedDays / totalDays) : 0
    return [progress, totalDays, elapsedDays]
  }
}
