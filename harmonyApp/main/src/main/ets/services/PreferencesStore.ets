/* (c) Copyright XiatStudio 2026~2026 */
import { preferences } from '@kit.ArkData'
import { Log } from './Log'
import { NativeBridge, VoluntaryOvertimeTotalResult } from './NativeBridge'

const STORE_NAME: string = 'sakipay_config'

/** The persisted shape of the voluntary-overtime state machine. */
interface OtStateJson {
  active: boolean
  accumulatedSeconds: number
  dateString: string
  sessionStartEpochSeconds: number
  weeklyEarnings: number
  weekStart: string
}

/**
 * Wraps @ohos.data.preferences for persistent key-value config storage.
 *
 * Config scalars and the breaks/overrides JSON are stored as plain values. The
 * voluntary-overtime state machine lives in the shared Kotlin logic; this store
 * only marshals its persisted fields to and from the Kotlin state document.
 */
export class PreferencesStore {
  private static sharedInstance: PreferencesStore | null = null
  private store: preferences.Preferences | null = null
  private appContext: Context | null = null

  /**
   * Process-wide store. The app and the widget already share a single underlying
   * Preferences file, and keeping every holder in a process on the same instance
   * means one reload() is seen by all of them.
   */
  public static shared(): PreferencesStore {
    if (PreferencesStore.sharedInstance === null) {
      PreferencesStore.sharedInstance = new PreferencesStore()
    }
    return PreferencesStore.sharedInstance
  }

  public async initialise(context: Context): Promise<void> {
    this.appContext = context
    try {
      this.store = await preferences.getPreferences(context, STORE_NAME)
      Log.info('PreferencesStore initialised')
    } catch (err) {
      Log.error(`PreferencesStore init failed: ${err}`)
    }
  }

  /**
   * Drops this process's cached copy and re-reads the persisted file.
   *
   * The widget (FormExtensionAbility) and the app (UIAbility) run in separate
   * processes, and each caches its own Preferences instance in memory. A value
   * flushed by one process is invisible to the other until its cache is dropped,
   * so any cross-process read must reload first — otherwise the reader returns
   * its stale copy and the next flush silently persists that over the other
   * side's change.
   *
   * Call this at every point where one side reads state the other may have
   * written (app foreground, widget update, widget toggle).
   */
  public async reload(): Promise<void> {
    if (this.appContext === null) {
      return
    }
    try {
      const options: preferences.Options = { name: STORE_NAME }
      await preferences.removePreferencesFromCache(this.appContext, options)
      // Hold the old reference until the fresh one is ready rather than nulling it:
      // an in-flight read (the 5s dashboard refresh) may land in this window and must
      // not dereference null. The stale instance is only read, never written, here.
      this.store = await preferences.getPreferences(this.appContext, STORE_NAME)
    } catch (err) {
      Log.error(`PreferencesStore reload failed: ${err}`)
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

  // ---- Pause Mode ----

  /**
   * Persists the user-armed pause. Sticky: it stays on across days and app launches until the
   * user switches it off again via the same control.
   */
  public async savePauseMode(paused: boolean): Promise<void> {
    if (this.store === null) { return }
    try {
      await this.store.put('isPaused', paused ? 1 : 0)
      await this.store.flush()
    } catch (err) {
      Log.error(`savePauseMode failed: ${err}`)
    }
  }

  public async loadPauseMode(): Promise<boolean> {
    if (this.store === null) { return false }
    try {
      const val: number = (await this.store.get('isPaused', 0)) as number
      return val === 1
    } catch (err) {
      Log.error(`loadPauseMode failed: ${err}`)
      return false
    }
  }

  // ---- Voluntary Overtime Session State ----
  //
  // Every transition is performed by the shared Kotlin logic. This store only
  // marshals the persisted fields to/from the Kotlin state document, so the app
  // and the widget settle overtime identically no matter where it is toggled.

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

  public async loadVoluntaryOTWeeklyEarnings(): Promise<number> {
    if (this.store === null) { return 0 }
    try {
      return (await this.store.get('voluntaryOTWeeklyEarnings', 0)) as number
    } catch (err) {
      Log.error(`loadVoluntaryOTWeeklyEarnings failed: ${err}`)
      return 0
    }
  }

  /**
   * Computes the total voluntary OT seconds for the live moment. A session left
   * over from a previous day is finished, so the shared logic clears it.
   */
  public async voluntaryOvertimeTotalSeconds(): Promise<number> {
    const stateJson: string = await this.readOtStateJson()
    const result: VoluntaryOvertimeTotalResult =
      NativeBridge.otTotalSeconds(stateJson, NativeBridge.nowMillis(), true)
    await this.writeOtStateJson(result.state)
    return result.seconds
  }

  public async startVoluntaryOTSession(): Promise<void> {
    const stateJson: string = await this.readOtStateJson()
    const next: string = NativeBridge.otStart(stateJson, NativeBridge.nowMillis())
    await this.writeOtStateJson(next)
  }

  /**
   * Ends the current session and settles the day's total into the weekly pool at
   * [secondRate]. The settle lives in the shared logic so the weekly figure
   * updates wherever OT is ended (app or widget).
   */
  public async endVoluntaryOTSession(secondRate: number): Promise<void> {
    const stateJson: string = await this.readOtStateJson()
    const next: string = NativeBridge.otEnd(stateJson, NativeBridge.nowMillis(), secondRate)
    await this.writeOtStateJson(next)
  }

  /**
   * Converts the day's accumulated OT seconds into money and adds to the weekly
   * total. Call when a new work day begins.
   */
  public async bankDailyVoluntaryOT(secondRate: number): Promise<void> {
    const stateJson: string = await this.readOtStateJson()
    const next: string = NativeBridge.otBankDaily(stateJson, NativeBridge.nowMillis(), secondRate)
    await this.writeOtStateJson(next)
  }

  private async readOtStateJson(): Promise<string> {
    if (this.store === null) {
      return JSON.stringify(PreferencesStore.emptyOtState())
    }
    try {
      const state: OtStateJson = {
        active: ((await this.store.get('voluntaryOTActive', 0)) as number) === 1,
        accumulatedSeconds: (await this.store.get('voluntaryOTAccumulated', 0)) as number,
        dateString: (await this.store.get('voluntaryOTDate', '')) as string,
        sessionStartEpochSeconds: (await this.store.get('voluntaryOTSessionStart', 0)) as number,
        weeklyEarnings: (await this.store.get('voluntaryOTWeeklyEarnings', 0)) as number,
        weekStart: (await this.store.get('voluntaryOTWeekStart', '')) as string
      }
      return JSON.stringify(state)
    } catch (err) {
      Log.error(`readOtStateJson failed: ${err}`)
      return JSON.stringify(PreferencesStore.emptyOtState())
    }
  }

  private async writeOtStateJson(json: string): Promise<void> {
    if (this.store === null) { return }
    try {
      const s: OtStateJson = JSON.parse(json) as OtStateJson
      await this.store.put('voluntaryOTActive', s.active ? 1 : 0)
      await this.store.put('voluntaryOTAccumulated', s.accumulatedSeconds)
      await this.store.put('voluntaryOTDate', s.dateString)
      await this.store.put('voluntaryOTSessionStart', s.sessionStartEpochSeconds)
      await this.store.put('voluntaryOTWeeklyEarnings', s.weeklyEarnings)
      await this.store.put('voluntaryOTWeekStart', s.weekStart)
      await this.store.flush()
    } catch (err) {
      Log.error(`writeOtStateJson failed: ${err}`)
    }
  }

  private static emptyOtState(): OtStateJson {
    const state: OtStateJson = {
      active: false,
      accumulatedSeconds: 0,
      dateString: '',
      sessionStartEpochSeconds: 0,
      weeklyEarnings: 0,
      weekStart: ''
    }
    return state
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
