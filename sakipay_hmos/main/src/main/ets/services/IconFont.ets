/* (c) Copyright XiatStudio 2026~2026 */
/**
 * Icon constants using standard Unicode text symbols.
 *
 * These are NOT emoji — they are Unicode glyphs from the system font
 * that render cleanly in any Text component. No external files needed.
 */
export class IconFont {
  /** House / home / dashboard tab */
  public static readonly HOME: string = '⌂'
  /** Trigram for heaven / hamburger menu / settings tab */
  public static readonly SETTINGS: string = '☰'
  /** Circle / generic indicator */
  public static readonly CALENDAR: string = '○'
  /** Black star / celebration */
  public static readonly CONFETTI: string = '★'
  /** Black diamond / money */
  public static readonly MONEY: string = '◆'
  /** Multiplication X / close */
  public static readonly CLOSE: string = '✕'
  /** Rightwards arrow / chevron */
  public static readonly CHEVRON_RIGHT: string = '→'
  /** White circle / clock */
  public static readonly CLOCK: string = '○'
  /** Two vertical lines / pause / break */
  public static readonly BREAK: string = '❚❚'
  /** White square / info */
  public static readonly INFO: string = '□'
  /** Check mark / save */
  public static readonly SAVE: string = '✓'
  /** Ring / percent */
  public static readonly PERCENT: string = '○'
  /** Heavy asterisk / payday */
  public static readonly PAYDAY: string = '✱'
  /** Check mark in box */
  public static readonly CALENDAR_CHECK: string = '✓'
  /** Upwards arrow / work */
  public static readonly WORK: string = '↑'
  /** Plus sign / add */
  public static readonly ADD: string = '+'

  /** Hollow circle / privacy off — visible */
  public static readonly EYE: string = '○'

  /** Filled circle / privacy on — hidden */
  public static readonly EYE_SLASH: string = '●'
}

/**
 * Reusable icon component using Unicode text symbols.
 *
 * Usage:
 *   IconFontView({
 *     code: IconFont.HOME,
 *     iconSize: 20,
 *     iconColor: $r('app.color.accent_blue')
 *   })
 */
@ComponentV2
export struct IconFontView {
  @Param public code: string = '★'
  @Param public iconSize: number = 20
  @Param public iconColor: ResourceColor = Color.Black

  public build(): void {
    Text(this.code)
      .fontSize(this.iconSize)
      .fontColor(this.iconColor)
  }
}
