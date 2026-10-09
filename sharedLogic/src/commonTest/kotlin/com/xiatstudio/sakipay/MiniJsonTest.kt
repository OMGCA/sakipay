/* (c) Copyright XiatStudio 2026~2026 */
package com.xiatstudio.sakipay

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MiniJsonTest {

    @Test
    fun writesAndParsesFlatObject() {
        val json = MiniJson.obj(
            "name" to "窝囊计费",
            "pay" to 21750,
            "rate" to 0.0,
            "paused" to false,
            "missing" to null,
        )
        val map = MiniJson.parse(json).asMapOrNull()!!
        assertEquals("窝囊计费", map.stringOr("name", ""))
        assertEquals(21750.0, map.doubleOr("pay", 0.0))
        assertEquals(0.0, map.doubleOr("rate", -1.0))
        assertEquals(false, map.boolOr("paused", true))
        assertNull(map["missing"])
    }

    @Test
    fun wholeNumbersAreWrittenWithoutDecimalPoint() {
        assertEquals("""{"a":5}""", MiniJson.obj("a" to 5))
        assertEquals("""{"a":5}""", MiniJson.obj("a" to 5.0))
        assertEquals("""{"a":5.5}""", MiniJson.obj("a" to 5.5))
    }

    @Test
    fun escapesStrings() {
        val json = MiniJson.obj("quote" to "a\"b\\c\nd")
        val map = MiniJson.parse(json).asMapOrNull()!!
        assertEquals("a\"b\\c\nd", map.stringOr("quote", ""))
    }

    @Test
    fun parsesNestedArraysOfObjects() {
        val original = listOf(
            BreakSegment.create(12, 0, 13, 30, id = "one"),
            BreakSegment.create(15, 0, 15, 15, id = "two"),
        )
        val json = MiniJson.arr(original.map { it.toMap() })
        val parsed = MiniJson.parse(json).asListOrNull()!!
        val segments = parsed.mapNotNull { it.asMapOrNull() }.map { BreakSegment.fromMap(it) }
        assertEquals(original, segments)
    }

    @Test
    fun parsesNumbersInExponentForm() {
        assertEquals(1000.0, MiniJson.parse("1e3") as Double)
        assertEquals(-2.5, MiniJson.parse("-2.5E0") as Double)
    }

    @Test
    fun parsesBooleansAndNull() {
        assertEquals(true, MiniJson.parse("true"))
        assertEquals(false, MiniJson.parse("false"))
        assertNull(MiniJson.parse("null"))
    }

    @Test
    fun roundTripsArbitraryNesting() {
        val json = """{"a":[1,2,{"b":"x"}],"c":{"d":true}}"""
        val map = MiniJson.parse(json).asMapOrNull()!!
        val a = map.listOrEmpty("a")
        assertEquals(3, a.size)
        assertTrue((a[2] as Map<*, *>)["b"] == "x")
    }
}
