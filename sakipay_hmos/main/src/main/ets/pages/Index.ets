/* (c) Copyright XiatStudio 2026~2026 */
import { DashboardViewModel } from '../viewmodels/DashboardViewModel'
import { SettingsViewModel } from '../viewmodels/SettingsViewModel'
import { DashboardPage } from '../views/DashboardPage'
import { SettingsPage } from '../views/SettingsPage'
import { BreakSegment } from '../models/BreakSegment'
import { Log } from '../services/Log'
import { PreferencesStore, ConfigData } from '../services/PreferencesStore'
import { EarningsCalculator, BreakScheduleEntry } from '../models/EarningsCalculator'
import { formProvider, formBindingData, formInfo } from '@kit.FormKit'
import { HdsTabs, HdsTabsController } from '@kit.UIDesignKit'

@Entry
@ComponentV2
struct Index {
  @Local public dashboardVM: DashboardViewModel = new DashboardViewModel()
  @Local public settingsVM: SettingsViewModel = new SettingsViewModel()
  private tabsController: HdsTabsController = new HdsTabsController()
  @Local private activeIndex: number = 0

  public aboutToAppear(): void {
    let ctx: Context | undefined = this.getUIContext().getHostContext()
    if (ctx === undefined) {
      ctx = AppStorage.get<Context>('abilityContext')
    }
    if (ctx !== undefined) {
      const appCtx: Context = ctx
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
      }).catch((err: Error): void => {
        Log.error(`DashboardVM init failed: ${err.message}`)
      })
    } else {
      Log.error('Failed to get context — config will not be loaded or saved')
    }
  }

  public build(): void {
    HdsTabs({ controller: this.tabsController }) {
      TabContent() {
        DashboardPage({
          viewModel: this.dashboardVM,
          onNavigateToSettings: (): void => {
            this.tabsController.changeIndex(1)
          }
        })
      }
      .tabBar(this.homeTab)

      TabContent() {
        SettingsPage({
          viewModel: this.settingsVM,
          onSaved: (): void => {
            this.applyConfigToDashboard()
            this.tabsController.changeIndex(0)
          }
        })
      }
      .tabBar(this.settingsTab)
    }
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .onChange((index: number): void => {
      this.activeIndex = index
    })
    .barFloatingStyle({
      barWidth: { smallWidth: 148, mediumWidth: 180, largeWidth: 212 },
      barBottomMargin: 28,
      gradientMask: { maskColor: $r('app.color.page_background'), maskHeight: 92 },
      systemMaterialEffect: {
        materialType: 100,
        materialLevel: 10
      }
    })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private homeTab(): void {
    Column({ space: 2 }) {
      SymbolGlyph(this.activeIndex === 0 ? $r('sys.symbol.house_fill') : $r('sys.symbol.house'))
        .fontSize(20)
        .fontColor([this.activeIndex === 0 ? $r('app.color.accent_blue') : $r('app.color.text_tertiary')])
      Text('今日')
        .fontSize(10)
        .fontWeight(this.activeIndex === 0 ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.activeIndex === 0 ? $r('app.color.accent_blue') : $r('app.color.text_tertiary'))
    }
    .width(68)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private settingsTab(): void {
    Column({ space: 2 }) {
      SymbolGlyph(this.activeIndex === 1 ? $r('sys.symbol.gearshape_fill') : $r('sys.symbol.gearshape'))
        .fontSize(20)
        .fontColor([this.activeIndex === 1 ? $r('app.color.accent_blue') : $r('app.color.text_tertiary')])
      Text('设置')
        .fontSize(10)
        .fontWeight(this.activeIndex === 1 ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.activeIndex === 1 ? $r('app.color.accent_blue') : $r('app.color.text_tertiary'))
    }
    .width(68)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private applyConfigToDashboard(): void {
    const breaks: BreakSegment[] = this.settingsVM.breakSegments
    this.dashboardVM.configure(
      parseFloat(this.settingsVM.monthlyPayText) || 0,
      this.settingsVM.workingDays,
      this.settingsVM.currency,
      this.settingsVM.taxRate,
      this.settingsVM.payDay,
      this.settingsVM.workStartH,
      this.settingsVM.workStartM,
      this.settingsVM.workEndH,
      this.settingsVM.workEndM,
      breaks
    )
  }

  /**
   * Pushes current earnings + privacy state to all running widget instances.
   * Called immediately when the user toggles privacy mode.
   */
  private async refreshWidgets(ctx: Context): Promise<void> {
    try {
      const runningForms: formInfo.RunningFormInfo[] = await formProvider.getPublishedRunningFormInfos()
      if (runningForms.length === 0) {
        return
      }
      const store: PreferencesStore = new PreferencesStore()
      await store.initialise(ctx)
      const config: ConfigData = await store.loadConfig()
      const isPrivacy: boolean = await store.loadPrivacyMode()

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
        const today = calc.calculateTodayEarnings()
        amount = today.amount.toFixed(2)
        progress = today.progress
        status = today.status as string
      }

      const data: Record<string, string | number> = {
        'cardAmount': amount,
        'cardProgress': progress,
        'cardStatus': status,
        'cardCurrency': currency,
        'cardPrivacy': isPrivacy ? '1' : '0'
      }
      const fbData: formBindingData.FormBindingData = formBindingData.createFormBindingData(data)
      for (const f of runningForms) {
        await formProvider.updateForm(f.formId, fbData)
      }
    } catch (err) {
      Log.error(`Widget refresh failed: ${err}`)
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
