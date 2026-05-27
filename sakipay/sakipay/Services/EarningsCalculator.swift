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

    var totalBreakMinutes: Int { breaks.reduce(0) { $0 + $1.durationMinutes } }
    var totalWorkMinutes: Int { (workEndMinutes - workStartMinutes) - totalBreakMinutes }
    var totalWorkHours: Double { Double(totalWorkMinutes) / 60.0 }

    /// All break schedules sorted by start time.
    var sortedBreaks: [BreakSchedule] { breaks.sorted { $0.startMinutes < $1.startMinutes } }

    /// Returns the break that contains the given minute, if any.
    func breakContaining(_ minute: Int) -> BreakSchedule? {
        sortedBreaks.first { minute >= $0.startMinutes && minute < $0.endMinutes }
    }

    /// Total break minutes that have fully elapsed before the given minute.
    func elapsedBreakMinutes(before minute: Int) -> Int {
        sortedBreaks
            .filter { $0.endMinutes <= minute }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    /// Total break seconds that have elapsed before the given second (exclusive of the break end).
    func elapsedBreakSeconds(before second: Double) -> Double {
        sortedBreaks
            .filter { Double($0.endMinutes * 60) < second }
            .reduce(0.0) { $0 + Double($1.durationMinutes * 60) }
    }
}

enum WorkStatus {
    case notStarted
    case working
    case onBreak
    case completed
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

    func fitsWithin(workStart: Int, workEnd: Int) -> Bool {
        startMinutes >= workStart && endMinutes <= workEnd
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

    init(monthlyPay: Double,
         workingDaysPerMonth: Double,
         schedule: WorkSchedule,
         payDay: Int,
         taxRate: Double = 0,
         calendar: Calendar = .current) {
        self.monthlyPay = monthlyPay
        self.workingDaysPerMonth = workingDaysPerMonth
        self.schedule = schedule
        self.payDay = payDay
        self.taxRate = taxRate
        self.calendar = calendar
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

    func calculateTodayEarnings(at date: Date = Date()) -> TodayEarnings {
        guard !isDayOff(date) else {
            return TodayEarnings(amount: 0, progress: 0, status: .dayOff,
                                 elapsedSeconds: 0, totalWorkSeconds: totalWorkSeconds)
        }

        let currentMinute = calendar.component(.hour, from: date) * 60
                          + calendar.component(.minute, from: date)
        let currentSec = Double(calendar.component(.hour, from: date) * 3600
                              + calendar.component(.minute, from: date) * 60
                              + calendar.component(.second, from: date))

        let wsSec = Double(schedule.workStartMinutes * 60)
        let weSec = Double(schedule.workEndMinutes * 60)

        if currentMinute < schedule.workStartMinutes {
            return TodayEarnings(amount: 0, progress: 0, status: .notStarted,
                                 elapsedSeconds: 0, totalWorkSeconds: totalWorkSeconds)
        }

        if currentMinute >= schedule.workEndMinutes {
            return TodayEarnings(amount: dailyRate, progress: 1, status: .completed,
                                 elapsedSeconds: totalWorkSeconds, totalWorkSeconds: totalWorkSeconds)
        }

        // Check if we're inside a break (minute precision ok for boundary check)
        if let activeBreak = schedule.breakContaining(currentMinute) {
            let breakStartSec = Double(activeBreak.startMinutes * 60)
            let previousBreakSec = schedule.elapsedBreakSeconds(before: breakStartSec)
            let elapsedSec = max(0, breakStartSec - wsSec - previousBreakSec)
            let progress = totalWorkSeconds > 0 ? elapsedSec / totalWorkSeconds : 0
            return TodayEarnings(amount: secondRate * elapsedSec, progress: progress,
                                 status: .onBreak, elapsedSeconds: elapsedSec, totalWorkSeconds: totalWorkSeconds)
        }

        // Working — use second-level precision
        let elapsedBreakSec = schedule.elapsedBreakSeconds(before: currentSec)
        let elapsedSec = max(0, currentSec - wsSec - elapsedBreakSec)
        let progress = totalWorkSeconds > 0 ? elapsedSec / totalWorkSeconds : 0
        return TodayEarnings(amount: secondRate * elapsedSec, progress: progress,
                             status: .working, elapsedSeconds: elapsedSec, totalWorkSeconds: totalWorkSeconds)
    }

    func calculateMonthSummary(at date: Date = Date()) -> MonthSummary {
        let workingDays = countWorkingDaysInMonth(date)
        let elapsedDays = countElapsedWorkingDays(date)
        let monthProgress = workingDays > 0 ? Double(elapsedDays) / Double(workingDays) : 0
        let monthEarnings = dailyRate * Double(elapsedDays)
        let totalMonthEarnings = dailyRate * Double(workingDays)
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

    private func isDayOff(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    private func countWorkingDaysInMonth(_ date: Date) -> Int {
        guard let range = calendar.range(of: .day, in: .month, for: date),
              let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else {
            return 0
        }

        var count = 0
        for day in range {
            guard let dayDate = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            let weekday = calendar.component(.weekday, from: dayDate)
            if weekday != 1 && weekday != 7 { count += 1 }
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
            let weekday = calendar.component(.weekday, from: current)
            if weekday != 1 && weekday != 7 { count += 1 }
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
