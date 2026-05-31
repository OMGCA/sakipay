/* (c) Copyright XiatStudio 2026~2026 */
import SwiftUI

// MARK: - Resolved day type (for colour coding)

enum ResolvedDayType: Equatable {
    case normal
    case weekend
    case publicHoliday
    case adjustedWorkday
    case userHoliday
    case userOvertime(multiplier: Double)
}

// MARK: - Calendar sheet view

struct CalendarSheetView: View {
    @Binding var dayOverrides: [String: DayOverride]
    let holidayCalendar: HolidayCalendar?
    var onSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var displayedMonth: Date = Date()
    @State private var selectedDateString: String = ""
    @State private var selectedDayType: DayType = .normal
    @State private var selectedOvertimeMultiplier: Double = 2.0

    private let calendar = Calendar.current
    private let weekdaySymbols: [String] = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("工作日日历")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 8)

            monthNavigation
            weekdayHeader
            dayGrid
            Divider().padding(.top, 12)
            dayTypePicker
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Month navigation

    private var monthNavigation: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { changeMonth(-1) }
            } label: {
                Text("‹")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.tint)
            }

            Text(monthYearString)
                .font(.headline)
                .frame(maxWidth: .infinity)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { changeMonth(1) }
            } label: {
                Text("›")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.bottom, 12)
    }

    private func changeMonth(_ delta: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
    }

    // MARK: - Weekday header

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Day grid

    private var dayGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 14) {
            ForEach(Array(daysInDisplayedMonth.enumerated()), id: \.offset) { _, date in
                if let date = date {
                    dayCell(date)
                        .padding(.vertical, 4)
                        .onTapGesture { selectDate(date) }
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fill)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let type = resolvedDayType(for: date)
        let ds = dateString(from: date)
        let isSelected = ds == selectedDateString
        let isToday = calendar.isDateInToday(date)

        return VStack(spacing: 0) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 14, weight: isToday ? .bold : .regular))
                .foregroundStyle(dayTextColor(type, isSelected: isSelected))

            if case .userOvertime(let mult) = type {
                Text(String(format: "%.1fx", mult))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary)
            } else if type == .adjustedWorkday {
                Text("调")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fill)
        .background(
            Circle()
                .fill(dayBgColor(type))
                .padding(-8)
        )
        .overlay(
            Circle()
                .strokeBorder(
                    isSelected ? Color.orange : (isToday ? Color.accentColor : Color.clear),
                    lineWidth: 3
                )
                .padding(-8)
        )
        .animation(.easeInOut(duration: 0.2), value: selectedDateString)
    }

    // MARK: - Day type picker (inline below calendar)

    private var dayTypePicker: some View {
        VStack(spacing: 0) {
            // Selected date label
            if !selectedDateString.isEmpty {
                Text(selectedDateString)
                    .font(.subheadline.weight(.bold))
                    .padding(.bottom, 4)

                calendarHint

                // Type pills
                HStack(spacing: 12) {
                    typePill("默认", type: .normal)
                    typePill("休息日", type: .holiday)
                    typePill("加班日", type: .overtime)
                }
                .padding(.vertical, 8)

                // Overtime multiplier
                if selectedDayType == .overtime {
                    HStack {
                        Text("加班倍率")
                            .font(.caption)
                        Spacer()
                        Stepper(
                            String(format: "%.1fx", selectedOvertimeMultiplier),
                            value: $selectedOvertimeMultiplier,
                            in: 1.0...5.0,
                            step: 0.5
                        )
                    }
                    .padding(.vertical, 4)
                }

                // Action buttons
                HStack {
                    if dayOverrides[selectedDateString] != nil {
                        Button("重置") {
                            dayOverrides.removeValue(forKey: selectedDateString)
                            selectedDayType = .normal
                            onSaved?()
                        }
                        .foregroundStyle(.orange)
                    }

                    Spacer()

                    Button("保存") {
                        saveOverride()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                    .background(.blue, in: Capsule())
                }
                .padding(.top, 8)
            } else {
                Text("请点击上方日期选择")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var calendarHint: some View {
        if let hc = holidayCalendar, let date = dateFromSelected {
            let m = calendar.component(.month, from: date)
            let d = calendar.component(.day, from: date)
            if hc.isHoliday(month: m, day: d) {
                Text("法定节假日 — 默认休息")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.bottom, 4)
            } else if hc.isAdjustedWorkday(month: m, day: d) {
                Text("调休工作日 — 默认上班")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.bottom, 4)
            }
        }
    }

    private func typePill(_ label: String, type: DayType) -> some View {
        let isSel = selectedDayType == type
        return Text(label)
            .font(.caption)
            .fontWeight(isSel ? .bold : .regular)
            .foregroundStyle(isSel ? pillAccent(type) : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSel ? pillBg(type) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSel ? pillAccent(type) : .secondary.opacity(0.3), lineWidth: isSel ? 1.5 : 1)
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedDayType = type
                }
            }
    }

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: displayedMonth)
    }

    private var dateFromSelected: Date? {
        guard !selectedDateString.isEmpty else { return nil }
        let parts = selectedDateString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func selectDate(_ date: Date) {
        let ds = dateString(from: date)
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDateString = ds
        }
        if let override = dayOverrides[ds] {
            selectedDayType = override.dayType
            selectedOvertimeMultiplier = override.overtimeMultiplier
        } else {
            selectedDayType = .normal
            selectedOvertimeMultiplier = 2.0
        }
    }

    private func saveOverride() {
        guard !selectedDateString.isEmpty else { return }
        let override = DayOverride(
            dateString: selectedDateString,
            dayType: selectedDayType,
            overtimeMultiplier: selectedOvertimeMultiplier,
            customWorkHours: nil
        )
        dayOverrides[override.dateString] = override
        onSaved?()
    }

    private var daysInDisplayedMonth: [Date?] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)),
              let range = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingEmpty = (firstWeekday + 5) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for day in 1...range.count {
            let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart)
            days.append(date)
        }
        return days
    }

    private func resolvedDayType(for date: Date) -> ResolvedDayType {
        let ds = dateString(from: date)
        if let override = dayOverrides[ds] {
            switch override.dayType {
            case .holiday: return .userHoliday
            case .overtime: return .userOvertime(multiplier: override.overtimeMultiplier)
            case .normal: break
            }
        }
        if let hc = holidayCalendar {
            let m = calendar.component(.month, from: date)
            let d = calendar.component(.day, from: date)
            if hc.isHoliday(month: m, day: d) { return .publicHoliday }
            if hc.isAdjustedWorkday(month: m, day: d) { return .adjustedWorkday }
        }
        let wd = calendar.component(.weekday, from: date)
        return (wd == 1 || wd == 7) ? .weekend : .normal
    }

    private func dayBgColor(_ type: ResolvedDayType) -> Color {
        switch type {
        case .publicHoliday, .userHoliday:
            return .purple.opacity(0.25)
        case .adjustedWorkday, .userOvertime:
            return .orange.opacity(0.30)
        case .weekend:
            return .gray.opacity(0.12)
        default:
            return .clear
        }
    }

    private func dayTextColor(_ type: ResolvedDayType, isSelected: Bool) -> Color {
        if isSelected { return .primary }
        if type == .weekend || type == .publicHoliday || type == .userHoliday {
            return .secondary
        }
        return .primary
    }

    private func pillAccent(_ type: DayType) -> Color {
        switch type {
        case .holiday: return .purple
        case .overtime: return .orange
        default: return .blue
        }
    }

    private func pillBg(_ type: DayType) -> Color {
        switch type {
        case .holiday: return .purple.opacity(0.15)
        case .overtime: return .orange.opacity(0.2)
        default: return .blue.opacity(0.15)
        }
    }

    private func dateString(from date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
