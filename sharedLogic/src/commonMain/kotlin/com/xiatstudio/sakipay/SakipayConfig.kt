/* (c) Copyright XiatStudio 2026~2026 */
package com.xiatstudio.sakipay

/**
 * The complete user configuration. Platforms persist this (as [toJson]) and hand
 * it back to the shared logic for every calculation, so all business rules —
 * schedule maths, break pruning, work-day calibration — live here.
 */
data class SakipayConfig(
    val monthlyPay: Double = 0.0,
    val currency: String = "¥",
    val payDay: Int = 15,
    val taxRate: Double = 0.0,
    val workingDaysPerMonth: Double = 21.75,
    val workStartHour: Int = 9,
    val workStartMinute: Int = 0,
    val workEndHour: Int = 18,
    val workEndMinute: Int = 0,
    val breakSegments: List<BreakSegment> = emptyList(),
    val dayOverrides: List<DayOverride> = emptyList(),
    val useCalibratedWorkDays: Boolean = true,
) {
    val workStartMinutes: Int get() = workStartHour * 60 + workStartMinute
    val workEndMinutes: Int get() = workEndHour * 60 + workEndMinute

    val workSchedule: WorkSchedule
        get() = WorkSchedule(
            workStartMinutes = workStartMinutes,
            workEndMinutes = workEndMinutes,
            breaks = breakSegments.filter { it.isValid }.map { it.asBreakSchedule },
        )

    /** Overrides keyed by their "YYYY-MM-DD" date string. */
    val dayOverrideMap: Map<String, DayOverride>
        get() = dayOverrides.associateBy { it.dateString }

    /** True once a salary has been entered. */
    val isConfigured: Boolean get() = monthlyPay > 0

    /**
     * Builds a calculator anchored to [date], pulling the matching holiday
     * calendar and calibrating the working-days divisor for that month.
     */
    fun calculatorFor(date: CivilDate): EarningsCalculator = EarningsCalculator(
        monthlyPay = monthlyPay,
        workingDaysPerMonth = effectiveWorkingDays(date.year, date.month),
        schedule = workSchedule,
        payDay = payDay,
        taxRate = taxRate,
        holidayCalendar = HolidayCalendarService.forYear(date.year),
        dayOverrides = dayOverrideMap,
    )

    /** Breaks that are valid and fit entirely inside the work window. */
    fun validBreaks(): List<BreakSegment> =
        breakSegments.filter { it.isValid && it.fitsWithin(workStartMinutes, workEndMinutes) }

    /**
     * @return this config with out-of-range breaks removed, plus the number that
     *   were removed (0 when nothing changed).
     */
    fun withPrunedBreaks(): Pair<SakipayConfig, Int> {
        val kept = validBreaks()
        val removed = breakSegments.size - kept.size
        return (if (removed == 0) this else copy(breakSegments = kept)) to removed
    }

    /**
     * Calibrated working days for the given month, accounting for the holiday
     * calendar and day overrides.
     */
    fun calibratedWorkingDays(year: Int, month: Int): Int {
        val calc = EarningsCalculator(
            monthlyPay = 0.0,
            workingDaysPerMonth = workingDaysPerMonth,
            schedule = workSchedule,
            payDay = payDay,
            taxRate = taxRate,
            holidayCalendar = HolidayCalendarService.forYear(year),
            dayOverrides = dayOverrideMap,
        )
        return calc.countWorkingDaysInMonth(year, month)
    }

    /** Working days per month to use for the given month (calibrated or fixed). */
    fun effectiveWorkingDays(year: Int, month: Int): Double =
        if (useCalibratedWorkDays) calibratedWorkingDays(year, month).toDouble() else workingDaysPerMonth

    // --- Serialisation --------------------------------------------------------

    fun toJson(): String = MiniJson.obj(
        "monthlyPay" to monthlyPay,
        "currency" to currency,
        "payDay" to payDay,
        "taxRate" to taxRate,
        "workingDaysPerMonth" to workingDaysPerMonth,
        "workStartHour" to workStartHour,
        "workStartMinute" to workStartMinute,
        "workEndHour" to workEndHour,
        "workEndMinute" to workEndMinute,
        "useCalibratedWorkDays" to useCalibratedWorkDays,
        "breaks" to MiniJson.arr(breakSegments.map { it.toMap() }),
        "dayOverrides" to MiniJson.arr(dayOverrides.map { it.toMap() }),
    )

    companion object {
        /** The first-launch default (no salary yet). */
        val DEFAULT = SakipayConfig()

        /** The break applied the first time the user opens settings. */
        fun defaultBreak(): BreakSegment = BreakSegment.create(12, 0, 13, 30)

        /**
         * Builds a config from the platform's separately-stored fields. [breaksJson]
         * and [dayOverridesJson] are JSON arrays (as the platforms store them).
         * This is the single place the platform shape is turned into a config, so
         * defaults and normalisation live in one place.
         */
        fun fromParts(
            monthlyPay: Double,
            currency: String,
            payDay: Int,
            taxRate: Double,
            workingDaysPerMonth: Double,
            workStartHour: Int,
            workStartMinute: Int,
            workEndHour: Int,
            workEndMinute: Int,
            breaksJson: String,
            dayOverridesJson: String,
            useCalibratedWorkDays: Boolean,
        ): SakipayConfig = SakipayConfig(
            monthlyPay = monthlyPay,
            currency = currency,
            payDay = payDay,
            taxRate = taxRate,
            workingDaysPerMonth = workingDaysPerMonth,
            workStartHour = workStartHour,
            workStartMinute = workStartMinute,
            workEndHour = workEndHour,
            workEndMinute = workEndMinute,
            breakSegments = decodeList(breaksJson).mapNotNull { it.asMapOrNull() }.map { BreakSegment.fromMap(it) },
            dayOverrides = decodeList(dayOverridesJson).mapNotNull { it.asMapOrNull() }.map { DayOverride.fromMap(it) },
            useCalibratedWorkDays = useCalibratedWorkDays,
        )

        fun fromJson(json: String): SakipayConfig {
            val map = try {
                MiniJson.parse(json).asMapOrNull()
            } catch (e: IllegalArgumentException) {
                null
            } ?: return DEFAULT
            return fromMap(map)
        }

        fun fromMap(map: Map<String, Any?>): SakipayConfig {
            val breaks = decodeList(map["breaks"]).mapNotNull { it.asMapOrNull() }.map { BreakSegment.fromMap(it) }
            val overrides = decodeList(map["dayOverrides"]).mapNotNull { it.asMapOrNull() }.map { DayOverride.fromMap(it) }
            return SakipayConfig(
                monthlyPay = map.doubleOr("monthlyPay", 0.0),
                currency = map.stringOr("currency", "¥"),
                payDay = map.intOr("payDay", 15),
                taxRate = map.doubleOr("taxRate", 0.0),
                workingDaysPerMonth = map.doubleOr("workingDaysPerMonth", 21.75),
                workStartHour = map.intOr("workStartHour", 9),
                workStartMinute = map.intOr("workStartMinute", 0),
                workEndHour = map.intOr("workEndHour", 18),
                workEndMinute = map.intOr("workEndMinute", 0),
                breakSegments = breaks,
                dayOverrides = overrides,
                useCalibratedWorkDays = map.boolOr("useCalibratedWorkDays", true),
            )
        }
    }
}

/**
 * Accepts a JSON list either as an already-decoded list or as a JSON-encoded
 * string (how the platforms store breaks/overrides), returning an empty list
 * for anything else.
 */
internal fun decodeList(value: Any?): List<Any?> = when (value) {
    null -> emptyList()
    is List<*> -> value
    is String -> {
        if (value.isBlank()) {
            emptyList()
        } else {
            try {
                MiniJson.parse(value).asListOrNull() ?: emptyList()
            } catch (e: IllegalArgumentException) {
                emptyList()
            }
        }
    }
    else -> emptyList()
}
