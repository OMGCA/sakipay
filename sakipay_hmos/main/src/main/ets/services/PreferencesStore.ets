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
}
