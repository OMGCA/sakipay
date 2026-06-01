/* (c) Copyright XiatStudio 2026~2026 */
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Toggle Privacy Intent

struct TogglePrivacyIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Privacy Mode"

    @Parameter(title: "Privacy Mode")
    var isOn: Bool

    init() { isOn = false }

    init(isOn: Bool) { self.isOn = isOn }

    func perform() async throws -> some IntentResult {
        let store = AppGroupStore()
        store.isPrivacyMode = isOn
        return .result()
    }
}

// MARK: - Toggle Voluntary Overtime Intent

struct ToggleVoluntaryOvertimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Voluntary Overtime"

    @Parameter(title: "Voluntary Overtime")
    var isOn: Bool

    init() { isOn = false }

    init(isOn: Bool) { self.isOn = isOn }

    func perform() async throws -> some IntentResult {
        let store = AppGroupStore()
        if isOn {
            store.startVoluntaryOTSession()
        } else {
            store.endVoluntaryOTSession()
        }
        return .result()
    }
}

// MARK: - Timeline Entry

struct EarningsEntry: TimelineEntry {
    let date: Date
    let todayAmount: Double
    let todayProgress: Double
    let status: WorkStatus
    let currency: String
    let isPrivacyMode: Bool
    let isVoluntaryOvertimeActive: Bool
}

// MARK: - Provider

struct EarningsProvider: TimelineProvider {
    private let store = AppGroupStore()

    func placeholder(in context: Context) -> EarningsEntry {
        EarningsEntry(date: Date(), todayAmount: 218.50, todayProgress: 0.6, status: .working,
                      currency: "¥", isPrivacyMode: false, isVoluntaryOvertimeActive: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (EarningsEntry) -> Void) {
        let entry = makeEntry(for: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EarningsEntry>) -> Void) {
        let now = Date()
        let calc = store.readCalculator()
        let voluntaryOT = store.voluntaryOTActive
        let totalOTSeconds = store.voluntaryOvertimeTotalSeconds(now: now)
        let today = calc.calculateTodayEarnings(at: now, voluntaryOvertimeTotalSeconds: totalOTSeconds)
        let privacy = store.isPrivacyMode
        let entry = EarningsEntry(
            date: now,
            todayAmount: today.amount,
            todayProgress: today.progress,
            status: today.status,
            currency: store.readCurrency(),
            isPrivacyMode: privacy,
            isVoluntaryOvertimeActive: voluntaryOT
        )

        var entries: [EarningsEntry] = [entry]

        let refreshDates = timelineRefreshDates(from: now, calc: calc, status: today.status)
        for refreshDate in refreshDates {
            let t = calc.calculateTodayEarnings(at: refreshDate,
                                                 voluntaryOvertimeTotalSeconds: store.voluntaryOvertimeTotalSeconds(now: refreshDate))
            entries.append(EarningsEntry(
                date: refreshDate,
                todayAmount: t.amount,
                todayProgress: t.progress,
                status: t.status,
                currency: store.readCurrency(),
                isPrivacyMode: privacy,
                isVoluntaryOvertimeActive: voluntaryOT
            ))
        }

        let policy: TimelineReloadPolicy = .atEnd
        completion(Timeline(entries: entries, policy: policy))
    }

    private func makeEntry(for date: Date) -> EarningsEntry {
        let calc = store.readCalculator()
        let voluntaryOT = store.voluntaryOTActive
        let totalOTSeconds = store.voluntaryOvertimeTotalSeconds(now: date)
        let today = calc.calculateTodayEarnings(at: date, voluntaryOvertimeTotalSeconds: totalOTSeconds)
        return EarningsEntry(
            date: date,
            todayAmount: today.amount,
            todayProgress: today.progress,
            status: today.status,
            currency: store.readCurrency(),
            isPrivacyMode: store.isPrivacyMode,
            isVoluntaryOvertimeActive: voluntaryOT
        )
    }

    private func timelineRefreshDates(from now: Date, calc: EarningsCalculator, status: WorkStatus) -> [Date] {
        let cal = Calendar.current
        var dates: [Date] = []
        let schedule = calc.schedule

        func dateFromMinutes(_ minutes: Int, after base: Date) -> Date? {
            let hour = minutes / 60
            let minute = minutes % 60
            var comps = cal.dateComponents([.year, .month, .day], from: base)
            comps.hour = hour
            comps.minute = minute
            return cal.date(from: comps)
        }

        let interval: Int
        switch status {
        case .working, .onBreak, .overtime, .voluntaryOvertime:
            interval = 5
        case .notStarted:
            interval = 15
        case .completed, .dayOff:
            interval = 0
        }

        if interval > 0 {
            let currentMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
            var checkMin = ((currentMinutes + interval) / interval) * interval

            while checkMin < schedule.workEndMinutes {
                if schedule.breakContaining(checkMin) == nil {
                    if let d = dateFromMinutes(checkMin, after: now) { dates.append(d) }
                }
                checkMin += interval
            }
        }

        var boundaries = [schedule.workStartMinutes, schedule.workEndMinutes]
        for br in schedule.breaks {
            boundaries.append(br.startMinutes)
            boundaries.append(br.endMinutes)
        }
        for boundary in boundaries {
            if let d = dateFromMinutes(boundary, after: now), d > now { dates.append(d) }
        }

        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now) {
            if let nextStart = dateFromMinutes(schedule.workStartMinutes, after: cal.startOfDay(for: tomorrow)) {
                dates.append(nextStart)
            }
        }

        return Array(Set(dates)).sorted().prefix(30).map { $0 }
    }
}

// MARK: - Widget Views

struct sakipayWidgetEntryView: View {
    var entry: EarningsEntry

    var body: some View {
        smallView
    }

    private var smallView: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: entry.todayProgress)
                .stroke(statusColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: entry.todayProgress)

            VStack(spacing: 8) {
                // Voluntary overtime + Privacy toggles
                HStack(spacing: 8) {
                    if entry.status == .completed || entry.status == .voluntaryOvertime {
                        Button(intent: ToggleVoluntaryOvertimeIntent(isOn: !entry.isVoluntaryOvertimeActive)) {
                            Image(systemName: entry.status == .voluntaryOvertime
                                  ? "clock.badge.exclamationmark.fill"
                                  : "clock.badge.exclamationmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(entry.status == .voluntaryOvertime
                                                 ? statusColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(intent: TogglePrivacyIntent(isOn: !entry.isPrivacyMode)) {
                        Image(systemName: entry.isPrivacyMode ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(entry.isPrivacyMode ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                if entry.status == .dayOff {
                    Text("🏖️")
                        .font(.system(size: 22))
                } else if entry.isPrivacyMode {
                    Text("***")
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                } else {
                    Text(entry.currency + String(format: "%.2f", entry.todayAmount))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText(value: entry.todayAmount))
                        .scaleEffect(entry.todayAmount == 0 ? 0.95 : 1.0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: entry.todayAmount)
                }

                Text(entry.todayProgress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: entry.todayProgress))

                HStack(spacing: 3) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 4, height: 4)
                    Text(statusText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
        .containerBackground(.background, for: .widget)
    }

    private var statusColor: Color {
        switch entry.status {
        case .notStarted: .gray
        case .working: .green
        case .onBreak: .orange
        case .completed: .blue
        case .overtime: Color(red: 0.78, green: 0.35, blue: 0.35)
        case .voluntaryOvertime: Color(red: 0.78, green: 0.35, blue: 0.35)
        case .dayOff: Color(red: 0.35, green: 0.73, blue: 0.67)
        }
    }

    private var statusText: String {
        switch entry.status {
        case .notStarted: "未开始"
        case .working: "窝囊费积累中"
        case .onBreak: "休息中"
        case .completed: "下班啦！"
        case .overtime: "加班中 💪"
        case .voluntaryOvertime: "自愿加班中"
        case .dayOff: "休息日"
        }
    }
}

// MARK: - Widget Configuration

struct sakipayWidget: Widget {
    let kind = "com.xiatstudio.sakipay.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EarningsProvider()) { entry in
            sakipayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("今日收入")
        .description("一眼看到今天挣了多少钱。")
        .supportedFamilies([.systemSmall])
    }
}
