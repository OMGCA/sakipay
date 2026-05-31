/* (c) Copyright XiatStudio 2026~2026 */
import { preferences } from '@kit.ArkData'
import { BreakSegment } from '../models/BreakSegment'
import { Log } from './Log'

const STORE_NAME: string = 'sakipay_config'

/**
 * Wraps @ohos.data.preferences for persistent key-value config storage.
 */
export class PreferencesStore {
  private store: preferences.Preferences | null = null

  public async initialise(context: Context): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, STORE_NAME)
      Log.info('PreferencesStore initialised')
    } catch (err) {
      Log.error(`PreferencesStore init failed: ${err}`)
    }
  }

  public async saveConfig(config: ConfigData): Promise<boolean> {
    if (this.store === null) {
      Log.error('saveConfig failed: store not initialised')
      return false
    }
    try {
      await this.store.put('monthlyPay', config.monthlyPay)
      await this.store.put('workingDaysPerMonth', config.workingDaysPerMonth)
      await this.store.put('currency', config.currency)
      await this.store.put('taxRate', config.taxRate)
      await this.store.put('payDay', config.payDay)
      await this.store.put('workStartHour', config.workStartHour)
      await this.store.put('workStartMinute', config.workStartMinute)
      await this.store.put('workEndHour', config.workEndHour)
      await this.store.put('workEndMinute', config.workEndMinute)
      await this.store.put('breaksJSON', config.breaksJSON)
      await this.store.put('dayOverridesJSON', config.dayOverridesJSON)
      await this.store.flush()
      Log.info('Config saved')
      return true
    } catch (err) {
      Log.error(`saveConfig failed: ${err}`)
      return false
    }
  }

  public async loadConfig(): Promise<ConfigData> {
    const config = new ConfigData()
    if (this.store === null) {
      return config
    }
    try {
      config.monthlyPay = (await this.store.get('monthlyPay', 0)) as number
      config.workingDaysPerMonth = (await this.store.get('workingDaysPerMonth', 21.75)) as number
      config.currency = (await this.store.get('currency', '¥')) as string
      config.taxRate = (await this.store.get('taxRate', 0)) as number
      config.payDay = (await this.store.get('payDay', 15)) as number
      config.workStartHour = (await this.store.get('workStartHour', 9)) as number
      config.workStartMinute = (await this.store.get('workStartMinute', 0)) as number
      config.workEndHour = (await this.store.get('workEndHour', 18)) as number
      config.workEndMinute = (await this.store.get('workEndMinute', 0)) as number
      config.breaksJSON = (await this.store.get('breaksJSON', '')) as string
      config.dayOverridesJSON = (await this.store.get('dayOverridesJSON', '')) as string
    } catch (err) {
      Log.error(`loadConfig failed: ${err}`)
    }
    return config
  }

  public async getFormIds(): Promise<string[]> {
    if (this.store === null) {
      return []
    }
    try {
      const raw: string = (await this.store.get('formIds', '[]')) as string
      const parsed: string[] = JSON.parse(raw) as string[]
      return Array.isArray(parsed) ? parsed : []
    } catch (err) {
      Log.error(`getFormIds failed: ${err}`)
      return []
    }
  }

  public async addFormId(formId: string): Promise<void> {
    const ids: string[] = await this.getFormIds()
    if (ids.indexOf(formId) === -1) {
      ids.push(formId)
      await this.saveFormIds(ids)
    }
  }

  public async removeFormId(formId: string): Promise<void> {
    let ids: string[] = await this.getFormIds()
    ids = ids.filter((id: string) => id !== formId)
    await this.saveFormIds(ids)
  }

  private async saveFormIds(ids: string[]): Promise<void> {
    if (this.store === null) {
      return
    }
    try {
      await this.store.put('formIds', JSON.stringify(ids))
      await this.store.flush()
    } catch (err) {
      Log.error(`saveFormIds failed: ${err}`)
    }
  }

  public async savePrivacyMode(enabled: boolean): Promise<void> {
    if (this.store === null) {
      return
    }
    try {
      await this.store.put('isPrivacyMode', enabled ? 1 : 0)
      await this.store.flush()
    } catch (err) {
      Log.error(`savePrivacyMode failed: ${err}`)
    }
  }

  public async loadPrivacyMode(): Promise<boolean> {
    if (this.store === null) {
      return false
    }
    try {
      const val: number = (await this.store.get('isPrivacyMode', 0)) as number
      return val === 1
    } catch (err) {
      Log.error(`loadPrivacyMode failed: ${err}`)
      return false
    }
  }

  // ---- Voluntary Overtime Session State ----

  public async saveVoluntaryOTActive(active: boolean): Promise<void> {
    if (this.store === null) { return }
    try {
      await this.store.put('voluntaryOTActive', active ? 1 : 0)
      await this.store.flush()
    } catch (err) {
      Log.error(`saveVoluntaryOTActive failed: ${err}`)
    }
  }

  public async loadVoluntaryOTActive(): Promise<boolean> {
    if (this.store === null) { return false }
    try {
      const val: number = (await this.store.get('voluntaryOTActive', 0)) as number
      return val === 1
    } catch (err) {
      Log.error(`loadVoluntaryOTActive failed: ${err}`)
      return false
    }
  }

  public async saveVoluntaryOTAccumulated(seconds: number): Promise<void> {
    if (this.store === null) { return }
    try {
      await this.store.put('voluntaryOTAccumulated', seconds)
      await this.store.flush()
    } catch (err) {
      Log.error(`saveVoluntaryOTAccumulated failed: ${err}`)
    }
  }

  public async loadVoluntaryOTAccumulated(): Promise<number> {
    if (this.store === null) { return 0 }
    try {
      return (await this.store.get('voluntaryOTAccumulated', 0)) as number
    } catch (err) {
      Log.error(`loadVoluntaryOTAccumulated failed: ${err}`)
      return 0
    }
  }

  public async saveVoluntaryOTDate(dateStr: string): Promise<void> {
    if (this.store === null) { return }
    try {
      await this.store.put('voluntaryOTDate', dateStr)
      await this.store.flush()
    } catch (err) {
      Log.error(`saveVoluntaryOTDate failed: ${err}`)
    }
  }

  public async loadVoluntaryOTDate(): Promise<string> {
    if (this.store === null) { return '' }
    try {
      return (await this.store.get('voluntaryOTDate', '')) as string
    } catch (err) {
      Log.error(`loadVoluntaryOTDate failed: ${err}`)
      return ''
    }
  }

  public async saveVoluntaryOTSessionStart(timestamp: number): Promise<void> {
    if (this.store === null) { return }
    try {
      await this.store.put('voluntaryOTSessionStart', timestamp)
      await this.store.flush()
    } catch (err) {
      Log.error(`saveVoluntaryOTSessionStart failed: ${err}`)
    }
  }

  public async loadVoluntaryOTSessionStart(): Promise<number> {
    if (this.store === null) { return 0 }
    try {
      return (await this.store.get('voluntaryOTSessionStart', 0)) as number
    } catch (err) {
      Log.error(`loadVoluntaryOTSessionStart failed: ${err}`)
      return 0
    }
  }

  /**
   * Computes the total voluntary OT seconds at the current moment.
   * Returns 0 if no session is active or if the stored date is stale (different day).
   * If stale, also resets the stored state.
   */
  public async voluntaryOvertimeTotalSeconds(): Promise<number> {
    const active: boolean = await this.loadVoluntaryOTActive()
    if (!active) { return 0 }

    const storedDate: string = await this.loadVoluntaryOTDate()
    const today: string = this.dateStringToday()
    if (storedDate !== today) {
      // Stale state from a previous day — reset
      await this.saveVoluntaryOTActive(false)
      await this.saveVoluntaryOTAccumulated(0)
      await this.saveVoluntaryOTDate('')
      await this.saveVoluntaryOTSessionStart(0)
      return 0
    }

    const accumulated: number = await this.loadVoluntaryOTAccumulated()
    const sessionStart: number = await this.loadVoluntaryOTSessionStart()
    const nowSec: number = Date.now() / 1000
    const sessionElapsed: number = Math.max(0, nowSec - sessionStart)
    return accumulated + sessionElapsed
  }

  /**
   * Starts a new voluntary OT session. Resets accumulated if the stored date is stale.
   */
  public async startVoluntaryOTSession(): Promise<void> {
    const today: string = this.dateStringToday()
    const storedDate: string = await this.loadVoluntaryOTDate()
    if (storedDate !== today) {
      await this.saveVoluntaryOTAccumulated(0)
      await this.saveVoluntaryOTDate(today)
    }
    const nowSec: number = Date.now() / 1000
    await this.saveVoluntaryOTSessionStart(nowSec)
    await this.saveVoluntaryOTActive(true)
  }

  /**
   * Ends the current voluntary OT session, adding its elapsed time to accumulated.
   */
  public async endVoluntaryOTSession(): Promise<void> {
    const active: boolean = await this.loadVoluntaryOTActive()
    if (!active) { return }
    const sessionStart: number = await this.loadVoluntaryOTSessionStart()
    const nowSec: number = Date.now() / 1000
    const sessionElapsed: number = Math.max(0, nowSec - sessionStart)
    const accumulated: number = await this.loadVoluntaryOTAccumulated()
    await this.saveVoluntaryOTAccumulated(accumulated + sessionElapsed)
    await this.saveVoluntaryOTActive(false)
    await this.saveVoluntaryOTSessionStart(0)
  }

  // ---- Weekly Voluntary OT Accumulation ----

  public async saveVoluntaryOTWeeklyEarnings(amount: number): Promise<void> {
    if (this.store === null) { return }
    try {
      await this.store.put('voluntaryOTWeeklyEarnings', amount)
      await this.store.flush()
    } catch (err) {
      Log.error(`saveVoluntaryOTWeeklyEarnings failed: ${err}`)
    }
  }

  public async loadVoluntaryOTWeeklyEarnings(): Promise<number> {
    if (this.store === null) { return 0 }
    try {
      return (await this.store.get('voluntaryOTWeeklyEarnings', 0)) as number
    } catch (err) {
      Log.error(`loadVoluntaryOTWeeklyEarnings failed: ${err}`)
      return 0
    }
  }

  public async saveVoluntaryOTWeekStart(dateStr: string): Promise<void> {
    if (this.store === null) { return }
    try {
      await this.store.put('voluntaryOTWeekStart', dateStr)
      await this.store.flush()
    } catch (err) {
      Log.error(`saveVoluntaryOTWeekStart failed: ${err}`)
    }
  }

  public async loadVoluntaryOTWeekStart(): Promise<string> {
    if (this.store === null) { return '' }
    try {
      return (await this.store.get('voluntaryOTWeekStart', '')) as string
    } catch (err) {
      Log.error(`loadVoluntaryOTWeekStart failed: ${err}`)
      return ''
    }
  }

  /**
   * Converts the daily accumulated OT seconds into money and adds to the weekly total.
   * Resets the daily accumulated and the stored date. Call this when a new work day begins.
   */
  public async bankDailyVoluntaryOT(secondRate: number): Promise<void> {
    const dailyOT: number = await this.loadVoluntaryOTAccumulated()
    if (dailyOT <= 0) { return }

    const monday: string = this.mondayOfWeek()
    const storedWeek: string = await this.loadVoluntaryOTWeekStart()
    if (storedWeek !== monday) {
      await this.saveVoluntaryOTWeeklyEarnings(0)
      await this.saveVoluntaryOTWeekStart(monday)
    }

    const current: number = await this.loadVoluntaryOTWeeklyEarnings()
    await this.saveVoluntaryOTWeeklyEarnings(current + dailyOT * secondRate)
    await this.saveVoluntaryOTAccumulated(0)
    await this.saveVoluntaryOTDate('')
  }

  private mondayOfWeek(): string {
    const d: Date = new Date()
    const day: number = d.getDay() // 0=Sun, 1=Mon, ..., 6=Sat
    const diff: number = day === 0 ? 6 : day - 1 // Days since Monday
    const monday: Date = new Date(d.getFullYear(), d.getMonth(), d.getDate() - diff)
    const y: number = monday.getFullYear()
    const m: number = monday.getMonth() + 1
    const dayNum: number = monday.getDate()
    return `${y}-${String(m).padStart(2, '0')}-${String(dayNum).padStart(2, '0')}`
  }

  private dateStringToday(): string {
    const d: Date = new Date()
    const y: number = d.getFullYear()
    const m: number = d.getMonth() + 1
    const day: number = d.getDate()
    return `${y}-${String(m).padStart(2, '0')}-${String(day).padStart(2, '0')}`
  }

  public async clear(): Promise<void> {
    if (this.store === null) {
      return
    }
    try {
      await this.store.clear()
      await this.store.flush()
    } catch (err) {
      Log.error(`clear failed: ${err}`)
    }
  }
}

/**
 * Plain data object for config transfer.
 */
export class ConfigData {
  public monthlyPay: number = 0
  public workingDaysPerMonth: number = 21.75
  public currency: string = '¥'
  public taxRate: number = 0
  public payDay: number = 15
  public workStartHour: number = 9
  public workStartMinute: number = 0
  public workEndHour: number = 18
  public workEndMinute: number = 0
  public breaksJSON: string = ''
  public dayOverridesJSON: string = ''
}
