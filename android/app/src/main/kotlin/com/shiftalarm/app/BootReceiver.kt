package com.shiftalarm.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 系統廣播接收器：於開機、覆蓋安裝更新、系統時間或時區變更時，
 * 透過 `goAsync()` 在背景線程委派 [BootRescheduler] 完整重建鬧鐘與預告排程。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != Intent.ACTION_TIME_CHANGED &&
            action != Intent.ACTION_TIMEZONE_CHANGED
        ) {
            return
        }

        val pending = goAsync()
        Thread {
            try {
                BootRescheduler.reschedule(context)
            } catch (_: Exception) {
            } finally {
                pending.finish()
            }
        }.start()
    }
}
