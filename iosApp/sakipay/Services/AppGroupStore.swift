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
        case isPaused
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

        let schedule = WorkSchedule(workStartMinutes: wsMin, workEndMinutes: weMin, breaks: breaks)
        return EarningsCalculator(monthlyPay: monthlyPay, workingDaysPerMonth: workingDays,
                                 schedule: schedule, payDay: 15, taxRate: taxRate,
                                 dayOverrides: dayOverrides)
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

    /// User-armed pause. Unlike the voluntary-OT session this is *sticky*: it stays on across
    /// days, app launches and schedule boundaries until the user switches it off again.
    var isPaused: Bool {
        get { defaults?.bool(forKey: Key.isPaused.rawValue) ?? false }
        set {
            defaults?.set(newValue, forKey: Key.isPaused.rawValue)
            defaults?.synchronize()
        }
    }

    // MARK: - Voluntary Overtime Session State
    //
    // Every transition is performed by the shared Kotlin logic. This store only
    // marshals the persisted fields to/from the Kotlin state document, so the app
    // and the widget settle overtime identically no matter where it is toggled.

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

    /// Computes the total voluntary OT seconds at the given moment.
    ///
    /// - Parameter mutatesState: Whether a stale date may reset the persisted session.
    ///   The default (`true`) is correct when evaluating the *live* current moment: a session
    ///   left over from a previous day is finished, so its state is cleared.
    ///   Callers that evaluate **hypothetical future dates** (the widget timeline provider
    ///   builds entries for upcoming refresh points, including the next day's work start) must
    ///   pass `false` — otherwise a probe for tomorrow would silently end a session that is
    ///   still running today, discarding its elapsed time before it can be banked.
    func voluntaryOvertimeTotalSeconds(now: Date = Date(),
                                       calendar: Calendar = .current,
                                       mutatesState: Bool = true) -> Double {
        let result = SakipayBridge.otTotalSeconds(stateJson: otStateJson(), at: now, mutatesState: mutatesState)
        if mutatesState {
            writeOtState(result.state)
        }
        return result.seconds
    }

    /// Starts a new voluntary OT session. Resets accumulated if the stored date is stale.
    func startVoluntaryOTSession(now: Date = Date(), calendar: Calendar = .current) {
        let next = SakipayBridge.otStart(stateJson: otStateJson(), at: now)
        writeOtState(next)
    }

    /// Ends the current voluntary OT session, adding its elapsed time to the accumulated total
    /// and settling the day's total into the weekly pool at the current per-second rate.
    func endVoluntaryOTSession(now: Date = Date(), calendar: Calendar = .current) {
        let rate = readCalculator().secondRate
        let next = SakipayBridge.otEnd(stateJson: otStateJson(), at: now, secondRate: rate)
        writeOtState(next)
    }

    /// Converts the daily accumulated OT seconds into money and adds to the weekly total.
    /// Resets the daily accumulated and the stored date. Call this when a new work day begins.
    func bankDailyVoluntaryOT(secondRate: Double, now: Date = Date(), calendar: Calendar = .current) {
        let next = SakipayBridge.otBankDaily(stateJson: otStateJson(), at: now, secondRate: secondRate)
        writeOtState(next)
    }

    // MARK: - Private

    private func otStateJson() -> String {
        let state: [String: Any] = [
            "active": voluntaryOTActive,
            "accumulatedSeconds": voluntaryOTAccumulated,
            "dateString": voluntaryOTDate,
            "sessionStartEpochSeconds": voluntaryOTSessionStart,
            "weeklyEarnings": voluntaryOTWeeklyEarnings,
            "weekStart": voluntaryOTWeekStart,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: state),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    private func writeOtState(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        voluntaryOTActive = (obj["active"] as? Bool) ?? false
        voluntaryOTAccumulated = (obj["accumulatedSeconds"] as? Double) ?? 0
        voluntaryOTDate = (obj["dateString"] as? String) ?? ""
        voluntaryOTSessionStart = (obj["sessionStartEpochSeconds"] as? Double) ?? 0
        voluntaryOTWeeklyEarnings = (obj["weeklyEarnings"] as? Double) ?? 0
        voluntaryOTWeekStart = (obj["weekStart"] as? String) ?? ""
    }
}
