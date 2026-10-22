package com.shiftalarm.app

import android.content.Context
import org.json.JSONArray

/**
 * 鬧鐘 id 註冊表（三條通知通道共用）。
 *
 * 職責：記住「原生側而家幫邊幾個 id 排過 AlarmManager 排程」，令每次全量
 * 重排（Dart `rescheduleAll`）之後可以對帳——把「上次有、今次冇」嘅 id
 * 連 AlarmManager 排程一齊清走。
 *
 * 為什麼要有呢個 object：三條通道（全鬧鐘／只通知／響鬧預告）本來只有預告
 * 有註冊表，另外兩條係「只加不清」。結果係「Dart 側認為唔應該再存在」嘅 id
 * 會永遠留喺 AlarmManager，變成**幽靈鬧鐘**——喺用戶完全搵唔到（因為對應嘅
 * 排班已經刪咗）嘅時間突然全屏響，而且冇任何預告。所以把預告用開嘅機制抽成
 * 通用版，三條通道各自 remember／prune。
 *
 * 儲存格式：同一個 prefs 檔（沿用預告用開嘅 `shiftalarm_prealerts`），每個
 * 通道一個 key，value 係 JSON int 陣列（例如 `[202610150,202610151]`）。
 * 用 JSON 而唔用 `putStringSet`：預告嗰份由 v3.5 起已經係呢個格式，改格式
 * 要寫遷移程式碼，而呢個 object 嘅唯一目的係「唔好再各自為政」。
 *
 * ⚠️ [KEY_PRE_ALERT] 嘅值**必須維持 `"ids"`**。呢個 key 由 v3.5 起已經喺
 * 用戶機上寫住現存預告 id。搬 key 等於開一張空註冊表，而下一次 `prune` 會
 * 把「註冊表有、keep 冇」嘅 id 當 stale 一次過 cancel——即係所有現存預告
 * （連通知欄嗰條倒數）喺升級後第一次開 App 就消失。新增通道只可以開新 key。
 */
object AlarmIdRegistry {
    /**
     * 註冊表 prefs 檔名。
     *
     * ⚠️ **字串值唔准改**（同 [KEY_PRE_ALERT] 同一個理由）：呢個係用戶機上
     * 現存嘅檔名，改咗就等於開一張空註冊表，下一次 prune 會把現存 id 當
     * stale 一次過 cancel。
     *
     * 另：[PreAlertScheduler] 喺同一個檔存「已 dismiss」記錄，但佢刻意寫
     * 自己嘅字面值而唔引用呢個常量（避免再多一條跨檔依賴）。兩處必須
     * 逐字一致，改任何一邊都要改另一邊。
     */
    internal const val PREFS_NAME = "shiftalarm_prealerts"

    /** 響鬧預告（v3.5 起沿用，**唔准改**，理由見檔頭）。 */
    const val KEY_PRE_ALERT = "ids"

    /** 全鬧鐘：`AlarmScheduler.schedule` → [AlarmReceiver]。 */
    const val KEY_FULL = "ids_full"

    /** 只通知：`AlarmScheduler.scheduleGentle` → [GentleAlarmReceiver]。 */
    const val KEY_GENTLE = "ids_gentle"

    /**
     * 讀某條通道嘅已排 id。
     *
     * 用 `optLong` 而非 `optInt`：JSON 數字若被解析成 Long／Double，
     * `optInt` 會走 `Number.intValue()` 靜默截斷（**唔係**回預設值），
     * 截斷後嘅 id 會變成另一條合法但錯誤嘅 id，反而更難查。先取 Long，
     * 再明確檢查落在 Int 正數範圍才收。
     */
    fun readIds(context: Context, key: String): Set<Int> {
        val out = mutableSetOf<Int>()
        try {
            val prefs = context.getSharedPreferences(
                PREFS_NAME, Context.MODE_PRIVATE
            )
            val raw = prefs.getString(key, null) ?: return out
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val v = arr.optLong(i, -1L)
                if (v > 0L && v <= Int.MAX_VALUE.toLong()) out.add(v.toInt())
            }
        } catch (_: Exception) {
            // 壞檔當空註冊表，唔 crash
        }
        return out
    }

    /**
     * 覆寫某條通道嘅已排 id。
     *
     * 內容同現存值一樣就唔寫：`apply()` 會排一筆 disk I/O，而
     * `rescheduleAll` 每次冷啟動都會跑一次，冇變化嘅寫入純屬浪費
     * （亦令 [prune] 嘅「幂等」契約更容易守住）。
     */
    fun writeIds(context: Context, key: String, ids: Set<Int>) {
        try {
            val arr = JSONArray()
            for (id in ids.sorted()) arr.put(id)
            val raw = arr.toString()
            val prefs = context.getSharedPreferences(
                PREFS_NAME, Context.MODE_PRIVATE
            )
            if (prefs.getString(key, null) == raw) return
            prefs.edit().putString(key, raw).apply()
        } catch (_: Exception) {
        }
    }

    /** 記住一個 id（已經喺註冊表就乜都唔做，唔會白寫一次）。 */
    fun remember(context: Context, key: String, id: Int) {
        try {
            val ids = readIds(context, key).toMutableSet()
            if (ids.add(id)) writeIds(context, key, ids)
        } catch (_: Exception) {
        }
    }

    /**
     * 唔再追蹤一個 id。
     *
     * 用喺「呢個 id 已經唔再係排班鬧鐘」嘅時刻——例如用戶㩒咗停止、
     * 或者貪睡把原本嗰條鬧鐘改成一個 5 分鐘後嘅一次性計時器。
     */
    fun forgetId(context: Context, key: String, id: Int) {
        try {
            val ids = readIds(context, key).toMutableSet()
            if (ids.remove(id)) writeIds(context, key, ids)
        } catch (_: Exception) {
        }
    }

    /**
     * 對帳：把「上次有、今次冇」嘅 id 逐個交 [onStale] 處理。
     *
     * 契約：
     *  1. **幂等**——同一 [keepIds] 連續呼叫兩次，第二次唔會再 cancel 任何嘢，
     *     亦唔會改寫註冊表。
     *  2. **全程 try/catch**——SharedPreferences 壞檔、JSON 解析失敗、
     *     [onStale] 拋錯，一律靜默，永不 crash。
     *  3. [keepIds] 嘅語意由呼叫方定義（預告用「鬧鐘未響」，全鬧鐘／只通知
     *     用「今次完整清單」），本 object 唔作任何假設。
     *
     * ⚠️ 呼叫方**只可以喺「今次真係完整處理完」嘅情況**才叫呢個方法。
     * 殘缺嘅 [keepIds] 會令本方法主動 cancel 一批本來有效嘅排程——代價係
     * 「鬧鐘唔響」，比「留低幽靈」嚴重得多。寧願唔清，等下一個完整週期。
     */
    fun prune(
        context: Context,
        key: String,
        keepIds: Set<Int>,
        onStale: (Int) -> Unit
    ) {
        try {
            val previous = readIds(context, key)
            for (staleId in previous - keepIds) {
                try {
                    onStale(staleId)
                } catch (_: Exception) {
                    // 單條清唔到唔影響其餘
                }
            }
            // 只有真正有變化才寫回，保證幂等（第二次呼叫一個字都唔改）
            if (previous != keepIds) {
                writeIds(context, key, keepIds)
            }
        } catch (_: Exception) {
        }
    }
}
