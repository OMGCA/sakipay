/* (c) Copyright XiatStudio 2026~2026 */
package com.xiatstudio.sakipay

/**
 * A tiny JSON reader/writer.
 *
 * The shared module deliberately has no third-party dependencies (the
 * OpenHarmony Kotlin toolchain does not publish every kotlinx library), so this
 * hand-written helper covers everything we need: the configuration object and
 * the small result objects that cross the NAPI boundary to ArkTS, plus the
 * embedded holiday data.
 *
 * Parsing yields plain Kotlin values: [Map]<String, Any?>, [List]<Any?>,
 * [String], [Double], [Boolean] and null.
 */

object MiniJson {

    // --- Writing --------------------------------------------------------------

    /** Serialises a value (Map/List/String/Number/Boolean/null) to compact JSON. */
    fun write(value: Any?): String {
        val sb = StringBuilder()
        writeValue(sb, value)
        return sb.toString()
    }

    /** Convenience builder for an object literal. */
    fun obj(vararg pairs: Pair<String, Any?>): String {
        val sb = StringBuilder()
        sb.append('{')
        pairs.forEachIndexed { index, (key, value) ->
            if (index > 0) sb.append(',')
            writeString(sb, key)
            sb.append(':')
            writeValue(sb, value)
        }
        sb.append('}')
        return sb.toString()
    }

    fun arr(values: List<Any?>): String {
        val sb = StringBuilder()
        writeArray(sb, values)
        return sb.toString()
    }

    private fun writeValue(sb: StringBuilder, value: Any?) {
        when (value) {
            null -> sb.append("null")
            is String -> writeString(sb, value)
            is Boolean -> sb.append(if (value) "true" else "false")
            is Int -> sb.append(value.toString())
            is Long -> sb.append(value.toString())
            is Double -> sb.append(formatDouble(value))
            is Float -> sb.append(formatDouble(value.toDouble()))
            is Map<*, *> -> writeMap(sb, value)
            is List<*> -> writeArray(sb, value)
            is Array<*> -> writeArray(sb, value.toList())
            else -> writeString(sb, value.toString())
        }
    }

    private fun writeMap(sb: StringBuilder, map: Map<*, *>) {
        sb.append('{')
        var first = true
        for ((k, v) in map) {
            if (!first) sb.append(',')
            first = false
            writeString(sb, k.toString())
            sb.append(':')
            writeValue(sb, v)
        }
        sb.append('}')
    }

    private fun writeArray(sb: StringBuilder, list: List<*>) {
        sb.append('[')
        list.forEachIndexed { index, item ->
            if (index > 0) sb.append(',')
            writeValue(sb, item)
        }
        sb.append(']')
    }

    private fun writeString(sb: StringBuilder, s: String) {
        sb.append('"')
        for (c in s) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                '\b' -> sb.append("\\b")
                '\u000C' -> sb.append("\\f")
                else -> if (c < ' ') {
                    sb.append("\\u").append(c.code.toString(16).padStart(4, '0'))
                } else {
                    sb.append(c)
                }
            }
        }
        sb.append('"')
    }

    /** Emits whole doubles without a trailing ".0" so JSON stays compact. */
    private fun formatDouble(d: Double): String {
        if (d.isNaN()) return "0"
        if (!d.isInfinite() && d == d.toLong().toDouble()) {
            return d.toLong().toString()
        }
        return d.toString()
    }

    // --- Parsing --------------------------------------------------------------

    fun parse(text: String): Any? = Parser(text).parseDocument()

    private class Parser(private val text: String) {
        private var pos = 0

        fun parseDocument(): Any? {
            skipWhitespace()
            if (pos >= text.length) return null
            return parseValue()
        }

        private fun parseValue(): Any? {
            skipWhitespace()
            if (pos >= text.length) error("Unexpected end of input")
            return when (val c = text[pos]) {
                '{' -> parseObject()
                '[' -> parseArray()
                '"' -> parseString()
                't', 'f' -> parseBoolean()
                'n' -> parseNull()
                else -> if (c == '-' || c in '0'..'9') parseNumber() else error("Unexpected char '$c' at $pos")
            }
        }

        private fun parseObject(): Map<String, Any?> {
            expect('{')
            val map = LinkedHashMap<String, Any?>()
            skipWhitespace()
            if (peek() == '}') {
                pos++
                return map
            }
            while (true) {
                skipWhitespace()
                val key = parseString()
                skipWhitespace()
                expect(':')
                map[key] = parseValue()
                skipWhitespace()
                when (val c = next()) {
                    ',' -> continue
                    '}' -> break
                    else -> error("Expected ',' or '}' but found '$c' at ${pos - 1}")
                }
            }
            return map
        }

        private fun parseArray(): List<Any?> {
            expect('[')
            val list = ArrayList<Any?>()
            skipWhitespace()
            if (peek() == ']') {
                pos++
                return list
            }
            while (true) {
                list.add(parseValue())
                skipWhitespace()
                when (val c = next()) {
                    ',' -> continue
                    ']' -> break
                    else -> error("Expected ',' or ']' but found '$c' at ${pos - 1}")
                }
            }
            return list
        }

        private fun parseString(): String {
            expect('"')
            val sb = StringBuilder()
            while (true) {
                val c = next()
                when (c) {
                    '"' -> break
                    '\\' -> sb.append(parseEscape())
                    else -> sb.append(c)
                }
            }
            return sb.toString()
        }

        private fun parseEscape(): String {
            return when (val c = next()) {
                '"' -> "\""
                '\\' -> "\\"
                '/' -> "/"
                'b' -> "\b"
                'f' -> "\u000C"
                'n' -> "\n"
                'r' -> "\r"
                't' -> "\t"
                'u' -> {
                    val hex = text.substring(pos, pos + 4)
                    pos += 4
                    hex.toInt(16).toChar().toString()
                }
                else -> error("Invalid escape '\\$c'")
            }
        }

        private fun parseBoolean(): Boolean {
            if (text.startsWith("true", pos)) {
                pos += 4
                return true
            }
            if (text.startsWith("false", pos)) {
                pos += 5
                return false
            }
            error("Invalid literal at $pos")
        }

        private fun parseNull(): Any? {
            if (text.startsWith("null", pos)) {
                pos += 4
                return null
            }
            error("Invalid literal at $pos")
        }

        private fun parseNumber(): Double {
            val start = pos
            if (peek() == '-') pos++
            while (pos < text.length && text[pos] in '0'..'9') pos++
            if (pos < text.length && text[pos] == '.') {
                pos++
                while (pos < text.length && text[pos] in '0'..'9') pos++
            }
            if (pos < text.length && (text[pos] == 'e' || text[pos] == 'E')) {
                pos++
                if (pos < text.length && (text[pos] == '+' || text[pos] == '-')) pos++
                while (pos < text.length && text[pos] in '0'..'9') pos++
            }
            return text.substring(start, pos).toDouble()
        }

        private fun skipWhitespace() {
            while (pos < text.length && text[pos].isWhitespace()) pos++
        }

        private fun peek(): Char = if (pos < text.length) text[pos] else '\u0000'

        private fun next(): Char {
            if (pos >= text.length) error("Unexpected end of input")
            return text[pos++]
        }

        private fun expect(c: Char) {
            skipWhitespace()
            val actual = next()
            if (actual != c) error("Expected '$c' but found '$actual' at ${pos - 1}")
        }

        private fun error(message: String): Nothing = throw IllegalArgumentException("MiniJson: $message")
    }
}

// --- Typed accessors ----------------------------------------------------------

@Suppress("UNCHECKED_CAST")
internal fun Any?.asMapOrNull(): Map<String, Any?>? = this as? Map<String, Any?>

@Suppress("UNCHECKED_CAST")
internal fun Any?.asListOrNull(): List<Any?>? = this as? List<Any?>

internal fun Map<String, Any?>.strOrNull(key: String): String? = this[key] as? String

internal fun Map<String, Any?>.stringOr(key: String, fallback: String): String =
    (this[key] as? String) ?: fallback

internal fun Map<String, Any?>.doubleOr(key: String, fallback: Double): Double =
    (this[key] as? Double) ?: fallback

internal fun Map<String, Any?>.intOr(key: String, fallback: Int): Int =
    (this[key] as? Double)?.toInt() ?: fallback

internal fun Map<String, Any?>.boolOr(key: String, fallback: Boolean): Boolean =
    (this[key] as? Boolean) ?: fallback

internal fun Map<String, Any?>.listOrEmpty(key: String): List<Any?> =
    (this[key] as? List<Any?>) ?: emptyList()
