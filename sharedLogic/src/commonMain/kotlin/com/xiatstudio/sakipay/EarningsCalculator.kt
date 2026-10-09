/* (c) Copyright XiatStudio 2026~2026 */
package com.xiatstudio.sakipay

/**
 * Pure calculation engine — takes configuration plus a moment in time and
 * produces earnings data. Contains no platform dependencies, so it produces
 * identical numbers on iOS and HarmonyOS.
 */
class EarningsCalculator(
    val monthlyPay: Double,
    val workingDaysPerMonth: Double,
    val schedule: WorkSchedule,
    val payDay: Int,
    val taxRate: Double = 0.0,
    val holidayCalendar: HolidayCalendar? = null,
    val dayOverrides: Map<String, DayOverride> = emptyMap(),
) {

    val dailyRate: Double
        get() = if (workingDaysPerMonth > 0) monthlyPay * (1 - taxRate) / workingDaysPerMonth else 0.0

    val hourlyRate: Double
        get() = if (schedule.totalWorkHours > 0) dailyRate / schedule.totalWorkHours else 0.0

    val secondRate: Double get() = hourlyRate / 3600.0

    val totalWorkSeconds: Double get() = maxOf(0, schedule.totalWorkMinutes) * 60.0

    /**
     * @param voluntaryOvertimeTotalSeconds pre-computed total OT seconds for the current session
     *   (accumulated from prior sessions today plus elapsed in the current session). When > 0 the
     *   calculator returns [WorkStatus.VOLUNTARY_OVERTIME] with earnings at the normal [secondRate].
     *   Pass 0 when no voluntary OT session is active.
     * @param isPaused user-armed pause. When true nothing accrues at all — the calendar and any day
     *   overrides are ignored entirely, so this is checked before the day-off test.
     */
    fun calculateTodayEarnings(
        now: CivilDateTime,
        voluntaryOvertimeTotalSeconds: Double = 0.0,
        isPaused: Boolean = false,
    ): TodayEarnings {
        if (isPaused) {
            return TodayEarnings(status = WorkStatus.PAUSED, totalWorkSeconds = totalWorkSeconds)
        }

        val today = now.date
        if (isDayOff(today)) {
            return TodayEarnings(status = WorkStatus.DAY_OFF, totalWorkSeconds = totalWorkSeconds)
        }

        val currentMinute = now.minuteOfDay
        val currentSec = now.secondOfDay

        // Overtime config for today (if any).
        val override = dayOverrides[now.isoDateString]
        val isOvertime = override?.dayType == DayType.OVERTIME
        val multiplier = if (isOvertime) override?.overtimeMultiplier ?: 2.0 else 1.0

        // When overtime has customWorkHours it acts as the reference for the per-second rate
        // (snapshotted from the normal work schedule). The rate stays anchored to this reference
        // regardless of the current schedule's totalWorkHours.
        val overtimeBaseSecondRate: Double =
            if (isOvertime && (override?.customWorkHours ?: 0.0) > 0) {
                dailyRate / override!!.customWorkHours!! / 3600.0
            } else {
                secondRate
            }

        // Standard schedule path (regular day or overtime) — same window, same breaks.
        val effectiveTotalSeconds = totalWorkSeconds
        val effectiveSecondRate = if (isOvertime) overtimeBaseSecondRate else secondRate

        // Not started: before work start (and not in cross-midnight's next-day portion).
        if (!schedule.isInWorkWindow(currentMinute) && !schedule.isAfterWork(currentMinute)) {
            return TodayEarnings(status = WorkStatus.NOT_STARTED, totalWorkSeconds = effectiveTotalSeconds)
        }

        // Completed: after work end.
        if (schedule.isAfterWork(currentMinute)) {
            // Voluntary overtime: only on normal workdays (not pre-planned overtime), triggered by
            // the user after work hours. The session duration is tracked externally and passed in.
            if (voluntaryOvertimeTotalSeconds > 0 && !isOvertime) {
                return TodayEarnings(
                    amount = voluntaryOvertimeTotalSeconds * secondRate,
                    progress = 1.0,
                    status = WorkStatus.VOLUNTARY_OVERTIME,
                    elapsedSeconds = effectiveTotalSeconds,
                    totalWorkSeconds = effectiveTotalSeconds,
                )
            }

            val fullAmount = if (isOvertime) {
                effectiveSecondRate * effectiveTotalSeconds * multiplier
            } else {
                dailyRate
            }
            return TodayEarnings(
                amount = fullAmount,
                progress = 1.0,
                status = if (isOvertime) WorkStatus.OVERTIME else WorkStatus.COMPLETED,
                elapsedSeconds = effectiveTotalSeconds,
                totalWorkSeconds = effectiveTotalSeconds,
            )
        }

        // In the work window — a break overrides the accruing value.
        val activeBreak = schedule.breakContaining(currentMinute)
        if (activeBreak != null) {
            val breakStartSec = activeBreak.startMinutes * 60.0
            val breakStartElapsedSec = schedule.elapsedSinceStartSeconds(breakStartSec)
            val priorBreakSec = schedule.elapsedBreakSeconds(breakStartSec)
            val elapsedSec = minOf(maxOf(0.0, breakStartElapsedSec - priorBreakSec), effectiveTotalSeconds)
            return TodayEarnings(
                amount = effectiveSecondRate * elapsedSec * multiplier,
                progress = if (effectiveTotalSeconds > 0) elapsedSec / effectiveTotalSeconds else 0.0,
                status = WorkStatus.ON_BREAK,
                elapsedSeconds = elapsedSec,
                totalWorkSeconds = effectiveTotalSeconds,
            )
        }

        // Working — second-level precision.
        val nowElapsedSec = schedule.elapsedSinceStartSeconds(currentSec)
        val elapsedBreakSec = schedule.elapsedBreakSeconds(currentSec)
        val elapsedSec = minOf(maxOf(0.0, nowElapsedSec - elapsedBreakSec), effectiveTotalSeconds)
        return TodayEarnings(
            amount = effectiveSecondRate * elapsedSec * multiplier,
            progress = if (effectiveTotalSeconds > 0) elapsedSec / effectiveTotalSeconds else 0.0,
            status = if (isOvertime) WorkStatus.OVERTIME else WorkStatus.WORKING,
            elapsedSeconds = elapsedSec,
            totalWorkSeconds = effectiveTotalSeconds,
        )
    }

    /**
     * @param isPaused when true today contributes nothing to the month totals — a paused day is
     *   treated as earning zero, matching [calculateTodayEarnings].
     */
    fun calculateMonthSummary(now: CivilDateTime, isPaused: Boolean = false): MonthSummary {
        val date = now.date
        val workingDays = countWorkingDaysInMonth(date.year, date.month)
        val elapsedDays = countElapsedWorkingDays(date)
        val payday = calculatePayday(date)
        val cycle = calculatePaydayCycle(date)
        return MonthSummary(
            workingDaysThisMonth = workingDays,
            workingDaysElapsed = elapsedDays,
            monthProgress = if (workingDays > 0) elapsedDays.toDouble() / workingDays else 0.0,
            monthEarnings = calculateElapsedMonthEarnings(date, isPaused),
            totalMonthEarnings = calculateTotalMonthEarnings(date, isPaused),
            daysUntilPayday = payday.first,
            isPayday = payday.second,
            paydayCycleProgress = cycle.first,
            paydayCycleTotal = cycle.second,
            paydayCycleElapsed = cycle.third,
        )
    }

    /** Counts the working days in the given month, accounting for the holiday calendar. */
    fun countWorkingDaysInMonth(year: Int, month: Int): Int {
        val total = daysInMonth(year, month)
        var count = 0
        for (day in 1..total) {
            if (!isDayOff(CivilDate(year, month, day))) count += 1
        }
        return count
    }

    /**
     * Resolves how [date] should be treated for display: user override first,
     * then the holiday calendar, then the weekend fallback. Platform calendar
     * grids render this instead of re-deriving the precedence themselves.
     */
    fun resolveDayKind(date: CivilDate): DayKind {
        dayOverrides[date.isoString]?.let { override ->
            when (override.dayType) {
                DayType.HOLIDAY -> return DayKind.USER_HOLIDAY
                DayType.OVERTIME -> return DayKind.USER_OVERTIME
                DayType.NORMAL -> Unit
            }
        }
        if (holidayCalendar != null) {
            if (holidayCalendar.isHoliday(date.month, date.day)) return DayKind.PUBLIC_HOLIDAY
            if (holidayCalendar.isAdjustedWorkday(date.month, date.day)) return DayKind.ADJUSTED_WORKDAY
        }
        val weekday = date.dayOfWeek
        return if (weekday == 0 || weekday == 6) DayKind.WEEKEND else DayKind.NORMAL
    }

    // MARK: - Private

    /**
     * Three-tier day-off determination: user override > holiday calendar > weekend check.
     * 0 = Sunday .. 6 = Saturday, matching JS `Date.getDay()` (weekend = 0 or 6).
     */
    private fun isDayOff(date: CivilDate): Boolean {
        // Tier 1: user override.
        dayOverrides[date.isoString]?.let { override ->
            when (override.dayType) {
                DayType.NORMAL -> Unit // fall through to the calendar/weekend check
                DayType.HOLIDAY -> return true
                DayType.OVERTIME -> return false // overtime days are working days
            }
        }

        // Tier 2: Chinese holiday calendar.
        if (holidayCalendar != null) {
            if (holidayCalendar.isHoliday(date.month, date.day)) return true
            if (holidayCalendar.isAdjustedWorkday(date.month, date.day)) return false
        }

        // Tier 3: weekend fallback.
        val weekday = date.dayOfWeek
        return weekday == 0 || weekday == 6
    }

    /** Per-day earnings for a given date, accounting for overtime. */
    private fun dailyEarningsForDate(date: CivilDate): Double {
        dayOverrides[date.isoString]?.let { override ->
            if (override.dayType == DayType.OVERTIME) {
                val rateRefHours = if ((override.customWorkHours ?: 0.0) > 0) {
                    override.customWorkHours!!
                } else {
                    schedule.totalWorkHours
                }
                val effSecondRate = dailyRate / rateRefHours / 3600.0
                return effSecondRate * schedule.totalWorkHours * 3600.0 * override.overtimeMultiplier
            }
        }
        if (isDayOff(date)) return 0.0
        return dailyRate
    }

    /** Sums earnings for every elapsed working day in the month (including today if working). */
    private fun calculateElapsedMonthEarnings(date: CivilDate, isPaused: Boolean): Double {
        val monthStart = CivilDate(date.year, date.month, 1)
        var total = 0.0
        var current = monthStart
        while (current <= date) {
            if (!(isPaused && current == date)) {
                total += dailyEarningsForDate(current)
            }
            current = current.plusDays(1)
        }
        return total
    }

    /** Sums earnings for every working day in the entire month. */
    private fun calculateTotalMonthEarnings(date: CivilDate, isPaused: Boolean): Double {
        val total = daysInMonth(date.year, date.month)
        var sum = 0.0
        for (day in 1..total) {
            val dayDate = CivilDate(date.year, date.month, day)
            if (isPaused && dayDate == date) continue
            sum += dailyEarningsForDate(dayDate)
        }
        return sum
    }

    private fun countElapsedWorkingDays(date: CivilDate): Int {
        val monthStart = CivilDate(date.year, date.month, 1)
        var count = 0
        var current = monthStart
        while (current <= date) {
            if (!isDayOff(current)) count += 1
            current = current.plusDays(1)
        }
        if (!isDayOff(date)) count -= 1
        return maxOf(0, count)
    }

    /** @return (daysUntilPayday, isPayday) */
    private fun calculatePayday(date: CivilDate): Pair<Int, Boolean> {
        if (date.day == payDay) return 0 to true

        val sameMonthPayday = CivilDate(date.year, date.month, minOf(payDay, daysInMonth(date.year, date.month)))
        val paydayDate = if (date.day > payDay) sameMonthPayday.plusMonthsClamped(1) else sameMonthPayday
        val days = (paydayDate.toEpochDays() - date.toEpochDays()).toInt()
        return days to false
    }

    /** @return (progress, totalDays, elapsedDays) */
    private fun calculatePaydayCycle(date: CivilDate): Triple<Double, Int, Int> {
        val thisMonthPayday = CivilDate(date.year, date.month, minOf(payDay, daysInMonth(date.year, date.month)))
        val cycleStart = if (date.day < payDay) thisMonthPayday.plusMonthsClamped(-1) else thisMonthPayday
        val cycleEnd = cycleStart.plusMonthsClamped(1)
        val totalDays = (cycleEnd.toEpochDays() - cycleStart.toEpochDays()).toInt()
        val elapsedDays = (date.toEpochDays() - cycleStart.toEpochDays()).toInt()
        val progress = if (totalDays > 0) minOf(1.0, elapsedDays.toDouble() / totalDays) else 0.0
        return Triple(progress, totalDays, elapsedDays)
    }
}
