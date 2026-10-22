package com.shiftalarm.app

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray

/**
 * 響鬧預告排程器（第三條通知通道）。
 *
 * 使用者原話：「我想在每次鬧鐘響之前1小時, 像本地鬧鐘一樣, 會提前有一個通知頂欄掛着,
 * 讓用戶知道即將要響。」→ 每個 enabled **而且係真正鬧鐘**（`notificationOnly == false`）
 * 嘅鬧鐘，喺真正觸發時刻之前 60 分鐘排一條預告廣播，由 [PreAlertReceiver] 發
 * ongoing 通知並以狀態欄倒計時顯示剩餘時間。
 *
 * ⚠️ 純通知類鬧鐘（打卡開工／收工、使用者自建嘅「只通知」）**唔排預告**（v3.6.1 裁示）。
 * 過濾喺三個呼叫點各自做：Dart `AlarmService.onAssigned`、Dart
 * `AlarmService.syncOnLaunch`、原生 `BootReceiver.scheduleAll`。本 object 唔再重複判斷
 * ——入得嚟就照排，保持「呼叫方決定排邊啲」嘅單一職責。
 *
 * 職責邊界：本 object **只碰 AlarmManager 同 id 註冊表**（例外係 [cancelNotification]，
 * 佢淨係清通知）。發通知嘅嘢全部喺 [PreAlertReceiver]。
 *
 * ⚠️ 排程 API 用 `setExactAndAllowWhileIdle`，**唔用 `setAlarmClock`**（已裁示，見 ARCH §7.5）。
 * 理由：`setAlarmClock` 會令系統時鐘 App 嘅「下一個鬧鐘」顯示預告時間（例如 08:00），
 * 而真鬧鐘係 09:00，等於每日向使用者謊報響鬧時間。系統鬧鐘指示器係使用者判斷
 * 「我幾點會被叫醒」嘅唯一權威來源，唔可以俾一個提示性通知污染。
 * 代價（Doze 下最多遲約 15 分鐘）已接受；真鬧鐘本身仍然走 `setAlarmClock`，不受影響。
 * 因為唔用 `setAlarmClock`，所以**冇** AlarmClockInfo、**冇** showIntent。
 */
object PreAlertScheduler {
    /** 預告 id 命名空間偏移。必須同 Dart `AlarmService.preAlertIdOffset` 一致。 */
    const val PRE_ALERT_ID_OFFSET = 900000

    /** 預告提前量（分鐘）。必須同 Dart `AlarmService.preAlertLeadMinutes` 一致。 */
    const val LEAD_MINUTES = 60

    /**
     * 預留欄位（P2-2「點擊通知跳該日」用），現階段**只寫入 extra 不消費**。
     *
     * 刻意**不**共用 [AlarmScheduler.EXTRA_DATE]（值 `"alarm_date"`）：
     * 兩者語意唔同（一個係預告要跳嘅日期、一個係真鬧鐘嘅日期），
     * 若日後有人把預告 Intent 誤交 [AlarmActivity]（例如共用一個 helper），
     * 共用 key 會令 AlarmActivity 讀到預告嘅日期而顯示錯誤嘅班次。
     * 呢個「刻意唔共用」寫喺度，免得下次「統一命名」嘅善意重構把它改掉。
     */
    const val EXTRA_PRE_ALERT_DATE = "pre_alert_date"

    /**
     * 鬧鐘**觸發**時刻（毫秒，`RTC_WAKEUP` 時基）。
     *
     * [PreAlertReceiver] 用佢做 `Notification.setWhen()`，配合
     * `setUsesChronometer(true)` + `setChronometerCountDown(true)` 就係狀態欄倒計時。
     *
     * ⚠️ 一定要傳真嘅 `triggerAtMillis`，**不准**喺 receiver 用
     * `System.currentTimeMillis() + LEAD_MILLIS` 反推：`setExactAndAllowWhileIdle`
     * 喺 Doze 下最多遲約 15 分鐘，反推出嚟嘅倒計時會比真鬧鐘遲 15 分鐘歸零，
     * 即係「倒數仲有 3 分鐘」嗰陣鬧鐘已經響咗——使用者最不能接受嘅錯。
     */
    const val EXTRA_TRIGGER_AT = "pre_alert_trigger_at"

    /** 註冊表 prefs 檔名（key "ids"，JSON int 陣列，內容係已偏移 id）。 */
    private const val PREFS_NAME = "shiftalarm_prealerts"
    private const val KEY_IDS = "ids"

    private const val LEAD_MILLIS = LEAD_MINUTES * 60_000L

    /**
     * 分支 2（已進入預告窗口）嘅派發延遲。
     *
     * 唔可以喺 `schedule()` 內直接 `notify`：本 object 嘅職責邊界係「只碰
     * AlarmManager 同 id 註冊表」，發通知一律經 [PreAlertReceiver]。所以用
     * `AlarmManager.set` 排一個 1 秒後嘅廣播，等 receiver 自己砌通知。
     *
     * 1 秒係取捨：太短（0）等同同步 notify，等於繞過職責邊界；太長會令
     * 「使用者開 App 後要等幾秒才見到倒計時」。
     */
    private const val IMMEDIATE_FIRE_DELAY_MILLIS = 1_000L

    /**
     * 唯一轉換點：鬧鐘 id → 預告 id。
     * 同時用作 AlarmManager 嘅 broadcast PendingIntent requestCode 與通知 id。
     */
    fun preAlertId(alarmId: Int): Int = alarmId + PRE_ALERT_ID_OFFSET

    /**
     * 排一條預告。三分支（v3.6.1 修訂）：
     *
     * | 條件 | 行為 |
     * |---|---|
     * | `triggerAtMillis <= now` | 已響過／過期 → `cancelNotification` 後 return |
     * | `leadAt <= now < triggerAtMillis` | **已進入 1 小時窗口** → `set(now + 1s)` 立刻派發倒計時 |
     * | `leadAt > now` | 正常 → `setExactAndAllowWhileIdle(leadAt)` |
     *
     * ⚠️ 分支 2 係 v3.6.1 補嘅。舊版把「已進入窗口」同「已過期」混為一談，
     * 一律 `cancelNotification` 後 return，造成兩個直接違反功能原意嘅缺陷：
     *  - 09:00 響、08:00 lead，使用者 08:30 開 App → `syncOnLaunch` 會親手
     *    殺掉**正在倒數 30 分鐘**嘅通知（畫面突然消失）。
     *  - 08:30 才排 09:00 嘅更 → 預告**永遠唔會出現**。
     *
     * 分支 2 用 `AlarmManager.set`，**唔用** `setExactAndAllowWhileIdle` 亦
     * **唔用** `setAlarmClock`：near-now 派發唔需要精確鬧鐘權限（避免
     * Android 12+ 未授權時靜默失敗），亦唔應該污染系統「下一個鬧鐘」指示器。
     *
     * @param triggerAtMillis 鬧鐘**觸發**時刻（唔係預告時刻），由呼叫方計好。
     *   分支 2 傳落 [PreAlertReceiver] 嘅仍然係呢個原值，倒計時數值才正確。
     */
    fun schedule(
        context: Context,
        alarmId: Int,
        triggerAtMillis: Long,
        title: String,
        body: String,
        date: String = "",
        shiftName: String = "",
        startTime: String = "",
        note: String = ""
    ) {
        val now = System.currentTimeMillis()
        val leadAt = triggerAtMillis - LEAD_MILLIS

        // ── 分支 1：已經響過／過期 ─────────────────────────────────────
        if (triggerAtMillis <= now) {
            // 真係過咗期：唔排、唔補發，順手清走殘留通知
            cancelNotification(context, alarmId)
            return
        }

        // 分支 2 / 3 嘅判別：是否已踏入 1 小時窗口
        val inWindow = leadAt <= now

        try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, PreAlertReceiver::class.java).apply {
                putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarmId)
                putExtra(AlarmScheduler.EXTRA_TITLE, title)
                putExtra(AlarmScheduler.EXTRA_BODY, body)
                // 倒計時終點：真鬧鐘觸發時刻（見 EXTRA_TRIGGER_AT KDoc）
                putExtra(EXTRA_TRIGGER_AT, triggerAtMillis)
                // 以下四個 extra 現階段**只寫不讀**（PreAlertReceiver 唔會讀），
                // 係 P2-2「點擊通知跳該日」嘅預留欄位——到時 PreAlertReceiver
                // 會用佢哋砌一條帶日期嘅 Intent 交 MainActivity。
                // ⚠️ 唔係死碼，唔好見到「寫咗但冇人讀」就刪：刪咗之後 P2-2
                // 要由 Dart 層重新打通整條解析鏈路（bridge → channel → intent）。
                putExtra(EXTRA_PRE_ALERT_DATE, date)
                putExtra(AlarmScheduler.EXTRA_SHIFT_NAME, shiftName)
                putExtra(AlarmScheduler.EXTRA_START_TIME, startTime)
                putExtra(AlarmScheduler.EXTRA_NOTE, note)
            }
            val pi = PendingIntent.getBroadcast(
                context,
                preAlertId(alarmId),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            if (inWindow) {
                // ── 分支 2：已進入窗口 → 立刻派發，唔取消 ──────────────
                // 用 set 而非 setExact*：near-now，唔需要精確鬧鐘權限，
                // 亦唔會污染系統「下一個鬧鐘」。
                am.set(
                    AlarmManager.RTC_WAKEUP,
                    now + IMMEDIATE_FIRE_DELAY_MILLIS,
                    pi
                )
            } else {
                // ── 分支 3：正常路徑，維持 v3.5 行為 ─────────────────
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP, leadAt, pi
                    )
                } else {
                    am.setExact(AlarmManager.RTC_WAKEUP, leadAt, pi)
                }
            }

            rememberId(context, preAlertId(alarmId))
            AlarmDebugLog.append(
                context,
                if (inWindow) {
                    "[PRE_ALERT_SCHED] id=$alarmId mode=immediate " +
                        "triggerAt=$triggerAtMillis"
                } else {
                    "[PRE_ALERT_SCHED] id=$alarmId mode=exact leadAt=$leadAt"
                }
            )
        } catch (_: Exception) {
            // Android 12+ 未授權精確鬧鐘會拋 SecurityException；任何異常嘅代價
            // 只可以係「冇預告」，絕不可以影響已經排好嘅真鬧鐘。
        }
    }

    /** 取消預告：PendingIntent + 通知一併清（對應 Dart cancelPreAlert）。 */
    fun cancel(context: Context, alarmId: Int) {
        val preId = preAlertId(alarmId)
        cancelAlarmById(context, preId)
        cancelNotification(context, alarmId)
        forgetId(context, preId)
    }

    /** 只清通知，唔動 AlarmManager（鬧鐘真正響嗰刻用）。 */
    fun cancelNotification(context: Context, alarmId: Int) {
        try {
            val nm = context.getSystemService(
                Context.NOTIFICATION_SERVICE
            ) as NotificationManager
            nm.cancel(preAlertId(alarmId))
        } catch (_: Exception) {
        }
    }

    /**
     * 全量重排：逐條 [schedule]，之後 [prune]。
     *
     * 每個元素各自獨立 try/catch——任何一條壞掉只記錄、唔中斷（T07-AC4）。
     *
     * `keep` 嘅條件係 `triggerAtMillis > now`，**唔係** `leadAt > now`：
     * 08:30 開 App 嗰陣，08:00 已經彈出、正掛喺通知欄嘅預告（鬧鐘 09:00 響）
     * 必須留喺 keep 裡面，否則會被誤殺。
     */
    fun rescheduleAll(context: Context, specs: List<Map<String, Any?>>) {
        val now = System.currentTimeMillis()
        val keep = mutableSetOf<Int>()
        for (spec in specs) {
            try {
                val alarmId = (spec["alarmId"] as? Number)?.toInt() ?: continue
                val triggerAtMillis =
                    (spec["triggerAtMillis"] as? Number)?.toLong() ?: continue
                val title = spec["title"] as? String ?: ""
                val body = spec["body"] as? String ?: ""
                val date = spec["date"] as? String ?: ""
                val shiftName = spec["shiftName"] as? String ?: ""
                val startTime = spec["startTime"] as? String ?: ""
                val note = spec["note"] as? String ?: ""
                if (triggerAtMillis > now) {
                    keep.add(preAlertId(alarmId))
                }
                schedule(
                    context, alarmId, triggerAtMillis, title, body,
                    date, shiftName, startTime, note
                )
            } catch (_: Exception) {
                // 單條壞掉唔影響其餘預告
            }
        }
        prune(context, keep)
    }

    /**
     * 註冊表對帳：把「上次有、今次冇」嘅預告 id 全部 cancel 掉。
     *
     * 契約（T07 驗收條件）：
     *  1. **幂等**——同一 `keepIds` 連續呼叫兩次，第二次唔會再 cancel 任何嘢，
     *     亦唔會改寫註冊表。
     *  2. **全程 try/catch**——SharedPreferences 壞檔、JSON 解析失敗、
     *     `nm.cancel` 拋錯、PendingIntent 失效，一律靜默，永不 crash。
     *  3. `keepIds` 必須包含「leadAt 已過但鬧鐘未響」嘅 id（由呼叫方保證）。
     */
    fun prune(context: Context, keepIds: Set<Int>) {
        try {
            val previous = readIds(context)
            for (staleId in previous - keepIds) {
                cancelAlarmById(context, staleId)
                try {
                    val nm = context.getSystemService(
                        Context.NOTIFICATION_SERVICE
                    ) as NotificationManager
                    nm.cancel(staleId)
                } catch (_: Exception) {
                }
            }
            // 只有真正有變化才寫回，保證幂等（第二次呼叫一個字都唔改）
            if (previous != keepIds) {
                writeIds(context, keepIds)
            }
        } catch (_: Exception) {
        }
    }

    /** 按**已偏移 id** 取消 AlarmManager 排程（prune 內部用）。 */
    private fun cancelAlarmById(context: Context, preId: Int) {
        try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            // PendingIntent 比對唔看 extras，所以唔帶 extras 都命中同一條
            val pi = PendingIntent.getBroadcast(
                context,
                preId,
                Intent(context, PreAlertReceiver::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            am.cancel(pi)
            pi.cancel()
        } catch (_: Exception) {
        }
    }

    private fun readIds(context: Context): Set<Int> {
        val out = mutableSetOf<Int>()
        try {
            val prefs = context.getSharedPreferences(
                PREFS_NAME, Context.MODE_PRIVATE
            )
            val raw = prefs.getString(KEY_IDS, null) ?: return out
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                // 用 optLong 而非 optInt：JSON 數字若被解析成 Long／Double，
                // optInt 會走 Number.intValue() 靜默截斷（不是回預設值），
                // 截斷後嘅 id 會變成另一條合法但錯誤嘅 id，反而更難查。
                // 先取 Long，再明確檢查落在 Int 正數範圍才收。
                val v = arr.optLong(i, -1L)
                if (v > 0L && v <= Int.MAX_VALUE.toLong()) out.add(v.toInt())
            }
        } catch (_: Exception) {
            // 壞檔當空註冊表，唔 crash
        }
        return out
    }

    private fun writeIds(context: Context, ids: Set<Int>) {
        try {
            val arr = JSONArray()
            for (id in ids.sorted()) arr.put(id)
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_IDS, arr.toString())
                .apply()
        } catch (_: Exception) {
        }
    }

    private fun rememberId(context: Context, preId: Int) {
        try {
            val ids = readIds(context).toMutableSet()
            if (ids.add(preId)) writeIds(context, ids)
        } catch (_: Exception) {
        }
    }

    private fun forgetId(context: Context, preId: Int) {
        try {
            val ids = readIds(context).toMutableSet()
            if (ids.remove(preId)) writeIds(context, ids)
        } catch (_: Exception) {
        }
    }
}
