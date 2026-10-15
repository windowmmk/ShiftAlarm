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
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 全屏鬧鐘頁：淺色底＋呼吸光暈＋超大時鐘＋更名 badge＋大關閉掣。
 * 鈴聲由 AlarmSoundService（前台服務）播，呢度只負責畫面＋關閉。
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
            // 雙保險：deprecated 但部分 OEM（HyperOS）更食呢套
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

        // 沉浸式：唔畀 status bar／導航欄干擾
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

        // 診斷標記：全屏鬧鐘已啟動（src 分辨自動彈 fullscreen／手動㩒 content／前台直起 direct）
        AlarmDebugLog.append(this, "[ALARM_UI] id=$alarmId src=$launchSource 全屏已啟動")

        // ---- 根佈局：淺色漸變（唔用深色模式） ----
        val root = FrameLayout(this).apply {
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(0xFFFFFFFF.toInt(), 0xFFF5F5F5.toInt())
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
        ).apply { topMargin = -dp(40) }
        root.addView(column, columnParams)

        // ---- 頂部：呼吸光暈圓環 ----
        val pulseWrap = FrameLayout(this)
        val pulseSize = dp(200)
        column.addView(
            pulseWrap,
            LinearLayout.LayoutParams(pulseSize, pulseSize).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
        )
        // 外層光暈（動畫目標）
        val glow = View(this).apply {
            background = ovalDrawable(accentBg, 0.35f)
        }
        pulseWrap.addView(glow, FrameLayout.LayoutParams(pulseSize, pulseSize))
        // 內圈細環
        val ringSize = dp(150)
        val ring = View(this).apply {
            background = ringDrawable(accentBg)
        }
        pulseWrap.addView(
            ring,
            FrameLayout.LayoutParams(ringSize, ringSize, Gravity.CENTER)
        )
        // 中央鬧鐘 emoji
        val bell = TextView(this).apply {
            text = "\u23F0"
            textSize = 56f
            gravity = Gravity.CENTER
        }
        pulseWrap.addView(
            bell,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        )
        startPulse(glow)

        // ---- 中央：超大時鐘 ----
        val timeView = TextView(this).apply {
            text = nowHm()
            setTextColor(0xFF242424.toInt())
            textSize = 90f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, dp(24), 0, 0)
        }
        column.addView(
            timeView,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )
        startClock(timeView)

        // ---- 更名 pill badge ----
        val badgeLabel = shiftName.ifEmpty { title }
        val badge = TextView(this).apply {
            text = badgeLabel
            setTextColor(0xFF1A1A1A.toInt())
            textSize = 20f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = pillDrawable(accentBg)
            setPadding(dp(28), dp(10), dp(28), dp(10))
        }
        column.addView(
            badge,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = dp(16)
            }
        )

        // ---- 副標題 ----
        val subtitleText = buildSubtitle(startTime, date, note, body)
        if (subtitleText.isNotEmpty()) {
            val subtitle = TextView(this).apply {
                text = subtitleText
                setTextColor(0xFF616161.toInt())
                textSize = 17f
                gravity = Gravity.CENTER
            }
            column.addView(
                subtitle,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { topMargin = dp(10) }
            )
        }

        // ---- 底部：停止＋貪睡，兩個掣並排 ----
        val btnRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        val stopBtn = TextView(this).apply {
            text = "停止"
            setTextColor(Color.WHITE)
            textSize = 20f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = capsuleDrawable(accentBg)
            isClickable = true
            isFocusable = true
            setOnClickListener { stopAndFinish() }
        }
        val snoozeBtn = TextView(this).apply {
            text = "5 分鐘後再響"
            setTextColor(0xFF424242.toInt())
            textSize = 18f
            gravity = Gravity.CENTER
            background = outlineCapsuleDrawable(accentBg)
            isClickable = true
            isFocusable = true
            setOnClickListener { snoozeAndFinish() }
        }
        val btnW = dp(168)
        val btnH = dp(64)
        btnRow.addView(
            stopBtn,
            LinearLayout.LayoutParams(btnW, btnH).apply {
                marginEnd = dp(12)
            }
        )
        btnRow.addView(
            snoozeBtn,
            LinearLayout.LayoutParams(btnW, btnH).apply {
                marginStart = dp(12)
            }
        )
        root.addView(
            btnRow,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            ).apply { bottomMargin = dp(72) }
        )

        setContentView(root)
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

    /** 呼吸脈衝：scale 1.0→1.08＋alpha 循環 */
    private fun startPulse(glow: View) {
        val sx = ObjectAnimator.ofFloat(glow, "scaleX", 1f, 1.08f).apply {
            duration = 1600
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
        }
        val sy = ObjectAnimator.ofFloat(glow, "scaleY", 1f, 1.08f).apply {
            duration = 1600
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
        }
        val alpha = ObjectAnimator.ofFloat(glow, "alpha", 0.45f, 1f).apply {
            duration = 1600
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
        }
        pulseSet = AnimatorSet().apply {
            playTogether(sx, sy, alpha)
            start()
        }
    }

    private fun buildSubtitle(startTime: String, date: String, note: String, body: String): String {
        if (startTime.isEmpty() && date.isEmpty()) return body
        val parts = mutableListOf<String>()
        if (startTime.isNotEmpty()) {
            parts.add("$startTime 開工" + if (note.isNotEmpty()) " · $note" else "")
        }
        val md = parseMd(date)
        if (md != null) parts.add(md)
        return parts.joinToString(" · ")
    }

    private fun parseMd(ymd: String): String? {
        return try {
            val p = ymd.split("-")
            if (p.size != 3) return null
            "${p[1].trimStart('0').ifEmpty { "0" }}月${p[2].trimStart('0').ifEmpty { "0" }}日"
        } catch (_: Exception) {
            null
        }
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

    private fun ringDrawable(color: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.TRANSPARENT)
            setStroke(dp(3), color)
        }
    }

    private fun pillDrawable(color: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(16).toFloat()
            setColor(color)
        }
    }

    private fun capsuleDrawable(color: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(36).toFloat()
            setColor(color)
        }
    }

    /** 描邊次要掣：白底＋時段色邊 */
    private fun outlineCapsuleDrawable(color: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(32).toFloat()
            setColor(Color.WHITE)
            setStroke(dp(2), color)
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
