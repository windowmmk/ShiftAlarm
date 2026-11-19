package com.shiftalarm.app

import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 全屏鬧鐘畫面樣式與高對比色解析工具。
 *
 * 解決淺粉／淺黃等柔和時段底色直接疊白字導致對比度不足的問題：
 * 當 `accentBg` 為高明度淺色時，徽章保留柔底深字，主按鈕與光圈則採用深色 `accentFg`。
 */
object AlarmUiStyles {
    data class ResolvedPalette(
        val primaryAccent: Int,
        val badgeBg: Int,
        val badgeText: Int
    )

    fun resolvePalette(accentBg: Int, accentFg: Int): ResolvedPalette {
        val bgLum = relativeLuminance(accentBg)
        val fgLum = relativeLuminance(accentFg)
        return if (bgLum > 0.65) {
            val deepAccent = if (fgLum < 0.55) accentFg else 0xFF0969DA.toInt()
            ResolvedPalette(
                primaryAccent = deepAccent,
                badgeBg = accentBg,
                badgeText = deepAccent
            )
        } else {
            ResolvedPalette(
                primaryAccent = accentBg,
                badgeBg = accentBg,
                badgeText = Color.WHITE
            )
        }
    }

    private fun relativeLuminance(color: Int): Double {
        val r = Color.red(color) / 255.0
        val g = Color.green(color) / 255.0
        val b = Color.blue(color) / 255.0
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    fun formatDateHeader(dateYmd: String): String {
        return try {
            val cal = Calendar.getInstance()
            if (dateYmd.isNotEmpty()) {
                val p = dateYmd.split("-")
                if (p.size == 3) {
                    cal.set(Calendar.YEAR, p[0].toInt())
                    cal.set(Calendar.MONTH, p[1].toInt() - 1)
                    cal.set(Calendar.DAY_OF_MONTH, p[2].toInt())
                }
            }
            val month = cal.get(Calendar.MONTH) + 1
            val day = cal.get(Calendar.DAY_OF_MONTH)
            val weekDay = when (cal.get(Calendar.DAY_OF_WEEK)) {
                Calendar.SUNDAY -> "星期日"
                Calendar.MONDAY -> "星期一"
                Calendar.TUESDAY -> "星期二"
                Calendar.WEDNESDAY -> "星期三"
                Calendar.THURSDAY -> "星期四"
                Calendar.FRIDAY -> "星期五"
                Calendar.SATURDAY -> "星期六"
                else -> ""
            }
            "${month}月${day}日 · $weekDay"
        } catch (_: Exception) {
            SimpleDateFormat("MM月dd日", Locale.getDefault()).format(Date())
        }
    }

    fun buildFallbackDetail(startTime: String, note: String): String {
        val venuePart = if (note.trim().isNotEmpty()) " · 地點：${note.trim()}" else ""
        return if (startTime.isNotEmpty()) {
            "班次時間：$startTime$venuePart"
        } else {
            venuePart.trimStart(' ', '·', ' ')
        }
    }

    fun ovalDrawable(color: Int, alpha: Float): GradientDrawable {
        val c = Color.argb(
            (255 * alpha).toInt(),
            Color.red(color),
            Color.green(color),
            Color.blue(color)
        )
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(c)
        }
    }

    fun cardDrawable(dp1: Int, radiusPx: Float): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radiusPx
            setColor(0xFFFFFFFF.toInt())
            setStroke(dp1, 0xFFE2E8F0.toInt())
        }

    fun badgeDrawable(bgColor: Int, radiusPx: Float): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radiusPx
            setColor(bgColor)
        }

    fun primaryBtnDrawable(color: Int, radiusPx: Float): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radiusPx
            setColor(color)
        }

    fun secondaryBtnDrawable(dp1: Int, radiusPx: Float): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radiusPx
            setColor(0xFFFFFFFF.toInt())
            setStroke(dp1, 0xFFCBD5E1.toInt())
        }
}
