package com.shiftalarm.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * 重排鬧鐘：直接讀 Flutter shared_preferences
 *（檔名 "FlutterSharedPreferences"，key 有 "flutter." 前綴）。
 * key "flutter.shift_defs": {"s06": {"name":..., "abbr":...,
 *   "startTime":"06:00", "endTime":"12:00",
 *   "alarms":[{"id":"a1","label":"開工鬧鐘","offsetMinutes":-60,
 *   "notificationOnly":false,"enabled":true}]}, ...}
 *   舊格式只有 "advanceMinutes"，兼容讀取。
 * key "flutter.assignments": {"2026-10-15": {"shiftId": "s06", "note": "A1"}, ...}
 *   舊格式 value 直接係 "s06" 字串，兼容讀取。
 *
 * 新制鬧鐘 id ＝ YYYYMMDD*10 + index（同 Dart AlarmService 一致）。
 *
 * 觸發時機（v3.6.2 起由一個放寬到四個，全部係「AlarmManager 排程已經冇咗，
 * 而用戶以為仲有」嘅情境）：
 *  - `BOOT_COMPLETED`：重開機，AlarmManager 排程全部清空。
 *  - `MY_PACKAGE_REPLACED`：**覆蓋安裝／Play Store 更新**。呢個係 v3.6.2 補
 *    嘅最重要一個：Android 更新 App 時會清走該 package 所有 AlarmManager
 *    排程（同 force-stop 一樣），以前冇聽呢個 broadcast，結果「更新完之後
 *    第二朝鬧鐘完全唔響，直到用戶手動開一次 App」。對鬧鐘 App 嚟講呢個係
 *    最傷嘅失敗模式——完全靜默、用戶唔會知，直到遲到。
 *  - `TIME_SET`：用戶手動改時間（換 SIM／維修後時鐘錯）。
 *  - `TIMEZONE_CHANGED`：跨時區（旅行）。`triggerAtMillis` 係絕對 UTC 毫秒，
 *    換時區之後同一個絕對時刻會對應另一個當地鐘點，要按新時區重算。
 *
 * ⚠️ manifest 寫嘅係 `android.intent.action.TIME_SET`，而 Java 常量
 * `Intent.ACTION_TIME_CHANGED` 嘅字串值就係 `"android.intent.action.TIME_SET"`
 * ——兩者係同一個字串，唔好以為寫錯。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // 白名單（v3.6.2）：以前係「唔係 BOOT_COMPLETED 就 return」嘅黑名單，
        // 加新 action 落 manifest 會被呢一行靜默擋死。改成白名單之後，日後
        // 再加 action 只需要改 manifest，唔會出現「filter 有但 onReceive 唔認」
        // 嘅半失效狀態。
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != Intent.ACTION_TIME_CHANGED &&
            action != Intent.ACTION_TIMEZONE_CHANGED
        ) {
            return
        }

        // goAsync()：`onReceive` 一 return，BroadcastReceiver 嘅生命週期就完，
        // 系統可以隨時回收 process。以前只係開一條裸 Thread 就 return，重排
        // 做到一半被殺就會「部分日子有鬧鐘、部分冇」，而用戶完全唔會知邊日缺。
        // goAsync() 令系統喺 finish() 之前唔會當呢個 broadcast 處理完。
        val pending = goAsync()
        Thread {
            try {
                reschedule(context)
            } catch (_: Exception) {
            } finally {
                // finish() 一定要喺 finally：漏咗就會拖住個 broadcast
                pending.finish()
            }
        }.start()
    }

    private data class ParsedAlarm(
        val label: String,
        val offsetMinutes: Int,
        val notificationOnly: Boolean,
        val enabled: Boolean
    )

    private fun reschedule(context: Context) {
        val keepIds = mutableSetOf<Int>()
        // completed：scheduleAll 回報嘅「keepIds 可唔可信」（＝資料數唔數得清，
        // 唔係「每一條都排到」；語義見 scheduleAll 嘅 KDoc 表），或者中途拋
        // 異常。
        //
        // 為什麼要呢個旗標：`keepIds` 嘅用途係「呢啲預告仍然有效，唔好清」。
        // 如果 keepIds 只係填到一半，PreAlertScheduler.prune 會把「註冊表有、
        // keepIds 冇」嘅 id 當 stale **主動 cancel**（連通知欄嗰條倒數都清走）。
        // 即係「做一半」會比「完全冇做」更差：用戶開機之後，未處理到嗰幾日
        // 嘅預告會全部消失。所以以前用 `finally` 無條件 prune 係錯嘅，
        // 改成「keepIds 可信才 prune」。
        val completed = try {
            scheduleAll(context, keepIds)
        } catch (_: Exception) {
            false
        }
        if (completed) {
            // 重排完之後對帳：唔再存在嘅預告喺呢度清走
            // （例如使用者停用咗個鬧鐘之後關機，開機時就唔會再排佢）。
            // 注意 keepIds 收嘅係「鬧鐘未響」嘅 id，唔係「leadAt 未到」，
            // 否則會誤殺已經彈出、正掛喺通知欄嘅預告。
            PreAlertScheduler.prune(context, keepIds)
        } else {
            AlarmDebugLog.append(
                context, "[BOOT_RESCHEDULE_SKIP_PRUNE] 重排未完整，今次唔對帳"
            )
        }
    }

    /**
     * 逐個 assignment 重排鬧鐘同對應預告；[keepIds] 收集所有仲未響嘅預告 id。
     * 預告嘅時間同文案全部重用本檔已有嘅 [triggerMillisWithOffset] 與
     * [formatAlarmBody]，唔准另寫第三份。
     *
     * @return `true` ＝ **資料完整讀完**（清單同結構都讀得通），`keepIds` 可信；
     *   `false` ＝ 資料唔完整（prefs 讀唔到／JSON 結構壞／`shiftId` 缺失／
     *   `ymd` 解析唔到／`alarms` 有條目唔係 object），呢個時候 `keepIds`
     *   唔可信，呼叫方**唔可以**用佢去 prune（見 [reschedule] 嘅 completed
     *   註釋）。
     *
     * ⚠️ **`dataOk` 嘅語義係「資料完整讀完」，唔係「每一條都排到」。**
     * 兩類跳過要嚴格分開，混埋一齊會出嚴重迴歸：
     *
     * | 類別 | 例子 | dataOk |
     * |---|---|---|
     * | **數唔清／對唔上 id** | prefs 讀唔到、JSON 結構壞、`shiftId` 缺失、`ymd` 解析唔到、`alarms` 有條目唔係 object | **false** |
     * | **數得清，只係唔應該排** | 鬧鐘停用、觸發時間已過、超過 10 個上限、**班次定義已刪**、`startTime` 缺失 | **唔影響** |
     *
     * 判別準則唔係「資料靚唔靚」，而係「**跳過呢一條之後，佢嘅 id 應唔應該
     * 繼續存在**」：數唔清＝我哋連應該有幾多個 id 都講唔出，keep 必然缺項，
     * prune 會誤殺；數得清＝我哋明確知道呢個 id 唔應該再排，正正應該由
     * prune 清走。
     *
     * 為什麼「業務性跳過」唔可以令 dataOk = false：**每一台真實裝置都會有
     * 已過期嘅鬧鐘**（昨日排的、今早已響的）。如果「時間已過」都當資料殘缺，
     * 後果係「只要用戶有一條過期鬧鐘，prune 就永遠唔會跑」——幽靈預告永遠
     * 清唔掉，而且比誤刪更難察覺（用戶唔會回報「清不到」，只會覺得有時多咗
     * 條怪通知）。呢個等於把「誤刪」換成「永遠清不到」。
     */
    private fun scheduleAll(
        context: Context,
        keepIds: MutableSet<Int>
    ): Boolean {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        // 呢兩個 return 係「殘缺」：連清單都讀唔到，後面嘅日子完全冇處理過。
        val defsRaw = prefs.getString("flutter.shift_defs", null) ?: return false
        val assignRaw =
            prefs.getString("flutter.assignments", null) ?: return false
        val defs = JSONObject(defsRaw)
        val assigns = JSONObject(assignRaw)
        val now = System.currentTimeMillis()

        // dataOk：資料完整性。只有「數唔清有幾多個 id／對唔上 id」才轉
        // false；「數得清、只係唔應該排」（停用／已過／超上限／班次定義
        // 已刪／startTime 缺失）一律唔准郁佢。判別準則見上面 KDoc 嘅表。
        var dataOk = true

        val keys = assigns.keys()
        while (keys.hasNext()) {
            val ymd = keys.next() // "YYYY-MM-DD"
            // 兼容新舊兩種格式
            val rawVal = assigns.get(ymd)
            var note = ""
            // 用 "" 做「冇有效 shiftId」嘅哨兵值，而唔用 null：
            // 一來 shiftId 本身唔可以係空字串（defs 嘅 key 一定非空），
            // 二來避免依賴「var 嘅 smart cast」呢類要靠編譯器推理嘅寫法，
            // 喺冇 SDK 可以試編譯嘅情況下，愈少隱含推理愈安全。
            val shiftId: String = when (rawVal) {
                is String -> rawVal
                is JSONObject -> {
                    note = rawVal.optString("note", "")
                    rawVal.optString("shiftId", "") ?: ""
                }
                else -> ""
            }
            if (shiftId.isEmpty()) {
                // 唔知呢日屬於邊個班次 → 呢日嘅預告 id 一定唔會入 keep。
                // 如果照 prune，就會把呢日嘅有效預告當 stale 刪走。
                dataOk = false
                continue
            }
            val def = defs.optJSONObject(shiftId)
            if (def == null) {
                // 班次定義唔存在 ＝ assignment 指向已刪班次（最常見成因：
                // 導入配置換走咗班次 id）。呢個**恰恰係幽靈嘅來源**，所以
                // 正確做法係「唔入 keep、但唔影響 dataOk」——下面嘅 prune
                // 就會把呢日嘅預告當 stale 清走。
                //
                // ⚠️ **唔可以設 dataOk = false**（v3.6.2 修正）。原因：
                // `ShiftStore.load()` 只係把孤兒由記憶體濾走，**唔會改寫
                // prefs**，所以 `flutter.assignments` 可能長期殘留孤兒條目。
                // 設 false 就等於「開機路徑嘅 prune 永久停擺」，幽靈永遠
                // 清唔掉——把「誤刪」換成「永遠清不到」，而後者更難察覺
                // （用戶只會覺得偶爾有條怪通知，唔會回報）。
                continue
            }
            val name = def.optString("name", "排班")
            val startTimeRaw = def.optString("startTime", null)
            if (startTimeRaw == null) {
                // 定義存在但核心欄位壞咗：id 數得清（baseId*10+index），
                // 只係算唔出時間，所以屬「業務性跳過」而唔係「數唔清」。
                // 同 def == null 一樣唔郁 dataOk，令呢日嘅預告可以被 prune
                // 清走（佢根本冇可能響）。
                AlarmDebugLog.append(
                    context, "[BOOT_SKIP_NO_START_TIME] shiftId=$shiftId ymd=$ymd"
                )
                continue
            }
            val startTime = startTimeRaw
            val endTime = def.optString("endTime", "")

            // 鬧鐘列表：新格式讀 alarms；舊格式由 advanceMinutes 遷移
            val alarms = mutableListOf<ParsedAlarm>()
            val arr: JSONArray? = def.optJSONArray("alarms")
            if (arr != null) {
                for (i in 0 until arr.length()) {
                    val a = arr.optJSONObject(i)
                    if (a == null) {
                        // 壞一條會令後面嘅 index 全部移位，同 Dart 側嘅
                        // `baseId * 10 + index` 對唔上 → 一定要標記殘缺。
                        dataOk = false
                        continue
                    }
                    alarms.add(
                        ParsedAlarm(
                            label = a.optString("label", "鬧鐘"),
                            offsetMinutes = a.optInt("offsetMinutes", -60),
                            notificationOnly =
                                a.optBoolean("notificationOnly", false),
                            enabled = a.optBoolean("enabled", true)
                        )
                    )
                }
            }
            if (alarms.isEmpty()) {
                val adv = def.optInt("advanceMinutes", 60)
                alarms.add(
                    ParsedAlarm("開工鬧鐘", -adv, false, true)
                )
            }

            val baseId = ymd.replace("-", "").toIntOrNull()
            if (baseId == null) {
                dataOk = false
                continue
            }
            for ((index, alarm) in alarms.withIndex()) {
                if (index >= 10) break
                val id = baseId * 10 + index
                // 唔應該再響嘅情況有**三種，但唔可以壓成同一個判斷**
                // （v3.6.2 修正）。三者嘅正確處理唔同：
                //
                //  1. 鬧鐘停用 → 主動 cancel。用戶明確表達唔想響。
                //  2. 計出嚟嘅時間已經過去（最常見：換時區／手動改時間之後，
                //     原本 07:00 嘅鬧鐘喺新時區已經變成過去）→ 主動 cancel。
                //     AlarmManager 對「觸發時間已過」嘅排程會**立即派發**，
                //     唔清走就會喺用戶改完時區嗰一刻無端端響一聲（而且係響
                //     一個已經過去嘅時間）。重開機路徑排程本身已清空，呢句
                //     係 no-op，冇副作用。
                //  3. **時間字串解析失敗 → 只 log，唔 cancel。** 舊排程係用
                //     上一個有效嘅 `startTime` 算出來，可能仍然正確；cancel
                //     就等於「鬧鐘永遠唔響」——對鬧鐘 App 嚟講「寧願響錯
                //     時間，都好過唔響」。而且呢條路徑每次 TIMEZONE_CHANGED
                //     ／TIME_SET 都會跑，一次資料損壞之後就會反覆主動拆走
                //     用戶嘅鬧鐘，仲要完全靜默。
                if (!alarm.enabled) {
                    AlarmScheduler.cancel(context, id)
                    AlarmScheduler.cancelGentleScheduleOnly(context, id)
                    continue
                }
                val triggerMillis = triggerMillisWithOffset(
                    ymd, startTime, alarm.offsetMinutes
                )
                if (triggerMillis == null) {
                    AlarmDebugLog.append(
                        context,
                        "[BOOT_SKIP_BAD_TIME] id=$id ymd=$ymd " +
                            "startTime=$startTime offset=${alarm.offsetMinutes}"
                    )
                    continue
                }
                if (triggerMillis <= now) {
                    AlarmScheduler.cancel(context, id)
                    AlarmScheduler.cancelGentleScheduleOnly(context, id)
                    continue
                }
                val title = "$name ${alarm.label}"
                val body = formatAlarmBody(
                    startTime,
                    endTime,
                    alarm.label,
                    alarm.offsetMinutes,
                    note
                )
                if (alarm.notificationOnly) {
                    AlarmScheduler.scheduleGentle(
                        context, id, triggerMillis, title, body
                    )
                } else {
                    AlarmScheduler.schedule(
                        context,
                        id,
                        triggerMillis,
                        title,
                        body,
                        accentBgFor(startTime),
                        AlarmScheduler.DEFAULT_ACCENT_FG,
                        name,
                        startTime,
                        ymd,
                        note
                    )
                }
                // 響鬧預告（第三條通道）：**只給真正的鬧鐘**（notificationOnly == false）。
                // 打卡開工／收工同使用者自建嘅「只通知」鬧鐘唔排預告——同 Dart
                // AlarmService.onAssigned / syncOnLaunch 兩處完全一致（v3.6.1 裁示）。
                // ⚠️ 呢度係原生獨立實作路徑，唔經 Dart；漏咗呢個 if，使用者一重開機
                // 打卡預告就會復活，而且同 App 內行為唔一致。
                if (!alarm.notificationOnly) {
                    keepIds.add(PreAlertScheduler.preAlertId(id))
                    PreAlertScheduler.schedule(
                        context,
                        id,
                        triggerMillis,
                        preAlertTitle(name, alarm.label),
                        preAlertBody(body),
                        ymd,
                        name,
                        startTime,
                        note
                    )
                }
            }
        }
        // 行到呢度 ＝ 整份清單都行過。但「行過」唔等於「數得清」——
        // 中途有 prefs 讀唔到／JSON 結構壞／`shiftId` 或 `ymd` 解析唔到／
        // `alarms` 條目唔係 object 嘅話，dataOk 已經係 false。
        // （班次定義已刪、startTime 缺失**唔會**令佢變 false，理由見 KDoc 表。）
        return dataOk
    }

    /**
     * 預告標題：「早更 開工鬧鐘」。
     *
     * 必須同 Dart `AlarmService.preAlertTitle` **逐字一致**。
     * ⚠️ 不准加「1 小時後：」之類嘅剩餘時間前綴：預告通知由 v3.6.1 起用
     * `setUsesChronometer(true)` 做狀態欄倒計時，剩餘時間由系統實時渲染；
     * 文案寫死「1 小時」會同倒計時顯示嘅數值互相矛盾。
     */
    private fun preAlertTitle(shiftName: String, label: String): String =
        "$shiftName $label"

    /**
     * 預告內文：直接回傳 `formatAlarmBody` 的輸出，唔加任何前綴。
     *
     * 必須同 Dart `AlarmService.preAlertBody` **逐字一致**。
     * 剩餘時間一律交由倒計時顯示，內文不准出現「仲有 N 小時響」。
     */
    private fun preAlertBody(alarmBody: String): String = alarmBody

    private fun formatAlarmBody(
        startTime: String,
        endTime: String,
        label: String,
        offsetMinutes: Int,
        note: String
    ): String {
        val triggerHhmm = formatTriggerHhmm(startTime, offsetMinutes)
        val venuePart = if (note.trim().isNotEmpty()) " · 地點：${note.trim()}" else ""
        val isClockOut = label.contains("收工") || label.contains("下班")
        val isClockIn = label.contains("開工打卡") || label.contains("上班打卡")

        if (isClockOut) {
            return "收工時間到了，記得打卡！ ($triggerHhmm)$venuePart"
        }
        if (isClockIn) {
            return "開工時間到了，記得打卡！ ($startTime)$venuePart"
        }
        val shiftRange = if (endTime.isNotEmpty()) "$startTime–$endTime" else startTime
        return "班次時間：$shiftRange$venuePart"
    }

    private fun formatTriggerHhmm(startTime: String, offsetMinutes: Int): String {
        val parts = startTime.split(":")
        val startMin = (parts.getOrNull(0)?.toIntOrNull() ?: 0) * 60 +
                (parts.getOrNull(1)?.toIntOrNull() ?: 0)
        var total = (startMin + offsetMinutes) % 1440
        if (total < 0) total += 1440
        val hh = (total / 60).toString().padStart(2, '0')
        val mm = (total % 60).toString().padStart(2, '0')
        return "$hh:$mm"
    }

    /** 按開工鐘點取時段 bg 色（同 Dart ShiftTokens.slotForTime 對應） */
    private fun accentBgFor(hhmm: String): Int {
        val hour = hhmm.split(":").firstOrNull()?.toIntOrNull() ?: 0
        return when {
            hour < 6 -> 0xFFFEF9C3.toInt() // 00–06 淺黃（同 app_theme 一致）
            hour < 12 -> 0xFFFDF2F8.toInt() // 06–12 極淺粉（同 app_theme 一致）
            hour < 18 -> 0xFFFBCFE8.toInt() // 12–18 粉紅（同 app_theme 一致）
            else -> 0xFFEDE9FE.toInt() // 18–00 淺紫（同 app_theme 一致）
        }
    }

    /** "YYYY-MM-DD" + "HH:mm" + offset分鐘 → epoch millis；解析失敗回 null */
    private fun triggerMillisWithOffset(
        ymd: String,
        hhmm: String,
        offsetMinutes: Int
    ): Long? {
        return try {
            val d = ymd.split("-").map { it.toInt() }
            val t = hhmm.split(":").map { it.toInt() }
            val cal = Calendar.getInstance()
            cal.set(d[0], d[1] - 1, d[2], t[0], t[1], 0)
            cal.set(Calendar.MILLISECOND, 0)
            cal.timeInMillis + offsetMinutes * 60_000L
        } catch (_: Exception) {
            null
        }
    }
}
