/* (c) Copyright XiatStudio 2026~2026 */
import { DashboardViewModel } from '../viewmodels/DashboardViewModel'
import { SettingsViewModel } from '../viewmodels/SettingsViewModel'
import { BreakSegment } from '../models/BreakSegment'
import { DayOverride, DayType, HolidayCalendarData } from '../models/HolidayCalendar'
import { HolidayCalendarService } from '../services/HolidayCalendarService'
import { Log } from '../services/Log'
import { PreferencesStore, ConfigData } from '../services/PreferencesStore'
import { EarningsCalculator, BreakScheduleEntry } from '../models/EarningsCalculator'
import { DeviceCapabilities } from '../services/DeviceCapabilities'
import { FormRefresher } from '../services/FormRefresher'
import { CalendarSheetPage } from '../views/CalendarSheetPage'
import { NativeTabsHost } from '../components/NativeTabsHost'
// Lazily imported: keeps @kit.UIDesignKit (API 20+) from ever resolving on older devices.
import lazy { HdsTabsHost } from '../components/HdsTabsHost'

@Entry
@ComponentV2
struct Index {
  @Local public dashboardVM: DashboardViewModel = new DashboardViewModel()
  @Local public settingsVM: SettingsViewModel = new SettingsViewModel()
  // Chosen once from the device API level — see services/DeviceCapabilities.ets
  @Local private useHdsTabs: boolean = false
  @Local private showCalendar: boolean = false
  @Local private calendarPopupOpacity: number = 0
  @Local private holidayCalendar: HolidayCalendarData | null = null

  public aboutToAppear(): void {
    this.useHdsTabs = DeviceCapabilities.supportsHdsTabs()
    let ctx: Context | undefined = this.getUIContext().getHostContext()
    if (ctx === undefined) {
      ctx = AppStorage.get<Context>('abilityContext')
    }
    if (ctx !== undefined) {
      const appCtx: Context = ctx

      // Load holiday calendar (bundled data)
      try {
        HolidayCalendarService.getInstance().loadBundledCalendars(appCtx)
      } catch (e) {
        Log.error(`Failed to load holiday calendar: ${e}`)
      }

      this.settingsVM.initialise(appCtx)
        .then((): Promise<void> => {
          return this.settingsVM.loadConfig()
        })
        .then((): void => {
          this.applyConfigToDashboard()
          Log.info('App initialised')
        })
        .catch((err: Error): void => {
          Log.error(`App init failed: ${err.message}`)
        })
      this.dashboardVM.initialise(appCtx).then((): void => {
        this.dashboardVM.onPrivacyToggled = (): void => {
          this.refreshWidgets(appCtx)
        }
        this.dashboardVM.onPauseToggled = (): void => {
          this.refreshWidgets(appCtx)
        }
        this.dashboardVM.onVoluntaryOvertimeToggled = (): void => {
          this.refreshWidgets(appCtx)
        }
      }).catch((err: Error): void => {
        Log.error(`DashboardVM init failed: ${err.message}`)
      })
    } else {
      Log.error('Failed to get context — config will not be loaded or saved')
    }
    this.holidayCalendar = HolidayCalendarService.getInstance().currentCalendar()
  }

  /**
   * Fires each time the page comes to the foreground. The widget toggles privacy
   * and voluntary OT from its own process, so the app must drop its cached
   * Preferences copy and re-read those flags on re-entry — otherwise it shows
   * (and later persists) its stale values, flipping the widget's toggle back.
   */
  public onPageShow(): void {
    this.dashboardVM.reloadToggles().catch((err: Error): void => {
      Log.error(`Foreground toggle reload failed: ${err.message}`)
    })
  }

  private onShowCalendar(): void {
    this.showCalendar = true
    this.calendarPopupOpacity = 0
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      this.calendarPopupOpacity = 1
    })
  }

  private onDismissCalendar(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
      this.calendarPopupOpacity = 0
    })
    setTimeout(() => {
      this.showCalendar = false
    }, 210)
  }

  public build(): void {
    Stack() {
      if (this.useHdsTabs) {
        HdsTabsHost({
          dashboardVM: this.dashboardVM,
          settingsVM: this.settingsVM,
          onSaved: (): void => {
            this.applyConfigToDashboard()
          },
          onCalendarSaved: (): void => {
            this.applyConfigToDashboard()
          },
          onShowCalendar: (): void => {
            this.onShowCalendar()
          }
        })
      } else {
        NativeTabsHost({
          dashboardVM: this.dashboardVM,
          settingsVM: this.settingsVM,
          onSaved: (): void => {
            this.applyConfigToDashboard()
          },
          onCalendarSaved: (): void => {
            this.applyConfigToDashboard()
          },
          onShowCalendar: (): void => {
            this.onShowCalendar()
          }
        })
      }

      // Calendar popup overlay (above tab bar)
      if (this.showCalendar) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.4)')
            .opacity(this.calendarPopupOpacity)
            .onClick(() => { this.onDismissCalendar() })

          Column() {
            CalendarSheetPage({
              holidayCalendar: this.holidayCalendar,
              dayOverrides: this.settingsVM.dayOverrides,
              workTotalHours: this.settingsVM.getTotalWorkHours(),
              onOverrideSaved: (override: DayOverride): void => {
                this.settingsVM.addOrUpdateOverride(override)
                this.settingsVM.saveConfig().then((success: boolean) => {
                  if (success) {
                    this.applyConfigToDashboard()
                  }
                })
              },
              onOverrideReset: (dateString: string): void => {
                this.settingsVM.removeOverride(dateString)
                this.settingsVM.saveConfig().then((success: boolean) => {
                  if (success) {
                    this.applyConfigToDashboard()
                  }
                })
              },
              onClose: (): void => { this.onDismissCalendar() }
            })
          }
          .width('92%')
          .margin({ top: 80, bottom: 40 })
          .opacity(this.calendarPopupOpacity)
          .scale({ x: this.calendarPopupOpacity * 0.05 + 0.95, y: this.calendarPopupOpacity * 0.05 + 0.95 })
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
        .zIndex(1000)
      }
    }
  }

  private applyConfigToDashboard(): void {
    const breaks: BreakSegment[] = this.settingsVM.breakSegments
    const holidayCalendar = HolidayCalendarService.getInstance().currentCalendar()
    const overrides: DayOverride[] = this.settingsVM.dayOverrides
    const effectiveWorkingDays: number = this.settingsVM.useCalibratedWorkDays
      ? this.settingsVM.calibratedWorkingDays
      : this.settingsVM.workingDays
    this.dashboardVM.configure(
      parseFloat(this.settingsVM.monthlyPayText) || 0,
      effectiveWorkingDays,
      this.settingsVM.currency,
      this.settingsVM.taxRate,
      this.settingsVM.payDay,
      this.settingsVM.workStartH,
      this.settingsVM.workStartM,
      this.settingsVM.workEndH,
      this.settingsVM.workEndM,
      breaks,
      holidayCalendar,
      overrides
    )
  }

  /**
   * Pushes current earnings + privacy state to all running widget instances.
   * Called immediately when the user toggles privacy mode.
   */
  private async refreshWidgets(ctx: Context): Promise<void> {
    try {
      const store: PreferencesStore = PreferencesStore.shared()
      await store.initialise(ctx)
      const config: ConfigData = await store.loadConfig()
      const isPrivacy: boolean = await store.loadPrivacyMode()
      const isVoluntaryOT: boolean = await store.loadVoluntaryOTActive()
      const isPaused: boolean = await store.loadPauseMode()
      const totalOTSeconds: number = await store.voluntaryOvertimeTotalSeconds()

      let amount: string = '0.00'
      let progress: number = 0
      let status: string = 'notStarted'
      const currency: string = config.currency

      if (config.monthlyPay > 0) {
        const calc: EarningsCalculator = new EarningsCalculator()
        calc.monthlyPay = config.monthlyPay
        calc.workingDaysPerMonth = config.workingDaysPerMonth
        calc.taxRate = config.taxRate
        calc.payDay = config.payDay
        calc.schedule.workStartMinutes = config.workStartHour * 60 + config.workStartMinute
        calc.schedule.workEndMinutes = config.workEndHour * 60 + config.workEndMinute
        calc.schedule.breaks = this.parseBreaksForWidget(config.breaksJSON)

        // Load holiday calendar
        try {
          HolidayCalendarService.getInstance().loadBundledCalendars(ctx)
          calc.holidayCalendar = HolidayCalendarService.getInstance().currentCalendar()
        } catch (e) {
          // Calendar unavailable — calculator falls back to weekend check
        }

        // Load day overrides
        this.loadDayOverridesForWidget(calc, config.dayOverridesJSON)

        const today = calc.calculateTodayEarnings(new Date(), totalOTSeconds, isPaused)
        amount = today.amount.toFixed(2)
        progress = today.progress
        status = today.status as string
      }

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
      Log.error(`Widget refresh failed: ${err}`)
    }
  }

  private loadDayOverridesForWidget(calc: EarningsCalculator, dayOverridesJSON: string): void {
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
      Log.error(`Widget parse day overrides: ${e}`)
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
      return breaks
    } catch (e) {
      return []
    }
  }
}
