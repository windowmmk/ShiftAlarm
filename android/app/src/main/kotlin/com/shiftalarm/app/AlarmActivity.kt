package com.shiftalarm.app

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
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
import java.util.Date
import java.util.Locale

/**
 * 全屏鬧鐘頁：淺色極簡底＋柔和呼吸動態光圈＋超大數字時鐘＋班次卡片＋停止／貪睡操作鈕。
 * 鈴聲播放交由前台服務 [AlarmSoundService]，本頁專責鎖屏呈現與使用者互動。
 */
class AlarmActivity : Activity() {

    private val handler = Handler(Looper.getMainLooper())
    private var clockTick: Runnable? = null
    private var pulseSet: AnimatorSet? = null
    private var alarmId: Int = 0

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureLockScreenWindow()

        val accentBg = intent.getIntExtra(
            AlarmScheduler.EXTRA_ACCENT_BG, AlarmScheduler.DEFAULT_ACCENT_BG
        )
        val accentFg = intent.getIntExtra(
            AlarmScheduler.EXTRA_ACCENT_FG, AlarmScheduler.DEFAULT_ACCENT_FG
        )
        val palette = AlarmUiStyles.resolvePalette(accentBg, accentFg)

        alarmId = intent.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, 0)
        val title = intent.getStringExtra(AlarmScheduler.EXTRA_TITLE) ?: "排班鬧鐘"
        val body = intent.getStringExtra(AlarmScheduler.EXTRA_BODY) ?: ""
        val shiftName = intent.getStringExtra(AlarmScheduler.EXTRA_SHIFT_NAME) ?: ""
        val startTime = intent.getStringExtra(AlarmScheduler.EXTRA_START_TIME) ?: ""
        val date = intent.getStringExtra(AlarmScheduler.EXTRA_DATE) ?: ""
        val note = intent.getStringExtra(AlarmScheduler.EXTRA_NOTE) ?: ""
        val launchSource = intent.getStringExtra(AlarmScheduler.EXTRA_LAUNCH_SOURCE) ?: "unknown"

        AlarmDebugLog.append(this, "[ALARM_UI] id=$alarmId src=$launchSource 全屏已啟動")

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
        root.addView(
            column,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            ).apply { topMargin = -dp(32) }
        )

        column.addView(buildDateHeader(date))
        column.addView(buildPulseBell(palette.primaryAccent))
        val timeView = buildClockView()
        column.addView(timeView)
        startClock(timeView)
        column.addView(buildShiftCard(palette, title, body, shiftName, startTime, note))
        root.addView(buildActionButtons(palette.primaryAccent))

        setContentView(root)
    }

    private fun configureLockScreenWindow() {
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
    }

    private fun buildDateHeader(date: String): View =
        TextView(this).apply {
            text = AlarmUiStyles.formatDateHeader(date)
            setTextColor(0xFF64748B.toInt())
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(16))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

    private fun buildPulseBell(accent: Int): View {
        val pulseSize = dp(140)
        val wrap = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(pulseSize, pulseSize).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
        }
        val glow = View(this).apply {
            background = AlarmUiStyles.ovalDrawable(accent, 0.16f)
        }
        wrap.addView(glow, FrameLayout.LayoutParams(pulseSize, pulseSize))

        val innerCircleSize = dp(96)
        wrap.addView(
            View(this).apply {
                background = AlarmUiStyles.ovalDrawable(accent, 0.24f)
            },
            FrameLayout.LayoutParams(innerCircleSize, innerCircleSize, Gravity.CENTER)
        )

        val iconSize = dp(42)
        wrap.addView(
            ImageView(this).apply {
                setImageResource(R.drawable.ic_alarm_bell)
                setColorFilter(accent)
            },
            FrameLayout.LayoutParams(iconSize, iconSize, Gravity.CENTER)
        )
        startPulse(glow)
        return wrap
    }

    private fun buildClockView(): TextView =
        TextView(this).apply {
            text = nowHm()
            setTextColor(0xFF0F172A.toInt())
            textSize = 84f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, 0)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

    private fun buildShiftCard(
        palette: AlarmUiStyles.ResolvedPalette,
        title: String,
        body: String,
        shiftName: String,
        startTime: String,
        note: String
    ): View {
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            background = AlarmUiStyles.cardDrawable(dp(1), dp(16).toFloat())
            setPadding(dp(20), dp(16), dp(20), dp(16))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                elevation = dp(2).toFloat()
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                marginStart = dp(28)
                marginEnd = dp(28)
                topMargin = dp(20)
            }
        }

        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        val shiftBadgeText = shiftName.ifEmpty { "排班" }
        headerRow.addView(
            TextView(this).apply {
                text = shiftBadgeText
                setTextColor(palette.badgeText)
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                background = AlarmUiStyles.badgeDrawable(palette.badgeBg, dp(8).toFloat())
                setPadding(dp(12), dp(4), dp(12), dp(4))
            }
        )

        val alarmLabelText = when {
            title.contains(" ") -> title.substringAfter(" ")
            title != shiftBadgeText -> title
            else -> "鬧鐘響起"
        }
        headerRow.addView(
            TextView(this).apply {
                text = alarmLabelText
                setTextColor(0xFF1E293B.toInt())
                textSize = 17f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                setPadding(dp(10), 0, 0, 0)
            }
        )
        card.addView(
            headerRow,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )

        val detailText = body.ifEmpty { AlarmUiStyles.buildFallbackDetail(startTime, note) }
        if (detailText.isNotEmpty()) {
            card.addView(
                TextView(this).apply {
                    text = detailText
                    setTextColor(0xFF64748B.toInt())
                    textSize = 14f
                    gravity = Gravity.CENTER
                    setPadding(0, dp(10), 0, 0)
                }
            )
        }
        return card
    }

    private fun buildActionButtons(primaryAccent: Int): View {
        val btnRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
            ).apply {
                marginStart = dp(24)
                marginEnd = dp(24)
                bottomMargin = dp(48)
            }
        }
        val btnH = dp(56)
        btnRow.addView(
            TextView(this).apply {
                text = "5 分鐘後再響"
                setTextColor(0xFF334155.toInt())
                textSize = 16f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                background = AlarmUiStyles.secondaryBtnDrawable(dp(1), dp(28).toFloat())
                isClickable = true
                isFocusable = true
                setOnClickListener { snoozeAndFinish() }
            },
            LinearLayout.LayoutParams(0, btnH, 1f).apply { marginEnd = dp(8) }
        )
        btnRow.addView(
            TextView(this).apply {
                text = "停止"
                setTextColor(Color.WHITE)
                textSize = 17f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                background = AlarmUiStyles.primaryBtnDrawable(primaryAccent, dp(28).toFloat())
                isClickable = true
                isFocusable = true
                setOnClickListener { stopAndFinish() }
            },
            LinearLayout.LayoutParams(0, btnH, 1f).apply { marginStart = dp(8) }
        )
        return btnRow
    }

    private fun nowHm(): String =
        SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())

    private fun startClock(tv: TextView) {
        clockTick = object : Runnable {
            override fun run() {
                tv.text = nowHm()
                handler.postDelayed(this, 1000)
            }
        }
        handler.post(clockTick!!)
    }

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
                AlarmScheduler.EXTRA_ACCENT_BG, AlarmScheduler.DEFAULT_ACCENT_BG
            )
            val accentFg = intent.getIntExtra(
                AlarmScheduler.EXTRA_ACCENT_FG, AlarmScheduler.DEFAULT_ACCENT_FG
            )
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
