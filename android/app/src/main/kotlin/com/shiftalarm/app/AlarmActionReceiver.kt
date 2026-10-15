package com.shiftalarm.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.widget.Toast

/**
 * 通知 action／全屏鬧鐘掣共用：停止＋5 分鐘貪睡。
 * 經 BroadcastReceiver 處理——熄屏後台 startService 會被掟
 * IllegalStateException，舊版「關閉鬧鐘」就係咁停唔到聲。
 */
object AlarmActions {
    const val ACTION_STOP = "com.museai.shift_alarm.ACTION_STOP"
    const val ACTION_SNOOZE = "com.museai.shift_alarm.ACTION_SNOOZE"

    /**
     * 停止：停聲＋cancel 呢個已響鬧鐘嘅 PendingIntent（已響嘅 one-shot，
     * cancel 係保險，唔會郁到未來其他鬧鐘）＋Toast。
     */
    fun stop(context: Context, alarmId: Int) {
        // instance-first：直接停活緊嘅 service，唔經 startService
        //（熄屏後台 startService 會被掟 IllegalStateException）
        AlarmSoundService.stop(context)
        try {
            AlarmScheduler.cancel(context, alarmId)
        } catch (_: Exception) {
        }
        dismissNotification(context, alarmId)
        toast(context, "已停止")
    }

    /**
     * 貪睡：只停而家響緊嘅聲，唔 cancel 未來鬧鐘；用同一個 alarmId
     * 5 分鐘後再排一次（schedule 會覆蓋舊 PendingIntent）。
     */
    fun snooze(
        context: Context,
        alarmId: Int,
        title: String,
        body: String,
        accentBg: Int,
        accentFg: Int,
        shiftName: String,
        startTime: String,
        date: String,
        note: String
    ) {
        // 先停聲（唔 cancel 未來鬧鐘）
        AlarmSoundService.stop(context)
        // 5 分鐘後再響
        try {
            AlarmScheduler.schedule(
                context,
                alarmId,
                System.currentTimeMillis() + 5 * 60 * 1000L,
                title,
                body,
                accentBg,
                accentFg,
                shiftName,
                startTime,
                date,
                note
            )
        } catch (_: Exception) {
        }
        dismissNotification(context, alarmId)
        toast(context, "5 分鐘後再響")
    }

    /**
     * 刪通知：service 路徑嘅通知由 stopForeground 刪；後備路徑（receiver
     * 直接發嘅）唔係經 service，要手動 cancel。兩個 id 都試（service 用
     * ifZeroThen(1)，後備用原 id）。
     */
    private fun dismissNotification(context: Context, alarmId: Int) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as android.app.NotificationManager
            nm.cancel(alarmId)
            if (alarmId == 0) nm.cancel(1)
        } catch (_: Exception) {
        }
    }

    private fun toast(context: Context, msg: String) {
        try {
            Toast.makeText(context.applicationContext, msg, Toast.LENGTH_SHORT).show()
        } catch (_: Exception) {
        }
    }
}

/**
 * 通知 action 入口（explicit intent，manifest exported=false）。
 */
class AlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, 0)
        when (intent.action) {
            AlarmActions.ACTION_STOP -> AlarmActions.stop(context, id)
            AlarmActions.ACTION_SNOOZE -> {
                val title = intent.getStringExtra(AlarmScheduler.EXTRA_TITLE) ?: "排班鬧鐘"
                val body = intent.getStringExtra(AlarmScheduler.EXTRA_BODY) ?: ""
                val accentBg = intent.getIntExtra(
                    AlarmScheduler.EXTRA_ACCENT_BG, AlarmScheduler.DEFAULT_ACCENT_BG)
                val accentFg = intent.getIntExtra(
                    AlarmScheduler.EXTRA_ACCENT_FG, AlarmScheduler.DEFAULT_ACCENT_FG)
                val shiftName = intent.getStringExtra(AlarmScheduler.EXTRA_SHIFT_NAME) ?: ""
                val startTime = intent.getStringExtra(AlarmScheduler.EXTRA_START_TIME) ?: ""
                val date = intent.getStringExtra(AlarmScheduler.EXTRA_DATE) ?: ""
                val note = intent.getStringExtra(AlarmScheduler.EXTRA_NOTE) ?: ""
                AlarmActions.snooze(
                    context, id, title, body,
                    accentBg, accentFg, shiftName, startTime, date, note
                )
            }
        }
    }
}
