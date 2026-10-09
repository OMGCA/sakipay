/* (c) Copyright XiatStudio 2026~2026 */
import { DashboardViewModel } from '../viewmodels/DashboardViewModel'
import { SettingsViewModel } from '../viewmodels/SettingsViewModel'
import { DashboardPage } from '../views/DashboardPage'
import { SettingsPage } from '../views/SettingsPage'
import { TabBarItem } from './TabBarItem'

type VoidCallback = () => void

/** Bar height without the navigation inset. */
const BAR_HEIGHT_BASE: number = 64

/**
 * Tab shell built on the framework Tabs container.
 *
 * Used on devices below API 20, where the UI Design Kit HdsTabs container does not
 * exist. Same pages, same tab bar items — the bar itself is a plain bottom bar
 * rather than the floating one HdsTabs provides.
 *
 * The app runs full-screen, so the framework does not keep the bar clear of the
 * system navigation bar; the measured bottom inset is added to both barHeight and
 * the item padding so the bar background still reaches the screen edge.
 */
@ComponentV2
export struct NativeTabsHost {
  @Require @Param public dashboardVM: DashboardViewModel
  @Require @Param public settingsVM: SettingsViewModel
  @Require @Param public onSaved: VoidCallback
  @Require @Param public onCalendarSaved: VoidCallback
  @Require @Param public onShowCalendar: VoidCallback

  @Local private controller: TabsController = new TabsController()
  @Local private currentIndex: number = 0

  /**
   * Bottom navigation inset in vp, published by MainAbility before the page loads.
   *
   * Read on every build rather than cached in an @Local: window.getLastWindow() is
   * asynchronous, so resolving this from inside the component (or its aboutToAppear)
   * lands after the tab bar has already been laid out and silently does nothing.
   */
  private navInsetVp(): number {
    const px: number = AppStorage.get<number>('bottomInsetPx') ?? 0
    return px > 0 ? px2vp(px) : 0
  }

  public build(): void {
    Tabs({ barPosition: BarPosition.End, controller: this.controller }) {
      TabContent() {
        DashboardPage({
          viewModel: this.dashboardVM,
          onNavigateToSettings: (): void => {
            this.controller.changeIndex(1)
          }
        })
      }
      .tabBar(this.homeTab)

      TabContent() {
        SettingsPage({
          viewModel: this.settingsVM,
          onSaved: (): void => {
            this.onSaved()
            this.controller.changeIndex(0)
          },
          onCalendarSaved: (): void => {
            this.onCalendarSaved()
          },
          onShowCalendar: (): void => {
            this.onShowCalendar()
          }
        })
      }
      .tabBar(this.settingsTab)
    }
    .barHeight(BAR_HEIGHT_BASE + this.navInsetVp())
    .barBackgroundColor($r('app.color.glass_overlay'))
    .barBackgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
    .onChange((index: number): void => {
      this.currentIndex = index
    })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private homeTab(): void {
    Column() {
      TabBarItem({
        symbolOn: $r('sys.symbol.house_fill'),
        symbolOff: $r('sys.symbol.house'),
        label: '今日',
        active: this.currentIndex === 0
      })
    }
    .padding({ bottom: this.navInsetVp() })
  }

  @Builder
  private settingsTab(): void {
    Column() {
      TabBarItem({
        symbolOn: $r('sys.symbol.gearshape_fill'),
        symbolOff: $r('sys.symbol.gearshape'),
        label: '设置',
        active: this.currentIndex === 1
      })
    }
    .padding({ bottom: this.navInsetVp() })
  }
}
