/* (c) Copyright XiatStudio 2026~2026 */
import { HolidayCalendarData, DayOverride, DayType } from '../models/HolidayCalendar'
import { IconFont } from '../services/IconFont'

/**
 * Resolved display type for a calendar day cell (used for colour coding).
 */
enum ResolvedDayType {
  NORMAL,
  WEEKEND,
  PUBLIC_HOLIDAY,
  ADJUSTED_WORKDAY,
  USER_HOLIDAY,
  USER_OVERTIME
}

/**
 * Data for a single day cell in the calendar grid.
 */
class DayCellData {
  public date: Date | null = null
  public dayNumber: number = 0
  public resolvedType: ResolvedDayType = ResolvedDayType.NORMAL
  public isToday: boolean = false
  public dateString: string = ''
  public overtimeMultiplier: number = 1.0
}

type OverrideSaveCallback = (override: DayOverride) => void
type OverrideResetCallback = (dateString: string) => void
type CloseCallback = () => void

/**
 * Calendar popup where users can view the holiday calendar and
 * designate individual days as workday, holiday, or overtime.
 */
@ComponentV2
export struct CalendarSheetPage {
  @Param public holidayCalendar: HolidayCalendarData | null = null
  @Param public dayOverrides: DayOverride[] = []
  @Param public onOverrideSaved: OverrideSaveCallback = (override: DayOverride): void => {}
  @Param public onOverrideReset: OverrideResetCallback = (dateString: string): void => {}
  @Param public onClose: CloseCallback = (): void => {}
  @Param public workTotalHours: number = 8

  @Local private displayedYear: number = new Date().getFullYear()
  @Local private displayedMonth: number = new Date().getMonth()
  @Local private selectedDateString: string = ''
  @Local private selectedDayType: DayType = DayType.NORMAL
  @Local private selectedOvertimeMultiplier: number = 2.0

  // Day cells and reactivity
  @Local private dayCells: DayCellData[] = []
  @Local private rebuildKey: number = 0
  @Local private selectSlideX: number = 0
  @Local private selectSlideY: number = 0
  @Local private animatingCellKey: string = ''

  private static readonly WEEKDAY_LABELS: string[] = ['一', '二', '三', '四', '五', '六', '日']

  // ---- Override map ----

  private buildOverrideMap(): Map<string, DayOverride> {
    const map: Map<string, DayOverride> = new Map()
    for (const override of this.dayOverrides) {
      map.set(override.dateString, override)
    }
    return map
  }

  // ---- Day type resolution ----

  private resolveDayType(date: Date, overrideMap: Map<string, DayOverride>): ResolvedDayType {
    const ds: string = this.dateStringFromDate(date)
    const override: DayOverride | undefined = overrideMap.get(ds)
    if (override !== undefined) {
      if (override.dayType === DayType.HOLIDAY) {
        return ResolvedDayType.USER_HOLIDAY
      }
      if (override.dayType === DayType.OVERTIME) {
        return ResolvedDayType.USER_OVERTIME
      }
    }
    const m: number = date.getMonth() + 1
    const d: number = date.getDate()
    if (this.holidayCalendar !== null) {
      if (this.holidayCalendar.isHoliday(m, d)) {
        return ResolvedDayType.PUBLIC_HOLIDAY
      }
      if (this.holidayCalendar.isAdjustedWorkday(m, d)) {
        return ResolvedDayType.ADJUSTED_WORKDAY
      }
    }
    const wd: number = date.getDay()
    if (wd === 0 || wd === 6) {
      return ResolvedDayType.WEEKEND
    }
    return ResolvedDayType.NORMAL
  }

  // ---- Build day cells ----

  private buildDayCells(): void {
    const year: number = this.displayedYear
    const month: number = this.displayedMonth
    const daysInMonth: number = new Date(year, month + 1, 0).getDate()
    const firstDay: number = new Date(year, month, 1).getDay()
    const leadingEmpty: number = firstDay === 0 ? 6 : firstDay - 1

    const overrideMap: Map<string, DayOverride> = this.buildOverrideMap()
    const today: Date = new Date()
    const todayStr: string = this.dateStringFromDate(today)

    const cells: DayCellData[] = []

    for (let i: number = 0; i < leadingEmpty; i++) {
      const cell: DayCellData = new DayCellData()
      cells.push(cell)
    }

    for (let d: number = 1; d <= daysInMonth; d++) {
      const date: Date = new Date(year, month, d)
      const ds: string = this.dateStringFromDate(date)
      const cell: DayCellData = new DayCellData()
      cell.date = date
      cell.dayNumber = d
      cell.dateString = ds
      cell.resolvedType = this.resolveDayType(date, overrideMap)
      cell.isToday = ds === todayStr

      const override: DayOverride | undefined = overrideMap.get(ds)
      if (override !== undefined && override.dayType === DayType.OVERTIME) {
        cell.overtimeMultiplier = override.overtimeMultiplier
      }

      cells.push(cell)
    }

    this.dayCells = cells
    this.rebuildKey = this.rebuildKey + 1
  }

  // ---- Lifecycle ----

  public aboutToAppear(): void {
    this.buildDayCells()
    if (this.dayOverrides.length > 0) {
      const first: DayOverride = this.dayOverrides[0]
      this.selectedDateString = first.dateString
      this.selectedDayType = first.dayType
      this.selectedOvertimeMultiplier = first.overtimeMultiplier
    }
  }

  // ---- Build ----

  public build(): void {
    Column() {
      // Header
      Row() {
        Text('工作日日历')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('✕')
          .fontSize(20)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.onClose()
          })
      }
      .width('100%')
      .padding({ top: 16, bottom: 12, left: 16, right: 16 })

      Scroll() {
        Column() {
          this.monthNav()
          this.weekdayHeader()
          this.dayGrid()
          Divider().margin({ top: 12, bottom: 8 })
          this.dayTypePicker()
          Blank().height(20)
        }
        .padding({ left: 16, right: 16 })
      }
      .height(520)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .backgroundColor($r('app.color.page_background'))
    .borderRadius(16)
  }

  // ---- Month navigation ----

  @Builder
  private monthNav(): void {
    Row() {
      Text('‹')
        .fontSize(26)
        .fontWeight(FontWeight.Lighter)
        .fontColor($r('app.color.accent_blue'))
        .padding({ left: 4, right: 12, top: 2, bottom: 2 })
        .onClick(() => { this.changeMonth(-1) })

      Text(`${this.displayedYear}年${this.displayedMonth + 1}月`)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Text('›')
        .fontSize(26)
        .fontWeight(FontWeight.Lighter)
        .fontColor($r('app.color.accent_blue'))
        .padding({ left: 12, right: 4, top: 2, bottom: 2 })
        .onClick(() => { this.changeMonth(1) })
    }
    .width('100%')
    .padding({ top: 8, bottom: 16 })
  }

  private changeMonth(delta: number): void {
    const newMonth: number = this.displayedMonth + delta
    const date: Date = new Date(this.displayedYear, newMonth, 1)
    this.displayedYear = date.getFullYear()
    this.displayedMonth = date.getMonth()
    this.buildDayCells()
  }

  // ---- Weekday header ----

  @Builder
  private weekdayHeader(): void {
    Row() {
      ForEach(CalendarSheetPage.WEEKDAY_LABELS, (label: string) => {
        Text(label)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
      })
    }
    .width('100%')
    .padding({ bottom: 4 })
  }

  // ---- Day grid ----

  @Builder
  private dayGrid(): void {
    Column() {
      Grid() {
        ForEach(this.dayCells, (cell: DayCellData) => {
          GridItem() {
            this.dayCellContent(cell)
          }
        })
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .rowsGap(2)
      .columnsGap(2)
      .width('100%')
      .key(`day_grid_${this.rebuildKey}`)
    }
    .width('100%')
  }

  @Builder
  private dayCellContent(cell: DayCellData): void {
    if (cell.date === null) {
      Row().width('100%').aspectRatio(1)
    } else {
      Column() {
        Text(cell.dayNumber.toString())
          .fontSize(14)
          .fontWeight(cell.isToday ? FontWeight.Bold : FontWeight.Regular)
          .fontColor(this.dayTextColor(cell))

        if (cell.resolvedType === ResolvedDayType.USER_OVERTIME) {
          Text(`${cell.overtimeMultiplier}x`)
            .fontSize(8)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
        }
        if (cell.resolvedType === ResolvedDayType.ADJUSTED_WORKDAY) {
          Text('调')
            .fontSize(8)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
        }
      }
      .width('100%')
      .aspectRatio(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius('50%')
      .backgroundColor(this.dayBgColor(cell.resolvedType))
      .border({
        width: this.isCellHighlighted(cell) ? 2 : 0,
        color: this.isCellSelected(cell) ? $r('app.color.accent_orange') : $r('app.color.accent_blue'),
        radius: '50%'
      })
      .translate({
        x: cell.dateString === this.animatingCellKey ? this.selectSlideX : 0,
        y: cell.dateString === this.animatingCellKey ? this.selectSlideY : 0
      })
      .onClick(() => { this.selectCell(cell) })
    }
  }

  private isCellSelected(cell: DayCellData): boolean {
    return cell.dateString === this.selectedDateString
  }

  private isCellHighlighted(cell: DayCellData): boolean {
    return cell.dateString === this.selectedDateString || cell.isToday
  }

  private findCellIndex(dateString: string): number {
    for (let i: number = 0; i < this.dayCells.length; i++) {
      if (this.dayCells[i].dateString === dateString) {
        return i
      }
    }
    return -1
  }

  private dayBgColor(type: ResolvedDayType): ResourceColor {
    if (type === ResolvedDayType.PUBLIC_HOLIDAY || type === ResolvedDayType.USER_HOLIDAY) {
      return $r('app.color.calendar_holiday_bg')
    }
    if (type === ResolvedDayType.ADJUSTED_WORKDAY || type === ResolvedDayType.USER_OVERTIME) {
      return $r('app.color.calendar_adjusted_bg')
    }
    if (type === ResolvedDayType.WEEKEND) {
      return $r('app.color.progress_track')
    }
    return Color.Transparent
  }

  private dayTextColor(cell: DayCellData): ResourceColor {
    if (cell.dateString === this.selectedDateString) {
      return $r('app.color.text_primary')
    }
    const type: ResolvedDayType = cell.resolvedType
    if (type === ResolvedDayType.WEEKEND || type === ResolvedDayType.PUBLIC_HOLIDAY ||
        type === ResolvedDayType.USER_HOLIDAY) {
      return $r('app.color.text_secondary')
    }
    return $r('app.color.text_primary')
  }

  // ---- Cell selection ----

  private selectCell(cell: DayCellData): void {
    if (cell.date === null) {
      return
    }

    // Compute slide direction from previous selection
    const prevIdx: number = this.findCellIndex(this.selectedDateString)
    const newIdx: number = this.findCellIndex(cell.dateString)
    if (prevIdx >= 0 && newIdx >= 0) {
      const cols: number = 7
      const prevCol: number = prevIdx % cols
      const prevRow: number = Math.floor(prevIdx / cols)
      const newCol: number = newIdx % cols
      const newRow: number = Math.floor(newIdx / cols)
      const dx: number = newCol - prevCol
      const dy: number = newRow - prevRow
      const dist: number = Math.sqrt(dx * dx + dy * dy)
      if (dist < 4) {
        this.selectSlideX = dx * 6
        this.selectSlideY = dy * 6
      } else {
        this.selectSlideX = 0
        this.selectSlideY = 0
      }
    } else {
      this.selectSlideX = 0
      this.selectSlideY = 0
    }

    this.animatingCellKey = cell.dateString
    this.selectedDateString = cell.dateString

    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.selectSlideX = 0
      this.selectSlideY = 0
    })

    const overrideMap: Map<string, DayOverride> = this.buildOverrideMap()
    const existing: DayOverride | undefined = overrideMap.get(cell.dateString)
    if (existing !== undefined) {
      this.selectedDayType = existing.dayType
      this.selectedOvertimeMultiplier = existing.overtimeMultiplier
    } else {
      this.selectedDayType = DayType.NORMAL
      this.selectedOvertimeMultiplier = 2.0
    }
  }

  // ---- Day type picker ----

  @Builder
  private dayTypePicker(): void {
    Column() {
      if (this.selectedDateString !== '') {
        Text(this.selectedDateString)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .padding({ bottom: 8 })
      } else {
        Text('请点击上方日期选择')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .padding({ bottom: 8 })
      }

      if (this.selectedDateString !== '') {
        this.calendarHint()
      }

      Row() {
        this.typePill('默认', DayType.NORMAL)
        this.typePill('休息日', DayType.HOLIDAY)
        this.typePill('加班日', DayType.OVERTIME)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .padding({ top: 8, bottom: 8 })

      // Overtime multiplier
      if (this.selectedDayType === DayType.OVERTIME) {
        Row() {
          Text('加班倍率')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text('−')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent_blue'))
            .padding({ left: 8, right: 8 })
            .onClick(() => {
              if (this.selectedOvertimeMultiplier > 1.0) {
                this.selectedOvertimeMultiplier = this.selectedOvertimeMultiplier - 0.5
              }
            })
          Text(`${this.selectedOvertimeMultiplier.toFixed(1)}x`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .padding({ left: 4, right: 4 })
          Text('+')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent_blue'))
            .padding({ left: 8, right: 8 })
            .onClick(() => {
              if (this.selectedOvertimeMultiplier < 5.0) {
                this.selectedOvertimeMultiplier = this.selectedOvertimeMultiplier + 0.5
              }
            })
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })
      }

      Row() {
        Button('重置')
          .fontSize(14)
          .fontColor($r('app.color.accent_orange'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            if (this.selectedDateString !== '') {
              this.onOverrideReset(this.selectedDateString)
              setTimeout(() => {
                this.buildDayCells()
              }, 100)
            }
          })

        Blank()

        Button('保存')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.accent_blue'))
          .borderRadius(8)
          .padding({ left: 24, right: 24 })
          .onClick(() => { this.saveOverride() })
      }
      .width('100%')
      .padding({ top: 12 })
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.card_border'), radius: 12 })
    .shadow({ radius: 8, color: $r('app.color.card_shadow'), offsetY: 2 })
  }

  @Builder
  private calendarHint(): void {
    if (this.holidayCalendar !== null && this.selectedDateString !== '') {
      if (this.holidayCalendar.isHoliday(this.selectedMonth(), this.selectedDay())) {
        Text('法定节假日 — 默认休息')
          .fontSize(12)
          .fontColor($r('app.color.accent_green'))
          .padding({ bottom: 4 })
      } else if (this.holidayCalendar.isAdjustedWorkday(this.selectedMonth(), this.selectedDay())) {
        Text('调休工作日 — 默认上班')
          .fontSize(12)
          .fontColor($r('app.color.accent_orange'))
          .padding({ bottom: 4 })
      }
    }
  }

  private selectedMonth(): number {
    if (this.selectedDateString === '') {
      return 1
    }
    return parseInt(this.selectedDateString.split('-')[1])
  }

  private selectedDay(): number {
    if (this.selectedDateString === '') {
      return 1
    }
    return parseInt(this.selectedDateString.split('-')[2])
  }

  // ---- Type pill ----

  @Builder
  private typePill(label: string, type: DayType): void {
    Column() {
      Text(label)
        .fontSize(12)
        .fontWeight(this.selectedDayType === type ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.selectedDayType === type ? this.pillAccent(type) : $r('app.color.text_secondary'))
    }
    .padding({ top: 6, bottom: 6, left: 10, right: 10 })
    .borderRadius(16)
    .border({
      width: this.selectedDayType === type ? 1.5 : 1,
      color: this.selectedDayType === type ? this.pillAccent(type) : $r('app.color.card_border'),
      radius: 16
    })
    .backgroundColor(this.selectedDayType === type ? this.pillBg(type) : Color.Transparent)
    .onClick(() => {
      this.selectedDayType = type
    })
  }

  private pillAccent(type: DayType): ResourceColor {
    if (type === DayType.HOLIDAY) {
      return '#AF52DE'
    }
    if (type === DayType.OVERTIME) {
      return $r('app.color.accent_orange')
    }
    return $r('app.color.accent_blue')
  }

  private pillBg(type: DayType): ResourceColor {
    if (type === DayType.HOLIDAY) {
      return $r('app.color.calendar_holiday_bg')
    }
    if (type === DayType.OVERTIME) {
      return $r('app.color.calendar_adjusted_bg')
    }
    return $r('app.color.calendar_normal_bg')
  }

  // ---- Save ----

  private saveOverride(): void {
    if (this.selectedDateString === '') {
      return
    }
    const override: DayOverride = new DayOverride()
    override.dateString = this.selectedDateString
    override.dayType = this.selectedDayType
    override.overtimeMultiplier = this.selectedOvertimeMultiplier
    override.customWorkHours = this.workTotalHours > 0 ? this.workTotalHours : null

    this.onOverrideSaved(override)
    // Defer rebuild so @Param dayOverrides syncs from parent re-render first
    setTimeout(() => {
      this.buildDayCells()
    }, 100)
  }

  // ---- Helpers ----

  private dateStringFromDate(date: Date): string {
    const y: number = date.getFullYear()
    const m: number = date.getMonth() + 1
    const d: number = date.getDate()
    return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`
  }
}
