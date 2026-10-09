/* (c) Copyright XiatStudio 2026~2026 */
package com.xiatstudio.sakipay

/**
 * Persisted state of the voluntary-overtime session machine.
 *
 * The app and the widget run in separate processes but share one store. Both
 * processes keep this value in the platform store (as [toJson]) and route every
 * transition through the pure functions below, so ending OT banks into the
 * weekly pool exactly once no matter where it is triggered.
 */
data class VoluntaryOvertimeState(
    val active: Boolean = false,
    /** OT seconds accumulated from completed sessions today (excludes the current one). */
    val accumulatedSeconds: Double = 0.0,
    /** "YYYY-MM-DD" the accumulated value belongs to; stale when it isn't today. */
    val dateString: String = "",
    /** Epoch seconds of when the current session started; 0 when inactive. */
    val sessionStartEpochSeconds: Double = 0.0,
    /** Money the company owes for the current week. */
    val weeklyEarnings: Double = 0.0,
    /** Monday "YYYY-MM-DD" the weekly total belongs to. */
    val weekStart: String = "",
) {

    /**
     * Total OT seconds at the given moment.
     *
     * @param mutatesState whether a stale date may reset the persisted session.
     *   The default (true) is correct when evaluating the *live* moment: a
     *   session left over from a previous day is finished, so its state is
     *   cleared. Callers that evaluate **hypothetical future dates** (the widget
     *   timeline builds entries for upcoming refresh points) must pass false —
     *   otherwise a probe for tomorrow would silently end a still-running
     *   session and discard its elapsed time before it can be banked.
     * @return the (possibly reset) state and the computed total seconds.
     */
    fun totalSeconds(
        nowEpochSeconds: Double,
        todayString: String,
        mutatesState: Boolean = true,
    ): Pair<VoluntaryOvertimeState, Double> {
        if (!active) return this to 0.0
        if (dateString != todayString) {
            if (mutatesState) {
                return VoluntaryOvertimeState() to 0.0
            }
            return this to 0.0
        }
        val elapsed = maxOf(0.0, nowEpochSeconds - sessionStartEpochSeconds)
        return this to (accumulatedSeconds + elapsed)
    }

    /** Starts a new session. Resets the day's accumulation when the stored date is stale. */
    fun withStartedSession(nowEpochSeconds: Double, todayString: String): VoluntaryOvertimeState {
        val sameDay = dateString == todayString
        return copy(
            active = true,
            accumulatedSeconds = if (sameDay) accumulatedSeconds else 0.0,
            dateString = todayString,
            sessionStartEpochSeconds = nowEpochSeconds,
        )
    }

    /**
     * Ends the current session, adding its elapsed time to the day's total and
     * immediately settling the day into the weekly pool at [secondRate].
     */
    fun withEndedSession(
        nowEpochSeconds: Double,
        todayString: String,
        secondRate: Double,
        mondayString: String,
    ): VoluntaryOvertimeState {
        if (!active) return this
        val elapsed = maxOf(0.0, nowEpochSeconds - sessionStartEpochSeconds)
        val ended = copy(
            active = false,
            accumulatedSeconds = accumulatedSeconds + elapsed,
            sessionStartEpochSeconds = 0.0,
        )
        return ended.withDailyBanked(secondRate, mondayString)
    }

    /**
     * Converts the day's accumulated OT seconds into money and adds to the weekly
     * total, then resets the daily accumulation. Call when a new work day begins
     * or when OT ends.
     */
    fun withDailyBanked(secondRate: Double, mondayString: String): VoluntaryOvertimeState {
        if (accumulatedSeconds <= 0.0) return this
        val sameWeek = weekStart == mondayString
        val baseWeekly = if (sameWeek) weeklyEarnings else 0.0
        return copy(
            weeklyEarnings = baseWeekly + accumulatedSeconds * secondRate,
            weekStart = mondayString,
            accumulatedSeconds = 0.0,
            dateString = "",
        )
    }

    // --- Serialisation --------------------------------------------------------

    fun toJson(): String = MiniJson.obj(
        "active" to active,
        "accumulatedSeconds" to accumulatedSeconds,
        "dateString" to dateString,
        "sessionStartEpochSeconds" to sessionStartEpochSeconds,
        "weeklyEarnings" to weeklyEarnings,
        "weekStart" to weekStart,
    )

    companion object {
        fun fromJson(json: String): VoluntaryOvertimeState {
            val map = try {
                MiniJson.parse(json).asMapOrNull()
            } catch (e: IllegalArgumentException) {
                null
            } ?: return VoluntaryOvertimeState()
            return VoluntaryOvertimeState(
                active = map.boolOr("active", false),
                accumulatedSeconds = map.doubleOr("accumulatedSeconds", 0.0),
                dateString = map.stringOr("dateString", ""),
                sessionStartEpochSeconds = map.doubleOr("sessionStartEpochSeconds", 0.0),
                weeklyEarnings = map.doubleOr("weeklyEarnings", 0.0),
                weekStart = map.stringOr("weekStart", ""),
            )
        }

        /** Monday of the week containing [date] (JS-week convention, Monday = start). */
        fun mondayOfWeek(date: CivilDate): String {
            val weekday = date.dayOfWeek // 0 = Sunday .. 6 = Saturday
            val diff = if (weekday == 0) 6 else weekday - 1
            return date.plusDays(-diff).isoString
        }
    }
}
