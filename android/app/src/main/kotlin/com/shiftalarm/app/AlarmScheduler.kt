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
        // 註冊（v3.6.2）：**任何排得成嘅 id 都必須入註冊表**，否則對帳
        // （[cancelAllExcept]）永遠睇唔到佢。
        //
        // 為什麼：`prune` 嘅 stale ＝ `previous - keep`，而 `previous` 就係
        // 註冊表內容。如果排程唔寫註冊表，註冊表只會等於「上一次 prune 寫入
        // 嘅 keep」。於是所有喺 `rescheduleAll` 週期之外排嘅 id（最典型：
        // `onAssigned` 排到第 3 條 App 被殺）從來唔會出現喺 `previous`，
        // 對帳永遠 cancel 唔到佢——佢會喺排班已刪嘅日子照樣全屏響，
        // 而且冇預告、用戶完全搵唔到來源。即係對帳對「中途被殺」呢個
        // 最主要嘅場景完全無效。
        //
        // 與 [PreAlertScheduler] 嘅 `rememberId` 一致，三條通道機制才閉環。
        AlarmIdRegistry.remember(context, AlarmIdRegistry.KEY_FULL, id)
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
        // 註冊（v3.6.2）：同 [schedule] 同一個理由——任何排得成嘅 id 都要入
        // 註冊表，否則對帳睇唔到佢。呢條通道嘅 id 同全鬧鐘共用同一個數字
        // 空間（同一個 alarmId 可以兩條通道都有），所以**一定要分開兩條
        // key**，唔可以靠「全鬧鐘嗰條有就當有」。
        AlarmIdRegistry.remember(context, AlarmIdRegistry.KEY_GENTLE, id)
    }

    fun cancelGentle(context: Context, id: Int) {
        cancelGentleScheduleOnly(context, id)
        // 有通知顯示緊都一併清走
        try {
            val nm = context.getSystemService(
                Context.NOTIFICATION_SERVICE
            ) as android.app.NotificationManager
            nm.cancel(id)
        } catch (_: Exception) {
        }
    }

    /**
     * 只取消「只通知」嘅 AlarmManager 排程，**唔碰通知**。
     *
     * 為什麼要同 [cancelGentle] 分家：對帳（[cancelAllExcept]）同開機／時區
     * 變更後嘅過期清理（[BootReceiver]）都會喺「可能正有通知掛喺通知欄、
     * 甚至正响緊」嘅時刻跑。嗰條嘅 trigger 已經過去，所以一定唔會喺 keep
     * 清單裡面，對帳就會想 cancel 佢——呢個時候如果順手 `nm.cancel`，就等於
     * 親手拆走用戶啱啱收到嘅提醒。殘留一條通知嘅代價遠低於「提醒無聲消失」，
     * 所以呢兩條路徑只 cancel 排程。
     */
    internal fun cancelGentleScheduleOnly(context: Context, id: Int) {
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
    }

    /**
     * 對帳：把註冊表裡面「唔喺今次預期清單」嘅全鬧鐘／只通知 id 全部 cancel。
     *
     * 為什麼需要（v3.6.2）：`PreAlertScheduler` 由 v3.5 起就有註冊表＋prune，
     * 但全鬧鐘／只通知兩條通道係「只加不清」。結果係「Dart 側認為唔應該再
     * 存在」嘅 id（例如導入配置換走咗班次、App 中途被殺令 `onAssigned` 只
     * 跑完一半）會永遠留喺 AlarmManager，變成幽靈鬧鐘：喺用戶完全搵唔到
     * （對應排班已刪）嘅時間突然全屏響，而且因為佢唔喺 Dart 嘅清單裡面，
     * 連預告都冇。三條通道行為一致之後，呢類殘留一律由對帳收拾。
     *
     * ⚠️ **刻意唔清通知**：見 [cancelGentleScheduleOnly] 嘅 KDoc。呢個方法會喺
     * 冷啟動時跑，而冷啟動嗰刻可能正有鬧鐘响緊。
     *
     * ⚠️ **只可以喺「今次清單完整」嘅情況呼叫**：殘缺嘅 keep 會令呢個方法
     * 主動 cancel 一批本來有效嘅鬧鐘，代價係「鬧鐘唔響」，比留低幽靈嚴重
     * 得多。呼叫方（`MainActivity` 嘅 `rescheduleAll`）用 completed 旗標守住。
     */
    fun cancelAllExcept(
        context: Context,
        keepFullIds: Set<Int>,
        keepGentleIds: Set<Int>
    ) {
        // 全鬧鐘：只 cancel AlarmManager 排程，唔碰通知
        AlarmIdRegistry.prune(
            context, AlarmIdRegistry.KEY_FULL, keepFullIds
        ) { staleId ->
            cancel(context, staleId)
        }
        // 只通知：同上，用唔碰通知嘅版本
        AlarmIdRegistry.prune(
            context, AlarmIdRegistry.KEY_GENTLE, keepGentleIds
        ) { staleId ->
            cancelGentleScheduleOnly(context, staleId)
        }
    }
}
