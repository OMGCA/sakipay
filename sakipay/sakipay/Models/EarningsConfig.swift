/* (c) Copyright XiatStudio 2026~2026 */
import Foundation
import SwiftData

@Model
final class EarningsConfig {
    var monthlyPay: Double = 0
    var currency: String = "¥"
    var payDay: Int = 15
    var taxRate: Double = 0
    var workingDaysPerMonth: Double = 21.75
    var workStartHour: Int = 9
    var workStartMinute: Int = 0
    var workEndHour: Int = 18
    var workEndMinute: Int = 0
    var updatedAt: Date = Date()

    // Legacy single-break fields (kept for migration)
    var breakStartHour: Int = 12
    var breakStartMinute: Int = 0
    var breakEndHour: Int = 13
    var breakEndMinute: Int = 30

    /// JSON-encoded break segments.
    var breaksJSON: String = ""

    /// JSON-encoded user day overrides (custom workday/holiday/overtime designations).
    var dayOverridesJSON: String = ""

    /// Whether to auto-calibrate workingDaysPerMonth based on the holiday calendar.
    var useCalibratedWorkDays: Bool = true

    init() {}

    var workStartMinutes: Int { workStartHour * 60 + workStartMinute }
    var workEndMinutes: Int { workEndHour * 60 + workEndMinute }

    var breaks: [BreakSegment] {
        get {
            if !breaksJSON.isEmpty,
               let data = breaksJSON.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([BreakSegment].self, from: data) {
                return decoded.sorted { $0.startMinutes < $1.startMinutes }
            }
            // Legacy migration: if old single-break fields were customized, preserve them
            let isLegacyCustom = breakStartHour != 12 || breakStartMinute != 0
                              || breakEndHour != 13 || breakEndMinute != 30
            if isLegacyCustom {
                return [BreakSegment(startHour: breakStartHour, startMinute: breakStartMinute,
                                     endHour: breakEndHour, endMinute: breakEndMinute)]
            }
            return []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue.sorted { $0.startMinutes < $1.startMinutes }),
               let str = String(data: data, encoding: .utf8) {
                breaksJSON = str
            }
        }
    }

    var workSchedule: WorkSchedule {
        WorkSchedule(
            workStartMinutes: workStartMinutes,
            workEndMinutes: workEndMinutes,
            breaks: breaks.filter(\.isValid).map(\.asBreakSchedule)
        )
    }

    var calculator: EarningsCalculator {
        let hc = HolidayCalendarService.shared.currentCalendar()
        let effectiveDays: Double = useCalibratedWorkDays
            ? Double(calibratedWorkingDays)
            : workingDaysPerMonth
        return EarningsCalculator(
            monthlyPay: monthlyPay,
            workingDaysPerMonth: effectiveDays,
            schedule: workSchedule,
            payDay: payDay,
            taxRate: taxRate,
            holidayCalendar: hc,
            dayOverrides: dayOverrides,
        )
    }

    /// User-designated day overrides, keyed by "YYYY-MM-DD".
    var dayOverrides: [String: DayOverride] {
        get {
            guard !dayOverridesJSON.isEmpty,
                  let data = dayOverridesJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([DayOverride].self, from: data) else {
                return [:]
            }
            return Dictionary(uniqueKeysWithValues: decoded.map { ($0.dateString, $0) })
        }
        set {
            let array = Array(newValue.values)
            if let data = try? JSONEncoder().encode(array),
               let str = String(data: data, encoding: .utf8) {
                dayOverridesJSON = str
            }
        }
    }

    /// Calibrated working days for the current month, accounting for the holiday calendar.
    /// Deliberately avoids calling `self.calculator` to prevent infinite recursion.
    var calibratedWorkingDays: Int {
        let hc = HolidayCalendarService.shared.currentCalendar()
        let calc = EarningsCalculator(
            monthlyPay: 0,
            workingDaysPerMonth: workingDaysPerMonth,
            schedule: workSchedule,
            payDay: payDay,
            taxRate: taxRate,
            holidayCalendar: hc,
            dayOverrides: dayOverrides,
        )
        return calc.countWorkingDaysInMonth(Date())
    }

    var validBreaks: [BreakSegment] {
        breaks.filter { $0.isValid && $0.fitsWithin(workStart: workStartMinutes, workEnd: workEndMinutes) }
    }

    @discardableResult
    func pruneInvalidBreaks() -> Int {
        let before = breaks.count
        breaks = breaks.filter { $0.isValid && $0.fitsWithin(workStart: workStartMinutes, workEnd: workEndMinutes) }
        return before - breaks.count
    }
}
