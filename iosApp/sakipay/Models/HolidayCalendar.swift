/* (c) Copyright XiatStudio 2026~2026 */
import Foundation

// MARK: - Day type enum

enum DayType: String, Codable, CaseIterable {
    case normal = "normal"
    case holiday = "holiday"
    case overtime = "overtime"
}

// MARK: - Day override (user's custom designation for a specific date)

struct DayOverride: Codable, Hashable, Identifiable {
    /// ISO 8601 date string, e.g. "2026-05-15".
    var dateString: String
    var dayType: DayType
    /// Overtime pay multiplier, e.g. 2.0 for double pay. Only meaningful when dayType is .overtime.
    var overtimeMultiplier: Double = 2.0
    /// Custom work hours for this overtime day. `nil` means use the default schedule's total work hours.
    var customWorkHours: Double? = nil

    var id: String { dateString }

    init(dateString: String, dayType: DayType, overtimeMultiplier: Double = 2.0, customWorkHours: Double? = nil) {
        self.dateString = dateString
        self.dayType = dayType
        self.overtimeMultiplier = overtimeMultiplier
        self.customWorkHours = customWorkHours
    }
}
