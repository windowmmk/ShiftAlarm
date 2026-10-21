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
                    // 每條各自 try/catch（T07-AC4）：使用者撤銷精確鬧鐘授權時
                    // （Android 12+ SCHEDULE_EXACT_ALARM 未授權會拋 SecurityException），
                    // 代價只可以係「冇預告」，絕不可以變成「鬧鐘全部唔響」。
                    for (a in alarms) {
                        try {
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
                        } catch (_: Exception) {
                            AlarmDebugLog.append(
                                this, "[RESCHEDULE_FAIL] full"
                            )
                        }
                    }
                    @Suppress("UNCHECKED_CAST")
                    val gentleAlarms =
                        call.argument<List<Map<String, Any>>>("gentleAlarms")
                            ?: emptyList()
                    for (a in gentleAlarms) {
                        try {
                            val id = (a["id"] as? Number)?.toInt() ?: continue
                            val triggerAtMillis =
                                (a["triggerAtMillis"] as? Number)?.toLong()
                                    ?: continue
                            val title = a["title"] as? String ?: ""
                            val body = a["body"] as? String ?: ""
                            AlarmScheduler.scheduleGentle(
                                this, id, triggerAtMillis, title, body
                            )
                        } catch (_: Exception) {
                            AlarmDebugLog.append(
                                this, "[RESCHEDULE_FAIL] gentle"
                            )
                        }
                    }
                    // 預告要喺 full／gentle 兩個迴圈之後才排：
                    // PreAlertScheduler 嘅 prune 要見到完整狀態才計得出 keep。
                    @Suppress("UNCHECKED_CAST")
                    val preAlerts =
                        call.argument<List<Map<String, Any>>>("preAlerts")
                            ?: emptyList()
                    PreAlertScheduler.rescheduleAll(this, preAlerts)
                    result.success(null)
                }
                "schedulePreAlert" -> {
                    // 用 Number 而非 Int 讀 alarmId：Flutter 的 StandardMessageCodec 對
                    // [-2^31, 2^31-1] 的 Dart int 編成 INT32（Kotlin 收到 Integer），
                    // 超出範圍才編成 INT64（Long）。call.argument<Int> 內部是
                    // `arguments[key] as? Int`，遇到 Long 會**靜默回 null**（不拋異常），
                    // 然後這裡會走 result.error，Dart 側 try/catch 吞掉 → 預告無聲消失。
                    // 現行 alarmId 上限 202612319（YYYYMMDD*10+9）恆在 Int 範圍，但 id
                    // 方案日後一改就會踩中；Number.toInt() 兩種編碼都吃，成本零。
                    val alarmId = (call.argument<Number>("alarmId"))?.toInt()
                    val triggerAtMillis =
                        (call.argument<Number>("triggerAtMillis"))?.toLong()
                    val title = call.argument<String>("title") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    val date = call.argument<String>("date") ?: ""
                    val shiftName = call.argument<String>("shiftName") ?: ""
                    val startTime = call.argument<String>("startTime") ?: ""
                    val note = call.argument<String>("note") ?: ""
                    if (alarmId == null || triggerAtMillis == null) {
                        result.error("ARG", "missing alarmId/triggerAtMillis", null)
                    } else {
                        PreAlertScheduler.schedule(
                            this, alarmId, triggerAtMillis, title, body,
                            date, shiftName, startTime, note
                        )
                        result.success(null)
                    }
                }
                "cancelPreAlert" -> {
                    // 同上：Int 讀法遇 Long 會靜默回 null，而取消失敗 = 幽靈通知
                    // 留在通知欄（正是本功能最要防的失敗模式），故用 Number。
                    val alarmId = (call.argument<Number>("alarmId"))?.toInt()
                    if (alarmId == null) {
                        result.error("ARG", "missing alarmId", null)
                    } else {
                        PreAlertScheduler.cancel(this, alarmId)
                        result.success(null)
                    }
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
