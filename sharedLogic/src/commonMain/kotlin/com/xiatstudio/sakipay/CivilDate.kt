/* (c) Copyright XiatStudio 2026~2026 */
package com.xiatstudio.sakipay

/**
 * Minimal, dependency-free proleptic-Gregorian calendar maths.
 *
 * The shared logic must behave identically on iOS (Foundation `Calendar`) and
 * HarmonyOS (JS `Date`), so instead of pulling in a date library we convert the
 * platform's absolute time into a plain civil date/time using the algorithms
 * from Howard Hinnant's `chrono` compatibility layer (public domain). The
 * platform supplies epoch milliseconds plus its UTC offset in minutes.
 */

/** A calendar date with no time component. */
data class CivilDate(val year: Int, val month: Int, val day: Int) : Comparable<CivilDate> {

    /** Days since 1970-01-01 (may be negative for earlier dates). */
    fun toEpochDays(): Long = daysFromCivil(year, month, day)

    fun plusDays(n: Int): CivilDate {
        val (y, m, d) = civilFromDays(toEpochDays() + n)
        return CivilDate(y, m, d)
    }

    /**
     * Adds [n] months, clamping the day to the last valid day of the target
     * month (e.g. Jan 31 + 1 month -> Feb 28/29).
     */
    fun plusMonthsClamped(n: Int): CivilDate {
        val total = year * 12 + (month - 1) + n
        val newYear = floorDiv(total.toLong(), 12L).toInt()
        val newMonth = total - newYear * 12 + 1
        val newDay = minOf(day, daysInMonth(newYear, newMonth))
        return CivilDate(newYear, newMonth, newDay)
    }

    /** "YYYY-MM-DD". */
    val isoString: String
        get() = "${year.toString().padStart(4, '0')}-${month.pad2()}-${day.pad2()}"

    /** 0 = Sunday .. 6 = Saturday (matches JS `Date.getDay()`). */
    val dayOfWeek: Int
        get() = dayOfWeekFromEpochDays(toEpochDays())

    override fun compareTo(other: CivilDate): Int {
        val a = toEpochDays()
        val b = other.toEpochDays()
        return when {
            a < b -> -1
            a > b -> 1
            else -> 0
        }
    }
}

/** A civil date and time-of-day. */
data class CivilDateTime(
    val year: Int,
    val month: Int,
    val day: Int,
    val hour: Int,
    val minute: Int,
    val second: Int,
) {
    val date: CivilDate get() = CivilDate(year, month, day)

    /** Minutes since local midnight. */
    val minuteOfDay: Int get() = hour * 60 + minute

    /** Seconds since local midnight. */
    val secondOfDay: Double get() = (hour * 3600 + minute * 60 + second).toDouble()

    /** 0 = Sunday .. 6 = Saturday (matches JS `Date.getDay()`). */
    val dayOfWeek: Int get() = date.dayOfWeek

    /** "YYYY-MM-DD". */
    val isoDateString: String get() = date.isoString
}

fun daysInMonth(year: Int, month: Int): Int = when (month) {
    1, 3, 5, 7, 8, 10, 12 -> 31
    4, 6, 9, 11 -> 30
    2 -> if (isLeapYear(year)) 29 else 28
    else -> 30
}

fun isLeapYear(year: Int): Boolean = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0

/**
 * Converts absolute epoch milliseconds and a UTC offset (minutes east of UTC,
 * e.g. +480 for UTC+8) into a local civil date-time.
 */
fun civilDateTimeFromEpochMillis(epochMillis: Long, tzOffsetMinutes: Int): CivilDateTime {
    val localMillis = epochMillis + tzOffsetMinutes.toLong() * 60_000L
    val days = floorDiv(localMillis, 86_400_000L)
    val msOfDay = localMillis - days * 86_400_000L
    val secondsOfDay = (msOfDay / 1000L).toInt()
    val (y, m, d) = civilFromDays(days)
    return CivilDateTime(
        year = y,
        month = m,
        day = d,
        hour = secondsOfDay / 3600,
        minute = (secondsOfDay % 3600) / 60,
        second = secondsOfDay % 60,
    )
}

// --- Hinnant civil algorithms -------------------------------------------------

/** Days since 1970-01-01 for a civil date. */
internal fun daysFromCivil(y: Int, m: Int, d: Int): Long {
    val yy = if (m <= 2) y - 1 else y
    val era = floorDiv(yy.toLong(), 400L)
    val yoe = (yy - era * 400).toInt()          // [0, 399]
    val doy = (153 * (if (m > 2) m - 3 else m + 9) + 2) / 5 + d - 1 // [0, 365]
    val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy                 // [0, 146096]
    return era * 146_097L + doe - 719_468L
}

/** Inverse of [daysFromCivil]. */
internal fun civilFromDays(epochDays: Long): Triple<Int, Int, Int> {
    val z = epochDays + 719_468L
    val era = floorDiv(z, 146_097L)
    val doe = z - era * 146_097L                                   // [0, 146096]
    val yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365 // [0, 399]
    val y = yoe + era * 400
    val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)               // [0, 365]
    val mp = (5 * doy + 2) / 153                                    // [0, 11]
    val d = doy - (153 * mp + 2) / 5 + 1                            // [1, 31]
    val m = if (mp < 10) mp + 3 else mp - 9
    return Triple((if (m <= 2) y + 1 else y).toInt(), m.toInt(), d.toInt())
}

/** 1970-01-01 was a Thursday, so shift by 4 to land on JS's Sunday=0 convention. */
internal fun dayOfWeekFromEpochDays(epochDays: Long): Int {
    val v = (epochDays + 4L) % 7L
    return ((v + 7L) % 7L).toInt()
}

internal fun floorDiv(a: Long, b: Long): Long {
    var q = a / b
    if ((a % b != 0L) && ((a < 0) != (b < 0))) {
        q -= 1
    }
    return q
}

internal fun Int.pad2(): String = if (this < 10) "0$this" else this.toString()
