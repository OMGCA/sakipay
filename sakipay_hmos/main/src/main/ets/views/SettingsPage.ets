/* (c) Copyright XiatStudio 2026~2026 */
import { SettingsViewModel } from '../viewmodels/SettingsViewModel'
import { BreakSegment } from '../models/BreakSegment'
import { IconFont, IconFontView } from '../services/IconFont'
import { Vibrator } from '@kit.SensorServiceKit'
import { common, Want } from '@kit.AbilityKit'

type SaveCallback = () => void

@ComponentV2
export struct SettingsPage {
  @Require @Param public viewModel: SettingsViewModel
  @Param public onSaved: SaveCallback = (): void => {}
  @Param public onCalendarSaved: SaveCallback = (): void => {}
  @Param public onShowCalendar: SaveCallback = (): void => {}

  private hourOptions: string[] = []
  private minuteOptions: string[] = []
  private paydayOptions: string[] = []

  // Force ForEach re-render when breaks are added/removed (bypasses V2 @Param tracing)
  @Local private breakListKey: number = 0
  @Local private showCalendar: boolean = false
  @Local private salaryFieldMasked: boolean = true

  /**
   * Trigger a short haptic pulse on picker value change.
   */
  private hapticTick(): void {
    try {
      Vibrator.vibrate({ mode: 'short', success: (): void => {} })
    } catch (e) {
      // Silently ignore if vibration is unavailable
    }
  }

  public aboutToAppear(): void {
    this.buildPickerOptions()
    if (!this.viewModel.isLoaded) {
      this.viewModel.loadConfig()
    }
  }

  public build(): void {
    Column() {
      // Header
      Row() {
        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
        Blank()
        Button('保存')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .onClick(() => {
            this.viewModel.saveConfig().then((success: boolean) => {
              if (success) {
                this.onSaved()
              }
            })
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 52, bottom: 8 })

      // Scrollable form
      Scroll() {
        Column({ space: 10 }) {
          this.salarySection()
          this.workHoursSection()
          this.breaksSection()
          this.taxSection()
          this.paydaySection()
          this.calendarSection()
          this.aboutSection()
          Blank().height(80)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4 })
      }
      .width('100%')
      .layoutWeight(1)

      // Toast
      if (this.viewModel.saveMessage.length > 0) {
        Text(this.viewModel.saveMessage)
          .fontSize(14)
          .fontColor(Color.White)
          .padding({ left: 20, right: 20, top: 10, bottom: 10 })
          .borderRadius(20)
          .backgroundColor('#CC000000')
          .margin({ bottom: 24 })
      }

      // Calendar popup is rendered at Index level (above tab bar)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  // ---- Section Title Helper ----

  @Builder
  private sectionTitle(text: string): void {
    Text(text)
      .fontSize(15)
      .fontColor($r('app.color.text_secondary'))
      .padding({ left: 4, bottom: 6 })
      .width('100%')
  }

  // ---- Salary ----

  @Builder
  private salarySection(): void {
    this.sectionTitle('月薪')

    Column({ space: 8 }) {
      Row({ space: 8 }) {
        TextPicker({ range: this.currencyOptions(), selected: this.currencyOptions().indexOf(this.viewModel.currency) })
          .onChange((value: string | string[], index: number | number[]) => {
            this.hapticTick()
            this.viewModel.currency = value as string
          })
          .width(56)
          .height(80)
          .defaultPickerItemHeight(42)
          .canLoop(false)
          .divider(null)
          .gradientHeight(36)
          .disappearTextStyle({ color: $r('app.color.text_tertiary'), font: { size: '13fp', weight: FontWeight.Regular } })
          .textStyle({ color: $r('app.color.text_secondary'), font: { size: '15fp', weight: FontWeight.Regular } })
          .selectedTextStyle({ color: $r('app.color.text_primary'), font: { size: '18fp', weight: FontWeight.Medium } })

        if (this.salaryFieldMasked && this.viewModel.monthlyPayText.length > 0) {
          Text('••••••••')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
            .onClick(() => {
              this.salaryFieldMasked = false
            })
        } else {
          TextInput({ text: this.viewModel.monthlyPayText, placeholder: '0.00' })
            .type(InputType.Normal)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.viewModel.monthlyPayText = this.filterDecimal(value)
            })
            .onBlur(() => {
              this.salaryFieldMasked = true
            })
        }
      }
      .width('100%')

      Row() {
        Text('每月工作天数').fontSize(14)
        Blank()
        if (this.viewModel.useCalibratedWorkDays) {
          Text(`${this.viewModel.calibratedWorkingDays} 天`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        } else {
          TextInput({ text: this.formatWorkingDays() })
            .type(InputType.Normal)
            .width(80)
            .textAlign(TextAlign.End)
            .onChange((value: string) => {
              const filtered: string = this.filterDecimal(value)
              const n: number = parseFloat(filtered)
              if (!isNaN(n) && n > 0 && n <= 31) {
                this.viewModel.workingDays = n
              }
              if (filtered.length === 0) {
                this.viewModel.workingDays = 0
              }
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor($r('app.color.glass_overlay'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
    .shadow({ radius: 8, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 2 })
    .border({ width: 0.5, color: $r('app.color.glass_border') })
  }

  // ---- Work Hours ----

  @Builder
  private workHoursSection(): void {
    this.sectionTitle('工作时间')

    Column({ space: 0 }) {
      // 上班
      Text('上班')
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .padding({ left: 4, bottom: 4 })
        .width('100%')
      this.timeWheelStrip(this.viewModel.workStartH, this.viewModel.workStartM,
        (h: number) => { this.viewModel.workStartH = h; this.viewModel.pruneInvalidBreaks() },
        (m: number) => { this.viewModel.workStartM = m; this.viewModel.pruneInvalidBreaks() }
      )

      Divider().strokeWidth(0.5).color($r('app.color.progress_track'))
        .margin({ top: 8, bottom: 8 })

      // 下班
      Text('下班')
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .padding({ left: 4, bottom: 4 })
        .width('100%')
      this.timeWheelStrip(this.viewModel.workEndH, this.viewModel.workEndM,
        (h: number) => { this.viewModel.workEndH = h; this.viewModel.pruneInvalidBreaks() },
        (m: number) => { this.viewModel.workEndM = m; this.viewModel.pruneInvalidBreaks() }
      )

      Divider().strokeWidth(0.5).color($r('app.color.progress_track'))
        .margin({ top: 8, bottom: 10 })

      // 每日工时
      Row() {
        Text('每日工时').fontSize(14)
        Blank()
        Text(this.viewModel.formattedWorkHours).fontSize(14).fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ top: 2, bottom: 2 })
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor($r('app.color.glass_overlay'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
    .shadow({ radius: 8, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 2 })
    .border({ width: 0.5, color: $r('app.color.glass_border') })
  }

  /**
   * Time-picker pair (hour : minute) without a label, centred for embedding in a parent layout.
   */
  @Builder
  private timeWheelStrip(
    hour: number, minute: number,
    onHourChange: (h: number) => void, onMinuteChange: (m: number) => void
  ): void {
    Row({ space: 4 }) {
      TextPicker({ range: this.hourOptions, selected: hour })
        .onChange((value: string | string[], index: number | number[]) => {
          this.hapticTick()
          const h: number = parseInt(value as string)
          if (!isNaN(h)) { onHourChange(h) }
        })
        .width(48)
        .height(80)
        .defaultPickerItemHeight(42)
        .canLoop(false)
        .divider(null)
        .gradientHeight(36)
        .disappearTextStyle({ color: $r('app.color.text_tertiary'), font: { size: '13fp', weight: FontWeight.Regular } })
        .textStyle({ color: $r('app.color.text_secondary'), font: { size: '15fp', weight: FontWeight.Regular } })
        .selectedTextStyle({ color: $r('app.color.text_primary'), font: { size: '18fp', weight: FontWeight.Medium } })

      Text(':').fontSize(18).fontWeight(FontWeight.Medium)

      TextPicker({ range: this.minuteOptions, selected: this.getMinuteIndex(minute) })
        .onChange((value: string | string[], index: number | number[]) => {
          this.hapticTick()
          const m: number = parseInt(value as string)
          if (!isNaN(m)) { onMinuteChange(m) }
        })
        .width(48)
        .height(80)
        .defaultPickerItemHeight(42)
        .canLoop(false)
        .divider(null)
        .gradientHeight(36)
        .disappearTextStyle({ color: $r('app.color.text_tertiary'), font: { size: '13fp', weight: FontWeight.Regular } })
        .textStyle({ color: $r('app.color.text_secondary'), font: { size: '15fp', weight: FontWeight.Regular } })
        .selectedTextStyle({ color: $r('app.color.text_primary'), font: { size: '18fp', weight: FontWeight.Medium } })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  // ---- Breaks ----

  @Builder
  private breaksSection(): void {
    this.sectionTitle('休息时段（不计薪）')

    Column({ space: 0 }) {
      ForEach(this.viewModel.breakSegments, (seg: BreakSegment, index: number) => {
        this.breakSegmentItem(seg, index)
      })

      Button('+ 添加休息时段')
        .margin({ top: 4 })
        .onClick(() => {
          this.viewModel.addBreak()
          this.breakListKey++
        })
        .width('100%')
        .fontSize(13)
        .height(36)
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor($r('app.color.glass_overlay'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
    .shadow({ radius: 8, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 2 })
    .border({ width: 0.5, color: $r('app.color.glass_border') })
  }

  @Builder
  private breakSegmentItem(seg: BreakSegment, index: number): void {
    Column() {
      Column({ space: 4 }) {
        // Header row
        Row() {
          Text(`时段 ${index + 1}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Button() {
            Text('−')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
          }
          .onClick(() => {
            this.viewModel.removeBreak(seg.id)
            this.breakListKey++
          })
          .width(22)
          .height(22)
          .borderRadius(11)
          .backgroundColor('#E53E3E')
        }
        .width('100%')

        // Start and end pickers side by side — same layout as iOS
        Row({ space: 4 }) {
          // Start
          Column({ space: 2 }) {
            Text('开始').fontSize(10).fontColor($r('app.color.text_tertiary'))
            this.breakTimeStrip(seg.startHour, seg.startMinute,
              (h: number) => { seg.startHour = h; this.viewModel.onBreakChanged() },
              (m: number) => { seg.startMinute = m; this.viewModel.onBreakChanged() }
            )
          }

          Text('—').fontSize(12).fontColor($r('app.color.text_tertiary')).margin({ top: 6 })

          // End
          Column({ space: 2 }) {
            Text('结束').fontSize(10).fontColor($r('app.color.text_tertiary'))
            this.breakTimeStrip(seg.endHour, seg.endMinute,
              (h: number) => { seg.endHour = h; this.viewModel.onBreakChanged() },
              (m: number) => { seg.endMinute = m; this.viewModel.onBreakChanged() }
            )
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .padding({ top: 6, bottom: 4, left: 4, right: 4 })

      Divider().strokeWidth(0.5).color($r('app.color.progress_track'))
    }
    .width('100%')
  }

  /**
   * Compact time-picker pair for break segments — narrower than the work-hours variant
   * so two can sit side by side inside a segment card.
   */
  @Builder
  private breakTimeStrip(
    hour: number, minute: number,
    onHourChange: (h: number) => void, onMinuteChange: (m: number) => void
  ): void {
    Row({ space: 2 }) {
      TextPicker({ range: this.hourOptions, selected: hour })
        .onChange((value: string | string[], index: number | number[]) => {
          this.hapticTick()
          const h: number = parseInt(value as string)
          if (!isNaN(h)) { onHourChange(h) }
        })
        .width(42)
        .height(68)
        .defaultPickerItemHeight(38)
        .canLoop(false)
        .divider(null)
        .gradientHeight(30)
        .disappearTextStyle({ color: $r('app.color.text_tertiary'), font: { size: '11fp', weight: FontWeight.Regular } })
        .textStyle({ color: $r('app.color.text_secondary'), font: { size: '13fp', weight: FontWeight.Regular } })
        .selectedTextStyle({ color: $r('app.color.text_primary'), font: { size: '16fp', weight: FontWeight.Medium } })

      Text(':').fontSize(16).fontWeight(FontWeight.Medium)

      TextPicker({ range: this.minuteOptions, selected: this.getMinuteIndex(minute) })
        .onChange((value: string | string[], index: number | number[]) => {
          this.hapticTick()
          const m: number = parseInt(value as string)
          if (!isNaN(m)) { onMinuteChange(m) }
        })
        .width(42)
        .height(68)
        .defaultPickerItemHeight(38)
        .canLoop(false)
        .divider(null)
        .gradientHeight(30)
        .disappearTextStyle({ color: $r('app.color.text_tertiary'), font: { size: '11fp', weight: FontWeight.Regular } })
        .textStyle({ color: $r('app.color.text_secondary'), font: { size: '13fp', weight: FontWeight.Regular } })
        .selectedTextStyle({ color: $r('app.color.text_primary'), font: { size: '16fp', weight: FontWeight.Medium } })
    }
    .justifyContent(FlexAlign.Center)
  }

  // ---- Tax ----

  @Builder
  private taxSection(): void {
    this.sectionTitle('个税（可选）')

    Column({ space: 6 }) {
      Row() {
        Text('税率').fontSize(14)
        Blank()
        Text(`${Math.floor(this.viewModel.taxRate * 100)}%`)
          .fontSize(14).fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      Slider({ value: this.viewModel.taxRate * 100, min: 0, max: 45, step: 1 })
        .width('100%')
        .onChange((value: number) => { this.viewModel.taxRate = value / 100 })

      if (this.viewModel.postTaxMonthly.length > 0) {
        Row() {
          Text('税后月薪').fontSize(14)
          Blank()
          Text(this.viewModel.postTaxMonthly).fontSize(14).fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor($r('app.color.glass_overlay'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
    .shadow({ radius: 8, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 2 })
    .border({ width: 0.5, color: $r('app.color.glass_border') })
  }

  // ---- Payday ----

  @Builder
  private paydaySection(): void {
    this.sectionTitle('发薪日')

    Column({ space: 0 }) {
      Row() {
        Text('每月几号').fontSize(14)
        Blank()
        Text(`${this.viewModel.payDay}日`)
          .fontSize(14)
          .fontColor($r('app.color.accent_blue'))
          .bindMenu(this.paydayMenuBuilder)
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor($r('app.color.glass_overlay'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
    .shadow({ radius: 8, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 2 })
    .border({ width: 0.5, color: $r('app.color.glass_border') })
  }

  @Builder
  private paydayMenuBuilder(): void {
    Menu() {
      ForEach(this.paydayOptions, (item: string, index: number) => {
        MenuItem({ content: item })
          .onClick(() => {
            this.viewModel.payDay = index + 1
          })
      })
    }
  }

  @Builder
  private calendarSection(): void {
    this.sectionTitle('工作日日历')

    Column({ space: 10 }) {
      // Open calendar page
      Row() {
        Text('自定义工作日')
          .fontSize(14)
          .fontColor($r('app.color.accent_blue'))
        Blank()
        Text('标记自定义日')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        IconFontView({ code: IconFont.CHEVRON_RIGHT, iconSize: 12, iconColor: $r('app.color.text_secondary') })
      }
      .width('100%')
      .onClick(() => {
        this.onShowCalendar()
      })

      Divider().strokeWidth(0.5).color($r('app.color.progress_track'))

      // Auto-calibrate toggle
      Row() {
        Text('自动校准每月工作天数')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.viewModel.useCalibratedWorkDays })
          .onChange((value: boolean) => {
            this.viewModel.useCalibratedWorkDays = value
          })
      }
      .width('100%')

      if (this.viewModel.useCalibratedWorkDays) {
        Divider().strokeWidth(0.5).color($r('app.color.progress_track'))

        Row() {
          Text('本月实际工作日')
            .fontSize(14)
          Blank()
          Text(`${this.viewModel.calibratedWorkingDays} 天`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor($r('app.color.glass_overlay'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
    .shadow({ radius: 8, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 2 })
    .border({ width: 0.5, color: $r('app.color.glass_border') })
  }

  @Builder
  private aboutSection(): void {
    this.sectionTitle('关于')

    Column({ space: 10 }) {
      Row() {
        Text('隐私政策')
          .fontSize(14)
          .fontColor($r('app.color.accent_blue'))
        Blank()
        IconFontView({ code: IconFont.CHEVRON_RIGHT, iconSize: 14, iconColor: $r('app.color.accent_blue') })
      }
      .width('100%')
      .onClick(() => { this.openURL('https://github.com/OMGCA/sakipay/blob/develop/privacy_policy/privacy_policy.md') })

      Divider().strokeWidth(0.5).color($r('app.color.progress_track'))

      Row() {
        Text('反馈')
          .fontSize(14)
          .fontColor($r('app.color.accent_blue'))
        Blank()
        IconFontView({ code: IconFont.CHEVRON_RIGHT, iconSize: 14, iconColor: $r('app.color.accent_blue') })
      }
      .width('100%')
      .onClick(() => { this.openURL('https://xiatstudio.feishu.cn/share/base/form/shrcnwvu9S2vUZVIqOXvKRTQhie') })

      Divider().strokeWidth(0.5).color($r('app.color.progress_track'))

      Row() {
        Text('版本').fontSize(14)
        Blank()
        Text('0.1.0').fontSize(14)
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor($r('app.color.glass_overlay'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
    .shadow({ radius: 8, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 2 })
    .border({ width: 0.5, color: $r('app.color.glass_border') })
  }

  private openURL(uri: string): void {
    const ctx: common.UIAbilityContext | undefined = this.getUIContext().getHostContext() as
      common.UIAbilityContext | undefined
    if (ctx !== undefined) {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: uri
      }
      ctx.startAbility(want).catch((err: Error) => {
        // Silently fail — browser unavailable
      })
    }
  }

  // ---- Helpers ----

  private buildPickerOptions(): void {
    if (this.hourOptions.length === 0) {
      const hours: string[] = []
      for (let i: number = 0; i < 24; i++) {
        hours.push(String(i).padStart(2, '0'))
      }
      this.hourOptions = hours
    }
    if (this.minuteOptions.length === 0) {
      const mins: string[] = []
      for (let i: number = 0; i < 60; i += 5) {
        mins.push(String(i).padStart(2, '0'))
      }
      this.minuteOptions = mins
    }
    if (this.paydayOptions.length === 0) {
      const days: string[] = []
      for (let i: number = 1; i <= 31; i++) {
        days.push(`${i}日`)
      }
      this.paydayOptions = days
    }
  }

  private filterDecimal(value: string): string {
    let result: string = ''
    let hasDot: boolean = false
    for (let i: number = 0; i < value.length; i++) {
      const ch: string = value.charAt(i)
      if (ch >= '0' && ch <= '9') {
        result += ch
      } else if (ch === '.' && !hasDot) {
        hasDot = true
        result += ch
      }
    }
    return result
  }

  private formatWorkingDays(): string {
    if (this.viewModel.workingDays <= 0) { return '' }
    return this.viewModel.workingDays.toString()
  }

  private currencyOptions(): string[] {
    return ['¥', '$', '€', '£', '₩', '₹']
  }

  private getMinuteIndex(minute: number): number {
    const idx: number = Math.round(minute / 5)
    return Math.max(0, Math.min(11, idx))
  }

}
