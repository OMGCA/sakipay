/* (c) Copyright XiatStudio 2026~2026 */
package com.xiatstudio.sakipay

/**
 * Bundled Chinese public-holiday / adjusted-workday data.
 *
 * The data used to ship as `holidays.json` inside each app bundle (iOS
 * `Resources/`, HarmonyOS `rawfile/`). It is embedded here instead so both
 * platforms share one copy and no platform-side file access is required.
 *
 * To update the data, replace the JSON below — the shape must stay
 * `{ "<year>": { "holidays": ["MM-DD", ...], "adjustedWorkdays": ["MM-DD", ...] } }`.
 */
internal object HolidaysJson {
    val raw: String = """
{
  "2025": {
    "holidays": [
      "01-01",
      "01-28", "01-29", "01-30", "01-31", "02-01", "02-02", "02-03", "02-04",
      "04-04", "04-05", "04-06",
      "05-01", "05-02", "05-03", "05-04", "05-05",
      "05-31", "06-01", "06-02",
      "10-01", "10-02", "10-03", "10-04", "10-05", "10-06", "10-07", "10-08"
    ],
    "adjustedWorkdays": [
      "01-26",
      "02-08",
      "04-27",
      "09-28",
      "10-11"
    ]
  },
  "2026": {
    "holidays": [
      "01-01", "01-02", "01-03",
      "02-15", "02-16", "02-17", "02-18", "02-19", "02-20", "02-21", "02-22", "02-23",
      "04-04", "04-05", "04-06",
      "05-01", "05-02", "05-03", "05-04", "05-05",
      "06-19", "06-20", "06-21",
      "09-25", "09-26", "09-27",
      "10-01", "10-02", "10-03", "10-04", "10-05", "10-06", "10-07"
    ],
    "adjustedWorkdays": [
      "01-04",
      "02-14",
      "02-28",
      "05-09",
      "09-20",
      "10-10"
    ]
  },
  "2027": {
    "holidays": [],
    "adjustedWorkdays": []
  }
}
""".trimIndent()
}

/** Loads and caches the bundled holiday calendars. */
object HolidayCalendarService {

    private val calendars: Map<Int, HolidayCalendar> by lazy { parse(HolidaysJson.raw) }

    /** The calendar for [year], or null when no data is bundled for it. */
    fun forYear(year: Int): HolidayCalendar? = calendars[year]

    /** True when holiday data is available for [year]. */
    fun hasDataForYear(year: Int): Boolean = calendars.containsKey(year)

    /** The calendar for the given [year] (convenience alias used by the app). */
    fun current(year: Int): HolidayCalendar? = forYear(year)

    /**
     * JSON of one year's calendar, for platform UIs that render a month grid:
     * `{"year":2026,"holidays":["10-01",...],"adjustedWorkdays":["10-10",...]}`.
     * Returns an empty string when no data is bundled for [year].
     */
    fun dataJson(year: Int): String {
        val c = forYear(year) ?: return ""
        return MiniJson.obj(
            "year" to c.year,
            "holidays" to c.holidays.sorted(),
            "adjustedWorkdays" to c.adjustedWorkdays.sorted(),
        )
    }

    private fun parse(raw: String): Map<Int, HolidayCalendar> {
        val root = MiniJson.parse(raw).asMapOrNull() ?: return emptyMap()
        val result = LinkedHashMap<Int, HolidayCalendar>()
        for ((yearKey, value) in root) {
            val year = yearKey.toIntOrNull() ?: continue
            val yearMap = value.asMapOrNull() ?: continue
            val holidays = yearMap.listOrEmpty("holidays")
                .mapNotNull { it as? String }
                .toSet()
            val adjusted = yearMap.listOrEmpty("adjustedWorkdays")
                .mapNotNull { it as? String }
                .toSet()
            result[year] = HolidayCalendar(year, holidays, adjusted)
        }
        return result
    }
}
