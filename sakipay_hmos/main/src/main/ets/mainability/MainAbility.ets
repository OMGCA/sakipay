/* (c) Copyright XiatStudio 2026~2026 */
import { AbilityConstant, ConfigurationConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { PreferencesStore, ConfigData } from '../services/PreferencesStore'
import { FormRefresher } from '../services/FormRefresher'
import { WindowInsets } from '../services/WindowInsets'
import { EarningsCalculator, BreakScheduleEntry } from '../models/EarningsCalculator'

const DOMAIN: number = 0x0000

export default class MainAbility extends UIAbility {
  private currentColorMode: ConfigurationConstant.ColorMode =
    ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
  private savedWindowStage: window.WindowStage | undefined = undefined

  public onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('abilityContext', this.context)
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err))
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate')
  }

  public onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy')
    this.updateWidgets()
  }

  public onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate')
    this.savedWindowStage = windowStage

    const mainWindow: window.Window | undefined = windowStage.getMainWindowSync()
    if (mainWindow !== undefined) {
      mainWindow.setWindowLayoutFullScreen(true).catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to set full screen layout: %{public}s', err.message)
      })
      // Must be published before loadContent: the tab bars read this on first build.
      this.publishBottomInset(mainWindow)
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err))
        return
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.')
      this.applyImmersiveBars(windowStage)
    })
  }

  public onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy')
  }

  public onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground')
  }

  public onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground')
    this.updateWidgets()
  }

  private async updateWidgets(): Promise<void> {
    try {
      const store: PreferencesStore = new PreferencesStore()
      await store.initialise(this.context)
      const config: ConfigData = await store.loadConfig()
      let amount: string = '0.00'
      let progress: number = 0
      let status: string = 'notStarted'
      const currency: string = config.currency

      const isVoluntaryOT: boolean = await store.loadVoluntaryOTActive()
      const isPaused: boolean = await store.loadPauseMode()
      const totalOTSeconds: number = await store.voluntaryOvertimeTotalSeconds()

      if (config.monthlyPay > 0) {
        const calc: EarningsCalculator = new EarningsCalculator()
        calc.monthlyPay = config.monthlyPay
        calc.workingDaysPerMonth = config.workingDaysPerMonth
        calc.taxRate = config.taxRate
        calc.payDay = config.payDay
        calc.schedule.workStartMinutes = config.workStartHour * 60 + config.workStartMinute
        calc.schedule.workEndMinutes = config.workEndHour * 60 + config.workEndMinute
        calc.schedule.breaks = this.parseBreaksForWidget(config.breaksJSON)
        const today = calc.calculateTodayEarnings(new Date(), totalOTSeconds, isPaused)
        amount = today.amount.toFixed(2)
        progress = today.progress
        status = today.status as string
      }

      const isPrivacy: boolean = await store.loadPrivacyMode()

      const data: Record<string, string | number> = {
        'cardAmount': amount,
        'cardProgress': progress,
        'cardStatus': status,
        'cardCurrency': currency,
        'cardPrivacy': isPrivacy ? '1' : '0',
        'cardVoluntaryOT': isVoluntaryOT ? '1' : '0'
      }
      await FormRefresher.refreshForms(store, data)
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Widget update failed: %{public}s', JSON.stringify(err))
    }
  }

  private parseBreaksForWidget(breaksJSON: string): BreakScheduleEntry[] {
    if (breaksJSON.length === 0) {
      return []
    }
    try {
      const raw: object[] = JSON.parse(breaksJSON) as object[]
      const breaks: BreakScheduleEntry[] = []
      for (const item of raw) {
        const obj = item as Record<string, Object>
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
      return breaks
    } catch (e) {
      return []
    }
  }

  public onConfigurationUpdate(newConfig: Configuration): void {
    const newMode: ConfigurationConstant.ColorMode = newConfig.colorMode !== undefined
      ? newConfig.colorMode
      : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
    if (newMode !== this.currentColorMode) {
      this.currentColorMode = newMode
      if (this.savedWindowStage !== undefined) {
        this.applyImmersiveBars(this.savedWindowStage)
      }
    }
  }

  /**
   * Publishes the bottom navigation inset (in px) for the tab bars to consume.
   *
   * Kept in AppStorage rather than read from the components because the tab bars
   * need it on their first build, and window.getLastWindow() is asynchronous —
   * resolving it from inside a component lands too late. Re-published on
   * configuration change, since the inset shifts with rotation and fold state.
   */
  private publishBottomInset(mainWindow: window.Window): void {
    const px: number = WindowInsets.bottomPx(mainWindow)
    AppStorage.setOrCreate('bottomInsetPx', px)
    hilog.info(DOMAIN, 'testTag', 'Bottom navigation inset: %{public}d px', px)
  }

  private applyImmersiveBars(windowStage: window.WindowStage): void {
    const mainWindow: window.Window | undefined = windowStage.getMainWindowSync()
    if (mainWindow === undefined) {
      return
    }

    this.publishBottomInset(mainWindow)

    const isDark: boolean = this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK

    mainWindow.setWindowSystemBarProperties({
      statusBarColor: isDark ? '#000000' : '#F2F2F7',
      navigationBarColor: isDark ? '#000000' : '#F2F2F7',
      isStatusBarLightIcon: isDark,
      isNavigationBarLightIcon: isDark
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'Failed to set system bar: %{public}s', err.message)
    })
  }
}
