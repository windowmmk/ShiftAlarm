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
 * 響鬧預告通知：鬧鐘真正響之前 1 小時，喺狀態欄掛一條 ongoing 通知，
 * 讓使用者知道即將要響（使用者原話「會提前有一個通知頂欄掛着」）。
 *
 * 職責邊界：本 receiver **只碰 NotificationManager**，唔碰 AlarmManager。
 * 排程／取消由 [PreAlertScheduler] 負責，兩邊共用 [PreAlertScheduler.preAlertId] 公式。
 *
 * 生命週期：
 *  - 建立：[PreAlertScheduler.schedule] 到時 → [onReceive] → `notify(id + 900000)`
 *  - ①「知道了」：[ACTION_DISMISS] → 只 `nm.cancel`，**唔動 AlarmManager**
 *    （原鬧鐘照響，使用者只係唔想再見到提示）
 *  - ②鬧鐘真正響：由 [AlarmReceiver] / [GentleAlarmReceiver] 呼叫
 *    [PreAlertScheduler.cancelNotification]
 *  - ③App 內取消／轉更：Dart `AlarmService._cancelAllFor` → `cancelPreAlert`
 *
 * 本 receiver **只讀三個 extra**（`alarm_id` / `title` / `body`）。Intent 內另有
 * `pre_alert_date` / `shift_name` / `start_time` / `note` 四個 extra，係 P2-2
 * 「點擊通知跳該日」嘅預留欄位，現階段刻意只寫不讀——寫入點在
 * [PreAlertScheduler.schedule]，原因寫喺嗰度，唔好當死碼刪。
 */
class PreAlertReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_DISMISS = "com.museai.shift_alarm.PRE_ALERT_DISMISS"
        const val CHANNEL_ID = "pre_alert_channel"
        const val CHANNEL_NAME = "響鬧預告"

        /**
         * 只建立、**永不刪除重建**。
         *
         * ⚠️ 絕對唔准抄 [GentleAlarmReceiver.ensureChannel] 裡面「重要度不足就
         * deleteNotificationChannel 再重建」嘅邏輯：刪頻道會把使用者在系統設定裡
         * 對「響鬧預告」嘅個人化（靜音／關閉）一併重置，等於 App 強行把使用者
         * 關掉嘅提醒再打開，係嚴重嘅信任問題。已存在就乜都唔做。
         */
        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    val nm = context.getSystemService(
                        Context.NOTIFICATION_SERVICE
                    ) as NotificationManager
                    if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                        val soundUri = RingtoneManager.getDefaultUri(
                            RingtoneManager.TYPE_NOTIFICATION
                        )
                        nm.createNotificationChannel(
                            NotificationChannel(
                                CHANNEL_ID,
                                CHANNEL_NAME,
                                NotificationManager.IMPORTANCE_DEFAULT
                            ).apply {
                                description = "鬧鐘響之前 1 小時嘅預告"
                                setSound(soundUri, null)
                                // 預告只係提示，唔震動
                                enableVibration(false)
                            }
                        )
                    }
                } catch (_: Exception) {
                }
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, 0)
        val nm = context.getSystemService(
            Context.NOTIFICATION_SERVICE
        ) as NotificationManager

        // 「知道了」：淨係取消呢隻通知，原鬧鐘照響
        if (intent.action == ACTION_DISMISS) {
            try {
                nm.cancel(PreAlertScheduler.preAlertId(alarmId))
            } catch (_: Exception) {
            }
            return
        }

        val title = intent.getStringExtra(AlarmScheduler.EXTRA_TITLE) ?: "響鬧預告"
        val body = intent.getStringExtra(AlarmScheduler.EXTRA_BODY) ?: ""

        try {
            ensureChannel(context)

            val dismissPi = PendingIntent.getBroadcast(
                context,
                alarmId + 800000,
                Intent(context, PreAlertReceiver::class.java).apply {
                    action = ACTION_DISMISS
                    putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarmId)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
            )
            val contentPi = PendingIntent.getActivity(
                context,
                alarmId + 850000,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
            )

            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_popup_reminder)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setContentIntent(contentPi)
                // 使用者原話「頂欄掛着」：划得走就等於功能失效
                .setOngoing(true)
                .setAutoCancel(false)
                .setSound(
                    RingtoneManager.getDefaultUri(
                        RingtoneManager.TYPE_NOTIFICATION
                    )
                )
                .addAction(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "知道了",
                    dismissPi
                )
                .build()

            nm.notify(PreAlertScheduler.preAlertId(alarmId), notification)
            AlarmDebugLog.append(
                context,
                "[PRE_ALERT_FIRE] id=$alarmId title=$title"
            )
        } catch (_: Exception) {
            // 發唔到通知都唔 crash（Android 13+ 未授權 POST_NOTIFICATIONS
            // 時 notify() 靜默丟棄，本身唔拋；其他異常一律吞掉）
        }
    }
}
