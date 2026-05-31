/* (c) Copyright XiatStudio 2026~2026 */
import Foundation

// MARK: - Data types

struct BreakSchedule: Equatable, Hashable {
    let startMinutes: Int
    let endMinutes: Int
    var durationMinutes: Int { endMinutes - startMinutes }
}

struct WorkSchedule {
    let workStartMinutes: Int
    let workEndMinutes: Int
    let breaks: [BreakSchedule]

    /// True when the work day crosses midnight (e.g. 22:00–06:00).
    var isCrossMidnight: Bool { workEndMinutes <= workStartMinutes }

    /// Total clock minutes in the work window (before subtracting breaks).
    var workWindowMinutes: Int {
        isCrossMidnight ? (1440 - workStartMinutes) + workEndMinutes : workEndMinutes - workStartMinutes
    }

    var totalBreakMinutes: Int { breaks.reduce(0) { $0 + $1.durationMinutes } }
    var totalWorkMinutes: Int { workWindowMinutes - totalBreakMinutes }
    var totalWorkHours: Double { Double(totalWorkMinutes) / 60.0 }

    /// All break schedules sorted by start time.
    var sortedBreaks: [BreakSchedule] { breaks.sorted { $0.startMinutes < $1.startMinutes } }

    /// Converts a clock-minute value to minutes elapsed since work start,
    /// handling the cross-midnight wrap.
    func elapsedSinceStart(_ clockMinute: Int) -> Int {
        if !isCrossMidnight {
            return max(0, clockMinute - workStartMinutes)
        }
        if clockMinute >= workStartMinutes {
            return clockMinute - workStartMinutes
        }
        return (1440 - workStartMinutes) + clockMinute
    }

    /// Converts a clock-second value to seconds elapsed since work start,
    /// handling the cross-midnight wrap with second-level precision.
    func elapsedSinceStartSeconds(_ clockSecond: Double) -> Double {
        let wsSec = Double(workStartMinutes * 60)
        if !isCrossMidnight {
            return max(0, clockSecond - wsSec)
        }
        if clockSecond >= wsSec {
            return clockSecond - wsSec
        }
        return Double(1440 * 60) - wsSec + clockSecond
    }

    /// True when clockMinute falls within the active work window.
    func isInWorkWindow(_ clockMinute: Int) -> Bool {
        if !isCrossMidnight {
            return clockMinute >= workStartMinutes && clockMinute < workEndMinutes
        }
        return clockMinute >= workStartMinutes || clockMinute < workEndMinutes
    }

    /// True when clockMinute is after the work window has ended for the day.
    func isAfterWork(_ clockMinute: Int) -> Bool {
        if !isCrossMidnight {
            return clockMinute >= workEndMinutes
        }
        return clockMinute >= workEndMinutes && clockMinute < workStartMinutes
    }

    /// Returns the break that contains the given minute, if any.
    func breakContaining(_ minute: Int) -> BreakSchedule? {
        sortedBreaks.first { minute >= $0.startMinutes && minute < $0.endMinutes }
    }

    /// Total break seconds that have elapsed before the given clock second,
    /// handling cross-midnight wrap by comparing in elapsed-since-start space.
    func elapsedBreakSeconds(before clockSecond: Double) -> Double {
        let beforeMinute = Int(clockSecond / 60)
        let beforeElapsed = elapsedSinceStart(beforeMinute)
        return sortedBreaks
            .filter { elapsedSinceStart($0.endMinutes) <= beforeElapsed }
            .reduce(0.0) { $0 + Double($1.durationMinutes * 60) }
    }
}

enum WorkStatus {
    case notStarted
    case working
    case onBreak
    case completed
    case overtime
    case voluntaryOvertime
    case dayOff
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

    var asBreakSchedule: BreakSchedule {
        BreakSchedule(startMinutes: startMinutes, endMinutes: endMinutes)
    }

    var isValid: Bool { endMinutes > startMinutes }

    /// Checks whether this break fits entirely within the work window.
    /// When workEnd <= workStart (cross-midnight), the break must fit in either
    /// the [workStart, 1440) or [0, workEnd] segment.
    func fitsWithin(workStart: Int, workEnd: Int) -> Bool {
        if workEnd > workStart {
            return startMinutes >= workStart && endMinutes <= workEnd
        }
        return (startMinutes >= workStart && endMinutes <= 1440) ||
               (startMinutes >= 0 && endMinutes <= workEnd)
    }
}

// MARK: - Calculator

final class EarningsCalculator {
    let monthlyPay: Double
    let workingDaysPerMonth: Double
    let schedule: WorkSchedule
    let payDay: Int
    let taxRate: Double
    let calendar: Calendar
    let holidayCalendar: HolidayCalendar?
    var dayOverrides: [String: DayOverride]

    init(monthlyPay: Double,
         workingDaysPerMonth: Double,
         schedule: WorkSchedule,
         payDay: Int,
         taxRate: Double = 0,
         calendar: Calendar = .current,
         holidayCalendar: HolidayCalendar? = nil,
         dayOverrides: [String: DayOverride] = [:]) {
        self.monthlyPay = monthlyPay
        self.workingDaysPerMonth = workingDaysPerMonth
        self.schedule = schedule
        self.payDay = payDay
        self.taxRate = taxRate
        self.calendar = calendar
        self.holidayCalendar = holidayCalendar
        self.dayOverrides = dayOverrides
    }

    var dailyRate: Double {
        guard workingDaysPerMonth > 0 else { return 0 }
        return monthlyPay * (1 - taxRate) / workingDaysPerMonth
    }
    var hourlyRate: Double {
        guard schedule.totalWorkHours > 0 else { return 0 }
        return dailyRate / schedule.totalWorkHours
    }
    var secondRate: Double { hourlyRate / 3600.0 }
    var totalWorkSeconds: Double { Double(max(0, schedule.totalWorkMinutes)) * 60.0 }

    /// - Parameter voluntaryOvertimeTotalSeconds: Pre-computed total OT seconds for the current
    ///   session (accumulated from prior sessions today + elapsed in current session). When > 0,
    ///   the calculator returns `.voluntaryOvertime` with earnings based on this duration at the
    ///   normal secondRate. Pass 0 when no voluntary OT session is active.
    func calculateTodayEarnings(at date: Date = Date(),
                                voluntaryOvertimeTotalSeconds: Double = 0) -> TodayEarnings {
        guard !isDayOff(date) else {
            return TodayEarnings(amount: 0, progress: 0, status: .dayOff,
                                 elapsedSeconds: 0, totalWorkSeconds: totalWorkSeconds)
        }

        let currentMinute = calendar.component(.hour, from: date) * 60
                          + calendar.component(.minute, from: date)
        let currentSec = Double(calendar.component(.hour, from: date) * 3600
                              + calendar.component(.minute, from: date) * 60
                              + calendar.component(.second, from: date))

        // Determine overtime config for today (if any)
        let ds = dateString(from: date)
        let isOvertime = dayOverrides[ds]?.dayType == .overtime
        let multiplier = isOvertime ? (dayOverrides[ds]?.overtimeMultiplier ?? 2.0) : 1.0

        // When overtime has customWorkHours, it acts as the reference for the per-second rate
        // (snapshotted from the normal work schedule). The per-second rate stays anchored to
        // this reference regardless of the current schedule's totalWorkHours.
        let overtimeBaseSecondRate: Double
        if isOvertime, let customHours = dayOverrides[ds]?.customWorkHours, customHours > 0 {
            overtimeBaseSecondRate = dailyRate / customHours / 3600.0
        } else {
            overtimeBaseSecondRate = secondRate
        }

        // Standard schedule path (regular day or overtime) — same window, same breaks.
        // Only the effective rate changes for overtime.
        let effectiveTotalSeconds = totalWorkSeconds
        let effectiveSecondRate = isOvertime ? overtimeBaseSecondRate : secondRate

        // Not started: before work start (and not in cross-midnight's next-day portion)
        if !schedule.isInWorkWindow(currentMinute) && !schedule.isAfterWork(currentMinute) {
            return TodayEarnings(amount: 0, progress: 0, status: .notStarted,
                                 elapsedSeconds: 0, totalWorkSeconds: effectiveTotalSeconds)
        }

        // Completed: after work end
        if schedule.isAfterWork(currentMinute) {
            // Voluntary overtime: only on normal workdays (not pre-planned overtime),
            // triggered by user after work hours. Session duration is tracked externally
            // and passed in as voluntaryOvertimeTotalSeconds.
            if voluntaryOvertimeTotalSeconds > 0 && !isOvertime {
                let overtimeAmount = voluntaryOvertimeTotalSeconds * secondRate
                return TodayEarnings(amount: overtimeAmount, progress: 1,
                                     status: .voluntaryOvertime,
                                     elapsedSeconds: effectiveTotalSeconds,
                                     totalWorkSeconds: effectiveTotalSeconds)
            }

            let fullAmount = isOvertime
                ? effectiveSecondRate * effectiveTotalSeconds * multiplier
                : dailyRate
            let status: WorkStatus = isOvertime ? .overtime : .completed
            return TodayEarnings(amount: fullAmount, progress: 1, status: status,
                                 elapsedSeconds: effectiveTotalSeconds,
                                 totalWorkSeconds: effectiveTotalSeconds)
        }

        // In work window — check breaks (schedule breaks apply to both regular and overtime)
        if let activeBreak = schedule.breakContaining(currentMinute) {
            let breakStartSec = Double(activeBreak.startMinutes * 60)
            let breakStartElapsedSec = schedule.elapsedSinceStartSeconds(breakStartSec)
            let priorBreakSec = schedule.elapsedBreakSeconds(before: breakStartSec)
            let elapsedSec = max(0, breakStartElapsedSec - priorBreakSec)
            let cappedElapsed = min(elapsedSec, effectiveTotalSeconds)
            let progress = effectiveTotalSeconds > 0 ? cappedElapsed / effectiveTotalSeconds : 0
            let amount = effectiveSecondRate * cappedElapsed * multiplier
            return TodayEarnings(amount: amount, progress: progress,
                                 status: .onBreak, elapsedSeconds: cappedElapsed,
                                 totalWorkSeconds: effectiveTotalSeconds)
        }

        // Working — use second-level precision
        let nowElapsedSec = schedule.elapsedSinceStartSeconds(currentSec)
        let elapsedBreakSec = schedule.elapsedBreakSeconds(before: currentSec)
        let elapsedSec = max(0, nowElapsedSec - elapsedBreakSec)
        let cappedElapsed = min(elapsedSec, effectiveTotalSeconds)
        let progress = effectiveTotalSeconds > 0 ? cappedElapsed / effectiveTotalSeconds : 0
        let amount = effectiveSecondRate * cappedElapsed * multiplier
        let status: WorkStatus = isOvertime ? .overtime : .working
        return TodayEarnings(amount: amount, progress: progress,
                             status: status, elapsedSeconds: cappedElapsed,
                             totalWorkSeconds: effectiveTotalSeconds)
    }

    func calculateMonthSummary(at date: Date = Date()) -> MonthSummary {
        let workingDays = countWorkingDaysInMonth(date)
        let elapsedDays = countElapsedWorkingDays(date)
        let monthProgress = workingDays > 0 ? Double(elapsedDays) / Double(workingDays) : 0
        let monthEarnings = calculateElapsedMonthEarnings(date)
        let totalMonthEarnings = calculateTotalMonthEarnings(date)
        let paydayInfo = calculatePayday(from: date)
        let cycleInfo = calculatePaydayCycle(from: date)

        return MonthSummary(
            workingDaysThisMonth: workingDays,
            workingDaysElapsed: elapsedDays,
            monthProgress: monthProgress,
            monthEarnings: monthEarnings,
            totalMonthEarnings: totalMonthEarnings,
            daysUntilPayday: paydayInfo.daysUntil,
            isPayday: paydayInfo.isPayday,
            paydayCycleProgress: cycleInfo.progress,
            paydayCycleTotal: cycleInfo.total,
            paydayCycleElapsed: cycleInfo.elapsed
        )
    }

    // MARK: - Private

    /// Formats a Date as "YYYY-MM-DD" for dictionary lookup.
    private func dateString(from date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Three-tier day-off determination: user override > holiday calendar > weekend check.
    private func isDayOff(_ date: Date) -> Bool {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let month = c.month, let day = c.day else {
            return false
        }

        // Tier 1: user override
        let ds = dateString(from: date)
        if let override = dayOverrides[ds] {
            switch override.dayType {
            case .normal:
                break // fall through to calendar/weekend check
            case .holiday:
                return true
            case .overtime:
                return false // overtime days are working days
            }
        }

        // Tier 2: Chinese holiday calendar
        if let hc = holidayCalendar {
            if hc.isHoliday(month: month, day: day) { return true }
            if hc.isAdjustedWorkday(month: month, day: day) { return false }
        }

        // Tier 3: weekend fallback
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    /// Returns the per-day earnings for a given date, accounting for overtime.
    private func dailyEarnings(for date: Date) -> Double {
        let ds = dateString(from: date)
        if let override = dayOverrides[ds], override.dayType == .overtime {
            let multiplier = override.overtimeMultiplier
            // Use snapshotted reference hours for the per-second rate, schedule for the window
            let rateRefHours: Double
            if let customHours = override.customWorkHours, customHours > 0 {
                rateRefHours = customHours
            } else {
                rateRefHours = schedule.totalWorkHours
            }
            let effSecondRate = dailyRate / rateRefHours / 3600.0
            return effSecondRate * schedule.totalWorkHours * 3600.0 * multiplier
        }
        if isDayOff(date) { return 0 }
        return dailyRate
    }

    /// Sums the earnings for every elapsed working day in the month (including today if working).
    private func calculateElapsedMonthEarnings(_ date: Date) -> Double {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else {
            return 0
        }
        let today = calendar.startOfDay(for: date)
        var total: Double = 0
        var current = monthStart
        while current <= today {
            total += dailyEarnings(for: current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return total
    }

    /// Sums the earnings for every working day in the entire month.
    private func calculateTotalMonthEarnings(_ date: Date) -> Double {
        guard let range = calendar.range(of: .day, in: .month, for: date),
              let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else {
            return 0
        }
        var total: Double = 0
        for day in range {
            guard let dayDate = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            total += dailyEarnings(for: dayDate)
        }
        return total
    }

    func countWorkingDaysInMonth(_ date: Date) -> Int {
        guard let range = calendar.range(of: .day, in: .month, for: date),
              let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else {
            return 0
        }

        var count = 0
        for day in range {
            guard let dayDate = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            if !isDayOff(dayDate) { count += 1 }
        }
        return count
    }

    private func countElapsedWorkingDays(_ date: Date) -> Int {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else {
            return 0
        }

        let today = calendar.startOfDay(for: date)
        var count = 0
        var current = monthStart

        while current <= today {
            if !isDayOff(current) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        if !isDayOff(date) { count -= 1 }
        return max(0, count)
    }

    private func calculatePayday(from date: Date) -> (daysUntil: Int, isPayday: Bool) {
        let todayDay = calendar.component(.day, from: date)
        let today = calendar.startOfDay(for: date)

        if todayDay == payDay { return (0, true) }

        var components = calendar.dateComponents([.year, .month], from: date)
        components.day = payDay

        guard var paydayDate = calendar.date(from: components) else { return (0, false) }

        if todayDay > payDay {
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: paydayDate) else {
                return (0, false)
            }
            paydayDate = nextMonth
        }

        let days = calendar.dateComponents([.day], from: today, to: paydayDate).day ?? 0
        return (days, false)
    }

    private func calculatePaydayCycle(from date: Date) -> (progress: Double, total: Int, elapsed: Int) {
        let today = calendar.startOfDay(for: date)
        let todayDay = calendar.component(.day, from: date)

        var startComponents = calendar.dateComponents([.year, .month], from: date)
        startComponents.day = payDay

        guard var cycleStart = calendar.date(from: startComponents) else {
            return (0, 0, 0)
        }

        if todayDay < payDay {
            cycleStart = calendar.date(byAdding: .month, value: -1, to: cycleStart) ?? cycleStart
        }

        guard let cycleEnd = calendar.date(byAdding: .month, value: 1, to: cycleStart) else {
            return (0, 0, 0)
        }

        let totalDays = calendar.dateComponents([.day], from: cycleStart, to: cycleEnd).day ?? 30
        let elapsedDays = calendar.dateComponents([.day], from: cycleStart, to: today).day ?? 0

        let progress = totalDays > 0 ? Double(elapsedDays) / Double(totalDays) : 0
        return (min(progress, 1.0), totalDays, elapsedDays)
    }
}
