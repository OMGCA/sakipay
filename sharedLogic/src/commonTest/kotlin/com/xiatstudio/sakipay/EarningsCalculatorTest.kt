/* (c) Copyright XiatStudio 2026~2026 */
package com.xiatstudio.sakipay

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class EarningsCalculatorTest {

    private val tol = 0.01

    /** 21750 / 21.75 == 1000/day; 9h window minus a 90-min break == 7.5h == 27000s. */
    private fun config(overrides: List<DayOverride> = emptyList()) = SakipayConfig(
        monthlyPay = 21750.0,
        workingDaysPerMonth = 21.75,
        taxRate = 0.0,
        payDay = 15,
        workStartHour = 9,
        workStartMinute = 0,
        workEndHour = 18,
        workEndMinute = 0,
        breakSegments = listOf(BreakSegment.create(12, 0, 13, 30)),
        dayOverrides = overrides,
        useCalibratedWorkDays = false,
    )

    private fun at(hour: Int, minute: Int, day: Int = 8) =
        CivilDateTime(2026, 10, day, hour, minute, 0)

    private fun calculator(overrides: List<DayOverride> = emptyList()) =
        config(overrides).calculatorFor(at(0, 0).date)

    @Test
    fun ratesDeriveFromPayAndSchedule() {
        val calc = calculator()
        assertEquals(1000.0, calc.dailyRate, tol)
        assertEquals(27000.0, calc.totalWorkSeconds, tol)
        assertEquals(0.037037, calc.secondRate, 0.000001)
    }

    @Test
    fun notStartedBeforeWork() {
        val result = calculator().calculateTodayEarnings(at(8, 0))
        assertEquals(WorkStatus.NOT_STARTED, result.status)
        assertEquals(0.0, result.amount, tol)
    }

    @Test
    fun workingAccruesAtSecondRate() {
        val result = calculator().calculateTodayEarnings(at(10, 0))
        assertEquals(WorkStatus.WORKING, result.status)
        assertEquals(3600.0, result.elapsedSeconds, tol)
        assertEquals(133.333, result.amount, tol)
        assertEquals(0.133333, result.progress, 0.0001)
    }

    @Test
    fun onBreakFreezesAtBreakStart() {
        val atStart = calculator().calculateTodayEarnings(at(12, 0))
        assertEquals(WorkStatus.ON_BREAK, atStart.status)
        assertEquals(10800.0, atStart.elapsedSeconds, tol)
        assertEquals(400.0, atStart.amount, tol)

        val midBreak = calculator().calculateTodayEarnings(at(12, 45))
        assertEquals(WorkStatus.ON_BREAK, midBreak.status)
        assertEquals(400.0, midBreak.amount, tol)
    }

    @Test
    fun resumesAfterBreak() {
        val result = calculator().calculateTodayEarnings(at(13, 30))
        assertEquals(WorkStatus.WORKING, result.status)
        assertEquals(400.0, result.amount, tol)
    }

    @Test
    fun completedAfterWorkEnd() {
        val result = calculator().calculateTodayEarnings(at(18, 0))
        assertEquals(WorkStatus.COMPLETED, result.status)
        assertEquals(1000.0, result.amount, tol)
        assertEquals(1.0, result.progress, tol)
    }

    @Test
    fun pausedEarnsNothing() {
        val result = calculator().calculateTodayEarnings(at(10, 0), isPaused = true)
        assertEquals(WorkStatus.PAUSED, result.status)
        assertEquals(0.0, result.amount, tol)
    }

    @Test
    fun weekendIsDayOff() {
        // 2026-10-10 is a Saturday.
        val result = calculator().calculateTodayEarnings(at(10, 0, day = 10))
        assertEquals(WorkStatus.DAY_OFF, result.status)
    }

    @Test
    fun publicHolidayIsDayOff() {
        // 2026-10-01 is in the bundled holiday calendar.
        val result = calculator().calculateTodayEarnings(at(10, 0, day = 1))
        assertEquals(WorkStatus.DAY_OFF, result.status)
    }

    @Test
    fun adjustedWorkdayOverridesWeekend() {
        // 2026-05-09 is a Saturday but an adjusted working day.
        val may = CivilDateTime(2026, 5, 9, 10, 0, 0)
        val result = config().calculatorFor(may.date).calculateTodayEarnings(may)
        assertFalse(result.status == WorkStatus.DAY_OFF)
    }

    @Test
    fun userOverrideWinsOverCalendar() {
        val holidayOverride = listOf(DayOverride("2026-10-08", DayType.HOLIDAY))
        assertEquals(
            WorkStatus.DAY_OFF,
            calculator(holidayOverride).calculateTodayEarnings(at(10, 0)).status,
        )
    }

    @Test
    fun overtimeDoublesTheRate() {
        val overtime = listOf(DayOverride("2026-10-08", DayType.OVERTIME, overtimeMultiplier = 2.0))
        val calc = calculator(overtime)
        val duringWork = calc.calculateTodayEarnings(at(10, 0))
        assertEquals(WorkStatus.OVERTIME, duringWork.status)
        assertEquals(266.666, duringWork.amount, tol)

        val afterWork = calc.calculateTodayEarnings(at(18, 0))
        assertEquals(2000.0, afterWork.amount, tol)
    }

    @Test
    fun voluntaryOvertimeUsesNormalRateAfterWork() {
        val calc = calculator()
        val result = calc.calculateTodayEarnings(at(19, 0), voluntaryOvertimeTotalSeconds = 3600.0)
        assertEquals(WorkStatus.VOLUNTARY_OVERTIME, result.status)
        assertEquals(133.333, result.amount, tol)
    }

    @Test
    fun crossMidnightScheduleWorks() {
        val night = SakipayConfig(
            monthlyPay = 21750.0,
            workingDaysPerMonth = 21.75,
            workStartHour = 22,
            workStartMinute = 0,
            workEndHour = 6,
            workEndMinute = 0,
            breakSegments = emptyList(),
            useCalibratedWorkDays = false,
        )
        // 8h window == 28800s.
        val calc = night.calculatorFor(CivilDate(2026, 10, 8))
        assertEquals(28800.0, calc.totalWorkSeconds, tol)
        // 23:00 is one hour into the shift.
        val result = calc.calculateTodayEarnings(CivilDateTime(2026, 10, 8, 23, 0, 0))
        assertEquals(WorkStatus.WORKING, result.status)
        assertEquals(3600.0, result.elapsedSeconds, tol)
    }

    @Test
    fun monthSummaryReflectsCalendarAndPayday() {
        val summary = calculator().calculateMonthSummary(at(10, 0))
        // October 2026 has 18 working days once the National Day holidays are removed.
        assertEquals(18, summary.workingDaysThisMonth)
        assertEquals(0, summary.workingDaysElapsed) // today not yet counted
        assertEquals(1000.0, summary.monthEarnings, tol) // only Oct 8 worked so far
        assertEquals(18000.0, summary.totalMonthEarnings, tol)
        assertEquals(7, summary.daysUntilPayday)
        assertFalse(summary.isPayday)
        assertEquals(30, summary.paydayCycleTotal)
        assertEquals(23, summary.paydayCycleElapsed)
        assertEquals(0.766666, summary.paydayCycleProgress, 0.0001)
    }

    @Test
    fun pausedMonthExcludesToday() {
        val running = calculator().calculateMonthSummary(at(10, 0))
        val paused = calculator().calculateMonthSummary(at(10, 0), isPaused = true)
        assertEquals(0.0, paused.monthEarnings, tol)
        assertTrue(paused.monthEarnings <= running.monthEarnings)
    }
}
