/* (c) Copyright XiatStudio 2026~2026 */
import { AbilityConstant, ConfigurationConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { PreferencesStore, ConfigData } from '../services/PreferencesStore'
import { FormRefresher } from '../services/FormRefresher'
import { WindowInsets } from '../services/WindowInsets'
import { EarningsCalculator, BreakScheduleEntry } from '../models/EarningsCalculator'
import { DayOverride, DayType } from '../models/HolidayCalendar'
import { HolidayCalendarService } from '../services/HolidayCalendarService'

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
      // Read the launch colour mode here. onConfigurationUpdate only fires on a
      // *change*, so a device already in dark mode when the app starts never
      // triggers it and the bars would be themed light against a black UI.
      const launchConfig: Configuration = this.context.config
      if (launchConfig.colorMode !== undefined) {
        this.currentColorMode = launchConfig.colorMode
      }

      mainWindow.setWindowLayoutFullScreen(true).catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to set full screen layout: %{public}s', err.message)
      })
      // Must run before loadContent, not from its callback: this publishes the
      // bottom inset the tab bars read on their first build, and gets the system
      // bars configured before the first frame is drawn rather than a frame later.
      this.applyImmersiveBars(windowStage)
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err))
        return
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.')
    })
  }

  public onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy')
  }

  public onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground')
    // The widget writes privacy/pause/OT from its own process. Drop the app's
    // cached Preferences copy so the page's re-read sees the widget's changes
    // instead of the app's stale values.
    PreferencesStore.shared().reload().catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'Foreground preferences reload failed: %{public}s', err.message)
    })
  }

  public onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground')
    this.updateWidgets()
  }

  private async updateWidgets(): Promise<void> {
    try {
      const store: PreferencesStore = PreferencesStore.shared()
      await store.initialise(this.context)
      // Read from the persisted file, not this process's cached copy, so the push
      // reflects any toggle the widget made rather than reverting it.
      await store.reload()
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
        // The holiday calendar and day overrides decide what counts as a rest day, so the
        // background push must load them too — otherwise it falls back to the weekend-only
        // check and a weekday public holiday is pushed to the widget as a working day.
        this.applyHolidayCalendar(calc)
        this.applyDayOverrides(calc, config.dayOverridesJSON)
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

  private applyHolidayCalendar(calc: EarningsCalculator): void {
    try {
      HolidayCalendarService.getInstance().loadBundledCalendars(this.context)
      calc.holidayCalendar = HolidayCalendarService.getInstance().currentCalendar()
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'Widget load holiday calendar: %{public}s', JSON.stringify(e))
    }
  }

  private applyDayOverrides(calc: EarningsCalculator, dayOverridesJSON: string): void {
    if (dayOverridesJSON.length === 0) {
      return
    }
    try {
      const arr: object[] = JSON.parse(dayOverridesJSON) as object[]
      const overrides: Map<string, DayOverride> = new Map()
      for (const item of arr) {
        const obj: Record<string, Object> = item as Record<string, Object>
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
        overrides.set(override.dateString, override)
      }
      calc.dayOverrides = overrides
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'Widget parse day overrides: %{public}s', JSON.stringify(e))
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

    // Transparent bars, never painted ones. The window lays out full-screen, so
    // whatever the page draws is already behind these regions — painting an opaque
    // colour turns the bar into a plate that ignores it. That showed up as the status
    // bar sitting on a fixed grey over every page, and as dragging the control centre
    // down dimming the app content while the bar went stark white instead of dimming
    // with it.
    //
    // The glyph colour is set explicitly rather than through isStatusBarLightIcon:
    // that flag only selects HarmonyOS's default "dark" variant, which renders
    // mid-grey and reads washed out next to the true black iOS draws on the very same
    // page background. Setting the content colour also overrides the light-icon flags,
    // so those are deliberately absent rather than left in as dead config.
    mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      statusBarContentColor: isDark ? '#FFFFFFFF' : '#FF000000',
      navigationBarContentColor: isDark ? '#FFFFFFFF' : '#FF000000'
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'Failed to set system bar: %{public}s', err.message)
    })
  }
}
