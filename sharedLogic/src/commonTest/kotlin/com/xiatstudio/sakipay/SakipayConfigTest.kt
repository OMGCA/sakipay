/* (c) Copyright XiatStudio 2026~2026 */
package com.xiatstudio.sakipay

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SakipayConfigTest {

    private fun sampleConfig() = SakipayConfig(
        monthlyPay = 12345.67,
        currency = "$",
        payDay = 5,
        taxRate = 0.1,
        workingDaysPerMonth = 20.0,
        workStartHour = 8,
        workStartMinute = 30,
        workEndHour = 17,
        workEndMinute = 45,
        breakSegments = listOf(
            BreakSegment.create(12, 0, 13, 0, id = "lunch"),
            BreakSegment.create(15, 0, 15, 15, id = "tea"),
        ),
        dayOverrides = listOf(
            DayOverride("2026-10-01", DayType.HOLIDAY),
            DayOverride("2026-10-10", DayType.OVERTIME, overtimeMultiplier = 3.0, customWorkHours = 6.0),
        ),
        useCalibratedWorkDays = false,
    )

    @Test
    fun jsonRoundTrips() {
        val original = sampleConfig()
        val restored = SakipayConfig.fromJson(original.toJson())
        assertEquals(original, restored)
    }

    @Test
    fun customWorkHoursNullSurvivesRoundTrip() {
        val restored = SakipayConfig.fromJson(sampleConfig().toJson())
        assertNull(restored.dayOverrides.first { it.dateString == "2026-10-01" }.customWorkHours)
        assertEquals(3.0, restored.dayOverrides.first { it.dateString == "2026-10-10" }.overtimeMultiplier, 0.0001)
    }

    @Test
    fun defaultsMatchFirstLaunch() {
        val c = SakipayConfig.DEFAULT
        assertEquals(0.0, c.monthlyPay, 0.0001)
        assertEquals("¥", c.currency)
        assertEquals(15, c.payDay)
        assertEquals(21.75, c.workingDaysPerMonth, 0.0001)
        assertEquals(540, c.workStartMinutes)
        assertEquals(1080, c.workEndMinutes)
        assertTrue(c.useCalibratedWorkDays)
        assertTrue(c.breakSegments.isEmpty())
        assertFalse(c.isConfigured)
    }

    @Test
    fun fromJsonOfGarbageFallsBackToDefaults() {
        assertEquals(SakipayConfig.DEFAULT, SakipayConfig.fromJson("not json at all"))
        assertEquals(SakipayConfig.DEFAULT, SakipayConfig.fromJson(""))
    }

    @Test
    fun pruningRemovesBreaksOutsideWorkWindow() {
        val c = SakipayConfig(
            workStartHour = 9,
            workEndHour = 18,
            breakSegments = listOf(
                BreakSegment.create(12, 0, 13, 0, id = "keep"),
                BreakSegment.create(20, 0, 21, 0, id = "drop"),
            ),
        )
        val (pruned, removed) = c.withPrunedBreaks()
        assertEquals(1, removed)
        assertEquals(listOf("keep"), pruned.breakSegments.map { it.id })
    }

    @Test
    fun prunedWorkingDaysMatchTheCalendar() {
        val c = SakipayConfig(useCalibratedWorkDays = true)
        assertEquals(18, c.calibratedWorkingDays(2026, 10))
        assertEquals(19, c.calibratedWorkingDays(2026, 5))
    }

    @Test
    fun effectiveWorkingDaysSwitchesWithCalibration() {
        val calibrated = SakipayConfig(useCalibratedWorkDays = true)
        assertEquals(18.0, calibrated.effectiveWorkingDays(2026, 10), 0.0001)
        val fixed = SakipayConfig(workingDaysPerMonth = 21.75, useCalibratedWorkDays = false)
        assertEquals(21.75, fixed.effectiveWorkingDays(2026, 10), 0.0001)
    }

    @Test
    fun addBreakAppendsWithinWindow() {
        val base = SakipayConfig(
            workStartHour = 9,
            workEndHour = 18,
            breakSegments = listOf(BreakSegment.create(12, 0, 13, 0, id = "lunch")),
            useCalibratedWorkDays = false,
        )
        val added = SakipayConfig.fromJson(SakipayCore.addBreakJson(base.toJson()))
        assertEquals(2, added.breakSegments.size)
        // New break starts an hour after the previous one ends (14:00) and lasts an hour.
        val newBreak = added.breakSegments.last()
        assertEquals(14 * 60, newBreak.startMinutes)
        assertEquals(15 * 60, newBreak.endMinutes)
    }

    @Test
    fun addBreakIsNoOpWhenWindowTooShort() {
        val short = SakipayConfig(
            workStartHour = 9,
            workEndHour = 10, // 1 hour < 2 hour minimum
            breakSegments = emptyList(),
            useCalibratedWorkDays = false,
        )
        val added = SakipayConfig.fromJson(SakipayCore.addBreakJson(short.toJson()))
        assertTrue(added.breakSegments.isEmpty())
    }

    @Test
    fun resolveDayKindFollowsPrecedence() {
        // 2026-10-01 is a bundled public holiday.
        assertEquals("publicHoliday", SakipayCore.resolveDayKind(2026, 10, 1, "[]"))
        // 2026-10-10 is a Saturday listed as an adjusted working day.
        assertEquals("adjustedWorkday", SakipayCore.resolveDayKind(2026, 10, 10, "[]"))
        // 2026-10-11 is an ordinary Sunday.
        assertEquals("weekend", SakipayCore.resolveDayKind(2026, 10, 11, "[]"))
        // 2026-10-08 is an ordinary Thursday.
        assertEquals("normal", SakipayCore.resolveDayKind(2026, 10, 8, "[]"))
        // A user override wins over the calendar.
        assertEquals(
            "userOvertime",
            SakipayCore.resolveDayKind(2026, 10, 8, """[{"dateString":"2026-10-08","dayType":"overtime"}]"""),
        )
        assertEquals(
            "userHoliday",
            SakipayCore.resolveDayKind(2026, 10, 8, """[{"dateString":"2026-10-08","dayType":"holiday"}]"""),
        )
    }

    @Test
    fun addBreakToBreaksPlacesWithinWindow() {
        val json = SakipayCore.addBreakToBreaks(540, 1080, """[{"startMinutes":720,"endMinutes":780}]""")
        val breaks = SakipayConfig.fromJson("""{"breaks":$json}""").breakSegments
        assertEquals(2, breaks.size)
        assertEquals(14 * 60, breaks.last().startMinutes)
        assertEquals(15 * 60, breaks.last().endMinutes)
    }

    @Test
    fun workWindowMinutesHandlesCrossMidnight() {
        assertEquals(540, SakipayCore.workWindowMinutes(540, 1080))
        assertEquals(480, SakipayCore.workWindowMinutes(1320, 360))
    }
}
