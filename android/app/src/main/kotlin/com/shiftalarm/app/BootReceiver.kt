package com.shiftalarm.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * 開機後重排鬧鐘：直接讀 Flutter shared_preferences
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
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        Thread {
            try {
                reschedule(context)
            } catch (_: Exception) {
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
        try {
            scheduleAll(context, keepIds)
        } finally {
            // 重排完之後對帳：唔再存在嘅預告喺呢度清走
            // （例如使用者停用咗個鬧鐘之後關機，開機時就唔會再排佢）。
            // 注意 keepIds 收嘅係「鬧鐘未響」嘅 id，唔係「leadAt 未到」，
            // 否則會誤殺已經彈出、正掛喺通知欄嘅預告。
            PreAlertScheduler.prune(context, keepIds)
        }
    }

    /**
     * 逐個 assignment 重排鬧鐘同對應預告；[keepIds] 收集所有仲未響嘅預告 id。
     * 預告嘅時間同文案全部重用本檔已有嘅 [triggerMillisWithOffset] 與
     * [formatAlarmBody]，唔准另寫第三份。
     */
    private fun scheduleAll(context: Context, keepIds: MutableSet<Int>) {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        val defsRaw = prefs.getString("flutter.shift_defs", null) ?: return
        val assignRaw = prefs.getString("flutter.assignments", null) ?: return
        val defs = JSONObject(defsRaw)
        val assigns = JSONObject(assignRaw)
        val now = System.currentTimeMillis()

        val keys = assigns.keys()
        while (keys.hasNext()) {
            val ymd = keys.next() // "YYYY-MM-DD"
            // 兼容新舊兩種格式
            val rawVal = assigns.get(ymd)
            val shiftId: String
            var note = ""
            when (rawVal) {
                is String -> shiftId = rawVal
                is JSONObject -> {
                    shiftId = rawVal.optString("shiftId", null) ?: continue
                    note = rawVal.optString("note", "")
                }
                else -> continue
            }
            val def = defs.optJSONObject(shiftId) ?: continue
            val name = def.optString("name", "排班")
            val startTime = def.optString("startTime", null) ?: continue
            val endTime = def.optString("endTime", "")

            // 鬧鐘列表：新格式讀 alarms；舊格式由 advanceMinutes 遷移
            val alarms = mutableListOf<ParsedAlarm>()
            val arr: JSONArray? = def.optJSONArray("alarms")
            if (arr != null) {
                for (i in 0 until arr.length()) {
                    val a = arr.optJSONObject(i) ?: continue
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

            val baseId = ymd.replace("-", "").toIntOrNull() ?: continue
            for ((index, alarm) in alarms.withIndex()) {
                if (index >= 10) break
                if (!alarm.enabled) continue
                val triggerMillis =
                    triggerMillisWithOffset(ymd, startTime, alarm.offsetMinutes)
                        ?: continue
                if (triggerMillis <= now) continue
                val id = baseId * 10 + index
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
