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

// MARK: - Holiday calendar (one year's public holiday and adjusted-workday schedule)

struct HolidayCalendar: Codable {
    let year: Int
    let holidays: Set<String>
    let adjustedWorkdays: Set<String>

    init(year: Int, holidays: Set<String>, adjustedWorkdays: Set<String>) {
        self.year = year
        self.holidays = holidays
        self.adjustedWorkdays = adjustedWorkdays
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case holidays, adjustedWorkdays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.year = 0
        let holidayArray = try container.decode([String].self, forKey: .holidays)
        self.holidays = Set(holidayArray)
        let workdayArray = try container.decode([String].self, forKey: .adjustedWorkdays)
        self.adjustedWorkdays = Set(workdayArray)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(holidays.sorted(), forKey: .holidays)
        try container.encode(adjustedWorkdays.sorted(), forKey: .adjustedWorkdays)
    }

    // MARK: Lookup

    /// Returns true if the given month/day is a public holiday (day off).
    func isHoliday(month: Int, day: Int) -> Bool {
        let key = String(format: "%02d-%02d", month, day)
        return holidays.contains(key)
    }

    /// Returns true if the given month/day is an adjusted working day (调休, typically a weekend).
    func isAdjustedWorkday(month: Int, day: Int) -> Bool {
        let key = String(format: "%02d-%02d", month, day)
        return adjustedWorkdays.contains(key)
    }
}
