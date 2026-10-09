/* (c) Copyright XiatStudio 2026~2026 */
package com.xiatstudio.sakipay

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class VoluntaryOvertimeTest {

    private val today = "2026-10-08"
    private val monday = "2026-10-05"

    @Test
    fun inactiveStateHasNoTotal() {
        val (state, seconds) = VoluntaryOvertimeState().totalSeconds(1_000_000.0, today)
        assertEquals(0.0, seconds, 0.0001)
        assertFalse(state.active)
    }

    @Test
    fun runningSessionTotalsElapsed() {
        val started = VoluntaryOvertimeState().withStartedSession(1000.0, today)
        assertTrue(started.active)
        assertEquals(today, started.dateString)

        val (_, seconds) = started.totalSeconds(4600.0, today)
        assertEquals(3600.0, seconds, 0.0001)
    }

    @Test
    fun staleDayResetsWhenMutating() {
        val started = VoluntaryOvertimeState().withStartedSession(1000.0, today)
        val (state, seconds) = started.totalSeconds(5000.0, "2026-10-09", mutatesState = true)
        assertEquals(0.0, seconds, 0.0001)
        assertFalse(state.active)
    }

    @Test
    fun staleDayDoesNotResetWhenProbingFuture() {
        // The widget timeline probes future dates; that must not end a live session.
        val started = VoluntaryOvertimeState().withStartedSession(1000.0, today)
        val (state, seconds) = started.totalSeconds(5000.0, "2026-10-09", mutatesState = false)
        assertEquals(0.0, seconds, 0.0001)
        assertTrue(state.active)
    }

    @Test
    fun endingSessionBanksIntoWeeklyPool() {
        val started = VoluntaryOvertimeState().withStartedSession(1000.0, today)
        val ended = started.withEndedSession(4600.0, today, secondRate = 0.5, mondayString = monday)
        assertFalse(ended.active)
        assertEquals(0.0, ended.accumulatedSeconds, 0.0001)
        assertEquals(monday, ended.weekStart)
        assertEquals(1800.0, ended.weeklyEarnings, 0.0001) // 3600s * 0.5
    }

    @Test
    fun multipleSessionsAccumulateWithinTheDay() {
        val first = VoluntaryOvertimeState().withStartedSession(1000.0, today)
        val afterFirst = first.withEndedSession(4000.0, today, secondRate = 0.5, mondayString = monday)
        // Second session of 1 hour on the same day.
        val second = afterFirst.withStartedSession(10_000.0, today)
        val afterSecond = second.withEndedSession(13_600.0, today, secondRate = 0.5, mondayString = monday)
        // 3000s + 3600s = 6600s * 0.5 = 3300.
        assertEquals(3300.0, afterSecond.weeklyEarnings, 0.0001)
    }

    @Test
    fun bankingResetsAccumulationAcrossWeeks() {
        val state = VoluntaryOvertimeState(
            accumulatedSeconds = 100.0,
            weekStart = "2026-09-28",
            weeklyEarnings = 999.0,
        )
        val banked = state.withDailyBanked(secondRate = 1.0, mondayString = monday)
        assertEquals(100.0, banked.weeklyEarnings, 0.0001) // prior week discarded
        assertEquals(monday, banked.weekStart)
        assertEquals(0.0, banked.accumulatedSeconds, 0.0001)
    }

    @Test
    fun stateJsonRoundTrips() {
        val state = VoluntaryOvertimeState(
            active = true,
            accumulatedSeconds = 1234.5,
            dateString = today,
            sessionStartEpochSeconds = 1000.0,
            weeklyEarnings = 42.0,
            weekStart = monday,
        )
        assertEquals(state, VoluntaryOvertimeState.fromJson(state.toJson()))
    }

    @Test
    fun mondayOfWeekUsesMondayStart() {
        // 2026-10-08 is a Thursday -> Monday is the 5th.
        assertEquals("2026-10-05", VoluntaryOvertimeState.mondayOfWeek(CivilDate(2026, 10, 8)))
        // A Sunday belongs to the week that started the previous Monday.
        assertEquals("2026-10-05", VoluntaryOvertimeState.mondayOfWeek(CivilDate(2026, 10, 11)))
    }
}
