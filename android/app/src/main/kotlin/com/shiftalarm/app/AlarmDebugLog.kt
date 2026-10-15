package com.shiftalarm.app

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 鬧鐘診斷 log：寫入 filesDir/crash.log（同「當機紀錄」同一個檔、
 * 同一個 viewer 睇到），格式同 CrashApp 一致（\n---\n 分隔、50 則上限）。
 * 唔掟異常——寫唔到就靜靜算。
 */
object AlarmDebugLog {
    private const val MAX_ENTRIES = 50

    fun append(context: Context, line: String) {
        try {
            val f = File(context.filesDir, "crash.log")
            val ts = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                .format(Date())
            val entry = "[$ts] $line"
            val existing = try {
                if (f.exists()) f.readText() else ""
            } catch (_: Exception) {
                ""
            }
            val parts = existing.split("\n---\n")
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .toMutableList()
            parts.add(entry.trim())
            val kept = parts.takeLast(MAX_ENTRIES)
            f.writeText(kept.joinToString("\n---\n") + "\n---\n")
        } catch (_: Exception) {
            // 診斷 log 唔可以影響主流程
        }
    }
}
