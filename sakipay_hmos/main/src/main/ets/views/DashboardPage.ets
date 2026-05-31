/* (c) Copyright XiatStudio 2026~2026 */
import { DashboardViewModel } from '../viewmodels/DashboardViewModel'
import { WorkStatus } from '../models/EarningsCalculator'
import { IconFont, IconFontView } from '../services/IconFont'
import curves from '@ohos.curves'

/**
 * Callback type for navigating to settings.
 */
type NavCallback = () => void

/**
 * Dashboard page — live earnings counter, month progress, payday countdown.
 * Spring-animated counter, breathing status dot, staggered card entrance.
 */
@ComponentV2
export struct DashboardPage {
  @Require @Param public viewModel: DashboardViewModel
  @Param public onNavigateToSettings: NavCallback = (): void => {}

  // Guaranteed re-render via @Local once config loads (bypasses V2 @Param/@Trace quirk)
  @Local private _isConfigured: boolean = false
  private configPollTimer: number = -1

  @Local private displayAmount: number = 0
  @Local private prevAmount: number = 0
  @Local private animating: boolean = false

  // Breathing status dot (B)
  @Local private statusDotOpacity: number = 1
  private pulseTimer: number = -1

  // Staggered card entrance (D)
  @Local private cardOpacityToday: number = 0
  @Local private cardOpacityMonth: number = 0
  @Local private cardOpacityPayday: number = 0
  @Local private cardOffsetToday: number = 24
  @Local private cardOffsetMonth: number = 24
  @Local private cardOffsetPayday: number = 24
  @Local private entranceTriggered: boolean = false

  public aboutToAppear(): void {
    this.displayAmount = this.viewModel.todayAmount
    this.prevAmount = this.viewModel.todayAmount
    this._isConfigured = this.viewModel.isConfigured
    this.triggerEntrance()
    this.startConfigPoll()
  }

  public aboutToDisappear(): void {
    this.stopPulse()
    this.stopConfigPoll()
  }

  /**
   * Polls viewModel.isConfigured until it becomes true, then sets @Local state
   * to trigger guaranteed re-render. Bypasses V2 @Param/@Trace propagation quirks.
   */
  private startConfigPoll(): void {
    if (this.configPollTimer !== -1) {
      return
    }
    const check = (): void => {
      if (this.viewModel.isConfigured) {
        this._isConfigured = true
        this.displayAmount = this.viewModel.todayAmount
        this.prevAmount = this.viewModel.todayAmount
        this.stopConfigPoll()
        return
      }
      this.configPollTimer = setTimeout(check, 100)
    }
    check()
  }

  private stopConfigPoll(): void {
    if (this.configPollTimer !== -1) {
      clearTimeout(this.configPollTimer)
      this.configPollTimer = -1
    }
  }

  public build(): void {
    if (this._isConfigured || this.viewModel.isConfigured) {
      this.configuredView()
    } else {
      this.emptyState()
    }
  }

  @Builder
  private configuredView(): void {
    Scroll() {
      Column({ space: 16 }) {
        this.todayCard()
        this.monthCard()
        this.paydayCard()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 52, bottom: 80 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .backgroundColor($r('app.color.page_background'))
  }

  // ---- Today Card ----

  @Builder
  private todayCard(): void {
    Column({ space: 12 }) {
      this.statusBadge()
      this.earningsCounter()
      this.progressBar()
    }
    .width('100%')
    .padding(20)
    .borderRadius(16)
    .backgroundColor($r('app.color.glass_overlay'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .shadow({ radius: 12, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 4 })
    .border({ width: 0.5, color: $r('app.color.glass_border') })
    .alignItems(HorizontalAlign.Center)
    .opacity(this.cardOpacityToday)
    .translate({ y: this.cardOffsetToday })
    .renderGroup(true)
  }

  @Builder
  private statusBadge(): void {
    Row({ space: 6 }) {
      Circle()
        .width(8)
        .height(8)
        .fill(this.getStatusColor())
        .opacity(this.statusDotOpacity)
        .animation({ duration: 800, curve: Curve.EaseInOut })

      Text(this.viewModel.getStatusText())
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))

      Blank()

      Row() {
        if (this.viewModel.isPrivacyMode) {
          SymbolGlyph($r('sys.symbol.eye_slash'))
            .fontSize(14)
            .fontColor([$r('app.color.accent_orange')])
        } else {
          SymbolGlyph($r('sys.symbol.eye'))
            .fontSize(14)
            .fontColor([$r('app.color.text_secondary')])
        }
      }
      .onClick(() => {
        this.viewModel.togglePrivacy()
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .borderRadius(12)
  }

  @Builder
  private earningsCounter(): void {
    Row() {
      if (this.viewModel.todayStatus === WorkStatus.DAY_OFF) {
        Text('🏖️')
          .fontSize(36)
      } else if (this.viewModel.isPrivacyMode) {
        Text('***')
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
      } else {
        Text(`${this.viewModel.currency}${this.formatCurrency(this.displayAmount)}`)
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
          .scale({ x: this.animating ? 1.04 : 1, y: this.animating ? 1.04 : 1 })
          .animation({ duration: 200, curve: Curve.EaseOut })
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private progressBar(): void {
    Column({ space: 6 }) {
      Progress({
        value: this.viewModel.todayProgress * 100,
        total: 100,
        type: ProgressType.Linear
      })
        .width('100%')
        .height(6)
        .color(this.getStatusColor())
        .backgroundColor($r('app.color.progress_track'))

      Row() {
        Text('今日进度')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))

        Blank()

        Text(`${Math.floor(this.viewModel.todayProgress * 100)}%`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
    }
  }

  // ---- Month Card ----

  @Builder
  private monthCard(): void {
    Column({ space: 12 }) {
      Row() {
        Text('本月').fontSize(16).fontWeight(FontWeight.Medium)
        Blank()
        if (this.viewModel.isPrivacyMode) {
          Text('***').fontSize(15).fontWeight(FontWeight.Medium)
        } else {
          Text(`${this.viewModel.currency}${this.formatCurrency(this.viewModel.monthSummary.monthEarnings)}`)
            .fontSize(15).fontWeight(FontWeight.Medium)
        }
      }
      .width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Text(`已工作 ${this.viewModel.monthSummary.workingDaysElapsed} / ${this.viewModel.monthSummary.workingDaysThisMonth} 天`)
          .fontSize(12).fontColor($r('app.color.text_secondary'))
        Blank()
        if (this.viewModel.isPrivacyMode) {
          Text('共 ***').fontSize(11).fontColor($r('app.color.text_secondary'))
        } else {
          Text(`共 ${this.viewModel.currency}${this.formatCurrency(this.viewModel.monthSummary.totalMonthEarnings)}`)
            .fontSize(11).fontColor($r('app.color.text_secondary'))
        }
      }
      .width('100%').alignItems(VerticalAlign.Center)

      Progress({
        value: this.viewModel.monthSummary.monthProgress * 100,
        total: 100,
        type: ProgressType.Linear
      })
        .width('100%')
        .height(5)
        .color($r('app.color.accent_blue'))
        .backgroundColor($r('app.color.progress_track'))
    }
    .width('100%')
    .padding(20)
    .borderRadius(16)
    .backgroundColor($r('app.color.glass_overlay'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .shadow({ radius: 12, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 4 })
    .border({ width: 0.5, color: $r('app.color.glass_border') })
    .opacity(this.cardOpacityMonth)
    .translate({ y: this.cardOffsetMonth })
    .renderGroup(true)
  }

  // ---- Payday Card ----

  @Builder
  private paydayCard(): void {
    Column({ space: 12 }) {
      Row() {
        IconFontView({
          code: this.viewModel.monthSummary.isPayday ? IconFont.CONFETTI : IconFont.CALENDAR,
          iconSize: 22,
          iconColor: $r('app.color.text_secondary')
        })
        Text(this.viewModel.getPaydayText())
          .fontSize(16).fontWeight(FontWeight.Medium).margin({ left: 10 })
        Blank()
        Text(this.viewModel.monthSummary.isPayday ? '你做到了' : `倒数 ${this.viewModel.monthSummary.paydayCycleElapsed} / ${this.viewModel.monthSummary.paydayCycleTotal} 天`)
          .fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      .width('100%').alignItems(VerticalAlign.Center)

      Progress({
        value: this.viewModel.monthSummary.paydayCycleProgress * 100,
        total: 100,
        type: ProgressType.Linear
      })
        .width('100%')
        .height(5)
        .color($r('app.color.accent_orange'))
        .backgroundColor($r('app.color.progress_track'))
    }
    .width('100%')
    .padding(20)
    .borderRadius(16)
    .backgroundColor($r('app.color.glass_overlay'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .shadow({ radius: 12, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 4 })
    .border({ width: 0.5, color: $r('app.color.glass_border') })
    .opacity(this.cardOpacityPayday)
    .translate({ y: this.cardOffsetPayday })
    .renderGroup(true)
  }

  // ---- Empty ----

  @Builder
  private emptyState(): void {
    Column({ space: 16 }) {
      IconFontView({ code: IconFont.MONEY, iconSize: 48, iconColor: $r('app.color.text_secondary') })

      Text('设置你的收入')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)

      Text('在设置中输入月薪和工作时间，\n开始追踪每日收入。')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)

      Button('前往设置')
        .onClick(() => {
          this.onNavigateToSettings()
        })
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  // ---- Digit Rolling Counter (A) ----

  @Monitor('viewModel.todayAmount')
  public onAmountChanged(): void {
    if (!this.animating && this.viewModel.todayAmount !== this.prevAmount) {
      this.prevAmount = this.viewModel.todayAmount
      this.animateToNewValue()
    }
  }

  private animateToNewValue(): void {
    const target: number = this.viewModel.todayAmount
    const start: number = this.displayAmount
    const diff: number = target - start

    if (Math.abs(diff) < 0.001) {
      return
    }

    this.animating = true
    const steps: number = 16
    const stepDelay: number = 16  // ~60fps
    const stepDiff: number = diff / steps
    let currentStep: number = 0

    const tick = (): void => {
      if (currentStep >= steps) {
        this.displayAmount = target
        this.prevAmount = target
        this.animating = false
        return
      }
      currentStep++
      this.displayAmount = start + stepDiff * currentStep
      setTimeout(tick, stepDelay)
    }

    tick()
  }

  // ---- Breathing Status Dot (B) ----

  @Monitor('viewModel.todayStatus')
  public onStatusChanged(): void {
    if (this.viewModel.todayStatus === WorkStatus.WORKING ||
        this.viewModel.todayStatus === WorkStatus.OVERTIME) {
      this.startPulse()
    } else {
      this.stopPulse()
      this.statusDotOpacity = 1
    }
  }

  private startPulse(): void {
    if (this.pulseTimer !== -1) {
      return
    }
    this.pulseTimer = setInterval((): void => {
      this.statusDotOpacity = this.statusDotOpacity > 0.5 ? 0.3 : 1
    }, 800)
  }

  private stopPulse(): void {
    if (this.pulseTimer !== -1) {
      clearInterval(this.pulseTimer)
      this.pulseTimer = -1
    }
  }

  // ---- Staggered Card Entrance (D) ----

  private triggerEntrance(): void {
    if (this.entranceTriggered) {
      return
    }
    this.entranceTriggered = true

    // Today card
    this.getUIContext().animateTo(
      { curve: curves.springMotion(0.55, 0.85) },
      (): void => {
        this.cardOpacityToday = 1
        this.cardOffsetToday = 0
      }
    )

    // Month card — 80ms delay
    setTimeout((): void => {
      this.getUIContext().animateTo(
        { curve: curves.springMotion(0.55, 0.85) },
        (): void => {
          this.cardOpacityMonth = 1
          this.cardOffsetMonth = 0
        }
      )
    }, 80)

    // Payday card — 160ms delay
    setTimeout((): void => {
      this.getUIContext().animateTo(
        { curve: curves.springMotion(0.55, 0.85) },
        (): void => {
          this.cardOpacityPayday = 1
          this.cardOffsetPayday = 0
        }
      )
    }, 160)
  }

  // ---- Helpers ----

  private getStatusColor(): ResourceColor {
    switch (this.viewModel.todayStatus) {
      case WorkStatus.WORKING:
        return $r('app.color.status_working')
      case WorkStatus.ON_BREAK:
        return $r('app.color.status_break')
      case WorkStatus.COMPLETED:
        return $r('app.color.status_completed')
      case WorkStatus.OVERTIME:
        return $r('app.color.status_overtime')
      case WorkStatus.DAY_OFF:
        return $r('app.color.status_dayoff')
      default:
        return $r('app.color.status_inactive')
    }
  }

  private formatCurrency(value: number): string {
    return value.toFixed(2)
  }
}
