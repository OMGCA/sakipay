/* (c) Copyright XiatStudio 2026~2026 */
import { window } from '@kit.ArkUI'
import { Log } from './Log'

/**
 * Window safe-area measurement for the bottom tab bars.
 *
 * The app runs with setWindowLayoutFullScreen(true), so the window content area
 * extends underneath the system navigation bar. HdsTabs performs no automatic
 * safe-area avoidance, so the inset has to be applied by hand.
 *
 * Resolution happens in MainAbility.onWindowStageCreate — from the main window,
 * which is available synchronously there — and is published to AppStorage *before*
 * the page loads. The timing matters: the tab bars must know the inset on their
 * very first build, and window.getLastWindow() is asynchronous, so resolving this
 * from inside a component lands after the bar has already been laid out.
 *
 * Value is returned in px; callers convert with px2vp(), which needs a UI context.
 */
export class WindowInsets {
  /**
   * Bottom navigation inset in px, or -1 when it could not be read.
   *
   * Prefers TYPE_NAVIGATION_INDICATOR — the region the gesture pill lives in, which
   * is exactly what the bar has to clear. TYPE_SYSTEM is only a fallback: in gesture
   * mode it still reserves a full navigation bar's height, so taking the larger of
   * the two over-reports and pushes the bar up too far.
   */
  public static bottomPx(win: window.Window): number {
    try {
      const indicator: window.AvoidArea =
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
      const system: window.AvoidArea =
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)

      const indicatorPx: number = indicator.bottomRect.height
      const systemPx: number = system.bottomRect.height
      Log.info(`WindowInsets: indicator=${indicatorPx}px system=${systemPx}px`)

      return indicatorPx > 0 ? indicatorPx : systemPx
    } catch (err) {
      Log.error(`WindowInsets: avoid area read failed — ${err}`)
      return -1
    }
  }
}
