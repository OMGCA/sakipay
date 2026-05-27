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
        EarningsCalculator(
            monthlyPay: monthlyPay,
            workingDaysPerMonth: workingDaysPerMonth,
            schedule: workSchedule,
            payDay: payDay,
            taxRate: taxRate
        )
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
