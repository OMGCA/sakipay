/* (c) Copyright XiatStudio 2026~2026 */
import { BreakSegment } from '../models/BreakSegment'
import { DayOverride, DayType, HolidayCalendarData } from '../models/HolidayCalendar'
import { HolidayCalendarService } from '../services/HolidayCalendarService'
import { ConfigData, PreferencesStore } from '../services/PreferencesStore'
import { Log } from '../services/Log'

/**
 * VM driving the Settings tab — manages form state and persistence.
 */
@ObservedV2
export class SettingsViewModel {
  // Salary
  @Trace public monthlyPayText: string = ''
  @Trace public currency: string = '¥'
  @Trace public workingDays: number = 21.75

  // Work hours
  @Trace public workStartH: number = 9
  @Trace public workStartM: number = 0
  @Trace public workEndH: number = 18
  @Trace public workEndM: number = 0

  // Break segments
  @Trace public breakSegments: BreakSegment[] = []

  // Tax & payday
  @Trace public taxRate: number = 0
  @Trace public payDay: number = 15

  @Trace public breakVersion: number = 0
  @Trace public isLoaded: boolean = false
  @Trace public saveMessage: string = ''

  // Calendar overrides
  @Trace public dayOverrides: DayOverride[] = []
  @Trace public useCalibratedWorkDays: boolean = true
  @Trace public calibratedWorkingDays: number = 0

  private store: PreferencesStore = new PreferencesStore()

  public async initialise(context: Context): Promise<void> {
    await this.store.initialise(context)
  }

  public async loadConfig(): Promise<void> {
    const config: ConfigData = await this.store.loadConfig()

    this.monthlyPayText = config.monthlyPay > 0 ? config.monthlyPay.toFixed(2) : ''
    this.currency = config.currency
    this.workingDays = config.workingDaysPerMonth
    this.workStartH = config.workStartHour
    this.workStartM = config.workStartMinute
    this.workEndH = config.workEndHour
    this.workEndM = config.workEndMinute
    this.taxRate = config.taxRate
    this.payDay = config.payDay

    // Parse breaks JSON
    this.breakSegments = this.parseBreaks(config.breaksJSON)

    // Only add default break on first launch (breaksJSON empty). If the user
    // explicitly saved an empty array (`[]`), respect that choice.
    if (this.breakSegments.length === 0 && config.breaksJSON.length === 0) {
      const defaultBreak: BreakSegment = new BreakSegment()
      defaultBreak.startHour = 12
      defaultBreak.startMinute = 0
      defaultBreak.endHour = 13
      defaultBreak.endMinute = 30
      this.breakSegments = [defaultBreak]
    }

    // Parse day overrides
    this.dayOverrides = this.parseDayOverrides(config.dayOverridesJSON)

    this.recalibrateWorkingDays()

    this.isLoaded = true
    Log.info('Config loaded')
  }

  /**
   * Recomputes the calibrated working day count for the current month,
   * accounting for the Chinese holiday calendar and any user overrides.
   */
  public recalibrateWorkingDays(): void {
    const hc: HolidayCalendarData | null = HolidayCalendarService.getInstance().currentCalendar()
    const today: Date = new Date()
    const year: number = today.getFullYear()
    const month: number = today.getMonth()
    const daysInMonth: number = new Date(year, month + 1, 0).getDate()

    // Build override lookup
    const overrideMap: Map<string, DayOverride> = new Map()
    for (const ov of this.dayOverrides) {
      overrideMap.set(ov.dateString, ov)
    }

    let count: number = 0
    for (let d: number = 1; d <= daysInMonth; d++) {
      const ds: string = `${year}-${String(month + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`
      const override: DayOverride | undefined = overrideMap.get(ds)

      // User override: holiday → day off, overtime → working
      if (override !== undefined) {
        if (override.dayType === DayType.HOLIDAY) {
          continue
        }
        if (override.dayType === DayType.OVERTIME) {
          count = count + 1
          continue
        }
      }

      // Holiday calendar check
      const m: number = month + 1
      if (hc !== null) {
        if (hc.isHoliday(m, d)) {
          continue
        }
        if (hc.isAdjustedWorkday(m, d)) {
          count = count + 1
          continue
        }
      }

      // Weekend fallback
      const wd: number = new Date(year, month, d).getDay()
      if (wd !== 0 && wd !== 6) {
        count = count + 1
      }
    }

    this.calibratedWorkingDays = count
  }

  /**
   * Adds or updates a day override and recalibrates working days.
   */
  public addOrUpdateOverride(override: DayOverride): void {
    const idx: number = this.dayOverrides.findIndex(
      (d: DayOverride) => d.dateString === override.dateString
    )
    if (idx >= 0) {
      const updated: DayOverride[] = [...this.dayOverrides]
      updated[idx] = override
      this.dayOverrides = updated
    } else {
      this.dayOverrides = this.dayOverrides.concat([override])
    }
    this.recalibrateWorkingDays()
  }

  /**
   * Removes a day override by date string and recalibrates.
   */
  public removeOverride(dateString: string): void {
    this.dayOverrides = this.dayOverrides.filter((d: DayOverride) => d.dateString !== dateString)
    this.recalibrateWorkingDays()
  }

  public async saveConfig(): Promise<boolean> {
    const pay: number = parseFloat(this.monthlyPayText)
    if (isNaN(pay) || pay <= 0) {
      this.showSaveMessage('请输入有效月薪')
      return false
    }

    const duration: number = this.getWorkDurationMinutes()
    if (duration > 1439) {
      this.showSaveMessage('总工作时长不能超过 23 小时 59 分')
      return false
    }

    // Prune breaks that are invalid or outside work hours
    const ws: number = this.workStartH * 60 + this.workStartM
    const we: number = this.workEndH * 60 + this.workEndM
    const before: number = this.breakSegments.length
    this.breakSegments = this.breakSegments.filter(
      (b: BreakSegment) => b.isValid && b.fitsWithin(ws, we)
    )
    const removed: number = before - this.breakSegments.length
    if (removed > 0) {
      this.showSaveMessage(`已自动清除 ${removed} 个无效休息时段`)
    }

    const config: ConfigData = new ConfigData()
    config.monthlyPay = pay
    config.workingDaysPerMonth = this.useCalibratedWorkDays
      ? this.calibratedWorkingDays
      : this.workingDays
    config.currency = this.currency
    config.taxRate = this.taxRate
    config.payDay = this.payDay
    config.workStartHour = this.workStartH
    config.workStartMinute = this.workStartM
    config.workEndHour = this.workEndH
    config.workEndMinute = this.workEndM
    config.breaksJSON = JSON.stringify(this.breakSegments)
    config.dayOverridesJSON = JSON.stringify(this.dayOverrides)

    const saved: boolean = await this.store.saveConfig(config)
    if (!saved) {
      this.showSaveMessage('保存失败')
      Log.error('Config save returned false')
      return false
    }
    this.showSaveMessage('已保存')
    Log.info('Config saved')
    return true
  }

  /**
   * Total work-window minutes, handling cross-midnight (end <= start means next day).
   */
  public getWorkDurationMinutes(): number {
    const ws: number = this.workStartH * 60 + this.workStartM
    const we: number = this.workEndH * 60 + this.workEndM
    if (we > ws) {
      return we - ws
    }
    return (1440 - ws) + we
  }

  /**
   * Computes the total working hours per day accounting for breaks.
   * Used to auto-wire customWorkHours when saving an overtime override.
   */
  public getTotalWorkHours(): number {
    const windowMinutes: number = this.getWorkDurationMinutes()
    const breakMinutes: number = this.getTotalBreakMinutes()
    const workMinutes: number = Math.max(0, windowMinutes - breakMinutes)
    return workMinutes / 60
  }

  private getTotalBreakMinutes(): number {
    let total: number = 0
    for (const b of this.breakSegments) {
      if (b.isValid) {
        total += b.endMinutes - b.startMinutes
      }
    }
    return total
  }

  public addBreak(): void {
    const ws: number = this.workStartH * 60 + this.workStartM
    const we: number = this.workEndH * 60 + this.workEndM
    const duration: number = this.getWorkDurationMinutes()
    if (duration < 120) {
      return
    }

    const lastEnd: number = this.breakSegments.length > 0
      ? this.breakSegments[this.breakSegments.length - 1].endMinutes
      : ws
    let newStart: number = lastEnd + 60

    // For cross-midnight, wrap if we go past midnight
    if (we <= ws && newStart >= 1440) {
      newStart = newStart - 1440
    }
    // Clamp to the work window
    const maxStart: number = we <= ws ? 1440 : we
    newStart = Math.min(newStart, maxStart - 60)
    let newEnd: number = newStart + 60
    if (we <= ws && newEnd > 1440) {
      newEnd = newEnd - 1440
    }
    newEnd = Math.min(newEnd, we <= ws ? 1440 : we)

    const seg: BreakSegment = new BreakSegment()
    seg.startHour = Math.floor(newStart / 60)
    seg.startMinute = Math.floor((newStart % 60) / 5) * 5
    seg.endHour = Math.floor(newEnd / 60)
    seg.endMinute = Math.floor((newEnd % 60) / 5) * 5
    this.breakSegments = this.breakSegments.concat([seg])
  }

  public removeBreak(id: string): void {
    this.breakSegments = this.breakSegments.filter((b: BreakSegment) => b.id !== id)
  }

  public pruneInvalidBreaks(): void {
    const ws: number = this.workStartH * 60 + this.workStartM
    const we: number = this.workEndH * 60 + this.workEndM
    if (this.getWorkDurationMinutes() <= 0) {
      return
    }
    const before: number = this.breakSegments.length
    this.breakSegments = this.breakSegments.filter((b: BreakSegment) => b.fitsWithin(ws, we))
    const removed: number = before - this.breakSegments.length
    if (removed > 0) {
      this.showSaveMessage(`已自动清除 ${removed} 个无效休息时段`)
    }
  }

  /**
   * Notify the VM that break segment properties have changed, so that computed
   * properties like formattedWorkHours re-evaluate reactively.
   */
  public onBreakChanged(): void {
    this.breakVersion++
  }

  public get workStartMinutes(): number {
    return this.workStartH * 60 + this.workStartM
  }

  public get workEndMinutes(): number {
    return this.workEndH * 60 + this.workEndM
  }

  public get formattedWorkHours(): string {
    // Read breakVersion to establish reactive dependency on break property changes
    const _v: number = this.breakVersion
    const duration: number = this.getWorkDurationMinutes()
    if (duration <= 0) {
      return '0.0 小时'
    }
    const breakMin: number = this.breakSegments
      .filter((b: BreakSegment) => b.isValid)
      .reduce((sum: number, b: BreakSegment) => sum + b.durationMinutes, 0)
    const workMin: number = Math.max(0, duration - breakMin)
    return `${(workMin / 60).toFixed(1)} 小时`
  }

  public get postTaxMonthly(): string {
    const pay: number = parseFloat(this.monthlyPayText)
    if (isNaN(pay) || pay <= 0 || this.taxRate <= 0) {
      return ''
    }
    return `${this.currency}${(pay * (1 - this.taxRate)).toFixed(2)}`
  }

  private parseBreaks(json: string): BreakSegment[] {
    if (json.length === 0) {
      return []
    }
    try {
      const arr: object[] = JSON.parse(json) as object[]
      const result: BreakSegment[] = []
      for (const item of arr) {
        const seg: BreakSegment = new BreakSegment()
        const obj = item as Record<string, number>
        if (obj.startHour !== undefined) {
          seg.startHour = obj.startHour
        }
        if (obj.startMinute !== undefined) {
          seg.startMinute = obj.startMinute
        }
        if (obj.endHour !== undefined) {
          seg.endHour = obj.endHour
        }
        if (obj.endMinute !== undefined) {
          seg.endMinute = obj.endMinute
        }
        result.push(seg)
      }
      return result
    } catch (err) {
      Log.error(`Failed to parse breaks JSON: ${err}`)
      return []
    }
  }

  /**
   * Returns the override for a given date string, or null.
   */
  public getOverride(dateString: string): DayOverride | null {
    const found: DayOverride | undefined = this.dayOverrides.find(
      (d: DayOverride) => d.dateString === dateString
    )
    return found !== undefined ? found : null
  }

  /**
   * Parses day overrides from a JSON string.
   */
  private parseDayOverrides(json: string): DayOverride[] {
    if (json.length === 0) {
      return []
    }
    try {
      const arr: object[] = JSON.parse(json) as object[]
      const result: DayOverride[] = []
      for (const item of arr) {
        const obj = item as Record<string, Object>
        const override: DayOverride = new DayOverride()
        if (obj.dateString !== undefined) {
          override.dateString = obj.dateString as string
        }
        if (obj.dayType !== undefined) {
          const dt: string = obj.dayType as string
          if (dt === DayType.HOLIDAY) {
            override.dayType = DayType.HOLIDAY
          } else if (dt === DayType.OVERTIME) {
            override.dayType = DayType.OVERTIME
          } else {
            override.dayType = DayType.NORMAL
          }
        }
        if (obj.overtimeMultiplier !== undefined) {
          override.overtimeMultiplier = obj.overtimeMultiplier as number
        }
        if (obj.customWorkHours !== undefined && obj.customWorkHours !== null) {
          override.customWorkHours = obj.customWorkHours as number
        }
        result.push(override)
      }
      return result
    } catch (err) {
      Log.error(`Failed to parse dayOverrides JSON: ${err}`)
      return []
    }
  }

  private showSaveMessage(msg: string): void {
    this.saveMessage = msg
    setTimeout(() => {
      this.saveMessage = ''
    }, 2000)
  }
}
