package com.xiatstudio.sakipay

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView
import java.util.TimeZone

/**
 * Android entry point.
 *
 * The UI is intentionally Android-only (plain views, no shared UI); every number
 * comes from the shared KMP module, exactly as on iOS and HarmonyOS.
 */
class MainActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Minimal sample configuration so the screen has something to show.
        val config = SakipayConfig(
            monthlyPay = 20000.0,
            currency = "¥",
            payDay = 15,
            breakSegments = listOf(BreakSegment.create(12, 0, 13, 30)),
            useCalibratedWorkDays = true,
        )

        val nowMillis = System.currentTimeMillis()
        val tzOffsetMinutes = TimeZone.getDefault().getOffset(nowMillis) / 60_000
        val now = civilDateTimeFromEpochMillis(nowMillis, tzOffsetMinutes)

        val calculator = config.calculatorFor(now.date)
        val today = calculator.calculateTodayEarnings(now)
        val summary = calculator.calculateMonthSummary(now)

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
        }
        layout.addView(title())
        layout.addView(line("状态：${SakipayCore.statusText(today.status.wire)}"))
        layout.addView(line("今日已赚：${config.currency}${"%.2f".format(today.amount)}"))
        layout.addView(line("本月累计：${config.currency}${"%.2f".format(summary.monthEarnings)}"))
        layout.addView(line(SakipayCore.paydayText(summary.daysUntilPayday, summary.isPayday)))
        layout.addView(line("收益由 KMP 共享逻辑计算"))

        setContentView(layout)
    }

    private fun title(): TextView = TextView(this).apply {
        text = "窝囊计费"
        textSize = 24f
        setTextColor(Color.parseColor("#1F1F1F"))
        gravity = Gravity.CENTER
    }

    private fun line(value: String): TextView = TextView(this).apply {
        text = value
        textSize = 16f
        setTextColor(Color.parseColor("#444444"))
        gravity = Gravity.CENTER
    }
}
