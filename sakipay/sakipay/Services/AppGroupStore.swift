/* (c) Copyright XiatStudio 2026~2026 */
import Foundation

final class AppGroupStore {
    static let suiteName = "group.com.xiatstudio.sakipay"

    enum Key: String {
        case monthlyPay, workingDaysPerMonth, currency, taxRate
        case workStartMinutes, workEndMinutes
        case breaksJSON
        case isPrivacyMode
    }

    private let defaults: UserDefaults?

    init() {
        defaults = UserDefaults(suiteName: Self.suiteName)
        if defaults == nil {
            print("[sakipay] WARNING: AppGroup '\(Self.suiteName)' not available — widget will show zeros")
        }
    }

    func sync(monthlyPay: Double, workingDaysPerMonth: Double, currency: String, taxRate: Double,
              workStartMinutes: Int, workEndMinutes: Int, breaks: [BreakSegment]) {
        defaults?.set(monthlyPay, forKey: Key.monthlyPay.rawValue)
        defaults?.set(workingDaysPerMonth, forKey: Key.workingDaysPerMonth.rawValue)
        defaults?.set(currency, forKey: Key.currency.rawValue)
        defaults?.set(taxRate, forKey: Key.taxRate.rawValue)
        defaults?.set(workStartMinutes, forKey: Key.workStartMinutes.rawValue)
        defaults?.set(workEndMinutes, forKey: Key.workEndMinutes.rawValue)

        if let data = try? JSONEncoder().encode(breaks.filter(\.isValid)),
           let str = String(data: data, encoding: .utf8) {
            defaults?.set(str, forKey: Key.breaksJSON.rawValue)
        }
        // Force flush to disk so the widget extension process sees fresh data immediately
        defaults?.synchronize()
    }

    func readCalculator() -> EarningsCalculator {
        let monthlyPay = defaults?.double(forKey: Key.monthlyPay.rawValue) ?? 0
        let workingDays = defaults?.double(forKey: Key.workingDaysPerMonth.rawValue) ?? 21.75
        let taxRate = defaults?.double(forKey: Key.taxRate.rawValue) ?? 0
        let wsMin = defaults?.integer(forKey: Key.workStartMinutes.rawValue) ?? 540
        let weMin = defaults?.integer(forKey: Key.workEndMinutes.rawValue) ?? 1080

        let breaks: [BreakSchedule]
        if let json = defaults?.string(forKey: Key.breaksJSON.rawValue),
           let data = json.data(using: .utf8),
           let segments = try? JSONDecoder().decode([BreakSegment].self, from: data) {
            breaks = segments.filter(\.isValid).map(\.asBreakSchedule)
        } else {
            breaks = [BreakSchedule(startMinutes: 720, endMinutes: 810)]
        }

        let schedule = WorkSchedule(workStartMinutes: wsMin, workEndMinutes: weMin, breaks: breaks)
        return EarningsCalculator(monthlyPay: monthlyPay, workingDaysPerMonth: workingDays, schedule: schedule, payDay: 15, taxRate: taxRate)
    }

    func readCurrency() -> String {
        defaults?.string(forKey: Key.currency.rawValue) ?? "¥"
    }

    var isPrivacyMode: Bool {
        get { defaults?.bool(forKey: Key.isPrivacyMode.rawValue) ?? false }
        set {
            defaults?.set(newValue, forKey: Key.isPrivacyMode.rawValue)
            defaults?.synchronize()
        }
    }
}
