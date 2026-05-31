/* (c) Copyright XiatStudio 2026~2026 */
import Foundation

final class AppGroupStore {
    static let suiteName = "group.com.xiatstudio.sakipay"

    enum Key: String {
        case monthlyPay, workingDaysPerMonth, currency, taxRate
        case workStartMinutes, workEndMinutes
        case breaksJSON
        case dayOverridesJSON
        case isPrivacyMode
        case voluntaryOTActive
        case voluntaryOTAccumulated
        case voluntaryOTDate
        case voluntaryOTSessionStart
        case voluntaryOTWeeklyEarnings
        case voluntaryOTWeekStart
    }

    private let defaults: UserDefaults?

    init() {
        defaults = UserDefaults(suiteName: Self.suiteName)
        if defaults == nil {
            print("[sakipay] WARNING: AppGroup '\(Self.suiteName)' not available — widget will show zeros")
        }
    }

    func sync(monthlyPay: Double, workingDaysPerMonth: Double, currency: String, taxRate: Double,
              workStartMinutes: Int, workEndMinutes: Int, breaks: [BreakSegment],
              dayOverridesJSON: String = "") {
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

        if !dayOverridesJSON.isEmpty {
            defaults?.set(dayOverridesJSON, forKey: Key.dayOverridesJSON.rawValue)
        } else {
            defaults?.removeObject(forKey: Key.dayOverridesJSON.rawValue)
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

        let dayOverrides: [String: DayOverride]
        if let json = defaults?.string(forKey: Key.dayOverridesJSON.rawValue),
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([DayOverride].self, from: data) {
            dayOverrides = Dictionary(uniqueKeysWithValues: decoded.map { ($0.dateString, $0) })
        } else {
            dayOverrides = [:]
        }

        let hc = HolidayCalendarService.shared.currentCalendar()
        let schedule = WorkSchedule(workStartMinutes: wsMin, workEndMinutes: weMin, breaks: breaks)
        return EarningsCalculator(monthlyPay: monthlyPay, workingDaysPerMonth: workingDays,
                                 schedule: schedule, payDay: 15, taxRate: taxRate,
                                 holidayCalendar: hc, dayOverrides: dayOverrides)
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

    // MARK: - Voluntary Overtime Session State

    /// Whether a voluntary OT session is currently active.
    var voluntaryOTActive: Bool {
        get { defaults?.bool(forKey: Key.voluntaryOTActive.rawValue) ?? false }
        set {
            defaults?.set(newValue, forKey: Key.voluntaryOTActive.rawValue)
            defaults?.synchronize()
        }
    }

    /// Total OT seconds accumulated from completed sessions today (excludes the current session).
    var voluntaryOTAccumulated: Double {
        get { defaults?.double(forKey: Key.voluntaryOTAccumulated.rawValue) ?? 0 }
        set {
            defaults?.set(newValue, forKey: Key.voluntaryOTAccumulated.rawValue)
            defaults?.synchronize()
        }
    }

    /// The date string ("YYYY-MM-DD") for which the accumulated value is valid.
    /// Reset accumulated to 0 when this doesn't match today.
    var voluntaryOTDate: String {
        get { defaults?.string(forKey: Key.voluntaryOTDate.rawValue) ?? "" }
        set {
            defaults?.set(newValue, forKey: Key.voluntaryOTDate.rawValue)
            defaults?.synchronize()
        }
    }

    /// Unix timestamp (seconds since 1970) of when the current session started. 0 when inactive.
    var voluntaryOTSessionStart: Double {
        get { defaults?.double(forKey: Key.voluntaryOTSessionStart.rawValue) ?? 0 }
        set {
            defaults?.set(newValue, forKey: Key.voluntaryOTSessionStart.rawValue)
            defaults?.synchronize()
        }
    }

    /// Computes the total voluntary OT seconds for the current moment.
    /// Returns 0 if no session is active or if the stored date doesn't match today.
    func voluntaryOvertimeTotalSeconds(now: Date = Date(), calendar: Calendar = .current) -> Double {
        guard voluntaryOTActive else { return 0 }

        let today = dateString(from: now, calendar: calendar)
        if voluntaryOTDate != today {
            // Stale state from a previous day — reset
            voluntaryOTActive = false
            voluntaryOTAccumulated = 0
            voluntaryOTDate = ""
            voluntaryOTSessionStart = 0
            return 0
        }

        let sessionElapsed = max(0, now.timeIntervalSince1970 - voluntaryOTSessionStart)
        return voluntaryOTAccumulated + sessionElapsed
    }

    /// Ends the current voluntary OT session, adding its elapsed time to the accumulated total.
    func endVoluntaryOTSession(now: Date = Date(), calendar: Calendar = .current) {
        guard voluntaryOTActive else { return }
        let sessionElapsed = max(0, now.timeIntervalSince1970 - voluntaryOTSessionStart)
        voluntaryOTAccumulated += sessionElapsed
        voluntaryOTActive = false
        voluntaryOTSessionStart = 0
    }

    /// Starts a new voluntary OT session. Resets accumulated if the stored date is stale.
    func startVoluntaryOTSession(now: Date = Date(), calendar: Calendar = .current) {
        let today = dateString(from: now, calendar: calendar)
        if voluntaryOTDate != today {
            voluntaryOTAccumulated = 0
            voluntaryOTDate = today
        }
        voluntaryOTActive = true
        voluntaryOTSessionStart = now.timeIntervalSince1970
    }

    // MARK: - Weekly Voluntary OT Accumulation

    /// Total OT money the company owes for the current week.
    var voluntaryOTWeeklyEarnings: Double {
        get { defaults?.double(forKey: Key.voluntaryOTWeeklyEarnings.rawValue) ?? 0 }
        set {
            defaults?.set(newValue, forKey: Key.voluntaryOTWeeklyEarnings.rawValue)
            defaults?.synchronize()
        }
    }

    /// Monday date string of the week for which weeklyEarnings is valid.
    var voluntaryOTWeekStart: String {
        get { defaults?.string(forKey: Key.voluntaryOTWeekStart.rawValue) ?? "" }
        set {
            defaults?.set(newValue, forKey: Key.voluntaryOTWeekStart.rawValue)
            defaults?.synchronize()
        }
    }

    /// Converts the daily accumulated OT seconds into money and adds to the weekly total.
    /// Resets the daily accumulated and the stored date. Call this when a new work day begins.
    func bankDailyVoluntaryOT(secondRate: Double, now: Date = Date(), calendar: Calendar = .current) {
        let dailyOT = voluntaryOTAccumulated
        guard dailyOT > 0 else { return }

        let monday = mondayOfWeek(from: now, calendar: calendar)
        if voluntaryOTWeekStart != monday {
            voluntaryOTWeeklyEarnings = 0
            voluntaryOTWeekStart = monday
        }

        voluntaryOTWeeklyEarnings += dailyOT * secondRate
        voluntaryOTAccumulated = 0
        voluntaryOTDate = ""
    }

    private func mondayOfWeek(from date: Date, calendar: Calendar) -> String {
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = 2 // Monday
        guard let monday = calendar.date(from: comps) else {
            return dateString(from: date, calendar: calendar)
        }
        return dateString(from: monday, calendar: calendar)
    }

    private func dateString(from date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
