/* (c) Copyright XiatStudio 2026~2026 */

/**
 * Enum describing the type of a calendar day.
 */
export enum DayType {
  NORMAL = 'normal',
  HOLIDAY = 'holiday',
  OVERTIME = 'overtime'
}

/**
 * A user's custom designation for a specific date.
 */
export class DayOverride {
  /** ISO 8601 date string, e.g. "2026-05-15". */
  public dateString: string = ''
  public dayType: DayType = DayType.NORMAL
  /** Overtime pay multiplier, e.g. 2.0 for double pay. Only meaningful when dayType is OVERTIME. */
  public overtimeMultiplier: number = 2.0
  /** Custom work hours for this overtime day. null means use the default schedule's total work hours. */
  public customWorkHours: number | null = null
}

/**
 * One year's public holiday and adjusted-workday schedule.
 * Uses Set<string> keyed by "MM-DD" for O(1) lookup.
 */
export class HolidayCalendarData {
  public year: number = 0
  public holidays: Set<string> = new Set()
  public adjustedWorkdays: Set<string> = new Set()

  /**
   * Returns true if the given month/day is a public holiday (day off).
   */
  public isHoliday(month: number, day: number): boolean {
    const key: string = `${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`
    return this.holidays.has(key)
  }

  /**
   * Returns true if the given month/day is an adjusted working day (调休, typically a weekend).
   */
  public isAdjustedWorkday(month: number, day: number): boolean {
    const key: string = `${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`
    return this.adjustedWorkdays.has(key)
  }
}
