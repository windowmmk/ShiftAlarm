package com.shiftalarm.app

import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

/**
 * Android 系統權限查詢與設定頁跳轉工具（供 MethodChannel 與權限自檢頁使用）。
 */
object PermissionHelper {
    fun canScheduleExactAlarms(context: Context): Boolean {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.canScheduleExactAlarms()
        } else {
            true
        }
    }

    fun requestExactAlarmPermission(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            activity.startActivity(
                Intent(
                    Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                    Uri.parse("package:${activity.packageName}")
                )
            )
        }
    }

    fun canUseFullScreenIntent(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= 34) {
            val nm = context.getSystemService(
                Context.NOTIFICATION_SERVICE
            ) as NotificationManager
            nm.canUseFullScreenIntent()
        } else {
            true
        }
    }

    fun openFullScreenIntentSettings(activity: Activity) {
        if (Build.VERSION.SDK_INT >= 34) {
            activity.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                    Uri.parse("package:${activity.packageName}")
                )
            )
        } else {
            openAppNotificationSettings(activity)
        }
    }

    fun areNotificationsEnabled(context: Context): Boolean {
        val nm = context.getSystemService(
            Context.NOTIFICATION_SERVICE
        ) as NotificationManager
        return nm.areNotificationsEnabled()
    }

    fun openAppNotificationSettings(activity: Activity) {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
            }
        } else {
            appDetailsIntent(activity)
        }
        activity.startActivity(intent)
    }

    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    fun requestIgnoreBatteryOptimizations(activity: Activity) {
        try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:${activity.packageName}")
                )
            )
        } catch (_: Exception) {
            openAppDetails(activity)
        }
    }

    fun canDrawOverlays(context: Context): Boolean =
        Settings.canDrawOverlays(context)

    fun openOverlaySettings(activity: Activity) {
        activity.startActivity(
            Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${activity.packageName}")
            )
        )
    }

    fun openAppDetails(activity: Activity) {
        activity.startActivity(appDetailsIntent(activity))
    }

    private fun appDetailsIntent(context: Context): Intent =
        Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:${context.packageName}")
        )
}
