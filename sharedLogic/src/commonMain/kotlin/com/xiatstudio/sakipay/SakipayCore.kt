/* (c) Copyright XiatStudio 2026~2026 */
package com.xiatstudio.sakipay

/**
 * Boundary-friendly facade over the shared logic.
 *
 * Everything here speaks JSON strings and primitives so a single implementation
 * serves both iOS (via direct Swift interop) and HarmonyOS (via the NAPI bridge,
 * where only strings/numbers can cross). Arguments named `...Json` are JSON
 * documents; `nowMillis` is Unix epoch milliseconds and `tzOffsetMinutes` is the
 * offset east of UTC (e.g. +480 for UTC+8).
 */
object SakipayCore {

    // --- Configuration --------------------------------------------------------

    /** JSON of the first-launch default configuration. */
    fun defaultConfigJson(): String = SakipayConfig.DEFAULT.toJson()

    /** JSON of the default break segment applied on first launch. */
    fun defaultBreakJson(): String = MiniJson.write(SakipayConfig.defaultBreak().toMap())

    /**
     * Builds a canonical config document from the platform's separately-stored
     * fields. [breaksJson]/[dayOverridesJson] are the JSON arrays the platform
     * persists. This is the one place the platform shape becomes a config, so
     * defaulting and normalisation live in the shared code.
     */
    fun composeConfigJson(
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
    ): String = SakipayConfig.fromParts(
        monthlyPay = monthlyPay,
        currency = currency,
        payDay = payDay,
        taxRate = taxRate,
        workingDaysPerMonth = workingDaysPerMonth,
        workStartHour = workStartHour,
        workStartMinute = workStartMinute,
        workEndHour = workEndHour,
        workEndMinute = workEndMinute,
        breaksJson = breaksJson,
        dayOverridesJson = dayOverridesJson,
        useCalibratedWorkDays = useCalibratedWorkDays,
    ).toJson()

    /** The breaks array (JSON string) from a config document. */
    fun configBreaksJson(configJson: String): String =
        MiniJson.arr(SakipayConfig.fromJson(configJson).breakSegments.map { it.toMap() })

    /** The day-overrides array (JSON string) from a config document. */
    fun configDayOverridesJson(configJson: String): String =
        MiniJson.arr(SakipayConfig.fromJson(configJson).dayOverrides.map { it.toMap() })

    /** Normalises a config document (unknown fields dropped, defaults filled). */
    fun normalizeConfig(configJson: String): String = SakipayConfig.fromJson(configJson).toJson()

    // --- Earnings -------------------------------------------------------------

    fun todayEarningsJson(
        configJson: String,
        nowMillis: Long,
        tzOffsetMinutes: Int,
        voluntaryOvertimeTotalSeconds: Double,
        isPaused: Boolean,
    ): String {
        val now = civilDateTimeFromEpochMillis(nowMillis, tzOffsetMinutes)
        val config = SakipayConfig.fromJson(configJson)
        val result = config.calculatorFor(now.date)
            .calculateTodayEarnings(now, voluntaryOvertimeTotalSeconds, isPaused)
        return MiniJson.obj(
            "amount" to result.amount,
            "progress" to result.progress,
            "status" to result.status.wire,
            "elapsedSeconds" to result.elapsedSeconds,
            "totalWorkSeconds" to result.totalWorkSeconds,
        )
    }

    fun monthSummaryJson(
        configJson: String,
        nowMillis: Long,
        tzOffsetMinutes: Int,
        isPaused: Boolean,
    ): String {
        val now = civilDateTimeFromEpochMillis(nowMillis, tzOffsetMinutes)
        val config = SakipayConfig.fromJson(configJson)
        val s = config.calculatorFor(now.date).calculateMonthSummary(now, isPaused)
        return MiniJson.obj(
            "workingDaysThisMonth" to s.workingDaysThisMonth,
            "workingDaysElapsed" to s.workingDaysElapsed,
            "monthProgress" to s.monthProgress,
            "monthEarnings" to s.monthEarnings,
            "totalMonthEarnings" to s.totalMonthEarnings,
            "daysUntilPayday" to s.daysUntilPayday,
            "isPayday" to s.isPayday,
            "paydayCycleProgress" to s.paydayCycleProgress,
            "paydayCycleTotal" to s.paydayCycleTotal,
            "paydayCycleElapsed" to s.paydayCycleElapsed,
        )
    }

    // --- Calendar / breaks ----------------------------------------------------

    /** Calibrated working days in the given month (holiday cal + overrides). */
    fun calibratedWorkingDays(configJson: String, year: Int, month: Int): Int =
        SakipayConfig.fromJson(configJson).calibratedWorkingDays(year, month)

    /** Holiday data for [year] as JSON (see [HolidayCalendarService.dataJson]). */
    fun holidayDataJson(year: Int): String = HolidayCalendarService.dataJson(year)

    /**
     * Resolves a calendar day for display: `"normal"`, `"weekend"`,
     * `"publicHoliday"`, `"adjustedWorkday"`, `"userHoliday"` or `"userOvertime"`.
     * [dayOverridesJson] is the platform's array of day overrides (may be empty).
     */
    fun resolveDayKind(year: Int, month: Int, day: Int, dayOverridesJson: String): String {
        val overrides = decodeList(dayOverridesJson)
            .mapNotNull { it.asMapOrNull() }
            .map { DayOverride.fromMap(it) }
            .associateBy { it.dateString }
        val calculator = EarningsCalculator(
            monthlyPay = 0.0,
            workingDaysPerMonth = 21.75,
            schedule = WorkSchedule(workStartMinutes = 540, workEndMinutes = 1080, breaks = emptyList()),
            payDay = 15,
            holidayCalendar = HolidayCalendarService.forYear(year),
            dayOverrides = overrides,
        )
        return calculator.resolveDayKind(CivilDate(year, month, day)).wire
    }

    /** Raw clock minutes in a work window, cross-midnight aware (breaks not subtracted). */
    fun workWindowMinutes(workStartMinutes: Int, workEndMinutes: Int): Int =
        WorkSchedule(workStartMinutes, workEndMinutes, emptyList()).workWindowMinutes

    /** The base per-second rate (used for voluntary-OT settlement). */
    fun secondRate(configJson: String, nowMillis: Long, tzOffsetMinutes: Int): Double {
        val date = civilDateTimeFromEpochMillis(nowMillis, tzOffsetMinutes).date
        return SakipayConfig.fromJson(configJson).calculatorFor(date).secondRate
    }

    /**
     * Paid hours in a work window after subtracting its breaks. Used by platform
     * UIs that show "hours per day" while the user edits the schedule.
     */
    fun workScheduleTotalHours(
        workStartMinutes: Int,
        workEndMinutes: Int,
        breaksJson: String,
    ): Double {
        val breaks = decodeList(breaksJson)
            .mapNotNull { it.asMapOrNull() }
            .map { BreakSegment.fromMap(it) }
            .filter { it.isValid }
            .map { it.asBreakSchedule }
        return WorkSchedule(workStartMinutes, workEndMinutes, breaks).totalWorkHours
    }

    /** Whether a break fits entirely inside the work window (cross-midnight aware). */
    fun breakFits(
        breakStartMinutes: Int,
        breakEndMinutes: Int,
        workStartMinutes: Int,
        workEndMinutes: Int,
    ): Boolean = BreakSegment(
        id = "",
        startHour = breakStartMinutes / 60,
        startMinute = breakStartMinutes % 60,
        endHour = breakEndMinutes / 60,
        endMinute = breakEndMinutes % 60,
    ).fitsWithin(workStartMinutes, workEndMinutes)

    /** Same, computed from a moment's local month. */
    fun calibratedWorkingDaysNow(configJson: String, nowMillis: Long, tzOffsetMinutes: Int): Int {
        val date = civilDateTimeFromEpochMillis(nowMillis, tzOffsetMinutes).date
        return calibratedWorkingDays(configJson, date.year, date.month)
    }

    /** Removes out-of-range breaks. Returns `{"config": "...", "removed": n}`. */
    fun pruneBreaksJson(configJson: String): String {
        val (pruned, removed) = SakipayConfig.fromJson(configJson).withPrunedBreaks()
        return MiniJson.obj("config" to pruned.toJson(), "removed" to removed)
    }

    /**
     * Appends a one-hour break after the last one, clamped inside the work
     * window. No break is added (config unchanged) when the window is shorter
     * than two hours. Returns the new config JSON.
     */
    fun addBreakJson(configJson: String): String {
        val config = SakipayConfig.fromJson(configJson)
        val placed = placeBreak(config.workStartMinutes, config.workEndMinutes, config.breakSegments)
            ?: return config.toJson()
        return config.copy(breakSegments = config.breakSegments + placed).toJson()
    }

    /**
     * Appends a break to a breaks array (JSON) using the same placement rule,
     * without needing a full config document. Returns the updated breaks array;
     * unchanged when the work window is shorter than two hours.
     */
    fun addBreakToBreaks(workStartMinutes: Int, workEndMinutes: Int, breaksJson: String): String {
        val breaks = decodeList(breaksJson).mapNotNull { it.asMapOrNull() }.map { BreakSegment.fromMap(it) }
        val placed = placeBreak(workStartMinutes, workEndMinutes, breaks)
        val result = if (placed == null) breaks else breaks + placed
        return MiniJson.arr(result.map { it.toMap() })
    }

    /** The shared break-placement rule; null when the work window is under two hours. */
    private fun placeBreak(
        workStartMinutes: Int,
        workEndMinutes: Int,
        breaks: List<BreakSegment>,
    ): BreakSegment? {
        val ws = workStartMinutes
        val we = workEndMinutes
        val duration = if (we > ws) we - ws else (1440 - ws) + we
        if (duration < 120) return null

        val isCross = we <= ws
        var newStart = (breaks.lastOrNull()?.endMinutes ?: ws) + 60
        if (isCross && newStart >= 1440) newStart -= 1440
        val maxStart = if (isCross) 1440 else we
        newStart = minOf(newStart, maxStart - 60)
        var newEnd = newStart + 60
        if (isCross && newEnd > 1440) newEnd -= 1440
        newEnd = minOf(newEnd, if (isCross) 1440 else we)

        return BreakSegment.create(
            startHour = newStart / 60,
            startMinute = (newStart % 60) / 5 * 5,
            endHour = newEnd / 60,
            endMinute = (newEnd % 60) / 5 * 5,
        )
    }

    // --- Voluntary overtime ---------------------------------------------------

    /** `{"state": "...", "seconds": n}` after evaluating the live total. */
    fun otTotalSecondsJson(
        stateJson: String,
        nowMillis: Long,
        tzOffsetMinutes: Int,
        mutatesState: Boolean,
    ): String {
        val now = civilDateTimeFromEpochMillis(nowMillis, tzOffsetMinutes)
        val state = VoluntaryOvertimeState.fromJson(stateJson)
        val (newState, seconds) = state.totalSeconds(
            nowEpochSeconds = nowMillis / 1000.0,
            todayString = now.isoDateString,
            mutatesState = mutatesState,
        )
        return MiniJson.obj("state" to newState.toJson(), "seconds" to seconds)
    }

    fun otStartJson(stateJson: String, nowMillis: Long, tzOffsetMinutes: Int): String {
        val now = civilDateTimeFromEpochMillis(nowMillis, tzOffsetMinutes)
        return VoluntaryOvertimeState.fromJson(stateJson)
            .withStartedSession(nowMillis / 1000.0, now.isoDateString)
            .toJson()
    }

    fun otEndJson(
        stateJson: String,
        nowMillis: Long,
        tzOffsetMinutes: Int,
        secondRate: Double,
    ): String {
        val now = civilDateTimeFromEpochMillis(nowMillis, tzOffsetMinutes)
        return VoluntaryOvertimeState.fromJson(stateJson)
            .withEndedSession(
                nowEpochSeconds = nowMillis / 1000.0,
                todayString = now.isoDateString,
                secondRate = secondRate,
                mondayString = VoluntaryOvertimeState.mondayOfWeek(now.date),
            )
            .toJson()
    }

    fun otBankDailyJson(
        stateJson: String,
        nowMillis: Long,
        tzOffsetMinutes: Int,
        secondRate: Double,
    ): String {
        val date = civilDateTimeFromEpochMillis(nowMillis, tzOffsetMinutes).date
        return VoluntaryOvertimeState.fromJson(stateJson)
            .withDailyBanked(secondRate, VoluntaryOvertimeState.mondayOfWeek(date))
            .toJson()
    }

    // --- Presentation helpers (shared user-facing strings) --------------------

    fun statusText(statusWire: String): String = when (WorkStatus.fromWire(statusWire)) {
        WorkStatus.NOT_STARTED -> "还没开始"
        WorkStatus.WORKING -> "窝囊费积累中"
        WorkStatus.ON_BREAK -> "休息中"
        WorkStatus.COMPLETED -> "下班啦！"
        WorkStatus.OVERTIME -> "加班攒钱中 💪"
        WorkStatus.VOLUNTARY_OVERTIME -> "自愿加班中 😤"
        WorkStatus.DAY_OFF -> "休息日"
        WorkStatus.PAUSED -> "已暂停"
    }

    fun paydayText(daysUntilPayday: Int, isPayday: Boolean): String = when {
        isPayday -> "今天发工资!"
        daysUntilPayday == 1 -> "明天发工资"
        else -> "还有 $daysUntilPayday 天发工资"
    }
}
