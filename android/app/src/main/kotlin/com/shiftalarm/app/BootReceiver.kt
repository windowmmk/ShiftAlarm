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
            val noteSuffix = if (note.isNotEmpty()) " · $note" else ""
            for ((index, alarm) in alarms.withIndex()) {
                if (index >= 10) break
                if (!alarm.enabled) continue
                val triggerMillis =
                    triggerMillisWithOffset(ymd, startTime, alarm.offsetMinutes)
                        ?: continue
                if (triggerMillis <= now) continue
                val id = baseId * 10 + index
                val title = "$name ${alarm.label}"
                val body = "$ymd ${startTime}開工" +
                    "（${offsetText(alarm.offsetMinutes)}）${noteSuffix}"
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
            }
        }
    }

    private fun offsetText(offsetMinutes: Int): String = when {
        offsetMinutes < 0 -> "提前${-offsetMinutes}分鐘"
        offsetMinutes > 0 -> "延後${offsetMinutes}分鐘"
        else -> "準時"
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
