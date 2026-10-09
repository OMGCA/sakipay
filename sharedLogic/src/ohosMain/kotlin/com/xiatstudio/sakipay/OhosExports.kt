/* (c) Copyright XiatStudio 2026~2026 */
// @CName is annotated @ExperimentalNativeApi, so every export in this file needs
// an explicit opt-in. The ohos source set is only compiled for the OHOS targets,
// where that experimental API is available.
@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package com.xiatstudio.sakipay

/**
 * C-ABI surface consumed by the HarmonyOS app.
 *
 * Kotlin/Native exports each top-level function annotated with @CName into the
 * generated header (`libsakipay_api.h`) and the shared library
 * (`libsakipay.so`). The HAP's NAPI module (`napi_init.cpp`) links that library
 * and re-exports these symbols to ArkTS.
 *
 * @CName is in `kotlin.native`, which is a default import on Native targets.
 *
 * Only primitives and strings cross the boundary, so the earning/summary calls
 * take and return JSON. Argument conventions match [SakipayCore]: `nowMillis`
 * is Unix epoch milliseconds, `tzOffsetMinutes` is minutes east of UTC.
 */

// --- Configuration -----------------------------------------------------------

@CName("sakipayDefaultConfigJson")
fun sakipayDefaultConfigJson(): String = SakipayCore.defaultConfigJson()

@CName("sakipayDefaultBreakJson")
fun sakipayDefaultBreakJson(): String = SakipayCore.defaultBreakJson()

@CName("sakipayNormalizeConfig")
fun sakipayNormalizeConfig(configJson: String): String = SakipayCore.normalizeConfig(configJson)

@CName("sakipayComposeConfigJson")
fun sakipayComposeConfigJson(
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
): String = SakipayCore.composeConfigJson(
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
)

@CName("sakipayConfigBreaksJson")
fun sakipayConfigBreaksJson(configJson: String): String = SakipayCore.configBreaksJson(configJson)

@CName("sakipayConfigDayOverridesJson")
fun sakipayConfigDayOverridesJson(configJson: String): String =
    SakipayCore.configDayOverridesJson(configJson)

// --- Earnings ----------------------------------------------------------------

@CName("sakipayTodayEarningsJson")
fun sakipayTodayEarningsJson(
    configJson: String,
    nowMillis: Long,
    tzOffsetMinutes: Int,
    voluntaryOvertimeTotalSeconds: Double,
    isPaused: Boolean,
): String = SakipayCore.todayEarningsJson(
    configJson = configJson,
    nowMillis = nowMillis,
    tzOffsetMinutes = tzOffsetMinutes,
    voluntaryOvertimeTotalSeconds = voluntaryOvertimeTotalSeconds,
    isPaused = isPaused,
)

@CName("sakipayMonthSummaryJson")
fun sakipayMonthSummaryJson(
    configJson: String,
    nowMillis: Long,
    tzOffsetMinutes: Int,
    isPaused: Boolean,
): String = SakipayCore.monthSummaryJson(
    configJson = configJson,
    nowMillis = nowMillis,
    tzOffsetMinutes = tzOffsetMinutes,
    isPaused = isPaused,
)

// --- Calendar / breaks -------------------------------------------------------

@CName("sakipayCalibratedWorkingDays")
fun sakipayCalibratedWorkingDays(configJson: String, year: Int, month: Int): Int =
    SakipayCore.calibratedWorkingDays(configJson, year, month)

@CName("sakipayCalibratedWorkingDaysNow")
fun sakipayCalibratedWorkingDaysNow(configJson: String, nowMillis: Long, tzOffsetMinutes: Int): Int =
    SakipayCore.calibratedWorkingDaysNow(configJson, nowMillis, tzOffsetMinutes)

@CName("sakipayHolidayDataJson")
fun sakipayHolidayDataJson(year: Int): String = SakipayCore.holidayDataJson(year)

@CName("sakipayResolveDayKind")
fun sakipayResolveDayKind(year: Int, month: Int, day: Int, dayOverridesJson: String): String =
    SakipayCore.resolveDayKind(year, month, day, dayOverridesJson)

@CName("sakipayWorkWindowMinutes")
fun sakipayWorkWindowMinutes(workStartMinutes: Int, workEndMinutes: Int): Int =
    SakipayCore.workWindowMinutes(workStartMinutes, workEndMinutes)

@CName("sakipayWorkScheduleTotalHours")
fun sakipayWorkScheduleTotalHours(
    workStartMinutes: Int,
    workEndMinutes: Int,
    breaksJson: String,
): Double = SakipayCore.workScheduleTotalHours(workStartMinutes, workEndMinutes, breaksJson)

@CName("sakipaySecondRate")
fun sakipaySecondRate(configJson: String, nowMillis: Long, tzOffsetMinutes: Int): Double =
    SakipayCore.secondRate(configJson, nowMillis, tzOffsetMinutes)

@CName("sakipayPruneBreaksJson")
fun sakipayPruneBreaksJson(configJson: String): String = SakipayCore.pruneBreaksJson(configJson)

@CName("sakipayAddBreakJson")
fun sakipayAddBreakJson(configJson: String): String = SakipayCore.addBreakJson(configJson)

@CName("sakipayAddBreakToBreaks")
fun sakipayAddBreakToBreaks(workStartMinutes: Int, workEndMinutes: Int, breaksJson: String): String =
    SakipayCore.addBreakToBreaks(workStartMinutes, workEndMinutes, breaksJson)

// --- Voluntary overtime ------------------------------------------------------

@CName("sakipayOtTotalSecondsJson")
fun sakipayOtTotalSecondsJson(
    stateJson: String,
    nowMillis: Long,
    tzOffsetMinutes: Int,
    mutatesState: Boolean,
): String = SakipayCore.otTotalSecondsJson(stateJson, nowMillis, tzOffsetMinutes, mutatesState)

@CName("sakipayOtStartJson")
fun sakipayOtStartJson(stateJson: String, nowMillis: Long, tzOffsetMinutes: Int): String =
    SakipayCore.otStartJson(stateJson, nowMillis, tzOffsetMinutes)

@CName("sakipayOtEndJson")
fun sakipayOtEndJson(
    stateJson: String,
    nowMillis: Long,
    tzOffsetMinutes: Int,
    secondRate: Double,
): String = SakipayCore.otEndJson(stateJson, nowMillis, tzOffsetMinutes, secondRate)

@CName("sakipayOtBankDailyJson")
fun sakipayOtBankDailyJson(
    stateJson: String,
    nowMillis: Long,
    tzOffsetMinutes: Int,
    secondRate: Double,
): String = SakipayCore.otBankDailyJson(stateJson, nowMillis, tzOffsetMinutes, secondRate)

// --- Presentation helpers ----------------------------------------------------

@CName("sakipayStatusText")
fun sakipayStatusText(statusWire: String): String = SakipayCore.statusText(statusWire)

@CName("sakipayPaydayText")
fun sakipayPaydayText(daysUntilPayday: Int, isPayday: Boolean): String =
    SakipayCore.paydayText(daysUntilPayday, isPayday)
