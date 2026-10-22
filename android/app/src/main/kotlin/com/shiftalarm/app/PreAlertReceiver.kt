package com.shiftalarm.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * 響鬧預告通知：鬧鐘真正響之前 1 小時，喺狀態欄掛一條 ongoing 通知，
 * 並以**倒計時**形式實時顯示仲有幾耐響（使用者原話「會提前有一個通知頂欄掛着」，
 * v3.6.1 起由靜態文案改為狀態欄倒計時）。
 *
 * ⚠️ **本檔依賴 `minSdkVersion >= 24`。**
 * 倒計時用 `setChronometerCountDown(true)`，佢係 API 24（Android 7.0）引入；
 * 喺 API < 24 上 `NotificationCompat` 會靜默忽略呢個 flag，通知會由「倒數」
 * 靜默退化為「正計時」（顯示 00:00 起往上加），唔會 crash 但語意完全錯。
 * 目前 `minSdk` 由 Flutter Gradle Plugin 提供（`flutter.minSdkVersion`，現值 24）。
 * 若日後有人調低 minSdk，**必須**喺下面加 `Build.VERSION.SDK_INT >= N` 守衛
 * 或者改用其他方案，唔可以若無其事咁照跑。
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
 * 本 receiver **只讀四個 extra**（`alarm_id` / `title` / `body` / `pre_alert_trigger_at`）。
 * Intent 內另有 `pre_alert_date` / `shift_name` / `start_time` / `note` 四個 extra，
 * 係 P2-2「點擊通知跳該日」嘅預留欄位，現階段刻意只寫不讀——寫入點在
 * [PreAlertScheduler.schedule]，原因寫喺嗰度，唔好當死碼刪。
 */
class PreAlertReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_DISMISS = "com.museai.shift_alarm.PRE_ALERT_DISMISS"

        /**
         * 頻道 id：`pre_alert_channel_v2`。
         *
         * ⚠️ **v3.6.1 特意換咗新 id，唔係改舊嗰個。**
         * `NotificationChannel` 一經建立，`importance` 同 `sound` 就係唯讀：
         * 對同一個 id 再 `createNotificationChannel` 只會更新 name／description，
         * 重要度同聲音會被系統**靜默忽略**。所以要由「有聲 IMPORTANCE_DEFAULT」
         * 改成「無聲 IMPORTANCE_LOW」，唯一乾淨嘅做法就係開一個新 id，
         * 舊嘅 `pre_alert_channel` 唔刪、唔重建，由系統自然淘汰（會喺使用者
         * 系統設定度顯示為「未使用」頻道，可接受）。
         *
         * 咁做同下面 [ensureChannel] 嘅禁令**唔衝突**：禁令係「唔准
         * deleteNotificationChannel 再重建同一個 id」，開新 id 完全合規。
         */
        const val CHANNEL_ID = "pre_alert_channel_v2"
        const val CHANNEL_NAME = "響鬧預告"

        /**
         * 只建立、**永不刪除重建**。
         *
         * ⚠️ 絕對唔准抄 [GentleAlarmReceiver.ensureChannel] 裡面「重要度不足就
         * deleteNotificationChannel 再重建」嘅邏輯：刪頻道會把使用者在系統設定裡
         * 對「響鬧預告」嘅個人化（靜音／關閉）一併重置，等於 App 強行把使用者
         * 關掉嘅提醒再打開，係嚴重嘅信任問題。已存在就乜都唔做。
         *
         * v3.6.1：`IMPORTANCE_LOW`、**無聲**、唔震動。預告嘅職責係「掛喺狀態欄
         * 畀你望到仲有幾耐」，唔應該好似真鬧鐘咁搶注意力；倒計時本身每秒都喺
         * 變，如果每次都響就變成騷擾。
         */
        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    val nm = context.getSystemService(
                        Context.NOTIFICATION_SERVICE
                    ) as NotificationManager
                    if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                        nm.createNotificationChannel(
                            NotificationChannel(
                                CHANNEL_ID,
                                CHANNEL_NAME,
                                NotificationManager.IMPORTANCE_LOW
                            ).apply {
                                description = "鬧鐘響之前 1 小時嘅狀態欄倒計時"
                                // 唔 setSound：倒計時通知唔應該發聲
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
            // 版本號（＝鬧鐘觸發時刻）由派發時寫入 dismissPi，見下面
            // dismissPi 嘅 `putExtra(EXTRA_TRIGGER_AT, …)`。讀唔到（0）就
            // 唔寫記錄——寧願漏記一次，都唔可以寫錯版本號而令真正嘅
            // 下一次預告被永久靜音。
            val triggerAt = intent.getLongExtra(
                PreAlertScheduler.EXTRA_TRIGGER_AT, 0L
            )
            try {
                nm.cancel(PreAlertScheduler.preAlertId(alarmId))
            } catch (_: Exception) {
            }
            // v3.6.2：記住「呢一次」已經被 dismiss。
            // 冇呢一句，任何一次 syncOnLaunch／onAssigned／重開機都會令
            // 通知喺幾分鐘後自己復活——使用者明確表達咗唔想再見到。
            PreAlertScheduler.markDismissed(context, alarmId, triggerAt)
            return
        }

        val title = intent.getStringExtra(AlarmScheduler.EXTRA_TITLE) ?: "響鬧預告"
        val body = intent.getStringExtra(AlarmScheduler.EXTRA_BODY) ?: ""

        // 倒計時終點＝真鬧鐘觸發時刻。讀唔到（0）或已經過咗就唔用 chronometer，
        // 降級做普通靜態通知——寧願冇倒計時，都唔可以出現「倒數 -56 年」呢種
        // 荒謬畫面。會讀唔到嘅唯一情況：升級前已排好嘅舊 PendingIntent
        // （嗰陣 Intent 未有呢個 extra），重開機或 syncOnLaunch 就會換成新嘅。
        val triggerAt = intent.getLongExtra(PreAlertScheduler.EXTRA_TRIGGER_AT, 0L)
        val useCountdown = triggerAt > System.currentTimeMillis()

        try {
            ensureChannel(context)

            val dismissPi = PendingIntent.getBroadcast(
                context,
                alarmId + 800000,
                Intent(context, PreAlertReceiver::class.java).apply {
                    action = ACTION_DISMISS
                    putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarmId)
                    // ⚠️ v3.6.2 必須帶埋版本號，否則 DISMISS 分支拿唔到
                    // triggerAtMillis 去做「已 dismiss」記錄，只能退而用
                    // alarmId 單獨做 key——咁就會變成永久靜音（今日㩒過
                    // 「知道了」，明日同一 index 永遠唔再彈）。
                    // FLAG_UPDATE_CURRENT 每次重派時會連 extras 一齊更新，
                    // 所以同一 requestCode 唔會殘留舊嘅 triggerAt。
                    putExtra(
                        PreAlertScheduler.EXTRA_TRIGGER_AT, triggerAt
                    )
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

            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_popup_reminder)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                // 頻道已 IMPORTANCE_LOW；pre-26 機讀 priority，保持一致
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setContentIntent(contentPi)
                // 使用者原話「頂欄掛着」：划得走就等於功能失效
                .setOngoing(true)
                .setAutoCancel(false)
                // 使用者掃走條通知（或者「全部清除」）都要當成 dismiss。
                // v3.6.2：刻意**重用同一個 dismissPi**——行為同㩒「知道了」
                // 完全一樣（都係 nm.cancel + markDismissed），冇必要多開一個
                // requestCode 帶（多一個帶就多一個同未來 id 撞嘅機會）。
                // 注意：`deleteIntent` 只會喺「使用者主動清除」時觸發，
                // App 自己 `nm.cancel()`（例如真鬧鐘響嗰刻清走預告）唔會觸發，
                // 所以唔會誤記「已 dismiss」。
                .setDeleteIntent(dismissPi)
                // 只提示一次：`PreAlertScheduler` 分支 2 每次 App 啟動都會用
                // `set(now+1s)` 重新派發同一個 PendingIntent，即係同一條通知會被
                // `notify()` 多次。同一 id 只會「更新」不會「新增」，加上頻道係
                // IMPORTANCE_LOW（無聲、無震）本身已經唔會響；`setOnlyAlertOnce`
                // 係第二層保險——即使日後有人把頻道調高重要度，重複 notify 都
                // 唔會再次發聲／震動／彈 heads-up。
                .setOnlyAlertOnce(true)
                // 頻道已無聲，唔再喺 builder 指定 sound（見 ensureChannel KDoc）

            if (useCountdown) {
                // 狀態欄倒計時：時間欄由 SystemUI 每秒重繪，顯示「仲有 01:00:00」遞減。
                // 唔需要 App 存活、唔需要任何背景服務——係通知本身嘅屬性。
                builder
                    .setWhen(triggerAt)
                    .setUsesChronometer(true)
                    .setChronometerCountDown(true) // API 24+，見檔頭 minSdk 說明
            } else {
                // 降級：普通靜態通知，唔顯示時間欄（免得顯示「56 年前」）
                builder.setShowWhen(false)
            }

            val notification = builder
                .addAction(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "知道了",
                    dismissPi
                )
                .build()

            nm.notify(PreAlertScheduler.preAlertId(alarmId), notification)
            AlarmDebugLog.append(
                context,
                "[PRE_ALERT_FIRE] id=$alarmId countdown=$useCountdown " +
                    "triggerAt=$triggerAt title=$title"
            )
        } catch (_: Exception) {
            // 發唔到通知都唔 crash（Android 13+ 未授權 POST_NOTIFICATIONS
            // 時 notify() 靜默丟棄，本身唔拋；其他異常一律吞掉）
        }
    }
}
