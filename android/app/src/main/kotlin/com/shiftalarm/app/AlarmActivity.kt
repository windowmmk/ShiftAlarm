package com.shiftalarm.app

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 全屏鬧鐘頁：瑞士極簡精密風格、純淨淺色底＋柔和呼吸動態光圈＋超大精密數字時鐘＋班次卡片＋自適應膠囊按鈕。
 * 鈴聲由 AlarmSoundService（前台服務）播，呢度負責純淨全屏畫面與交互。
 */
class AlarmActivity : Activity() {

    private val handler = Handler(Looper.getMainLooper())
    private var clockTick: Runnable? = null
    private var pulseSet: AnimatorSet? = null
    private var alarmId: Int = 0

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 鎖屏彈出＋亮屏＋常亮
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // 沉浸式：狀態欄與導航欄透明，無干擾
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            window.statusBarColor = Color.TRANSPARENT
            window.navigationBarColor = Color.TRANSPARENT
        }

        val accentBg = intent.getIntExtra(
            AlarmScheduler.EXTRA_ACCENT_BG, AlarmScheduler.DEFAULT_ACCENT_BG)
        val alarmId = intent.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, 0)
        this.alarmId = alarmId
        val title = intent.getStringExtra(AlarmScheduler.EXTRA_TITLE) ?: "排班鬧鐘"
        val body = intent.getStringExtra(AlarmScheduler.EXTRA_BODY) ?: ""
        val shiftName = intent.getStringExtra(AlarmScheduler.EXTRA_SHIFT_NAME) ?: ""
        val startTime = intent.getStringExtra(AlarmScheduler.EXTRA_START_TIME) ?: ""
        val date = intent.getStringExtra(AlarmScheduler.EXTRA_DATE) ?: ""
        val note = intent.getStringExtra(AlarmScheduler.EXTRA_NOTE) ?: ""
        val launchSource = intent.getStringExtra(AlarmScheduler.EXTRA_LAUNCH_SOURCE) ?: "unknown"

        AlarmDebugLog.append(this, "[ALARM_UI] id=$alarmId src=$launchSource 全屏已啟動")

        // ---- 根佈局：極簡清爽漸變底色 ----
        val root = FrameLayout(this).apply {
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(0xFFFFFFFF.toInt(), 0xFFF8FAFC.toInt())
            )
        }

        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }
        val columnParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        ).apply { topMargin = -dp(32) }
        root.addView(column, columnParams)

        // ---- 頂部日期星期抬頭 ----
        val dateHeader = TextView(this).apply {
            text = getFormattedDate(date)
            setTextColor(0xFF64748B.toInt()) // Slate 500
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(16))
        }
        column.addView(
            dateHeader,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )

        // ---- 中央：呼吸動態光暈 + 矢量精緻鬧鐘 ----
        val pulseWrap = FrameLayout(this)
        val pulseSize = dp(140)
        column.addView(
            pulseWrap,
            LinearLayout.LayoutParams(pulseSize, pulseSize).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
        )
        // 外層呼吸光暈（柔和擴散）
        val glow = View(this).apply {
            background = ovalDrawable(accentBg, 0.16f)
        }
        pulseWrap.addView(glow, FrameLayout.LayoutParams(pulseSize, pulseSize))

        // 內圈半透圓心底座
        val innerCircleSize = dp(96)
        val innerCircle = View(this).apply {
            background = ovalDrawable(accentBg, 0.28f)
        }
        pulseWrap.addView(
            innerCircle,
            FrameLayout.LayoutParams(innerCircleSize, innerCircleSize, Gravity.CENTER)
        )

        // 精緻雙耳時鐘矢量圖標（替換卡通 Emoji）
        val bellIcon = ImageView(this).apply {
            setImageResource(R.drawable.ic_alarm_bell)
            setColorFilter(accentBg)
        }
        val iconSize = dp(42)
        pulseWrap.addView(
            bellIcon,
            FrameLayout.LayoutParams(iconSize, iconSize, Gravity.CENTER)
        )
        startPulse(glow)

        // ---- 超大現代數字時鐘 ----
        val timeView = TextView(this).apply {
            text = nowHm()
            setTextColor(0xFF0F172A.toInt()) // Slate 900
            textSize = 84f
            typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.BOLD)
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, 0)
        }
        column.addView(
            timeView,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )
        startClock(timeView)

        // ---- 班次與提醒精緻卡片 ----
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            background = cardDrawable()
            setPadding(dp(20), dp(16), dp(20), dp(16))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                elevation = dp(2).toFloat()
            }
        }
        val cardParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            marginStart = dp(28)
            marginEnd = dp(28)
            topMargin = dp(20)
        }
        column.addView(card, cardParams)

        // 卡片首行：更名 Badge + 鬧鐘標籤
        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        card.addView(headerRow, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))

        val shiftBadgeText = shiftName.ifEmpty { "排班" }
        val badge = TextView(this).apply {
            text = shiftBadgeText
            setTextColor(Color.WHITE)
            textSize = 14f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = badgeDrawable(accentBg)
            setPadding(dp(12), dp(4), dp(12), dp(4))
        }
        headerRow.addView(badge)

        val alarmLabelText = if (title.contains(" ")) {
            title.substringAfter(" ")
        } else if (title != shiftBadgeText) {
            title
        } else {
            "鬧鐘響起"
        }
        val labelView = TextView(this).apply {
            text = alarmLabelText
            setTextColor(0xFF1E293B.toInt()) // Slate 800
            textSize = 17f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(dp(10), 0, 0, 0)
        }
        headerRow.addView(labelView)

        // 卡片次行：自然友好的提示文案（無技術位移用語）
        val detailText = if (body.isNotEmpty()) body else buildFallbackDetail(startTime, note)
        if (detailText.isNotEmpty()) {
            val detailView = TextView(this).apply {
                text = detailText
                setTextColor(0xFF64748B.toInt()) // Slate 500
                textSize = 14f
                gravity = Gravity.CENTER
                setPadding(0, dp(10), 0, 0)
            }
            card.addView(detailView)
        }

        // ---- 底部操作掣：自適應寬度（weight=1），停止＋貪睡 ----
        val btnRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        val snoozeBtn = TextView(this).apply {
            text = "5 分鐘後再響"
            setTextColor(0xFF334155.toInt()) // Slate 700
            textSize = 16f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = secondaryBtnDrawable()
            isClickable = true
            isFocusable = true
            setOnClickListener { snoozeAndFinish() }
        }
        val stopBtn = TextView(this).apply {
            text = "停止"
            setTextColor(Color.WHITE)
            textSize = 17f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = primaryBtnDrawable(accentBg)
            isClickable = true
            isFocusable = true
            setOnClickListener { stopAndFinish() }
        }
        val btnH = dp(56)
        btnRow.addView(
            snoozeBtn,
            LinearLayout.LayoutParams(0, btnH, 1f).apply {
                marginEnd = dp(8)
            }
        )
        btnRow.addView(
            stopBtn,
            LinearLayout.LayoutParams(0, btnH, 1f).apply {
                marginStart = dp(8)
            }
        )
        root.addView(
            btnRow,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
            ).apply {
                marginStart = dp(24)
                marginEnd = dp(24)
                bottomMargin = dp(48)
            }
        )

        setContentView(root)
    }

    private fun nowHm(): String =
        SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())

    private fun getFormattedDate(dateYmd: String): String {
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

    private fun startClock(tv: TextView) {
        clockTick = object : Runnable {
            override fun run() {
                tv.text = nowHm()
                handler.postDelayed(this, 1000)
            }
        }
        handler.post(clockTick!!)
    }

    /** 呼吸脈衝：柔和縮放與透明度呼吸 */
    private fun startPulse(glow: View) {
        val sx = ObjectAnimator.ofFloat(glow, "scaleX", 1f, 1.08f).apply {
            duration = 1800
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
        }
        val sy = ObjectAnimator.ofFloat(glow, "scaleY", 1f, 1.08f).apply {
            duration = 1800
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
        }
        val alpha = ObjectAnimator.ofFloat(glow, "alpha", 0.45f, 1f).apply {
            duration = 1800
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
        }
        pulseSet = AnimatorSet().apply {
            playTogether(sx, sy, alpha)
            start()
        }
    }

    private fun buildFallbackDetail(startTime: String, note: String): String {
        val venuePart = if (note.trim().isNotEmpty()) " · 地點：${note.trim()}" else ""
        return if (startTime.isNotEmpty()) "班次時間：$startTime$venuePart" else venuePart.trimStart(' ', '·', ' ')
    }

    private fun ovalDrawable(color: Int, alpha: Float): GradientDrawable {
        val c = Color.argb(
            (255 * alpha).toInt(),
            Color.red(color), Color.green(color), Color.blue(color)
        )
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(c)
        }
    }

    private fun cardDrawable(): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(16).toFloat()
            setColor(0xFFFFFFFF.toInt())
            setStroke(dp(1), 0xFFE2E8F0.toInt())
        }
    }

    private fun badgeDrawable(color: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(8).toFloat()
            setColor(color)
        }
    }

    private fun primaryBtnDrawable(color: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(28).toFloat()
            setColor(color)
        }
    }

    private fun secondaryBtnDrawable(): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(28).toFloat()
            setColor(0xFFFFFFFF.toInt())
            setStroke(dp(1), 0xFFCBD5E1.toInt())
        }
    }

    private fun stopAndFinish() {
        try {
            AlarmActions.stop(this, alarmId)
        } catch (_: Exception) {
        }
        finish()
    }

    private fun snoozeAndFinish() {
        try {
            val accentBg = intent.getIntExtra(
                AlarmScheduler.EXTRA_ACCENT_BG, AlarmScheduler.DEFAULT_ACCENT_BG)
            val accentFg = intent.getIntExtra(
                AlarmScheduler.EXTRA_ACCENT_FG, AlarmScheduler.DEFAULT_ACCENT_FG)
            val title = intent.getStringExtra(AlarmScheduler.EXTRA_TITLE) ?: "排班鬧鐘"
            val body = intent.getStringExtra(AlarmScheduler.EXTRA_BODY) ?: ""
            val shiftName = intent.getStringExtra(AlarmScheduler.EXTRA_SHIFT_NAME) ?: ""
            val startTime = intent.getStringExtra(AlarmScheduler.EXTRA_START_TIME) ?: ""
            val date = intent.getStringExtra(AlarmScheduler.EXTRA_DATE) ?: ""
            val note = intent.getStringExtra(AlarmScheduler.EXTRA_NOTE) ?: ""
            AlarmActions.snooze(
                this, alarmId, title, body,
                accentBg, accentFg, shiftName, startTime, date, note
            )
        } catch (_: Exception) {
        }
        finish()
    }

    override fun onDestroy() {
        try {
            clockTick?.let { handler.removeCallbacks(it) }
        } catch (_: Exception) {
        }
        try {
            pulseSet?.cancel()
        } catch (_: Exception) {
        }
        super.onDestroy()
    }
}
