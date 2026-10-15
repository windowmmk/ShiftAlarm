package com.shiftalarm.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * 「只通知」輕量提醒：到時只發一隻普通高優先級通知
 * （預設通知聲＋震動），唔用 fullScreenIntent、唔用前台服務、
 * 唔用 MediaPlayer、唔強制亮屏。
 * 帶一個「知道了」action 取消通知；㩒通知 body 開 App。
 */
class GentleAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_DISMISS = "com.museai.shift_alarm.GENTLE_DISMISS"
        const val CHANNEL_ID = "gentle_alarm_channel"

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = context.getSystemService(
                    Context.NOTIFICATION_SERVICE
                ) as NotificationManager
                val existing = nm.getNotificationChannel(CHANNEL_ID)
                // Android 8+ 有冇聲由 Channel 控制，唔係 Builder。
                // 如果個 Channel 之前已經係靜音／低優先級，刪咗重建，
                // 確保預設通知聲＋震動＋高優先級（彈出）。
                val needsRecreate = existing == null ||
                    existing.sound == null ||
                    existing.importance < NotificationManager.IMPORTANCE_HIGH
                if (needsRecreate) {
                    try {
                        nm.deleteNotificationChannel(CHANNEL_ID)
                    } catch (_: Exception) {
                    }
                    val soundUri = RingtoneManager.getDefaultUri(
                        RingtoneManager.TYPE_NOTIFICATION
                    )
                    nm.createNotificationChannel(
                        NotificationChannel(
                            CHANNEL_ID,
                            "提示通知",
                            NotificationManager.IMPORTANCE_HIGH
                        ).apply {
                            description = "班次提示（只通知，不響鬧鐘）"
                            setSound(soundUri, null)
                            enableVibration(true)
                            vibrationPattern = longArrayOf(0, 300, 200, 300)
                        }
                    )
                }
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, 0)
        val nm = context.getSystemService(
            Context.NOTIFICATION_SERVICE
        ) as NotificationManager

        // 「知道了」：淨係取消呢隻通知
        if (intent.action == ACTION_DISMISS) {
            try {
                nm.cancel(id)
            } catch (_: Exception) {
            }
            return
        }

        val title = intent.getStringExtra(AlarmScheduler.EXTRA_TITLE) ?: "提醒"
        val body = intent.getStringExtra(AlarmScheduler.EXTRA_BODY) ?: ""

        try {
            ensureChannel(context)

            val dismissPi = PendingIntent.getBroadcast(
                context,
                id + 500000,
                Intent(context, GentleAlarmReceiver::class.java).apply {
                    action = ACTION_DISMISS
                    putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
            )
            val contentPi = PendingIntent.getActivity(
                context,
                id + 600000,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
            )

            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setContentIntent(contentPi)
                .addAction(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "知道了",
                    dismissPi
                )
                .setAutoCancel(true)
                .setSound(
                    RingtoneManager.getDefaultUri(
                        RingtoneManager.TYPE_NOTIFICATION
                    )
                )
                .setVibrate(longArrayOf(0, 300, 200, 300))
                .build()

            nm.notify(id, notification)
        } catch (_: Exception) {
            // 發唔到通知都唔 crash
        }
    }
}
