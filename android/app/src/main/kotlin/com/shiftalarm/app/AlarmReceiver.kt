package com.shiftalarm.app

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.media.RingtoneManager
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * 鬧鐘觸發：起 AlarmSoundService（前台服務，熄屏都播到聲）。
 * 唔再依賴背景 startActivity（Android 10+ 會攔截），視覺層交通知嘅 fullScreenIntent。
 */
class AlarmReceiver : BroadcastReceiver() {
    companion object {
        const val CHANNEL_ID = "shift_alarm_channel"
    }

    override fun onReceive(context: Context, intent: Intent) {
        // 著屏：鬧鐘一響即刻強制亮屏。setTurnScreenOn 喺部分機型（HyperOS 等）
        // 唔可靠，呢個係鬧鐘 App 常用做法；10 秒後自動放手，Activity 嘅
        // FLAG_KEEP_SCREEN_ON 會接手。
        try {
            @Suppress("DEPRECATION")
            val screenLock = (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(
                    PowerManager.FULL_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP or
                        PowerManager.ON_AFTER_RELEASE,
                    "ShiftAlarm:screen"
                )
            screenLock.acquire(10_000)
            AlarmDebugLog.append(context, "[ALARM_WAKE] 已請求亮屏")
        } catch (_: Exception) {
        }

        val id = intent.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, 0)
        val title = intent.getStringExtra(AlarmScheduler.EXTRA_TITLE) ?: "排班鬧鐘"
        val body = intent.getStringExtra(AlarmScheduler.EXTRA_BODY) ?: ""

        // 診斷標記：鬧鐘觸發
        AlarmDebugLog.append(context, "[ALARM_FIRE] id=$id title=$title")
        val accentBg = intent.getIntExtra(
            AlarmScheduler.EXTRA_ACCENT_BG, AlarmScheduler.DEFAULT_ACCENT_BG)
        val accentFg = intent.getIntExtra(
            AlarmScheduler.EXTRA_ACCENT_FG, AlarmScheduler.DEFAULT_ACCENT_FG)
        val shiftName = intent.getStringExtra(AlarmScheduler.EXTRA_SHIFT_NAME) ?: ""
        val startTime = intent.getStringExtra(AlarmScheduler.EXTRA_START_TIME) ?: ""
        val date = intent.getStringExtra(AlarmScheduler.EXTRA_DATE) ?: ""
        val note = intent.getStringExtra(AlarmScheduler.EXTRA_NOTE) ?: ""

        val svc = Intent(context, AlarmSoundService::class.java).apply {
            putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
            putExtra(AlarmScheduler.EXTRA_TITLE, title)
            putExtra(AlarmScheduler.EXTRA_BODY, body)
            putExtra(AlarmScheduler.EXTRA_ACCENT_BG, accentBg)
            putExtra(AlarmScheduler.EXTRA_ACCENT_FG, accentFg)
            putExtra(AlarmScheduler.EXTRA_SHIFT_NAME, shiftName)
            putExtra(AlarmScheduler.EXTRA_START_TIME, startTime)
            putExtra(AlarmScheduler.EXTRA_DATE, date)
            putExtra(AlarmScheduler.EXTRA_NOTE, note)
        }
        try {
            ContextCompat.startForegroundService(context, svc)
        } catch (_: Exception) {
            // 後備：唔經 service，直接發通知（帶鬧鐘聲＋fullScreenIntent），
            // 確保任何情況下都有聲有通知，唔會靜默無事發生。
            try {
                postFallbackNotification(
                    context, id, title, body,
                    accentBg, accentFg, shiftName, startTime, date, note)
            } catch (_: Exception) {
            }
        }

        // App 在前台（亮屏使用中）：fullScreenIntent 只出 heads-up，
        // 直接 startActivity 起全屏（唔加 CLEAR_TASK，保留日曆喺下面）。
        // 熄屏／鎖屏／其他 App 在前台：唔郁，繼續靠 setFullScreenIntent。
        if (CrashApp.isForeground) {
            try {
                val direct = Intent(context, AlarmActivity::class.java).apply {
                    putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
                    putExtra(AlarmScheduler.EXTRA_TITLE, title)
                    putExtra(AlarmScheduler.EXTRA_BODY, body)
                    putExtra(AlarmScheduler.EXTRA_ACCENT_BG, accentBg)
                    putExtra(AlarmScheduler.EXTRA_ACCENT_FG, accentFg)
                    putExtra(AlarmScheduler.EXTRA_SHIFT_NAME, shiftName)
                    putExtra(AlarmScheduler.EXTRA_START_TIME, startTime)
                    putExtra(AlarmScheduler.EXTRA_DATE, date)
                    putExtra(AlarmScheduler.EXTRA_NOTE, note)
                    putExtra(AlarmScheduler.EXTRA_LAUNCH_SOURCE, "direct")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                AlarmDebugLog.append(context, "[ALARM_FG_DIRECT] id=$id 前台直接起全屏")
                context.startActivity(direct)
            } catch (_: Exception) {
                // heads-up 兜底，唔掟
            }
        }
    }

    /**
     * 後備通知：前台服務起唔到嗰陣用。直接播鬧鐘聲（setSound＋USAGE_ALARM），
     * 唔依賴 service／Activity。
     */
    private fun postFallbackNotification(
        context: Context, id: Int, title: String, body: String,
        accentBg: Int, accentFg: Int,
        shiftName: String, startTime: String, date: String, note: String
    ) {
        AlarmSoundService.ensureChannel(context)

        val fullIntent = Intent(context, AlarmActivity::class.java).apply {
            putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
            putExtra(AlarmScheduler.EXTRA_TITLE, title)
            putExtra(AlarmScheduler.EXTRA_BODY, body)
            putExtra(AlarmScheduler.EXTRA_ACCENT_BG, accentBg)
            putExtra(AlarmScheduler.EXTRA_ACCENT_FG, accentFg)
            putExtra(AlarmScheduler.EXTRA_SHIFT_NAME, shiftName)
            putExtra(AlarmScheduler.EXTRA_START_TIME, startTime)
            putExtra(AlarmScheduler.EXTRA_DATE, date)
            putExtra(AlarmScheduler.EXTRA_NOTE, note)
            putExtra(AlarmScheduler.EXTRA_LAUNCH_SOURCE, "fallback")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val fullPi = PendingIntent.getActivity(
            context, id, fullIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

        // 後備通知都要有停止／貪睡掣，唔係呢條路又會停唔到聲
        val stopPi = PendingIntent.getBroadcast(
            context, 100 + id,
            Intent(context, AlarmActionReceiver::class.java).apply {
                action = AlarmActions.ACTION_STOP
                putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
                putExtra(AlarmScheduler.EXTRA_TITLE, title)
                putExtra(AlarmScheduler.EXTRA_BODY, body)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val snoozePi = PendingIntent.getBroadcast(
            context, 200 + id,
            Intent(context, AlarmActionReceiver::class.java).apply {
                action = AlarmActions.ACTION_SNOOZE
                putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
                putExtra(AlarmScheduler.EXTRA_TITLE, title)
                putExtra(AlarmScheduler.EXTRA_BODY, body)
                putExtra(AlarmScheduler.EXTRA_ACCENT_BG, accentBg)
                putExtra(AlarmScheduler.EXTRA_ACCENT_FG, accentFg)
                putExtra(AlarmScheduler.EXTRA_SHIFT_NAME, shiftName)
                putExtra(AlarmScheduler.EXTRA_START_TIME, startTime)
                putExtra(AlarmScheduler.EXTRA_DATE, date)
                putExtra(AlarmScheduler.EXTRA_NOTE, note)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(fullPi, true)
            .setContentIntent(fullPi)
            .setSound(alarmUri)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "停止", stopPi)
            .addAction(android.R.drawable.ic_lock_idle_alarm, "5 分鐘後再響", snoozePi)
            .setAutoCancel(true)
            .build()

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        nm.notify(id, notification)
    }
}
