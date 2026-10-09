/* (c) Copyright XiatStudio 2026~2026 */
package com.xiatstudio.sakipay

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CivilDateTest {

    @Test
    fun epochDaysRoundTrip() {
        for (date in listOf(
            CivilDate(1970, 1, 1),
            CivilDate(2026, 10, 8),
            CivilDate(2024, 2, 29),
            CivilDate(2025, 1, 1),
            CivilDate(2026, 12, 31),
        )) {
            val days = date.toEpochDays()
            val (y, m, d) = civilFromDays(days)
            assertEquals(date, CivilDate(y, m, d), "round-trip failed for $date")
        }
    }

    @Test
    fun knownEpochDays() {
        assertEquals(0L, CivilDate(1970, 1, 1).toEpochDays())
        assertEquals(20734L, CivilDate(2026, 10, 8).toEpochDays())
    }

    @Test
    fun dayOfWeekMatchesJsConvention() {
        // 0 = Sunday .. 6 = Saturday, matching JS Date.getDay().
        assertEquals(4, CivilDate(2026, 10, 8).dayOfWeek) // Thursday
        assertEquals(6, CivilDate(2026, 10, 10).dayOfWeek) // Saturday
        assertEquals(0, CivilDate(2026, 12, 27).dayOfWeek) // Sunday
        assertEquals(4, CivilDate(1970, 1, 1).dayOfWeek) // Thursday
    }

    @Test
    fun daysInMonthHandlesLeapYears() {
        assertEquals(29, daysInMonth(2024, 2))
        assertEquals(28, daysInMonth(2026, 2))
        assertEquals(31, daysInMonth(2026, 10))
        assertEquals(30, daysInMonth(2026, 11))
    }

    @Test
    fun plusMonthsClampsDay() {
        assertEquals(CivilDate(2026, 2, 28), CivilDate(2026, 1, 31).plusMonthsClamped(1))
        assertEquals(CivilDate(2024, 2, 29), CivilDate(2024, 1, 31).plusMonthsClamped(1))
        assertEquals(CivilDate(2025, 12, 15), CivilDate(2026, 1, 15).plusMonthsClamped(-1))
    }

    @Test
    fun epochMillisConvertsToLocalCivilTime() {
        // 2026-10-08T00:00:00Z viewed at UTC+8 is 08:00 on the 8th.
        val utcMidnight = CivilDate(2026, 10, 8).toEpochDays() * 86_400_000L
        val local = civilDateTimeFromEpochMillis(utcMidnight, 480)
        assertEquals(CivilDateTime(2026, 10, 8, 8, 0, 0), local)
        // And at UTC-5 it is 19:00 on the 7th.
        val west = civilDateTimeFromEpochMillis(utcMidnight, -300)
        assertEquals(CivilDateTime(2026, 10, 7, 19, 0, 0), west)
    }

    @Test
    fun compareToOrdersChronologically() {
        assertTrue(CivilDate(2026, 10, 8) > CivilDate(2026, 10, 7))
        assertTrue(CivilDate(2026, 1, 31) < CivilDate(2026, 2, 1))
    }
}
