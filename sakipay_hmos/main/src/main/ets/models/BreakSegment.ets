/* (c) Copyright XiatStudio 2026~2026 */
/**
 * Represents a single break (rest) period during the work day.
 */
export class BreakSegment {
  public id: string = ''
  public startHour: number = 12
  public startMinute: number = 0
  public endHour: number = 13
  public endMinute: number = 30

  constructor() {
    this.id = this.generateId()
  }

  public get startMinutes(): number {
    return this.startHour * 60 + this.startMinute
  }

  public get endMinutes(): number {
    return this.endHour * 60 + this.endMinute
  }

  public get durationMinutes(): number {
    return this.endMinutes - this.startMinutes
  }

  public get isValid(): boolean {
    return this.endMinutes > this.startMinutes
  }

  /**
   * Checks whether this break fits entirely within the work window.
   * When workEnd <= workStart (cross-midnight), the break must fit in either
   * the [workStart, 1440) or [0, workEnd] segment.
   */
  public fitsWithin(workStart: number, workEnd: number): boolean {
    if (workEnd > workStart) {
      return this.startMinutes >= workStart && this.endMinutes <= workEnd
    }
    return (this.startMinutes >= workStart && this.endMinutes <= 1440) ||
      (this.startMinutes >= 0 && this.endMinutes <= workEnd)
  }

  private generateId(): string {
    return `${Date.now()}_${Math.floor(Math.random() * 10000)}`
  }
}
