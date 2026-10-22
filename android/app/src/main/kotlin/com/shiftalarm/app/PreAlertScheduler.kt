package com.shiftalarm.app

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONObject

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

    /**
     * 註冊表 key（＝ [AlarmIdRegistry.KEY_PRE_ALERT] ＝ `"ids"`）。
     *
     * v3.6.2 起註冊表嘅讀寫搬去 [AlarmIdRegistry]，令全鬧鐘／只通知兩條
     * 通道可以共用同一套 remember／prune（見 [AlarmScheduler.cancelAllExcept]）。
     * 呢個 key 嘅**字串值唔准改**，理由寫喺 [AlarmIdRegistry] 檔頭。
     */
    private const val KEY_IDS = AlarmIdRegistry.KEY_PRE_ALERT

    /**
     * 「已 dismiss」記錄嘅 key。同一個 prefs 檔，value 係 JSON 物件
     * `{"<preAlertId>": <triggerAtMillis>}`。
     *
     * 為什麼要有呢份記錄（v3.6.2 修）：使用者喺通知欄㩒「知道了」或者掃走
     * 條倒計時之後，以前只係 `nm.cancel`——**冇任何狀態**。於是任何一次
     * `syncOnLaunch` / `onAssigned` / 重開機，只要 `triggerAtMillis` 仍在未來，
     * `schedule()` 就會再 `notify` 一次，通知喺幾分鐘後自己復活。使用者明確
     * 表達咗「唔想再見到」，App 卻再彈，屬信任問題。
     *
     * ⚠️ 版本號一定要用 `triggerAtMillis`，**唔可以**用 `alarmId` 單獨做 key：
     * 咁樣會變成永久靜音——今日 09:00 㩒過「知道了」，明日同一 index 嘅預告
     * 永遠唔再出現。用 triggerAtMillis 做版本號，同一個 index 嘅下一次鬧鐘
     * 時間唔同，記錄自動失效；使用者改班次時間令 triggerAt 改變，舊記錄亦
     * 自動失效。
     */
    private const val KEY_DISMISSED = "dismissed"

    /**
     * dismissed 記錄所用嘅 prefs 檔名。
     *
     * ⚠️ **必須同 [AlarmIdRegistry.PREFS_NAME] 逐字一致**（`"shiftalarm_prealerts"`）。
     * 兩者唔一致嘅後果係：dismiss 記錄寫入另一個檔，`schedule()` 永遠讀唔到，
     * 通知照樣復活——而且完全靜默，冇任何錯誤訊息。
     *
     * 為什麼唔直接引用 `AlarmIdRegistry.PREFS_NAME`（明明係同一個模組、
     * 引用得到）：呢個檔已經有一條跨檔 `const val` 依賴（`KEY_IDS` ＝
     * `AlarmIdRegistry.KEY_PRE_ALERT`），再加一條就等於把「預告通道嘅儲存
     * 佈局」同 `AlarmIdRegistry` 嘅內部細節綁得更死。呢個字串由 v3.5 起就係
     * 用戶機上嘅實際檔名，**永遠唔會改**，所以直接寫字面值＋呢段警告，比
     * 多一條隱形耦合更實在。
     */
    private const val PREFS_NAME = "shiftalarm_prealerts"

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
     * 排一條預告。四分支（v3.6.2 加入分支 0）：
     *
     * | 條件 | 行為 |
     * |---|---|
     * | `dismissed[preAlertId] == triggerAtMillis` | **使用者已 dismiss 過呢一次** → 直接 return（唔排、唔 notify） |
     * | `triggerAtMillis <= now` | 已響過／過期 → `cancelNotification` 後 return |
     * | `leadAt <= now < triggerAtMillis` | **已進入 1 小時窗口** → `set(now + 1s)` 立刻派發倒計時 |
     * | `leadAt > now` | 正常 → `setExactAndAllowWhileIdle(leadAt)` |
     *
     * ⚠️ 分支 0 一定要排喺最前，連分支 3 都要受保護——理由見下面 `schedule()`
     * 開頭嘅註釋。
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

        // ── 分支 0：使用者已經明確 dismiss 過「呢一次」 ────────────────
        // 必須放喺**所有分支之前**（包括分支 3 嘅正常 setExact）。如果只保護
        // 分支 2，「㩒知道了 → 改班次時間 → 重排 → 分支 3 照排 → 一小時後
        // 又彈」會由另一個入口復發，同一個病換個入口。
        //
        // 防線一定要放喺 `schedule()` 內部而唔係呼叫端：
        // `PreAlertScheduler.schedule` 有三個入口——[BootReceiver] 開機重建、
        // `MainActivity` 嘅 `schedulePreAlert`、`MainActivity` 嘅 `rescheduleAll`
        // 內部迴圈。任何一個漏咗就破功，而開機重建係最容易被漏嗰個。
        //
        // 版本號用 `triggerAtMillis`（見 [KEY_DISMISSED] 嘅 KDoc）：記錄存在
        // 但數值唔同 ＝ 呢個係「另一次」鬧鐘，照樣要彈。
        if (isDismissed(context, preAlertId(alarmId), triggerAtMillis)) {
            return
        }

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
        } catch (e: Exception) {
            // Android 12+ 未授權精確鬧鐘會拋 SecurityException；任何異常嘅代價
            // 只可以係「冇預告」，絕不可以影響已經排好嘅真鬧鐘。
            //
            // ⚠️ 但唔可以**零痕跡**（v3.6.2 修）：Android 14 起，targetSdk 33+
            // 嘅新安裝唔再預授 SCHEDULE_EXACT_ALARM，呢個 catch 會變成新用戶
            // 嘅常態路徑。以前靜靜吞掉，結果係「預告由頭到尾冇出現過、App 內
            // 零提示、crash.log 零記錄」，連 QA 都驗唔出。至少留一行 log，
            // 令「權限自檢 → 當機紀錄」睇得到真正原因。
            AlarmDebugLog.append(
                context, "[PRE_ALERT_FAIL] id=$alarmId $e"
            )
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
        AlarmIdRegistry.prune(context, KEY_IDS, keepIds) { staleId ->
            cancelAlarmById(context, staleId)
            // 預告嘅通知 id 就係已偏移 id，所以呢度 cancel 嘅係通知欄嗰條倒數。
            // ⚠️ 唔可以照抄呢句去全鬧鐘／只通知兩條通道：佢哋嘅通知可能
            // 正响緊，拆走就等於拆走用戶嘅「停止」掣（見
            // [AlarmScheduler.cancelAllExcept] 嘅 KDoc）。
            try {
                val nm = context.getSystemService(
                    Context.NOTIFICATION_SERVICE
                ) as NotificationManager
                nm.cancel(staleId)
            } catch (_: Exception) {
            }
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

    /**
     * 以下兩個係 [AlarmIdRegistry] 嘅薄轉接層。
     *
     * 保留（而唔係喺呼叫點直接寫 `AlarmIdRegistry.xxx(context, KEY_IDS, …)`）
     * 嘅理由：預告通道嘅 id 語意（「已偏移 id」）只有本檔知，把 `KEY_IDS`
     * 收喺呢度可以保證「預告永遠只會寫預告嗰條 key」，唔會有人手快寫錯
     * 隔籬通道而令對帳互相踩。
     */
    private fun rememberId(context: Context, preId: Int) {
        AlarmIdRegistry.remember(context, KEY_IDS, preId)
    }

    private fun forgetId(context: Context, preId: Int) {
        AlarmIdRegistry.forgetId(context, KEY_IDS, preId)
    }

    // ─────────────────────────────────────────────────────────────────
    // 「已 dismiss」記錄（分支 0）
    // ─────────────────────────────────────────────────────────────────

    /**
     * 記住「呢一次預告已經被使用者 dismiss」。
     *
     * 由 [PreAlertReceiver] 喺兩處呼叫：㩒「知道了」action、以及通知被使用者
     * 掃走（`deleteIntent`）。兩者都係「使用者明確表達唔想再見到」。
     *
     * @param triggerAtMillis 呢一次預告對應嘅**鬧鐘觸發時刻**，同時做版本號。
     *   傳 0 或者負數（例如升級前舊 PendingIntent 冇帶呢個 extra）就乜都唔寫
     *   ——寧願漏記一次，都唔可以寫入一個錯誤版本號而令真正嘅下一次預告被
     *   永久靜音。
     */
    fun markDismissed(context: Context, alarmId: Int, triggerAtMillis: Long) {
        if (triggerAtMillis <= 0L) return
        try {
            val preId = preAlertId(alarmId)
            val map = readDismissed(context)
            if (map[preId] == triggerAtMillis) return
            map[preId] = triggerAtMillis
            writeDismissed(context, map)
            AlarmDebugLog.append(
                context,
                "[PRE_ALERT_DISMISSED] id=$alarmId triggerAt=$triggerAtMillis"
            )
        } catch (_: Exception) {
        }
    }

    /**
     * 呢一次預告係咪已經被 dismiss。
     *
     * ⚠️ 比較嘅係**數值**，唔係「key 存在」。記錄存在但 `triggerAtMillis`
     * 唔同 ＝ 呢個係同一個 index 嘅「另一次」鬧鐘（例如明日 09:00，或者
     * 使用者改咗班次時間），必須照樣派發。
     */
    private fun isDismissed(
        context: Context,
        preId: Int,
        triggerAtMillis: Long
    ): Boolean {
        return try {
            readDismissed(context)[preId] == triggerAtMillis
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 讀 dismissed 記錄，順手清走「觸發時刻已經過去」嘅條目。
     *
     * 清走係必要嘅：記錄嘅用途只係「阻止一條未響嘅預告復活」，一旦鬧鐘響過
     * （`triggerAtMillis` 已過去），呢條記錄永遠唔會再被查，留住只會令 prefs
     * 無限膨脹。清走之後記錄數量嘅上界 ＝ 未來預告嘅數量。
     */
    private fun readDismissed(context: Context): MutableMap<Int, Long> {
        val out = mutableMapOf<Int, Long>()
        try {
            val prefs = context.getSharedPreferences(
                PREFS_NAME, Context.MODE_PRIVATE
            )
            val raw = prefs.getString(KEY_DISMISSED, null) ?: return out
            val obj = JSONObject(raw)
            val now = System.currentTimeMillis()
            val it = obj.keys()
            while (it.hasNext()) {
                val k = it.next()
                // key 係 preAlertId（正數 Int）。解析唔到就當壞條目跳過。
                val id = k.toIntOrNull() ?: continue
                // 用 optLong 而非 optInt，理由同 AlarmIdRegistry.readIds：
                // optInt 會靜默截斷成另一個合法但錯誤嘅數值。
                val v = obj.optLong(k, 0L)
                if (v > now) out[id] = v
            }
        } catch (_: Exception) {
            // 壞檔當「冇人 dismiss 過」——最壞情況係通知多彈一次，
            // 遠比「全部預告永久靜音」安全。
        }
        return out
    }

    private fun writeDismissed(context: Context, map: Map<Int, Long>) {
        try {
            val obj = JSONObject()
            // obj.put(String, Long) 係明確多載，唔會把 Long 誤當 Object 而
            // 序列化成字串——dismissed 嘅值一定要係 JSON 數字，
            // readDismissed 嘅 `optLong` 才讀得返。
            for ((id, ts) in map) obj.put(id.toString(), ts)
            context.getSharedPreferences(
                PREFS_NAME, Context.MODE_PRIVATE
            ).edit().putString(KEY_DISMISSED, obj.toString()).apply()
        } catch (_: Exception) {
        }
    }
}
