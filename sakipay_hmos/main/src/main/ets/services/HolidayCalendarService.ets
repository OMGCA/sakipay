/* (c) Copyright XiatStudio 2026~2026 */
import { resourceManager } from '@kit.LocalizationKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { util } from '@kit.ArkTS'
import { HolidayCalendarData } from '../models/HolidayCalendar'

/**
 * Singleton that loads and caches Chinese holiday calendars from bundled rawfile JSON.
 */
export class HolidayCalendarService {
  private static instance: HolidayCalendarService | null = null
  private calendars: Map<number, HolidayCalendarData> = new Map()
  private isLoaded: boolean = false

  static getInstance(): HolidayCalendarService {
    if (HolidayCalendarService.instance === null) {
      HolidayCalendarService.instance = new HolidayCalendarService()
    }
    return HolidayCalendarService.instance
  }

  private constructor() {}

  /**
   * Loads the bundled holiday JSON from rawfile using the given resource manager.
   * Safe to call multiple times — subsequent calls are no-ops.
   */
  public loadBundledCalendars(context: Context): void {
    if (this.isLoaded) {
      return
    }
    this.isLoaded = true

    const rm: resourceManager.ResourceManager = context.resourceManager
    try {
      const rawData: Uint8Array = rm.getRawFileContentSync('holidays.json')
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8')
      const jsonStr: string = decoder.decode(rawData)
      const raw: Record<string, Record<string, string[]>> = JSON.parse(jsonStr) as Record<string, Record<string, string[]>>

      const years: string[] = Object.keys(raw)
      for (const yearStr of years) {
        const year: number = parseInt(yearStr)
        const yearData: Record<string, string[]> = raw[yearStr]
        const calendar: HolidayCalendarData = new HolidayCalendarData()
        calendar.year = year

        const holidayArray: string[] = yearData['holidays'] as string[]
        if (holidayArray !== undefined && holidayArray !== null) {
          calendar.holidays = new Set(holidayArray)
        }

        const workdayArray: string[] = yearData['adjustedWorkdays'] as string[]
        if (workdayArray !== undefined && workdayArray !== null) {
          calendar.adjustedWorkdays = new Set(workdayArray)
        }

        this.calendars.set(year, calendar)
      }
    } catch (err) {
      const error: BusinessError = err as BusinessError
      // Calendar data unavailable — calculator will fall back to weekend-only check.
      console.error(`HolidayCalendarService: failed to load bundled data — ${error.message}`)
    }
  }

  /**
   * Returns the holiday calendar for a given year, or null if none is available.
   */
  public calendarForYear(year: number): HolidayCalendarData | null {
    const result: HolidayCalendarData | undefined = this.calendars.get(year)
    return result !== undefined ? result : null
  }

  /**
   * Returns the holiday calendar for the current calendar year, or null.
   */
  public currentCalendar(): HolidayCalendarData | null {
    const year: number = new Date().getFullYear()
    return this.calendarForYear(year)
  }

  /**
   * Returns true if holiday data is available for the given year.
   */
  public hasDataForYear(year: number): boolean {
    return this.calendars.has(year)
  }
}
