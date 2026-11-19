package com.shiftalarm.app

import android.content.Context
import org.json.JSONObject

/**
 * 響鬧預告「已關閉（dismissed）」狀態持久化儲存。
 *
 * 以 `triggerAtMillis` 作為版本號（`{"<preAlertId>": <triggerAtMillis>}`），
 * 防止使用者關閉倒計時後因 App 重啟而復活，同時確保下次新鬧鐘正常觸發。
 */
object PreAlertDismissStore {
    /** 必須與 [AlarmIdRegistry.PREFS_NAME] 維持相同檔名以相容既有使用者資料。 */
    private const val PREFS_NAME = "shiftalarm_prealerts"
    private const val KEY_DISMISSED = "dismissed"

    fun markDismissed(context: Context, preAlertId: Int, alarmId: Int, triggerAtMillis: Long) {
        if (triggerAtMillis <= 0L) return
        try {
            val map = readDismissed(context)
            if (map[preAlertId] == triggerAtMillis) return
            map[preAlertId] = triggerAtMillis
            writeDismissed(context, map)
            AlarmDebugLog.append(
                context,
                "[PRE_ALERT_DISMISSED] id=$alarmId triggerAt=$triggerAtMillis"
            )
        } catch (_: Exception) {
        }
    }

    fun isDismissed(context: Context, preAlertId: Int, triggerAtMillis: Long): Boolean {
        return try {
            readDismissed(context)[preAlertId] == triggerAtMillis
        } catch (_: Exception) {
            false
        }
    }

    private fun readDismissed(context: Context): MutableMap<Int, Long> {
        val out = mutableMapOf<Int, Long>()
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY_DISMISSED, null) ?: return out
            val obj = JSONObject(raw)
            val now = System.currentTimeMillis()
            val it = obj.keys()
            while (it.hasNext()) {
                val k = it.next()
                val id = k.toIntOrNull() ?: continue
                val v = obj.optLong(k, 0L)
                if (v > now) out[id] = v
            }
        } catch (_: Exception) {
        }
        return out
    }

    private fun writeDismissed(context: Context, map: Map<Int, Long>) {
        try {
            val obj = JSONObject()
            for ((id, ts) in map) obj.put(id.toString(), ts)
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_DISMISSED, obj.toString())
                .apply()
        } catch (_: Exception) {
        }
    }
}
