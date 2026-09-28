/* (c) Copyright XiatStudio 2026~2026 */
import { HdsTabs, HdsTabsController } from '@kit.UIDesignKit'
import { DashboardViewModel } from '../viewmodels/DashboardViewModel'
import { SettingsViewModel } from '../viewmodels/SettingsViewModel'
import { DashboardPage } from '../views/DashboardPage'
import { SettingsPage } from '../views/SettingsPage'
import { TabBarItem } from './TabBarItem'
import { DeviceCapabilities } from '../services/DeviceCapabilities'

type VoidCallback = () => void

/**
 * Tab shell built on the UI Design Kit HdsTabs container — API 20 (6.0.0(20)) and above.
 *
 * IMPORTANT: this is the only module in the project that imports @kit.UIDesignKit.
 * Index.ets imports this file *lazily* so that on devices below API 20 the kit is
 * never resolved and the Hds components are never referenced.
 *
 * The floating tab bar (barFloatingStyle) is API 23 (6.1.0(23)); on API 20-22 the
 * same tabs render with a plain bar.
 *
 * HdsTabs does no safe-area avoidance of its own, and the two bar styles need two
 * different remedies:
 *
 *   - Floating (API 23+) — positioned with barBottomMargin.
 *   - Plain (API 20-22) — barBottomMargin does not exist, and padding the tab items
 *     has no effect either: the plain bar keeps a fixed height and ignores it. The
 *     only thing that moves it is shrinking the container, so that branch reserves
 *     the inset below the HdsTabs and fills the gap with the bar's own background
 *     so the bar still appears to reach the screen edge.
 */
@ComponentV2
export struct HdsTabsHost {
  @Require @Param public dashboardVM: DashboardViewModel
  @Require @Param public settingsVM: SettingsViewModel
  @Require @Param public onSaved: VoidCallback
  @Require @Param public onCalendarSaved: VoidCallback
  @Require @Param public onShowCalendar: VoidCallback

  @Local private controller: HdsTabsController = new HdsTabsController()
  @Local private currentIndex: number = 0

  private floatingBar: boolean = DeviceCapabilities.supportsFloatingTabBar()

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
    if (this.floatingBar) {
      HdsTabs({ controller: this.controller }) {
        this.tabsContent()
      }
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .onChange((index: number): void => {
        this.currentIndex = index
      })
      .barFloatingStyle({
        barWidth: { smallWidth: 148, mediumWidth: 180, largeWidth: 212 },
        barBottomMargin: Math.max(28, this.navInsetVp()),
        gradientMask: { maskColor: $r('app.color.page_background'), maskHeight: 92 },
        systemMaterialEffect: {
          materialType: 100,
          materialLevel: 10
        }
      })
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    } else {
      Column() {
        HdsTabs({ controller: this.controller }) {
          this.tabsContent()
        }
        .barOverlap(true)
        .barPosition(BarPosition.End)
        .vertical(false)
        .onChange((index: number): void => {
          this.currentIndex = index
        })
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.navInsetVp() })
      .backgroundColor($r('app.color.page_background'))
    }
  }

  @Builder
  private tabsContent(): void {
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

  @Builder
  private homeTab(): void {
    TabBarItem({
      symbolOn: $r('sys.symbol.house_fill'),
      symbolOff: $r('sys.symbol.house'),
      label: '今日',
      active: this.currentIndex === 0
    })
  }

  @Builder
  private settingsTab(): void {
    TabBarItem({
      symbolOn: $r('sys.symbol.gearshape_fill'),
      symbolOff: $r('sys.symbol.gearshape'),
      label: '设置',
      active: this.currentIndex === 1
    })
  }
}
