/* (c) Copyright XiatStudio 2026~2026 */
import { formBindingData, formInfo, formProvider, FormExtensionAbility } from '@kit.FormKit'
import { ConfigData, PreferencesStore } from '../services/PreferencesStore'
import { EarningsCalculator, TodayEarnings, BreakScheduleEntry } from '../models/EarningsCalculator'
import { Log } from '../services/Log'

export default class SakipayFormAbility extends FormExtensionAbility {
  private store: PreferencesStore = new PreferencesStore()

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
      const config: ConfigData = await this.store.loadConfig()

      let cardAmount: string = '0.00'
      let cardProgress: number = 0
      let cardStatus: string = 'notStarted'
      let cardCurrency: string = config.currency

      if (config.monthlyPay > 0) {
        const calc: EarningsCalculator = this.buildCalculator(config)
        const today: TodayEarnings = calc.calculateTodayEarnings()
        cardAmount = today.amount.toFixed(2)
        cardProgress = today.progress
        cardStatus = today.status as string
      }

      const isPrivacy: boolean = await this.store.loadPrivacyMode()

      const updateData: Record<string, string | number> = {
        'cardAmount': cardAmount,
        'cardProgress': cardProgress,
        'cardStatus': cardStatus,
        'cardCurrency': cardCurrency,
        'cardPrivacy': isPrivacy ? '1' : '0'
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
      }
    } catch (err) {
      Log.error(`onFormEvent parse failed: ${err}`)
    }
  }

  private async handlePrivacyToggle(formId: string): Promise<void> {
    try {
      const current: boolean = await this.store.loadPrivacyMode()
      await this.store.savePrivacyMode(!current)
      await this.onUpdateForm(formId)
    } catch (err) {
      Log.error(`handlePrivacyToggle failed: ${err}`)
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
    const calc: EarningsCalculator = new EarningsCalculator()
    calc.monthlyPay = config.monthlyPay
    calc.workingDaysPerMonth = config.workingDaysPerMonth
    calc.taxRate = config.taxRate
    calc.payDay = config.payDay
    calc.schedule.workStartMinutes = config.workStartHour * 60 + config.workStartMinute
    calc.schedule.workEndMinutes = config.workEndHour * 60 + config.workEndMinute

    if (config.breaksJSON.length > 0) {
      try {
        const raw: object[] = JSON.parse(config.breaksJSON) as object[]
        const breaks: BreakScheduleEntry[] = []
        for (const item of raw) {
          const obj: Record<string, Object> = item as Record<string, Object>
          const sh: number = obj.startHour as number ?? 0
          const sm: number = obj.startMinute as number ?? 0
          const eh: number = obj.endHour as number ?? 0
          const em: number = obj.endMinute as number ?? 0
          const startMin: number = sh * 60 + sm
          const endMin: number = eh * 60 + em
          if (endMin > startMin) {
            const entry: BreakScheduleEntry = new BreakScheduleEntry()
            entry.startMinutes = startMin
            entry.endMinutes = endMin
            breaks.push(entry)
          }
        }
        calc.schedule.breaks = breaks
      } catch (e) {
        Log.error(`Widget parse breaks: ${e}`)
      }
    }
    return calc
  }
}
