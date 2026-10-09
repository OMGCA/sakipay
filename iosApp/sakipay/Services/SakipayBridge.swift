/* (c) Copyright XiatStudio 2026~2026 */
import Foundation
// This is the ONLY file that imports the shared Kotlin framework. Keeping the
// import isolated means the app's own Swift types (EarningsCalculator,
// WorkStatus, …) never clash with the Kotlin ones of the same name — Swift
// reports an ambiguity only in files that see both.
import SharedLogic

// MARK: - Result shapes decoded from the shared JSON

/// Mirrors `TodayEarnings` on the Kotlin side.
struct EarningsTodayResult: Decodable {
    let amount: Double
    let progress: Double
    let status: String
    let elapsedSeconds: Double
    let totalWorkSeconds: Double
}

/// Mirrors `MonthSummary` on the Kotlin side.
struct EarningsMonthResult: Decodable {
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
}

/// Result of a break-pruning pass.
struct EarningsPruneResult: Decodable {
    let config: String
    let removed: Int
}

/// Result of reading the voluntary-overtime total.
struct EarningsOtTotalResult: Decodable {
    let state: String
    let seconds: Double
}

/// Thin Swift facade over the shared `SakipayCore`. Every call forwards to the
/// Kotlin business logic, so the numbers are identical to the HarmonyOS app.
enum SakipayBridge {
    private static let decoder = JSONDecoder()

    /// Minutes east of UTC — the convention the shared logic expects.
    static func tzOffsetMinutes() -> Int32 {
        Int32(TimeZone.current.secondsFromGMT() / 60)
    }

    static func nowMillis(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000.0)
    }

    // MARK: Configuration

    static func composeConfig(
        monthlyPay: Double,
        currency: String,
        payDay: Int,
        taxRate: Double,
        workingDaysPerMonth: Double,
        workStartHour: Int,
        workStartMinute: Int,
        workEndHour: Int,
        workEndMinute: Int,
        breaksJson: String,
        dayOverridesJson: String,
        useCalibratedWorkDays: Bool
    ) -> String {
        SakipayCore.shared.composeConfigJson(
            monthlyPay: monthlyPay,
            currency: currency,
            payDay: Int32(payDay),
            taxRate: taxRate,
            workingDaysPerMonth: workingDaysPerMonth,
            workStartHour: Int32(workStartHour),
            workStartMinute: Int32(workStartMinute),
            workEndHour: Int32(workEndHour),
            workEndMinute: Int32(workEndMinute),
            breaksJson: breaksJson,
            dayOverridesJson: dayOverridesJson,
            useCalibratedWorkDays: useCalibratedWorkDays
        )
    }

    static func defaultBreakJson() -> String {
        SakipayCore.shared.defaultBreakJson()
    }

    // MARK: Earnings

    static func todayEarnings(
        configJson: String,
        at date: Date,
        voluntaryOvertimeTotalSeconds: Double,
        isPaused: Bool
    ) -> EarningsTodayResult {
        let json = SakipayCore.shared.todayEarningsJson(
            configJson: configJson,
            nowMillis: nowMillis(date),
            tzOffsetMinutes: tzOffsetMinutes(),
            voluntaryOvertimeTotalSeconds: voluntaryOvertimeTotalSeconds,
            isPaused: isPaused
        )
        return decode(json) ?? EarningsTodayResult(
            amount: 0, progress: 0, status: "notStarted", elapsedSeconds: 0, totalWorkSeconds: 0
        )
    }

    static func monthSummary(configJson: String, at date: Date, isPaused: Bool) -> EarningsMonthResult {
        let json = SakipayCore.shared.monthSummaryJson(
            configJson: configJson,
            nowMillis: nowMillis(date),
            tzOffsetMinutes: tzOffsetMinutes(),
            isPaused: isPaused
        )
        return decode(json) ?? EarningsMonthResult(
            workingDaysThisMonth: 0, workingDaysElapsed: 0, monthProgress: 0, monthEarnings: 0,
            totalMonthEarnings: 0, daysUntilPayday: 0, isPayday: false, paydayCycleProgress: 0,
            paydayCycleTotal: 0, paydayCycleElapsed: 0
        )
    }

    static func secondRate(configJson: String, at date: Date) -> Double {
        SakipayCore.shared.secondRate(
            configJson: configJson,
            nowMillis: nowMillis(date),
            tzOffsetMinutes: tzOffsetMinutes()
        )
    }

    static func calibratedWorkingDays(configJson: String, year: Int, month: Int) -> Int {
        Int(SakipayCore.shared.calibratedWorkingDays(configJson: configJson, year: Int32(year), month: Int32(month)))
    }

    // MARK: Schedule helpers

    static func totalWorkHours(workStartMinutes: Int, workEndMinutes: Int, breaksJson: String) -> Double {
        SakipayCore.shared.workScheduleTotalHours(
            workStartMinutes: Int32(workStartMinutes),
            workEndMinutes: Int32(workEndMinutes),
            breaksJson: breaksJson
        )
    }

    static func breakFits(breakStartMinutes: Int, breakEndMinutes: Int, workStartMinutes: Int, workEndMinutes: Int) -> Bool {
        SakipayCore.shared.breakFits(
            breakStartMinutes: Int32(breakStartMinutes),
            breakEndMinutes: Int32(breakEndMinutes),
            workStartMinutes: Int32(workStartMinutes),
            workEndMinutes: Int32(workEndMinutes)
        )
    }

    static func pruneBreaks(configJson: String) -> EarningsPruneResult {
        let json = SakipayCore.shared.pruneBreaksJson(configJson: configJson)
        return decode(json) ?? EarningsPruneResult(config: configJson, removed: 0)
    }

    static func configBreaksJson(configJson: String) -> String {
        SakipayCore.shared.configBreaksJson(configJson: configJson)
    }

    /// Appends a break (shared placement rule); returns the updated config document.
    static func addBreak(configJson: String) -> String {
        SakipayCore.shared.addBreakJson(configJson: configJson)
    }

    /// Appends a break to a breaks array (JSON) using the shared placement rule.
    static func addBreakToBreaks(workStartMinutes: Int, workEndMinutes: Int, breaksJson: String) -> String {
        SakipayCore.shared.addBreakToBreaks(
            workStartMinutes: Int32(workStartMinutes),
            workEndMinutes: Int32(workEndMinutes),
            breaksJson: breaksJson
        )
    }

    /// Raw clock minutes in a work window (breaks not subtracted, cross-midnight aware).
    static func workWindowMinutes(workStartMinutes: Int, workEndMinutes: Int) -> Int {
        Int(SakipayCore.shared.workWindowMinutes(
            workStartMinutes: Int32(workStartMinutes),
            workEndMinutes: Int32(workEndMinutes)
        ))
    }

    // MARK: Holiday data

    static func holidayDataJson(year: Int) -> String {
        SakipayCore.shared.holidayDataJson(year: Int32(year))
    }

    /// "normal" | "weekend" | "publicHoliday" | "adjustedWorkday" | "userHoliday" | "userOvertime".
    static func resolveDayKind(year: Int, month: Int, day: Int, dayOverridesJson: String) -> String {
        SakipayCore.shared.resolveDayKind(
            year: Int32(year),
            month: Int32(month),
            day: Int32(day),
            dayOverridesJson: dayOverridesJson
        )
    }

    // MARK: Voluntary overtime

    static func otTotalSeconds(stateJson: String, at date: Date, mutatesState: Bool) -> EarningsOtTotalResult {
        let json = SakipayCore.shared.otTotalSecondsJson(
            stateJson: stateJson,
            nowMillis: nowMillis(date),
            tzOffsetMinutes: tzOffsetMinutes(),
            mutatesState: mutatesState
        )
        return decode(json) ?? EarningsOtTotalResult(state: stateJson, seconds: 0)
    }

    static func otStart(stateJson: String, at date: Date) -> String {
        SakipayCore.shared.otStartJson(
            stateJson: stateJson,
            nowMillis: nowMillis(date),
            tzOffsetMinutes: tzOffsetMinutes()
        )
    }

    static func otEnd(stateJson: String, at date: Date, secondRate: Double) -> String {
        SakipayCore.shared.otEndJson(
            stateJson: stateJson,
            nowMillis: nowMillis(date),
            tzOffsetMinutes: tzOffsetMinutes(),
            secondRate: secondRate
        )
    }

    static func otBankDaily(stateJson: String, at date: Date, secondRate: Double) -> String {
        SakipayCore.shared.otBankDailyJson(
            stateJson: stateJson,
            nowMillis: nowMillis(date),
            tzOffsetMinutes: tzOffsetMinutes(),
            secondRate: secondRate
        )
    }

    // MARK: Presentation

    static func statusText(_ statusWire: String) -> String {
        SakipayCore.shared.statusText(statusWire: statusWire)
    }

    static func paydayText(daysUntilPayday: Int, isPayday: Bool) -> String {
        SakipayCore.shared.paydayText(daysUntilPayday: Int32(daysUntilPayday), isPayday: isPayday)
    }

    // MARK: Private

    private static func decode<T: Decodable>(_ json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}
