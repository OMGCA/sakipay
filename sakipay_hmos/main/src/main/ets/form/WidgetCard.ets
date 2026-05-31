/* (c) Copyright XiatStudio 2026~2026 */
/**
 * Widget card — ring progress + earnings on the HarmonyOS home screen.
 * Data is provided by SakipayFormAbility via formBindingData → StorageProp.
 *
 * Widget animation constraints (per HarmonyOS guidelines):
 *   - duration: max 2000ms
 *   - iterations, delay, tempo: forbidden
 */
@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('cardAmount') cardAmount: string = '0.00'
  @LocalStorageProp('cardProgress') cardProgress: number = 0
  @LocalStorageProp('cardStatus') cardStatus: string = 'notStarted'
  @LocalStorageProp('cardCurrency') cardCurrency: string = '¥'
  @LocalStorageProp('cardPrivacy') isPrivacyMode: string = '0'
  @State private contentScale: number = 1

  public build(): void {
    Stack() {
      Progress({ value: this.cardProgress * 100, total: 100, type: ProgressType.Ring })
        .width('85%')
        .height('85%')
        .color(this.statusColor())
        .backgroundColor($r('app.color.progress_track'))

      Column({ space: 4 }) {
        // Privacy toggle — above the number
        Row() {
          if (this.isPrivacyMode === '1') {
            SymbolGlyph($r('sys.symbol.eye_slash'))
              .fontSize(16)
              .fontColor([$r('app.color.accent_orange')])
          } else {
            SymbolGlyph($r('sys.symbol.eye'))
              .fontSize(16)
              .fontColor([$r('app.color.text_secondary')])
          }
        }
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: 6 })
        .onClick(() => {
          postCardAction(this, {
            action: 'message',
            params: { message: 'togglePrivacy' }
          })
        })

        if (this.cardStatus === 'dayOff') {
          Text('🏖️')
            .fontSize(18)
        } else if (this.isPrivacyMode === '1') {
          Text('***')
            .fontSize(15)
            .fontWeight(600)
            .fontFamily('monospace')
        } else {
          Text(`${this.cardCurrency}${this.cardAmount}`)
            .fontSize(15)
            .fontWeight(600)
            .fontFamily('monospace')
        }

        Text(`${Math.floor(this.cardProgress * 100)}%`)
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))

        Row({ space: 2 }) {
          Circle().width(4).height(4).fill(this.statusColor())
          Text(this.statusText())
            .fontSize(8)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .padding(12)
      .scale({ x: this.contentScale, y: this.contentScale })
      .animation({ duration: 300, curve: Curve.EaseOut })
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'MainAbility',
        params: {}
      })
    })
  }

  public aboutToAppear(): void {
    this.pulseContent()
  }

  /**
   * Brief scale pulse — called when widget first appears.
   */
  private pulseContent(): void {
    this.contentScale = 1.06
    animateTo({ duration: 300, curve: Curve.EaseOut }, (): void => {
      this.contentScale = 1
    })
  }

  private statusColor(): ResourceColor {
    if (this.cardStatus === 'working') { return $r('app.color.status_working') }
    if (this.cardStatus === 'onBreak') { return $r('app.color.status_break') }
    if (this.cardStatus === 'completed') { return $r('app.color.status_completed') }
    if (this.cardStatus === 'overtime') { return $r('app.color.status_overtime') }
    if (this.cardStatus === 'dayOff') { return $r('app.color.status_dayoff') }
    return $r('app.color.status_inactive')
  }

  private statusText(): string {
    if (this.cardStatus === 'notStarted') { return '未开始' }
    if (this.cardStatus === 'working') { return '窝囊费积累中' }
    if (this.cardStatus === 'onBreak') { return '休息中' }
    if (this.cardStatus === 'completed') { return '下班啦！' }
    if (this.cardStatus === 'overtime') { return '加班中 💪' }
    return '休息日'
  }
}
