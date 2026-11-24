package com.shiftalarm.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * 開機／覆蓋更新／改時區後的原生鬧鐘重建引擎。
 *
 * 直接讀取 Flutter `shared_preferences`（檔名 `"FlutterSharedPreferences"`），
 * 依與 Dart `AlarmService` 完全一致的 id 公式（`YYYYMMDD * 10 + index`）與文案規格重建排程。
 */
object BootRescheduler {
    private data class ParsedAlarm(
        val label: String,
        val offsetMinutes: Int,
        val notificationOnly: Boolean,
        val enabled: Boolean
    )

    fun reschedule(context: Context) {
        val keepIds = mutableSetOf<Int>()
        val completed = try {
            scheduleAll(context, keepIds)
        } catch (_: Exception) {
            false
        }
        if (completed) {
            PreAlertScheduler.prune(context, keepIds)
        } else {
            AlarmDebugLog.append(
                context, "[BOOT_RESCHEDULE_SKIP_PRUNE] 重排未完整，今次不對帳"
            )
        }
    }

    /**
     * 逐筆重排所有排班鬧鐘與響鬧預告，並把所有尚未響起的預告 id 收集入 [keepIds]。
     *
     * 回傳 `true` 表示資料結構完整可信，可安全執行 [PreAlertScheduler.prune]；
     * 若清單或結構損壞導致無法點齊應保留的 id，則回傳 `false` 以跳過清理避免誤殺。
     */
    private fun scheduleAll(
        context: Context,
        keepIds: MutableSet<Int>
    ): Boolean {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        val defsRaw = prefs.getString("flutter.shift_defs", null) ?: return false
        val assignRaw = prefs.getString("flutter.assignments", null) ?: return false
        val defs = JSONObject(defsRaw)
        val assigns = JSONObject(assignRaw)
        val now = System.currentTimeMillis()
        var dataOk = true

        val keys = assigns.keys()
        while (keys.hasNext()) {
            val ymd = keys.next()
            val rawVal = assigns.get(ymd)
            var note = ""
            val shiftId: String = when (rawVal) {
                is String -> rawVal
                is JSONObject -> {
                    note = rawVal.optString("note", "")
                    rawVal.optString("shiftId", "") ?: ""
                }
                else -> ""
            }
            if (shiftId.isEmpty()) {
                dataOk = false
                continue
            }
            val def = defs.optJSONObject(shiftId) ?: continue
            if (shiftId == "__leave__" || def.optBoolean("isLeave", false)) {
                continue
            }
            val name = def.optString("name", "排班")
            if (!def.has("startTime") || def.isNull("startTime")) {
                AlarmDebugLog.append(
                    context, "[BOOT_SKIP_NO_START_TIME] shiftId=$shiftId ymd=$ymd"
                )
                continue
            }
            val startTime = def.optString("startTime", "")
            if (startTime.isEmpty()) {
                AlarmDebugLog.append(
                    context, "[BOOT_SKIP_NO_START_TIME] shiftId=$shiftId ymd=$ymd"
                )
                continue
            }
            val endTime = def.optString("endTime", "")

            val (alarms, alarmsOk) = parseShiftAlarms(def)
            if (!alarmsOk) dataOk = false

            val baseId = ymd.replace("-", "").toIntOrNull()
            if (baseId == null) {
                dataOk = false
                continue
            }

            val accentBg = accentBgFor(startTime)
            val accentFg = accentFgFor(startTime)

            for ((index, alarm) in alarms.withIndex()) {
                if (index >= 10) break
                val id = baseId * 10 + index
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
                    startTime, endTime, alarm.label, alarm.offsetMinutes, note
                )
                if (alarm.notificationOnly) {
                    AlarmScheduler.scheduleGentle(
                        context, id, triggerMillis, title, body
                    )
                } else {
                    AlarmScheduler.schedule(
                        context, id, triggerMillis, title, body,
                        accentBg, accentFg, name, startTime, ymd, note
                    )
                    keepIds.add(PreAlertScheduler.preAlertId(id))
                    PreAlertScheduler.schedule(
                        context, id, triggerMillis,
                        preAlertTitle(name, alarm.label),
                        preAlertBody(body),
                        ymd, name, startTime, note
                    )
                }
            }
        }
        return dataOk
    }

    private fun parseShiftAlarms(def: JSONObject): Pair<List<ParsedAlarm>, Boolean> {
        val alarms = mutableListOf<ParsedAlarm>()
        var ok = true
        val arr: JSONArray? = def.optJSONArray("alarms")
        if (arr != null) {
            for (i in 0 until arr.length()) {
                val a = arr.optJSONObject(i)
                if (a == null) {
                    ok = false
                    continue
                }
                alarms.add(
                    ParsedAlarm(
                        label = a.optString("label", "鬧鐘"),
                        offsetMinutes = a.optInt("offsetMinutes", -60),
                        notificationOnly = a.optBoolean("notificationOnly", false),
                        enabled = a.optBoolean("enabled", true)
                    )
                )
            }
        }
        if (alarms.isEmpty()) {
            val adv = def.optInt("advanceMinutes", 60)
            alarms.add(ParsedAlarm("開工鬧鐘", -adv, false, true))
        }
        return alarms to ok
    }

    private fun preAlertTitle(shiftName: String, label: String): String =
        "$shiftName $label"

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

        if (isClockOut) return "收工時間到了，記得打卡！ ($triggerHhmm)$venuePart"
        if (isClockIn) return "開工時間到了，記得打卡！ ($startTime)$venuePart"
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

    private fun accentBgFor(hhmm: String): Int {
        val hour = hhmm.split(":").firstOrNull()?.toIntOrNull() ?: 0
        return when {
            hour < 6 -> 0xFFFEF9C3.toInt()
            hour < 12 -> 0xFFFDF2F8.toInt()
            hour < 18 -> 0xFFFBCFE8.toInt()
            else -> 0xFFEDE9FE.toInt()
        }
    }

    private fun accentFgFor(hhmm: String): Int {
        val hour = hhmm.split(":").firstOrNull()?.toIntOrNull() ?: 0
        return when {
            hour < 6 -> 0xFF854D0E.toInt()
            hour < 12 -> 0xFF9D174D.toInt()
            hour < 18 -> 0xFF831843.toInt()
            else -> 0xFF5B21B6.toInt()
        }
    }

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
