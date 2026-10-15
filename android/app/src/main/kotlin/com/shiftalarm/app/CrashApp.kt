package com.shiftalarm.app

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 自訂 Application：註冊全域未捕捉異常處理器。
 * 原生層 crash 嗰陣，將 stack trace＋時間戳 append 去 filesDir/crash.log
 * （最多留最後 50 則），然後交返畀原本嘅 default handler——唔吞 crash，
 * 系統照樣彈「應用程式已停止」。
 */
class CrashApp : Application() {

    override fun onCreate() {
        super.onCreate()
        val prev = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, e ->
            try {
                appendCrashLog(e)
            } catch (_: Exception) {
                // 寫 log 失敗都唔可以阻住原本嘅 crash 流程
            }
            try {
                prev?.uncaughtException(thread, e)
            } catch (_: Exception) {
            }
        }
        // 前台追蹤：亮屏使用中 fullScreenIntent 只出 heads-up，
        // 要全屏必須 App 在前台時直接 startActivity。
        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) {
                resumedCount++
                isForeground = true
            }

            override fun onActivityPaused(activity: Activity) {
                resumedCount = (resumedCount - 1).coerceAtLeast(0)
                isForeground = resumedCount > 0
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })
    }

    private fun appendCrashLog(e: Throwable) {
        val f = File(filesDir, "crash.log")
        val ts = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            .format(Date())
        val entry = "[$ts] ${e.javaClass.name}: ${e.message}\n" +
            Log.getStackTraceString(e)
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
    }

    companion object {
        const val MAX_ENTRIES = 50

        /** App 係咪在前台（有 resumed 嘅 activity） */
        @Volatile
        var isForeground: Boolean = false
            private set

        @Volatile
        private var resumedCount: Int = 0
    }
}
