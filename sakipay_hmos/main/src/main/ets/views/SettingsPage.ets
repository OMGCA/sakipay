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

  private hourOptions: string[] = []
  private minuteOptions: string[] = []

  // Force ForEach re-render when breaks are added/removed (bypasses V2 @Param tracing)
  @Local private breakListKey: number = 0

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
        Column({ space: 14 }) {
          this.salarySection()
          this.workHoursSection()
          this.breaksSection()
          this.taxSection()
          this.paydaySection()
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

    Column({ space: 12 }) {
      Row({ space: 8 }) {
        TextPicker({ range: this.currencyOptions(), selected: this.currencyOptions().indexOf(this.viewModel.currency) })
          .onChange((value: string | string[], index: number | number[]) => {
            this.hapticTick()
            this.viewModel.currency = value as string
          })
          .width(56)
          .height(80)

        TextInput({ text: this.viewModel.monthlyPayText, placeholder: '0.00' })
          .type(InputType.Normal)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.viewModel.monthlyPayText = this.filterDecimal(value)
          })
      }
      .width('100%')

      Row() {
        Text('每月工作天数').fontSize(14)
        Blank()
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
      .width('100%')
    }
    .width('100%')
    .padding(16)
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

    Column({ space: 12 }) {
      this.timeWheelRow('上班', this.viewModel.workStartH, this.viewModel.workStartM,
        (h: number) => { this.viewModel.workStartH = h; this.viewModel.pruneInvalidBreaks() },
        (m: number) => { this.viewModel.workStartM = m; this.viewModel.pruneInvalidBreaks() }
      )
      this.timeWheelRow('下班', this.viewModel.workEndH, this.viewModel.workEndM,
        (h: number) => { this.viewModel.workEndH = h; this.viewModel.pruneInvalidBreaks() },
        (m: number) => { this.viewModel.workEndM = m; this.viewModel.pruneInvalidBreaks() }
      )

      Divider().strokeWidth(0.5).color($r('app.color.progress_track'))

      Row() {
        Text('每日工时').fontSize(14)
        Blank()
        Text(this.viewModel.formattedWorkHours).fontSize(14).fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(14)
    .backgroundColor($r('app.color.glass_overlay'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
    .shadow({ radius: 8, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 2 })
    .border({ width: 0.5, color: $r('app.color.glass_border') })
  }

  @Builder
  private timeWheelRow(
    label: string, hour: number, minute: number,
    onHourChange: (h: number) => void, onMinuteChange: (m: number) => void
  ): void {
    Row({ space: 4 }) {
      Text(label).fontSize(14).width(56)

      TextPicker({ range: this.hourOptions, selected: hour })
        .onChange((value: string | string[], index: number | number[]) => {
          this.hapticTick()
          const h: number = parseInt(value as string)
          if (!isNaN(h)) { onHourChange(h) }
        })
        .width(44)
        .height(44)
        .disappearTextStyle({ color: $r('app.color.text_tertiary'), font: { size: '12fp', weight: FontWeight.Regular } })
        .textStyle({ color: $r('app.color.text_secondary'), font: { size: '14fp', weight: FontWeight.Regular } })
        .selectedTextStyle({ color: $r('app.color.text_primary'), font: { size: '15fp', weight: FontWeight.Medium } })

      Text(':').fontSize(16).fontWeight(FontWeight.Medium)

      TextPicker({ range: this.minuteOptions, selected: this.getMinuteIndex(minute) })
        .onChange((value: string | string[], index: number | number[]) => {
          this.hapticTick()
          const m: number = parseInt(value as string)
          if (!isNaN(m)) { onMinuteChange(m) }
        })
        .width(44)
        .height(44)
        .disappearTextStyle({ color: $r('app.color.text_tertiary'), font: { size: '12fp', weight: FontWeight.Regular } })
        .textStyle({ color: $r('app.color.text_secondary'), font: { size: '14fp', weight: FontWeight.Regular } })
        .selectedTextStyle({ color: $r('app.color.text_primary'), font: { size: '15fp', weight: FontWeight.Medium } })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  // ---- Breaks ----

  @Builder
  private breaksSection(): void {
    this.sectionTitle('休息时段（不计薪）')

    Column({ space: 10 }) {
      ForEach(this.viewModel.breakSegments, (seg: BreakSegment, index: number) => {
        this.breakSegmentItem(seg, index)
      })

      Button('+ 添加休息时段')
        .onClick(() => {
          this.viewModel.addBreak()
          this.breakListKey++
        })
        .width('100%')
        .fontSize(13)
        .height(36)
    }
    .width('100%')
    .padding(16)
    .borderRadius(14)
    .backgroundColor($r('app.color.glass_overlay'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
    .shadow({ radius: 8, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 2 })
    .border({ width: 0.5, color: $r('app.color.glass_border') })
  }

  @Builder
  private breakSegmentItem(seg: BreakSegment, index: number): void {
    Column({ space: 8 }) {
      Row() {
        Text(`时段 ${index + 1}`).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Blank()
        Button() {
          Text('−')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
        }
        .onClick(() => {
          this.viewModel.removeBreak(seg.id)
          this.breakListKey++
        })
        .width(24)
        .height(24)
        .borderRadius(12)
        .backgroundColor('#E53E3E')
      }
      .width('100%')

      // Start time — horizontal, same as work time picker
      this.breakTimeRow('开始', seg.startHour, seg.startMinute,
        (h: number) => { seg.startHour = h },
        (m: number) => { seg.startMinute = m }
      )

      // End time — horizontal, same as work time picker
      this.breakTimeRow('结束', seg.endHour, seg.endMinute,
        (h: number) => { seg.endHour = h },
        (m: number) => { seg.endMinute = m }
      )
    }
    .width('100%')
    .padding(10)
    .borderRadius(10)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private breakTimeRow(
    label: string, hour: number, minute: number,
    onHourChange: (h: number) => void, onMinuteChange: (m: number) => void
  ): void {
    Row({ space: 4 }) {
      Text(label).fontSize(11).width(40)

      TextPicker({ range: this.hourOptions, selected: hour })
        .onChange((value: string | string[], index: number | number[]) => {
          this.hapticTick()
          const h: number = parseInt(value as string)
          if (!isNaN(h)) { onHourChange(h) }
        })
        .width(40)
        .height(36)
        .disappearTextStyle({ color: $r('app.color.text_tertiary'), font: { size: '10fp', weight: FontWeight.Regular } })
        .textStyle({ color: $r('app.color.text_secondary'), font: { size: '12fp', weight: FontWeight.Regular } })
        .selectedTextStyle({ color: $r('app.color.text_primary'), font: { size: '13fp', weight: FontWeight.Medium } })

      Text(':').fontSize(14).fontWeight(FontWeight.Medium)

      TextPicker({ range: this.minuteOptions, selected: this.getMinuteIndex(minute) })
        .onChange((value: string | string[], index: number | number[]) => {
          this.hapticTick()
          const m: number = parseInt(value as string)
          if (!isNaN(m)) { onMinuteChange(m) }
        })
        .width(40)
        .height(36)
        .disappearTextStyle({ color: $r('app.color.text_tertiary'), font: { size: '10fp', weight: FontWeight.Regular } })
        .textStyle({ color: $r('app.color.text_secondary'), font: { size: '12fp', weight: FontWeight.Regular } })
        .selectedTextStyle({ color: $r('app.color.text_primary'), font: { size: '13fp', weight: FontWeight.Medium } })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  // ---- Tax ----

  @Builder
  private taxSection(): void {
    this.sectionTitle('个税（可选）')

    Column({ space: 10 }) {
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
    .padding(16)
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

    Column({ space: 8 }) {
      Row() {
        Text('每月几号').fontSize(14)
        Blank()
        TextPicker({ range: this.buildDayOptions(), selected: this.viewModel.payDay - 1 })
          .onChange((value: string | string[], index: number | number[]) => {
            this.hapticTick()
            const d: number = parseInt((value as string).replace('日', ''))
            if (!isNaN(d)) { this.viewModel.payDay = d }
          })
          .width(56)
          .height(44)
          .disappearTextStyle({ color: $r('app.color.text_tertiary'), font: { size: '12fp', weight: FontWeight.Regular } })
          .textStyle({ color: $r('app.color.text_secondary'), font: { size: '14fp', weight: FontWeight.Regular } })
          .selectedTextStyle({ color: $r('app.color.text_primary'), font: { size: '15fp', weight: FontWeight.Medium } })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
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
        Text('0.0.3').fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
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

  private buildDayOptions(): string[] {
    const arr: string[] = []
    for (let i: number = 1; i <= 31; i++) {
      arr.push(`${i}日`)
    }
    return arr
  }
}
