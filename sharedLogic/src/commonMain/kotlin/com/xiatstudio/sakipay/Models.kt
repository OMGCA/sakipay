/* (c) Copyright XiatStudio 2026~2026 */
package com.xiatstudio.sakipay

import kotlin.random.Random

// MARK: - Break / schedule

/** A single break window expressed in minutes from midnight. */
data class BreakSchedule(val startMinutes: Int, val endMinutes: Int) {
    val durationMinutes: Int get() = endMinutes - startMinutes
}

/**
 * Internal work-schedule representation used by the calculator.
 *
 * Supports cross-midnight schedules where `workEndMinutes <= workStartMinutes`
 * (e.g. a 22:00–06:00 night shift).
 */
data class WorkSchedule(
    val workStartMinutes: Int,
    val workEndMinutes: Int,
    val breaks: List<BreakSchedule>,
) {
    /** True when the work day crosses midnight (e.g. 22:00–06:00). */
    val isCrossMidnight: Boolean get() = workEndMinutes <= workStartMinutes

    /** Total clock minutes in the work window (before subtracting breaks). */
    val workWindowMinutes: Int
        get() = if (isCrossMidnight) (1440 - workStartMinutes) + workEndMinutes
        else workEndMinutes - workStartMinutes

    val totalBreakMinutes: Int get() = breaks.sumOf { it.durationMinutes }

    val totalWorkMinutes: Int get() = workWindowMinutes - totalBreakMinutes

    val totalWorkHours: Double get() = totalWorkMinutes / 60.0

    /** All break schedules sorted by start time. */
    val sortedBreaks: List<BreakSchedule> get() = breaks.sortedBy { it.startMinutes }

    /**
     * Converts a clock-minute value to minutes elapsed since work start,
     * handling the cross-midnight wrap. Clamped to 0 for minutes before start.
     */
    fun elapsedSinceStart(clockMinute: Int): Int {
        if (!isCrossMidnight) {
            return maxOf(0, clockMinute - workStartMinutes)
        }
        return if (clockMinute >= workStartMinutes) {
            clockMinute - workStartMinutes
        } else {
            (1440 - workStartMinutes) + clockMinute
        }
    }

    /** Seconds elapsed since work start for a clock-second value, with wrap. */
    fun elapsedSinceStartSeconds(clockSecond: Double): Double {
        val wsSec = workStartMinutes * 60.0
        if (!isCrossMidnight) {
            return maxOf(0.0, clockSecond - wsSec)
        }
        return if (clockSecond >= wsSec) {
            clockSecond - wsSec
        } else {
            (1440.0 * 60.0) - wsSec + clockSecond
        }
    }

    /** True when [clockMinute] falls within the active work window. */
    fun isInWorkWindow(clockMinute: Int): Boolean {
        if (!isCrossMidnight) {
            return clockMinute >= workStartMinutes && clockMinute < workEndMinutes
        }
        return clockMinute >= workStartMinutes || clockMinute < workEndMinutes
    }

    /** True when [clockMinute] is after the work window has ended for the day. */
    fun isAfterWork(clockMinute: Int): Boolean {
        if (!isCrossMidnight) {
            return clockMinute >= workEndMinutes
        }
        return clockMinute >= workEndMinutes && clockMinute < workStartMinutes
    }

    /** The break containing [minute], if any. */
    fun breakContaining(minute: Int): BreakSchedule? =
        sortedBreaks.firstOrNull { minute >= it.startMinutes && minute < it.endMinutes }

    /**
     * Total break seconds that have elapsed before the given clock second,
     * comparing in elapsed-since-start space so the cross-midnight wrap is safe.
     */
    fun elapsedBreakSeconds(beforeClockSecond: Double): Double {
        val beforeMinute = (beforeClockSecond / 60.0).toInt()
        val beforeElapsed = elapsedSinceStart(beforeMinute)
        return sortedBreaks
            .filter { elapsedSinceStart(it.endMinutes) <= beforeElapsed }
            .sumOf { it.durationMinutes * 60.0 }
    }
}

/** A user-editable break period (stored as clock hour/minute, not minutes). */
data class BreakSegment(
    val id: String,
    val startHour: Int,
    val startMinute: Int,
    val endHour: Int,
    val endMinute: Int,
) {
    val startMinutes: Int get() = startHour * 60 + startMinute
    val endMinutes: Int get() = endHour * 60 + endMinute
    val durationMinutes: Int get() = endMinutes - startMinutes

    val asBreakSchedule: BreakSchedule get() = BreakSchedule(startMinutes, endMinutes)

    val isValid: Boolean get() = endMinutes > startMinutes

    /**
     * Whether this break fits entirely inside the work window. When
     * `workEnd <= workStart` (cross-midnight) it must fit in either the
     * `[workStart, 1440)` or the `[0, workEnd]` segment.
     */
    fun fitsWithin(workStart: Int, workEnd: Int): Boolean {
        if (workEnd > workStart) {
            return startMinutes >= workStart && endMinutes <= workEnd
        }
        return (startMinutes >= workStart && endMinutes <= 1440) ||
            (startMinutes >= 0 && endMinutes <= workEnd)
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "startHour" to startHour,
        "startMinute" to startMinute,
        "endHour" to endHour,
        "endMinute" to endMinute,
    )

    companion object {
        fun create(
            startHour: Int,
            startMinute: Int,
            endHour: Int,
            endMinute: Int,
            id: String = newId(),
        ): BreakSegment = BreakSegment(id, startHour, startMinute, endHour, endMinute)

        fun newId(): String = Random.nextLong().toString()

        fun fromMap(map: Map<String, Any?>): BreakSegment {
            // Accept either hour/minute fields or flat minutes (the platform
            // schedule model stores breaks as start/end minutes).
            if (map.containsKey("startMinutes") || map.containsKey("endMinutes")) {
                val start = map.intOr("startMinutes", 720)
                val end = map.intOr("endMinutes", 810)
                return BreakSegment(
                    id = map.stringOr("id", newId()),
                    startHour = start / 60,
                    startMinute = start % 60,
                    endHour = end / 60,
                    endMinute = end % 60,
                )
            }
            return BreakSegment(
                id = map.stringOr("id", newId()),
                startHour = map.intOr("startHour", 12),
                startMinute = map.intOr("startMinute", 0),
                endHour = map.intOr("endHour", 13),
                endMinute = map.intOr("endMinute", 30),
            )
        }
    }
}

// MARK: - Status & results

/** The current work status for a day. */
enum class WorkStatus(val wire: String) {
    NOT_STARTED("notStarted"),
    WORKING("working"),
    ON_BREAK("onBreak"),
    COMPLETED("completed"),
    OVERTIME("overtime"),
    VOLUNTARY_OVERTIME("voluntaryOvertime"),
    DAY_OFF("dayOff"),
    /** User-armed pause: nothing accrues, regardless of day type or calendar. */
    PAUSED("paused");

    companion object {
        fun fromWire(value: String?): WorkStatus =
            entries.firstOrNull { it.wire == value } ?: NOT_STARTED
    }
}

/** Result of a today's-earnings calculation. */
data class TodayEarnings(
    val amount: Double = 0.0,
    val progress: Double = 0.0,
    val status: WorkStatus = WorkStatus.NOT_STARTED,
    val elapsedSeconds: Double = 0.0,
    val totalWorkSeconds: Double = 0.0,
)

/** Month-level summary data. */
data class MonthSummary(
    val workingDaysThisMonth: Int = 0,
    val workingDaysElapsed: Int = 0,
    val monthProgress: Double = 0.0,
    val monthEarnings: Double = 0.0,
    val totalMonthEarnings: Double = 0.0,
    val daysUntilPayday: Int = 0,
    val isPayday: Boolean = false,
    val paydayCycleProgress: Double = 0.0,
    val paydayCycleTotal: Int = 0,
    val paydayCycleElapsed: Int = 0,
)

// MARK: - Day overrides & holiday calendar

/** The kind of a calendar day. */
enum class DayType(val wire: String) {
    NORMAL("normal"),
    HOLIDAY("holiday"),
    OVERTIME("overtime");

    companion object {
        fun fromWire(value: String?): DayType =
            entries.firstOrNull { it.wire == value } ?: NORMAL
    }
}

/**
 * How a date should be displayed in a calendar grid — the resolved outcome of
 * the day-off precedence (user override > holiday calendar > weekend).
 * Platform calendar UIs render this; they never re-derive it.
 */
enum class DayKind(val wire: String) {
    NORMAL("normal"),
    WEEKEND("weekend"),
    PUBLIC_HOLIDAY("publicHoliday"),
    ADJUSTED_WORKDAY("adjustedWorkday"),
    USER_HOLIDAY("userHoliday"),
    USER_OVERTIME("userOvertime");
}

/** A user's custom designation for a specific date. */
data class DayOverride(
    val dateString: String,
    val dayType: DayType,
    val overtimeMultiplier: Double = 2.0,
    val customWorkHours: Double? = null,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "dateString" to dateString,
        "dayType" to dayType.wire,
        "overtimeMultiplier" to overtimeMultiplier,
        "customWorkHours" to customWorkHours,
    )

    companion object {
        fun fromMap(map: Map<String, Any?>): DayOverride = DayOverride(
            dateString = map.stringOr("dateString", ""),
            dayType = DayType.fromWire(map.strOrNull("dayType")),
            overtimeMultiplier = map.doubleOr("overtimeMultiplier", 2.0),
            customWorkHours = (map["customWorkHours"] as? Double),
        )
    }
}

/**
 * One year's public-holiday and adjusted-workday schedule, keyed by "MM-DD".
 */
data class HolidayCalendar(
    val year: Int,
    val holidays: Set<String>,
    val adjustedWorkdays: Set<String>,
) {
    fun isHoliday(month: Int, day: Int): Boolean = holidays.contains(key(month, day))

    fun isAdjustedWorkday(month: Int, day: Int): Boolean = adjustedWorkdays.contains(key(month, day))

    private fun key(month: Int, day: Int): String = "${month.pad2()}-${day.pad2()}"
}
