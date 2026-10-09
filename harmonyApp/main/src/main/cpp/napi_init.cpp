// NAPI bridge exposing the shared Kotlin logic (libsakipay.so) to ArkTS.
//
// Every exported function forwards straight to the Kotlin implementation so
// there is exactly one copy of the business logic. Strings cross the boundary
// as UTF-8 and structured results as JSON documents.

#include "napi/native_api.h"
#include <cstdint>
#include <string>

// --- libsakipay.so symbols (Kotlin/Native @CName exports) ---------------------
extern "C" {
const char* sakipayDefaultConfigJson();
const char* sakipayDefaultBreakJson();
const char* sakipayNormalizeConfig(const char* configJson);
const char* sakipayComposeConfigJson(
    double monthlyPay, const char* currency, int payDay, double taxRate,
    double workingDaysPerMonth, int workStartHour, int workStartMinute,
    int workEndHour, int workEndMinute, const char* breaksJson,
    const char* dayOverridesJson, bool useCalibratedWorkDays);
const char* sakipayConfigBreaksJson(const char* configJson);
const char* sakipayConfigDayOverridesJson(const char* configJson);
const char* sakipayTodayEarningsJson(
    const char* configJson, long long nowMillis, int tzOffsetMinutes,
    double voluntaryOvertimeTotalSeconds, bool isPaused);
const char* sakipayMonthSummaryJson(
    const char* configJson, long long nowMillis, int tzOffsetMinutes, bool isPaused);
int sakipayCalibratedWorkingDays(const char* configJson, int year, int month);
int sakipayCalibratedWorkingDaysNow(
    const char* configJson, long long nowMillis, int tzOffsetMinutes);
const char* sakipayHolidayDataJson(int year);
const char* sakipayResolveDayKind(int year, int month, int day, const char* dayOverridesJson);
int sakipayWorkWindowMinutes(int workStartMinutes, int workEndMinutes);
double sakipayWorkScheduleTotalHours(int workStartMinutes, int workEndMinutes, const char* breaksJson);
double sakipaySecondRate(const char* configJson, long long nowMillis, int tzOffsetMinutes);
const char* sakipayPruneBreaksJson(const char* configJson);
const char* sakipayAddBreakJson(const char* configJson);
const char* sakipayAddBreakToBreaks(int workStartMinutes, int workEndMinutes, const char* breaksJson);
const char* sakipayOtTotalSecondsJson(
    const char* stateJson, long long nowMillis, int tzOffsetMinutes, bool mutatesState);
const char* sakipayOtStartJson(const char* stateJson, long long nowMillis, int tzOffsetMinutes);
const char* sakipayOtEndJson(
    const char* stateJson, long long nowMillis, int tzOffsetMinutes, double secondRate);
const char* sakipayOtBankDailyJson(
    const char* stateJson, long long nowMillis, int tzOffsetMinutes, double secondRate);
const char* sakipayStatusText(const char* statusWire);
const char* sakipayPaydayText(int daysUntilPayday, bool isPayday);
}

// --- Helpers -----------------------------------------------------------------

static napi_value MakeString(napi_env env, const char* s) {
    napi_value out;
    napi_create_string_utf8(env, s != nullptr ? s : "", NAPI_AUTO_LENGTH, &out);
    return out;
}

static napi_value MakeInt(napi_env env, int value) {
    napi_value out;
    napi_create_int32(env, value, &out);
    return out;
}

static std::string ArgString(napi_env env, napi_value value) {
    size_t len = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    std::string s;
    s.resize(len + 1);
    napi_get_value_string_utf8(env, value, &s[0], len + 1, &len);
    s.resize(len);
    return s;
}

static double ArgDouble(napi_env env, napi_value value) {
    double d = 0;
    napi_get_value_double(env, value, &d);
    return d;
}

static int32_t ArgInt(napi_env env, napi_value value) {
    return static_cast<int32_t>(ArgDouble(env, value));
}

static int64_t ArgInt64(napi_env env, napi_value value) {
    // ArkTS numbers arrive as doubles; millisecond timestamps fit in 53 bits.
    return static_cast<int64_t>(ArgDouble(env, value));
}

static bool ArgBool(napi_env env, napi_value value) {
    bool b = false;
    napi_get_value_bool(env, value, &b);
    return b;
}

// Owns the argument array and fills it in one call.
static size_t ReadArgs(napi_env env, napi_callback_info info, napi_value* args, size_t maxArgs) {
    size_t argc = maxArgs;
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    return argc;
}

// --- Exported functions ------------------------------------------------------

static napi_value DefaultConfigJson(napi_env env, napi_callback_info) {
    return MakeString(env, sakipayDefaultConfigJson());
}

static napi_value DefaultBreakJson(napi_env env, napi_callback_info) {
    return MakeString(env, sakipayDefaultBreakJson());
}

static napi_value NormalizeConfig(napi_env env, napi_callback_info info) {
    napi_value args[1] = {nullptr};
    ReadArgs(env, info, args, 1);
    std::string json(ArgString(env, args[0]));
    return MakeString(env, sakipayNormalizeConfig(json.c_str()));
}

static napi_value ComposeConfigJson(napi_env env, napi_callback_info info) {
    napi_value args[12] = {nullptr};
    ReadArgs(env, info, args, 12);
    std::string currency(ArgString(env, args[1]));
    std::string breaksJson(ArgString(env, args[9]));
    std::string overridesJson(ArgString(env, args[10]));
    return MakeString(env, sakipayComposeConfigJson(
        ArgDouble(env, args[0]), currency.c_str(), ArgInt(env, args[2]), ArgDouble(env, args[3]),
        ArgDouble(env, args[4]), ArgInt(env, args[5]), ArgInt(env, args[6]),
        ArgInt(env, args[7]), ArgInt(env, args[8]), breaksJson.c_str(),
        overridesJson.c_str(), ArgBool(env, args[11])));
}

static napi_value ConfigBreaksJson(napi_env env, napi_callback_info info) {
    napi_value args[1] = {nullptr};
    ReadArgs(env, info, args, 1);
    std::string json(ArgString(env, args[0]));
    return MakeString(env, sakipayConfigBreaksJson(json.c_str()));
}

static napi_value ConfigDayOverridesJson(napi_env env, napi_callback_info info) {
    napi_value args[1] = {nullptr};
    ReadArgs(env, info, args, 1);
    std::string json(ArgString(env, args[0]));
    return MakeString(env, sakipayConfigDayOverridesJson(json.c_str()));
}

static napi_value TodayEarningsJson(napi_env env, napi_callback_info info) {
    napi_value args[5] = {nullptr};
    ReadArgs(env, info, args, 5);
    std::string configJson(ArgString(env, args[0]));
    return MakeString(env, sakipayTodayEarningsJson(
        configJson.c_str(), ArgInt64(env, args[1]), ArgInt(env, args[2]),
        ArgDouble(env, args[3]), ArgBool(env, args[4])));
}

static napi_value MonthSummaryJson(napi_env env, napi_callback_info info) {
    napi_value args[4] = {nullptr};
    ReadArgs(env, info, args, 4);
    std::string configJson(ArgString(env, args[0]));
    return MakeString(env, sakipayMonthSummaryJson(
        configJson.c_str(), ArgInt64(env, args[1]), ArgInt(env, args[2]), ArgBool(env, args[3])));
}

static napi_value CalibratedWorkingDays(napi_env env, napi_callback_info info) {
    napi_value args[3] = {nullptr};
    ReadArgs(env, info, args, 3);
    std::string configJson(ArgString(env, args[0]));
    return MakeInt(env, sakipayCalibratedWorkingDays(
        configJson.c_str(), ArgInt(env, args[1]), ArgInt(env, args[2])));
}

static napi_value CalibratedWorkingDaysNow(napi_env env, napi_callback_info info) {
    napi_value args[3] = {nullptr};
    ReadArgs(env, info, args, 3);
    std::string configJson(ArgString(env, args[0]));
    return MakeInt(env, sakipayCalibratedWorkingDaysNow(
        configJson.c_str(), ArgInt64(env, args[1]), ArgInt(env, args[2])));
}

static napi_value HolidayDataJson(napi_env env, napi_callback_info info) {
    napi_value args[1] = {nullptr};
    ReadArgs(env, info, args, 1);
    return MakeString(env, sakipayHolidayDataJson(ArgInt(env, args[0])));
}

static napi_value ResolveDayKind(napi_env env, napi_callback_info info) {
    napi_value args[4] = {nullptr};
    ReadArgs(env, info, args, 4);
    std::string overridesJson(ArgString(env, args[3]));
    return MakeString(env, sakipayResolveDayKind(
        ArgInt(env, args[0]), ArgInt(env, args[1]), ArgInt(env, args[2]), overridesJson.c_str()));
}

static napi_value WorkWindowMinutes(napi_env env, napi_callback_info info) {
    napi_value args[2] = {nullptr};
    ReadArgs(env, info, args, 2);
    return MakeInt(env, sakipayWorkWindowMinutes(ArgInt(env, args[0]), ArgInt(env, args[1])));
}

static napi_value WorkScheduleTotalHours(napi_env env, napi_callback_info info) {
    napi_value args[3] = {nullptr};
    ReadArgs(env, info, args, 3);
    std::string breaksJson(ArgString(env, args[2]));
    napi_value out;
    napi_create_double(env, sakipayWorkScheduleTotalHours(
        ArgInt(env, args[0]), ArgInt(env, args[1]), breaksJson.c_str()), &out);
    return out;
}

static napi_value SecondRate(napi_env env, napi_callback_info info) {
    napi_value args[3] = {nullptr};
    ReadArgs(env, info, args, 3);
    std::string configJson(ArgString(env, args[0]));
    napi_value out;
    napi_create_double(env, sakipaySecondRate(configJson.c_str(), ArgInt64(env, args[1]), ArgInt(env, args[2])), &out);
    return out;
}

static napi_value PruneBreaksJson(napi_env env, napi_callback_info info) {
    napi_value args[1] = {nullptr};
    ReadArgs(env, info, args, 1);
    std::string json(ArgString(env, args[0]));
    return MakeString(env, sakipayPruneBreaksJson(json.c_str()));
}

static napi_value AddBreakJson(napi_env env, napi_callback_info info) {
    napi_value args[1] = {nullptr};
    ReadArgs(env, info, args, 1);
    std::string json(ArgString(env, args[0]));
    return MakeString(env, sakipayAddBreakJson(json.c_str()));
}

static napi_value AddBreakToBreaks(napi_env env, napi_callback_info info) {
    napi_value args[3] = {nullptr};
    ReadArgs(env, info, args, 3);
    std::string breaksJson(ArgString(env, args[2]));
    return MakeString(env, sakipayAddBreakToBreaks(
        ArgInt(env, args[0]), ArgInt(env, args[1]), breaksJson.c_str()));
}

static napi_value OtTotalSecondsJson(napi_env env, napi_callback_info info) {
    napi_value args[4] = {nullptr};
    ReadArgs(env, info, args, 4);
    std::string stateJson(ArgString(env, args[0]));
    return MakeString(env, sakipayOtTotalSecondsJson(
        stateJson.c_str(), ArgInt64(env, args[1]), ArgInt(env, args[2]), ArgBool(env, args[3])));
}

static napi_value OtStartJson(napi_env env, napi_callback_info info) {
    napi_value args[3] = {nullptr};
    ReadArgs(env, info, args, 3);
    std::string stateJson(ArgString(env, args[0]));
    return MakeString(env, sakipayOtStartJson(
        stateJson.c_str(), ArgInt64(env, args[1]), ArgInt(env, args[2])));
}

static napi_value OtEndJson(napi_env env, napi_callback_info info) {
    napi_value args[4] = {nullptr};
    ReadArgs(env, info, args, 4);
    std::string stateJson(ArgString(env, args[0]));
    return MakeString(env, sakipayOtEndJson(
        stateJson.c_str(), ArgInt64(env, args[1]), ArgInt(env, args[2]), ArgDouble(env, args[3])));
}

static napi_value OtBankDailyJson(napi_env env, napi_callback_info info) {
    napi_value args[4] = {nullptr};
    ReadArgs(env, info, args, 4);
    std::string stateJson(ArgString(env, args[0]));
    return MakeString(env, sakipayOtBankDailyJson(
        stateJson.c_str(), ArgInt64(env, args[1]), ArgInt(env, args[2]), ArgDouble(env, args[3])));
}

static napi_value StatusText(napi_env env, napi_callback_info info) {
    napi_value args[1] = {nullptr};
    ReadArgs(env, info, args, 1);
    std::string status(ArgString(env, args[0]));
    return MakeString(env, sakipayStatusText(status.c_str()));
}

static napi_value PaydayText(napi_env env, napi_callback_info info) {
    napi_value args[2] = {nullptr};
    ReadArgs(env, info, args, 2);
    return MakeString(env, sakipayPaydayText(ArgInt(env, args[0]), ArgBool(env, args[1])));
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"defaultConfigJson", nullptr, DefaultConfigJson, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"defaultBreakJson", nullptr, DefaultBreakJson, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"normalizeConfig", nullptr, NormalizeConfig, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"composeConfigJson", nullptr, ComposeConfigJson, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"configBreaksJson", nullptr, ConfigBreaksJson, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"configDayOverridesJson", nullptr, ConfigDayOverridesJson, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"todayEarningsJson", nullptr, TodayEarningsJson, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"monthSummaryJson", nullptr, MonthSummaryJson, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"calibratedWorkingDays", nullptr, CalibratedWorkingDays, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"calibratedWorkingDaysNow", nullptr, CalibratedWorkingDaysNow, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"holidayDataJson", nullptr, HolidayDataJson, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"resolveDayKind", nullptr, ResolveDayKind, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"workWindowMinutes", nullptr, WorkWindowMinutes, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"workScheduleTotalHours", nullptr, WorkScheduleTotalHours, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"secondRate", nullptr, SecondRate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pruneBreaksJson", nullptr, PruneBreaksJson, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"addBreakJson", nullptr, AddBreakJson, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"addBreakToBreaks", nullptr, AddBreakToBreaks, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"otTotalSecondsJson", nullptr, OtTotalSecondsJson, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"otStartJson", nullptr, OtStartJson, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"otEndJson", nullptr, OtEndJson, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"otBankDailyJson", nullptr, OtBankDailyJson, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"statusText", nullptr, StatusText, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"paydayText", nullptr, PaydayText, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module sakipayModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void*)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterSakipayModule(void) {
    napi_module_register(&sakipayModule);
}
