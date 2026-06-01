/* (c) Copyright XiatStudio 2026~2026 */
import Foundation
import SwiftUI
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var todayAmount: Double = 0
    @Published var todayProgress: Double = 0
    @Published var todayStatus: WorkStatus = .notStarted
    @Published var monthSummary = MonthSummary(
        workingDaysThisMonth: 0, workingDaysElapsed: 0, monthProgress: 0,
        monthEarnings: 0, totalMonthEarnings: 0, daysUntilPayday: 0, isPayday: false,
        paydayCycleProgress: 0, paydayCycleTotal: 0, paydayCycleElapsed: 0
    )
    @Published var currency = "¥"
    @Published var isConfigured = false
    @Published var isPrivacyMode = false
    @Published var isVoluntaryOvertimeActive = false
    @Published var voluntaryOTWeeklyEarnings: Double = 0

    private var calculator: EarningsCalculator?
    private var timer: Timer?
    private let store = AppGroupStore()
    private var lastConfiguredAt: Date?
    private var previousStatus: WorkStatus = .notStarted

    init() {
        isPrivacyMode = store.isPrivacyMode
        isVoluntaryOvertimeActive = store.voluntaryOTActive
        voluntaryOTWeeklyEarnings = store.voluntaryOTWeeklyEarnings
    }

    func configure(with config: EarningsConfig) {
        if let last = lastConfiguredAt, last == config.updatedAt { return }
        lastConfiguredAt = config.updatedAt

        calculator = config.calculator
        currency = config.currency
        isConfigured = config.monthlyPay > 0
        store.sync(
            monthlyPay: config.monthlyPay,
            workingDaysPerMonth: config.workingDaysPerMonth,
            currency: config.currency,
            taxRate: config.taxRate,
            workStartMinutes: config.workStartMinutes,
            workEndMinutes: config.workEndMinutes,
            breaks: config.validBreaks,
            dayOverridesJSON: config.dayOverridesJSON
        )
        refresh()
        startTimer()
    }

    func refresh() {
        guard let calc = calculator else { return }
        // Re-read from store so widget toggles are picked up on next refresh
        isVoluntaryOvertimeActive = store.voluntaryOTActive
        let totalOTSeconds = store.voluntaryOvertimeTotalSeconds()
        let today = calc.calculateTodayEarnings(voluntaryOvertimeTotalSeconds: totalOTSeconds)

        // Reset voluntary OT accumulation when a new work day begins
        // (transition from notStarted to working)
        if today.status == .working && previousStatus == .notStarted {
            store.bankDailyVoluntaryOT(secondRate: calc.secondRate)
        }
        previousStatus = today.status
        voluntaryOTWeeklyEarnings = store.voluntaryOTWeeklyEarnings

        withAnimation(.easeInOut(duration: 0.3)) {
            todayAmount = today.amount
            todayProgress = today.progress
            todayStatus = today.status
        }
        monthSummary = calc.calculateMonthSummary()
    }

    func togglePrivacy() {
        isPrivacyMode.toggle()
        store.isPrivacyMode = isPrivacyMode
    }

    /// Toggles voluntary overtime on/off. When starting, begins a new session counting from now.
    /// When ending, accumulates the current session's elapsed time. Sessions accumulate across
    /// toggles within the same day and reset on the next working day.
    func toggleVoluntaryOvertime() {
        if isVoluntaryOvertimeActive {
            store.endVoluntaryOTSession()
            // Bank immediately so the weekly card appears right after ending OT
            if let calc = calculator {
                store.bankDailyVoluntaryOT(secondRate: calc.secondRate)
            }
        } else {
            store.startVoluntaryOTSession()
        }
        isVoluntaryOvertimeActive = store.voluntaryOTActive
        refresh()
        voluntaryOTWeeklyEarnings = store.voluntaryOTWeeklyEarnings
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }

    var statusText: String {
        switch todayStatus {
        case .notStarted: "还没开始"
        case .working: "窝囊费积累中"
        case .onBreak: "休息中"
        case .completed: "下班啦！"
        case .overtime: "加班攒钱中 💪"
        case .voluntaryOvertime: "自愿加班中 😤"
        case .dayOff: "休息日"
        }
    }

    var statusColor: Color {
        switch todayStatus {
        case .notStarted: .gray
        case .working: .green
        case .onBreak: .orange
        case .completed: .blue
        case .overtime: Color(red: 0.78, green: 0.35, blue: 0.35)
        case .voluntaryOvertime: Color(red: 0.78, green: 0.35, blue: 0.35)
        case .dayOff: Color(red: 0.35, green: 0.73, blue: 0.67)
        }
    }

    var paydayText: String {
        if monthSummary.isPayday { return "今天发工资!" }
        if monthSummary.daysUntilPayday == 1 { return "明天发工资" }
        return "还有 \(monthSummary.daysUntilPayday) 天发工资"
    }

    /// Formatted weekly voluntary OT earnings string, or nil if zero.
    var voluntaryOTWeeklyText: String? {
        guard voluntaryOTWeeklyEarnings > 0 else { return nil }
        return String(format: "%.2f", voluntaryOTWeeklyEarnings)
    }
}
