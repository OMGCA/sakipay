/* (c) Copyright XiatStudio 2026~2026 */
/**
 * A single break entry in the work schedule.
 */
export class BreakScheduleEntry {
  public startMinutes: number = 0
  public endMinutes: number = 0
}

/**
 * Internal schedule representation used by the calculator.
 */
class WorkSchedule {
  public workStartMinutes: number = 540 // 09:00
  public workEndMinutes: number = 1080  // 18:00
  public breaks: BreakScheduleEntry[] = []

  public get totalBreakMinutes(): number {
    let total: number = 0
    for (const b of this.breaks) {
      total += (b.endMinutes - b.startMinutes)
    }
    return total
  }

  public get totalWorkMinutes(): number {
    return (this.workEndMinutes - this.workStartMinutes) - this.totalBreakMinutes
  }

  public get totalWorkHours(): number {
    return this.totalWorkMinutes / 60
  }

  public breakContaining(minute: number): BreakScheduleEntry | null {
    const sorted: BreakScheduleEntry[] = [...this.breaks].sort(
      (a: BreakScheduleEntry, b: BreakScheduleEntry) => a.startMinutes - b.startMinutes
    )
    const found: BreakScheduleEntry | undefined = sorted.find(
      (b: BreakScheduleEntry) => minute >= b.startMinutes && minute < b.endMinutes
    )
    return found !== undefined ? found : null
  }

  public elapsedBreakSeconds(beforeSecond: number): number {
    const sorted: BreakScheduleEntry[] = [...this.breaks].sort(
      (a: BreakScheduleEntry, b: BreakScheduleEntry) => a.startMinutes - b.startMinutes
    )
    let total: number = 0
    for (const b of sorted) {
      if (b.endMinutes * 60 < beforeSecond) {
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

    const wsSec: number = this.schedule.workStartMinutes * 60
    const weSec: number = this.schedule.workEndMinutes * 60

    if (currentMinute < this.schedule.workStartMinutes) {
      result.status = WorkStatus.NOT_STARTED
      return result
    }

    if (currentMinute >= this.schedule.workEndMinutes) {
      result.amount = this.dailyRate
      result.progress = 1
      result.status = WorkStatus.COMPLETED
      result.elapsedSeconds = result.totalWorkSeconds
      return result
    }

    const activeBreak = this.schedule.breakContaining(currentMinute)
    if (activeBreak !== null) {
      const breakStartSec: number = activeBreak.startMinutes * 60
      const previousBreakSec: number = this.schedule.elapsedBreakSeconds(breakStartSec)
      result.elapsedSeconds = Math.max(0, breakStartSec - wsSec - previousBreakSec)
      result.amount = this.secondRate * result.elapsedSeconds
      result.progress = result.totalWorkSeconds > 0 ? result.elapsedSeconds / result.totalWorkSeconds : 0
      result.status = WorkStatus.ON_BREAK
      return result
    }

    const elapsedBreakSec: number = this.schedule.elapsedBreakSeconds(currentSec)
    result.elapsedSeconds = Math.max(0, currentSec - wsSec - elapsedBreakSec)
    result.amount = this.secondRate * result.elapsedSeconds
    result.progress = result.totalWorkSeconds > 0 ? result.elapsedSeconds / result.totalWorkSeconds : 0
    result.status = WorkStatus.WORKING
    return result
  }

  public calculateMonthSummary(date: Date = new Date()): MonthSummary {
    const summary = new MonthSummary()
    const workingDays: number = this.countWorkingDaysInMonth(date)
    const elapsedDays: number = this.countElapsedWorkingDays(date)
    summary.workingDaysThisMonth = workingDays
    summary.workingDaysElapsed = elapsedDays
    summary.monthProgress = workingDays > 0 ? elapsedDays / workingDays : 0
    summary.monthEarnings = this.dailyRate * elapsedDays
    summary.totalMonthEarnings = this.dailyRate * workingDays

    const paydayInfo = this.calculatePayday(date)
    summary.daysUntilPayday = paydayInfo[0]
    summary.isPayday = paydayInfo[1]

    const cycleInfo = this.calculatePaydayCycle(date)
    summary.paydayCycleProgress = cycleInfo[0]
    summary.paydayCycleTotal = cycleInfo[1]
    summary.paydayCycleElapsed = cycleInfo[2]

    return summary
  }

  private isDayOff(date: Date): boolean {
    const day: number = date.getDay()
    return day === 0 || day === 6
  }

  private countWorkingDaysInMonth(date: Date): number {
    const year: number = date.getFullYear()
    const month: number = date.getMonth()
    const daysInMonth: number = new Date(year, month + 1, 0).getDate()
    let count: number = 0
    for (let d: number = 1; d <= daysInMonth; d++) {
      const check: Date = new Date(year, month, d)
      const wd: number = check.getDay()
      if (wd !== 0 && wd !== 6) {
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
      const wd: number = check.getDay()
      if (wd !== 0 && wd !== 6) {
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
