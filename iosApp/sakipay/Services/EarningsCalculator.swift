/* (c) Copyright XiatStudio 2026~2026 */
import Foundation

// MARK: - Data types
//
// These types keep the exact shape the rest of the app already consumes, but
// every rule is delegated to the shared Kotlin logic through SakipayBridge — so
// iOS and HarmonyOS compute identical numbers from one implementation.

/// A single break window expressed in minutes from midnight.
struct BreakSchedule: Equatable, Hashable {
    let startMinutes: Int
    let endMinutes: Int
    var durationMinutes: Int { endMinutes - startMinutes }
}

/// Work-schedule data. Cross-midnight and break arithmetic live in the shared logic.
struct WorkSchedule {
    let workStartMinutes: Int
    let workEndMinutes: Int
    let breaks: [BreakSchedule]

    /// True when the work day crosses midnight (e.g. 22:00–06:00).
    var isCrossMidnight: Bool { workEndMinutes <= workStartMinutes }

    /// Paid hours per day (window minus breaks), computed by the shared logic.
    var totalWorkHours: Double {
        SakipayBridge.totalWorkHours(
            workStartMinutes: workStartMinutes,
            workEndMinutes: workEndMinutes,
            breaksJson: BreakSegment.encodeSchedules(breaks)
        )
    }

    /// The break that contains the given clock minute, if any.
    func breakContaining(_ minute: Int) -> BreakSchedule? {
        breaks.sorted { $0.startMinutes < $1.startMinutes }
            .first { minute >= $0.startMinutes && minute < $0.endMinutes }
    }
}

enum WorkStatus: String {
    case notStarted
    case working
    case onBreak
    case completed
    case overtime
    case voluntaryOvertime
    case dayOff
    /// User-armed pause: nothing accrues, regardless of day type or calendar.
    case paused

    init(wire: String) {
        self = WorkStatus(rawValue: wire) ?? .notStarted
    }
}

struct TodayEarnings {
    let amount: Double
    let progress: Double
    let status: WorkStatus
    let elapsedSeconds: Double
    let totalWorkSeconds: Double
}

struct MonthSummary {
    let workingDaysThisMonth: Int
    let workingDaysElapsed: Int
    let monthProgress: Double
    let monthEarnings: Double
    let totalMonthEarnings: Double
    let daysUntilPayday: Int
    let isPayday: Bool
    let paydayCycleProgress: Double
    let paydayCycleTotal: Int
    let paydayCycleElapsed: Int

    init(workingDaysThisMonth: Int, workingDaysElapsed: Int, monthProgress: Double,
         monthEarnings: Double, totalMonthEarnings: Double, daysUntilPayday: Int, isPayday: Bool,
         paydayCycleProgress: Double, paydayCycleTotal: Int, paydayCycleElapsed: Int) {
        self.workingDaysThisMonth = workingDaysThisMonth
        self.workingDaysElapsed = workingDaysElapsed
        self.monthProgress = monthProgress
        self.monthEarnings = monthEarnings
        self.totalMonthEarnings = totalMonthEarnings
        self.daysUntilPayday = daysUntilPayday
        self.isPayday = isPayday
        self.paydayCycleProgress = paydayCycleProgress
        self.paydayCycleTotal = paydayCycleTotal
        self.paydayCycleElapsed = paydayCycleElapsed
    }
}

// MARK: - BreakSegment (Codable — for storage)

struct BreakSegment: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    var startMinutes: Int { startHour * 60 + startMinute }
    var endMinutes: Int { endHour * 60 + endMinute }
    var durationMinutes: Int { endMinutes - startMinutes }

    var asBreakSchedule: BreakSchedule { BreakSchedule(startMinutes: startMinutes, endMinutes: endMinutes) }

    var isValid: Bool { endMinutes > startMinutes }

    /// Whether this break fits entirely inside the work window (shared logic).
    func fitsWithin(workStart: Int, workEnd: Int) -> Bool {
        SakipayBridge.breakFits(
            breakStartMinutes: startMinutes,
            breakEndMinutes: endMinutes,
            workStartMinutes: workStart,
            workEndMinutes: workEnd
        )
    }

    /// Encodes a list of schedules as the JSON array the shared config expects.
    static func encodeSchedules(_ breaks: [BreakSchedule]) -> String {
        let array: [[String: Int]] = breaks.map { ["startMinutes": $0.startMinutes, "endMinutes": $0.endMinutes] }
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }
}

// MARK: - Calculator

/// Facade over the shared earnings engine. Assign configuration via the
/// initializer; each calculation rebuilds the config document and asks Kotlin.
final class EarningsCalculator {
    let monthlyPay: Double
    let workingDaysPerMonth: Double
    let schedule: WorkSchedule
    let payDay: Int
    let taxRate: Double
    let calendar: Calendar
    var dayOverrides: [String: DayOverride]

    init(monthlyPay: Double,
         workingDaysPerMonth: Double,
         schedule: WorkSchedule,
         payDay: Int,
         taxRate: Double = 0,
         calendar: Calendar = .current,
         dayOverrides: [String: DayOverride] = [:]) {
        self.monthlyPay = monthlyPay
        self.workingDaysPerMonth = workingDaysPerMonth
        self.schedule = schedule
        self.payDay = payDay
        self.taxRate = taxRate
        self.calendar = calendar
        self.dayOverrides = dayOverrides
    }

    /// The base per-second rate, used to settle voluntary overtime.
    var secondRate: Double {
        SakipayBridge.secondRate(configJson: buildConfigJson(), at: Date())
    }

    func calculateTodayEarnings(at date: Date = Date(),
                                voluntaryOvertimeTotalSeconds: Double = 0,
                                isPaused: Bool = false) -> TodayEarnings {
        let r = SakipayBridge.todayEarnings(
            configJson: buildConfigJson(),
            at: date,
            voluntaryOvertimeTotalSeconds: voluntaryOvertimeTotalSeconds,
            isPaused: isPaused
        )
        return TodayEarnings(
            amount: r.amount,
            progress: r.progress,
            status: WorkStatus(wire: r.status),
            elapsedSeconds: r.elapsedSeconds,
            totalWorkSeconds: r.totalWorkSeconds
        )
    }

    func calculateMonthSummary(at date: Date = Date(), isPaused: Bool = false) -> MonthSummary {
        let r = SakipayBridge.monthSummary(configJson: buildConfigJson(), at: date, isPaused: isPaused)
        return MonthSummary(
            workingDaysThisMonth: r.workingDaysThisMonth,
            workingDaysElapsed: r.workingDaysElapsed,
            monthProgress: r.monthProgress,
            monthEarnings: r.monthEarnings,
            totalMonthEarnings: r.totalMonthEarnings,
            daysUntilPayday: r.daysUntilPayday,
            isPayday: r.isPayday,
            paydayCycleProgress: r.paydayCycleProgress,
            paydayCycleTotal: r.paydayCycleTotal,
            paydayCycleElapsed: r.paydayCycleElapsed
        )
    }

    /// Working days in the month of `date`, accounting for the holiday calendar.
    func countWorkingDaysInMonth(_ date: Date) -> Int {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return SakipayBridge.calibratedWorkingDays(
            configJson: buildConfigJson(),
            year: comps.year ?? 2026,
            month: comps.month ?? 1
        )
    }

    // MARK: - Private

    /// Builds the canonical config document from the current field values.
    /// `useCalibratedWorkDays` is false because callers pass the already-resolved
    /// working-day count in `workingDaysPerMonth`.
    private func buildConfigJson() -> String {
        let breaksJson = BreakSegment.encodeSchedules(schedule.breaks)
        let overridesJson = Self.encodeOverrides(dayOverrides)
        return SakipayBridge.composeConfig(
            monthlyPay: monthlyPay,
            currency: "¥",
            payDay: payDay,
            taxRate: taxRate,
            workingDaysPerMonth: workingDaysPerMonth,
            workStartHour: schedule.workStartMinutes / 60,
            workStartMinute: schedule.workStartMinutes % 60,
            workEndHour: schedule.workEndMinutes / 60,
            workEndMinute: schedule.workEndMinutes % 60,
            breaksJson: breaksJson,
            dayOverridesJson: overridesJson,
            useCalibratedWorkDays: false
        )
    }

    private static func encodeOverrides(_ overrides: [String: DayOverride]) -> String {
        let array: [[String: Any]] = overrides.values.map { override in
            var dict: [String: Any] = [
                "dateString": override.dateString,
                "dayType": override.dayType.rawValue,
                "overtimeMultiplier": override.overtimeMultiplier,
            ]
            if let hours = override.customWorkHours {
                dict["customWorkHours"] = hours
            }
            return dict
        }
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }
}
