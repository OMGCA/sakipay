/* (c) Copyright XiatStudio 2026~2026 */
import { formBindingData, formInfo, formProvider, FormExtensionAbility } from '@kit.FormKit'
import { ConfigData, PreferencesStore } from '../services/PreferencesStore'
import { EarningsCalculator, TodayEarnings } from '../models/EarningsCalculator'
import { NativeBridge } from '../services/NativeBridge'
import { Log } from '../services/Log'

export default class SakipayFormAbility extends FormExtensionAbility {
  private store: PreferencesStore = PreferencesStore.shared()

  public onAddForm(want: Record<string, Object>): formBindingData.FormBindingData {
    Log.info('Widget added')
    const params: Record<string, Object> = want['parameters'] as Record<string, Object> ?? {}
    const formId: string = (params[formInfo.FormParam.IDENTITY_KEY] as string) ?? ''
    if (formId.length > 0) {
      this.store.initialise(this.context).then((): void => {
        this.store.addFormId(formId)
      })
    }
    const initial: Record<string, string | number> = {
      'cardAmount': '--',
      'cardProgress': 0,
      'cardStatus': 'loading',
      'cardCurrency': '¥',
      'cardPrivacy': '0'
    }
    return formBindingData.createFormBindingData(initial)
  }

  public async onUpdateForm(formId: string): Promise<void> {
    Log.info(`Widget update: ${formId}`)
    try {
      await this.store.initialise(this.context)
      // Reload from the persisted file: the app runs in its own process, so its
      // toggle writes are invisible to this process's cached Preferences copy.
      await this.store.reload()
      const config: ConfigData = await this.store.loadConfig()

      let cardAmount: string = '0.00'
      let cardProgress: number = 0
      let cardStatus: string = 'notStarted'
      let cardCurrency: string = config.currency

      const isVoluntaryOT: boolean = await this.store.loadVoluntaryOTActive()
      const isPaused: boolean = await this.store.loadPauseMode()
      const totalOTSeconds: number = await this.store.voluntaryOvertimeTotalSeconds()

      if (config.monthlyPay > 0) {
        const calc: EarningsCalculator = this.buildCalculator(config)
        const today: TodayEarnings = calc.calculateTodayEarnings(new Date(), totalOTSeconds, isPaused)
        cardAmount = today.amount.toFixed(2)
        cardProgress = today.progress
        cardStatus = today.status as string
      }

      const isPrivacy: boolean = await this.store.loadPrivacyMode()

      const updateData: Record<string, string | number> = {
        'cardAmount': cardAmount,
        'cardProgress': cardProgress,
        'cardStatus': cardStatus,
        'cardStatusText': NativeBridge.statusText(cardStatus),
        'cardCurrency': cardCurrency,
        'cardPrivacy': isPrivacy ? '1' : '0',
        'cardVoluntaryOT': isVoluntaryOT ? '1' : '0'
      }

      const formData: formBindingData.FormBindingData = formBindingData.createFormBindingData(updateData)
      await formProvider.updateForm(formId, formData)
    } catch (err) {
      Log.error(`Widget update failed: ${err}`)
    }
  }

  public onFormEvent(formId: string, message: string): void {
    Log.info(`Widget event: ${formId} ${message}`)
    try {
      const parsed: Record<string, Object> = JSON.parse(message) as Record<string, Object>
      if (parsed.message === 'togglePrivacy') {
        this.store.initialise(this.context).then((): void => {
          this.handlePrivacyToggle(formId)
        })
      } else if (parsed.message === 'toggleVoluntaryOvertime') {
        this.store.initialise(this.context).then((): void => {
          this.handleVoluntaryOvertimeToggle(formId)
        })
      }
    } catch (err) {
      Log.error(`onFormEvent parse failed: ${err}`)
    }
  }

  private async handlePrivacyToggle(formId: string): Promise<void> {
    try {
      // Reload first so the flip is based on the persisted value, not a stale
      // cache that could re-apply an old state.
      await this.store.reload()
      const current: boolean = await this.store.loadPrivacyMode()
      await this.store.savePrivacyMode(!current)
      await this.onUpdateForm(formId)
    } catch (err) {
      Log.error(`handlePrivacyToggle failed: ${err}`)
    }
  }

  private async handleVoluntaryOvertimeToggle(formId: string): Promise<void> {
    try {
      await this.store.reload()
      const current: boolean = await this.store.loadVoluntaryOTActive()
      if (current) {
        // Settle the session into the weekly pool at the same per-second rate the app
        // uses, derived from the stored config.
        const config: ConfigData = await this.store.loadConfig()
        const calc: EarningsCalculator = this.buildCalculator(config)
        await this.store.endVoluntaryOTSession(calc.secondRate)
      } else {
        await this.store.startVoluntaryOTSession()
      }
      await this.onUpdateForm(formId)
    } catch (err) {
      Log.error(`handleVoluntaryOvertimeToggle failed: ${err}`)
    }
  }

  public onRemoveForm(formId: string): void {
    Log.info(`Widget removed: ${formId}`)
    this.store.initialise(this.context).then((): void => {
      this.store.removeFormId(formId)
    })
  }

  public onCastToNormalForm(formId: string): void {
    Log.info(`Widget cast: ${formId}`)
  }

  public onAcquireFormState(want: Record<string, Object>): formInfo.FormState {
    return formInfo.FormState.READY
  }

  private buildCalculator(config: ConfigData): EarningsCalculator {
    // Hand the stored config straight to the shared logic.
    const calc: EarningsCalculator = new EarningsCalculator()
    calc.configureFromConfigJson(NativeBridge.composeConfigJson(
      config.monthlyPay, config.currency, config.payDay, config.taxRate, config.workingDaysPerMonth,
      config.workStartHour, config.workStartMinute, config.workEndHour, config.workEndMinute,
      config.breaksJSON, config.dayOverridesJSON, false
    ))
    return calc
  }
}
