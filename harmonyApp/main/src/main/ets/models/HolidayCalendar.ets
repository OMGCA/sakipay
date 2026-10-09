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
