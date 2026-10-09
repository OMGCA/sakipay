/* (c) Copyright XiatStudio 2026~2026 */
/**
 * Bottom tab-bar item — system symbol plus caption, tinted by active state.
 *
 * Shared by HdsTabsHost (API 20+) and NativeTabsHost (below API 20) so both
 * tab bars render identically regardless of which host is in use.
 */
@ComponentV2
export struct TabBarItem {
  @Require @Param public symbolOn: Resource
  @Require @Param public symbolOff: Resource
  @Require @Param public label: string
  @Param public active: boolean = false
  @Param public itemWidth: number = 68
  @Param public itemHeight: number = 48

  public build(): void {
    Column({ space: 2 }) {
      SymbolGlyph(this.active ? this.symbolOn : this.symbolOff)
        .fontSize(20)
        .fontColor([this.active ? $r('app.color.accent_blue') : $r('app.color.text_tertiary')])
      Text(this.label)
        .fontSize(10)
        .fontWeight(this.active ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.active ? $r('app.color.accent_blue') : $r('app.color.text_tertiary'))
    }
    .width(this.itemWidth)
    .height(this.itemHeight)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
