/* (c) Copyright XiatStudio 2026~2026 */
import Foundation

/// Singleton that loads and caches Chinese holiday calendars.
final class HolidayCalendarService {
    static let shared = HolidayCalendarService()

    private var calendars: [Int: HolidayCalendar] = [:]
    private var isLoaded = false

    private init() {}

    // MARK: - Loading

    /// Loads the bundled holiday JSON from the main bundle.
    func loadBundledCalendars() {
        guard !isLoaded else { return }
        isLoaded = true

        guard let url = Bundle.main.url(forResource: "holidays", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return
        }

        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        for (yearStr, dict) in raw {
            guard let year = Int(yearStr),
                  let yearData = dict as? [String: Any],
                  let holidayArray = yearData["holidays"] as? [String],
                  let workdayArray = yearData["adjustedWorkdays"] as? [String] else {
                continue
            }
            let calendar = HolidayCalendar(
                year: year,
                holidays: Set(holidayArray),
                adjustedWorkdays: Set(workdayArray)
            )
            calendars[year] = calendar
        }
    }

    // MARK: - Lookup

    /// Returns the holiday calendar for a given year, or nil if none is available.
    func calendarForYear(_ year: Int) -> HolidayCalendar? {
        loadBundledCalendars()
        return calendars[year]
    }

    /// Returns the holiday calendar for the current calendar year.
    func currentCalendar() -> HolidayCalendar? {
        let year = Calendar.current.component(.year, from: Date())
        return calendarForYear(year)
    }

    /// Returns true if holiday data is available for the given year.
    func hasDataForYear(_ year: Int) -> Bool {
        return calendarForYear(year) != nil
    }
}
