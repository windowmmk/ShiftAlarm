package com.shiftalarm.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent

/** 鬧鐘排程：setAlarmClock（鬧鐘專用 API）。
 *  相對 setExactAndAllowWhileIdle 嘅好處：Doze／App Standby 豁免、
 *  鬧鐘響嗰刻系統畀臨時後台執行豁免（准許起前台服務／彈畫面），
 *  status bar 仲會顯示鬧鐘 icon。id 愈大愈唔會撞（同 id 覆蓋）。 */
object AlarmScheduler {
    const val EXTRA_ALARM_ID = "alarm_id"
    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val EXTRA_ACCENT_BG = "accent_bg"
    const val EXTRA_ACCENT_FG = "accent_fg"
    const val EXTRA_SHIFT_NAME = "shift_name"
    const val EXTRA_START_TIME = "start_time"
    const val EXTRA_DATE = "alarm_date"
    const val EXTRA_NOTE = "note"
    const val EXTRA_LAUNCH_SOURCE = "launch_source"

    /** 預設 accent：品牌藍 #0078D4／白字（用 val，const 唔俾 call toInt()） */
    val DEFAULT_ACCENT_BG = 0xFF0078D4.toInt()
    val DEFAULT_ACCENT_FG = 0xFFFFFFFF.toInt()

    fun schedule(
        context: Context,
        id: Int,
        triggerAtMillis: Long,
        title: String,
        body: String,
        accentBg: Int = DEFAULT_ACCENT_BG,
        accentFg: Int = DEFAULT_ACCENT_FG,
        shiftName: String = "",
        startTime: String = "",
        date: String = "",
        note: String = ""
    ) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra(EXTRA_ALARM_ID, id)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_ACCENT_BG, accentBg)
            putExtra(EXTRA_ACCENT_FG, accentFg)
            putExtra(EXTRA_SHIFT_NAME, shiftName)
            putExtra(EXTRA_START_TIME, startTime)
            putExtra(EXTRA_DATE, date)
            putExtra(EXTRA_NOTE, note)
        }
        val pi = PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // 鬧鐘專用 API：status bar 顯示鬧鐘 icon，觸發時系統畀後台執行豁免
        val showIntent = PendingIntent.getActivity(
            context,
            id + 200000,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val clockInfo = AlarmManager.AlarmClockInfo(triggerAtMillis, showIntent)
        am.setAlarmClock(clockInfo, pi)
    }

    fun cancel(context: Context, id: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java)
        val pi = PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        am.cancel(pi)
        pi.cancel()
    }

    /**
     * 「只通知」輕量提醒：setExactAndAllowWhileIdle＋GentleAlarmReceiver。
     * 唔用 setAlarmClock（唔使 status bar 鬧鐘 icon），唔用前台服務。
     * 同一個數字 id 都唔會同全鬧鐘撞（PendingIntent 指向唔同 Receiver）。
     */
    fun scheduleGentle(
        context: Context,
        id: Int,
        triggerAtMillis: Long,
        title: String,
        body: String
    ) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, GentleAlarmReceiver::class.java).apply {
            putExtra(EXTRA_ALARM_ID, id)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
        }
        val pi = PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // 用 setAlarmClock 保證準時（HyperOS 會 delay setExactAndAllowWhileIdle）。
        // Receiver 係 GentleAlarmReceiver，只彈通知唔彈全屏。
        // showIntent 用開 App（唔顯示鬧鐘詳情，避免誤導）。
        val showIntent = PendingIntent.getActivity(
            context,
            id + 700000,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val clockInfo = AlarmManager.AlarmClockInfo(triggerAtMillis, showIntent)
        am.setAlarmClock(clockInfo, pi)
    }

    fun cancelGentle(context: Context, id: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, GentleAlarmReceiver::class.java)
        val pi = PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        am.cancel(pi)
        pi.cancel()
        // 有通知顯示緊都一併清走
        try {
            val nm = context.getSystemService(
                Context.NOTIFICATION_SERVICE
            ) as android.app.NotificationManager
            nm.cancel(id)
        } catch (_: Exception) {
        }
    }
}
