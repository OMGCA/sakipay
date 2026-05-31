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

    private var calculator: EarningsCalculator?
    private var timer: Timer?
    private let store = AppGroupStore()
    private var lastConfiguredAt: Date?

    init() {
        isPrivacyMode = store.isPrivacyMode
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
        let today = calc.calculateTodayEarnings()
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
        case .dayOff: "休息日"
        }
    }

    var statusColor: Color {
        switch todayStatus {
        case .notStarted: .gray
        case .working: .green
        case .onBreak: .orange
        case .completed: .blue
        case .dayOff: .gray
        }
    }

    var paydayText: String {
        if monthSummary.isPayday { return "今天发工资!" }
        if monthSummary.daysUntilPayday == 1 { return "明天发工资" }
        return "还有 \(monthSummary.daysUntilPayday) 天发工资"
    }
}
