package com.shiftalarm.app

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "shift_alarm/alarm"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "schedule" -> {
                    val id = call.argument<Int>("id")
                    val triggerAtMillis =
                        (call.argument<Number>("triggerAtMillis"))?.toLong()
                    val title = call.argument<String>("title") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    val accentBg = (call.argument<Number>("accentBg"))?.toInt()
                        ?: AlarmScheduler.DEFAULT_ACCENT_BG
                    val accentFg = (call.argument<Number>("accentFg"))?.toInt()
                        ?: AlarmScheduler.DEFAULT_ACCENT_FG
                    val shiftName = call.argument<String>("shiftName") ?: ""
                    val startTime = call.argument<String>("startTime") ?: ""
                    val date = call.argument<String>("date") ?: ""
                    val note = call.argument<String>("note") ?: ""
                    if (id == null || triggerAtMillis == null) {
                        result.error("ARG", "missing id/triggerAtMillis", null)
                    } else {
                        AlarmScheduler.schedule(
                            this, id, triggerAtMillis, title, body,
                            accentBg, accentFg, shiftName, startTime, date, note
                        )
                        result.success(null)
                    }
                }
                "getFilesDir" -> {
                    result.success(filesDir.absolutePath)
                }
                "cancel" -> {
                    val id = call.argument<Int>("id")
                    if (id == null) {
                        result.error("ARG", "missing id", null)
                    } else {
                        AlarmScheduler.cancel(this, id)
                        result.success(null)
                    }
                }
                "scheduleGentle" -> {
                    val id = call.argument<Int>("id")
                    val triggerAtMillis =
                        (call.argument<Number>("triggerAtMillis"))?.toLong()
                    val title = call.argument<String>("title") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    if (id == null || triggerAtMillis == null) {
                        result.error("ARG", "missing id/triggerAtMillis", null)
                    } else {
                        AlarmScheduler.scheduleGentle(
                            this, id, triggerAtMillis, title, body
                        )
                        result.success(null)
                    }
                }
                "cancelGentle" -> {
                    val id = call.argument<Int>("id")
                    if (id == null) {
                        result.error("ARG", "missing id", null)
                    } else {
                        AlarmScheduler.cancelGentle(this, id)
                        result.success(null)
                    }
                }
                "rescheduleAll" -> {
                    @Suppress("UNCHECKED_CAST")
                    val alarms =
                        call.argument<List<Map<String, Any>>>("alarms")
                            ?: emptyList()
                    for (a in alarms) {
                        val id = (a["id"] as? Number)?.toInt() ?: continue
                        val triggerAtMillis =
                            (a["triggerAtMillis"] as? Number)?.toLong()
                                ?: continue
                        val title = a["title"] as? String ?: ""
                        val body = a["body"] as? String ?: ""
                        val accentBg = (a["accentBg"] as? Number)?.toInt()
                            ?: AlarmScheduler.DEFAULT_ACCENT_BG
                        val accentFg = (a["accentFg"] as? Number)?.toInt()
                            ?: AlarmScheduler.DEFAULT_ACCENT_FG
                        val shiftName = a["shiftName"] as? String ?: ""
                        val startTime = a["startTime"] as? String ?: ""
                        val date = a["date"] as? String ?: ""
                        val note = a["note"] as? String ?: ""
                        AlarmScheduler.schedule(
                            this, id, triggerAtMillis, title, body,
                            accentBg, accentFg, shiftName, startTime, date, note
                        )
                    }
                    @Suppress("UNCHECKED_CAST")
                    val gentleAlarms =
                        call.argument<List<Map<String, Any>>>("gentleAlarms")
                            ?: emptyList()
                    for (a in gentleAlarms) {
                        val id = (a["id"] as? Number)?.toInt() ?: continue
                        val triggerAtMillis =
                            (a["triggerAtMillis"] as? Number)?.toLong()
                                ?: continue
                        val title = a["title"] as? String ?: ""
                        val body = a["body"] as? String ?: ""
                        AlarmScheduler.scheduleGentle(
                            this, id, triggerAtMillis, title, body
                        )
                    }
                    result.success(null)
                }
                "canScheduleExactAlarms" -> {
                    val am =
                        getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        am.canScheduleExactAlarms()
                    } else {
                        true
                    }
                    result.success(ok)
                }
                "requestExactAlarmPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        startActivity(
                            Intent(
                                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                Uri.parse("package:$packageName")
                            )
                        )
                    }
                    result.success(null)
                }
                "canUseFullScreenIntent" -> {
                    // API 34+ 先有呢個授權；低版本一律視為允許
                    val ok = if (Build.VERSION.SDK_INT >= 34) {
                        val nm = getSystemService(
                            Context.NOTIFICATION_SERVICE
                        ) as NotificationManager
                        nm.canUseFullScreenIntent()
                    } else {
                        true
                    }
                    result.success(ok)
                }
                "openFullScreenIntentSettings" -> {
                    if (Build.VERSION.SDK_INT >= 34) {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                Uri.parse("package:$packageName")
                            )
                        )
                    } else {
                        // 低版本：開通知設定頁代替
                        openAppNotificationSettings()
                    }
                    result.success(null)
                }
                "areNotificationsEnabled" -> {
                    val nm = getSystemService(
                        Context.NOTIFICATION_SERVICE
                    ) as NotificationManager
                    result.success(nm.areNotificationsEnabled())
                }
                "openNotificationSettings" -> {
                    openAppNotificationSettings()
                    result.success(null)
                }
                "isIgnoringBatteryOptimizations" -> {
                    val pm = getSystemService(
                        Context.POWER_SERVICE
                    ) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        startActivity(
                            Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName")
                            )
                        )
                    } catch (_: Exception) {
                        // 個別 ROM 冇呢個 action，退返應用詳情
                        openAppDetails()
                    }
                    result.success(null)
                }
                "canDrawOverlays" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                "openOverlaySettings" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                    )
                    result.success(null)
                }
                "openAppDetailsSettings" -> {
                    openAppDetails()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openAppNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
        } else {
            openAppDetailsIntent()
        }
        startActivity(intent)
    }

    private fun openAppDetailsIntent(): Intent =
        Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:$packageName")
        )

    private fun openAppDetails() {
        startActivity(openAppDetailsIntent())
    }
}
