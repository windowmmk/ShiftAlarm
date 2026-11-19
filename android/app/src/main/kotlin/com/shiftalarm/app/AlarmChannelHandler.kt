package com.shiftalarm.app

import android.app.Activity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter MethodChannel (`shift_alarm/alarm`) 原生指令派發器。
 *
 * 跨端數字參數一律先透過 [Number] 讀取再轉為 Int/Long，
 * 避免 StandardMessageCodec 於 INT32/INT64 切換時造成靜默 null。
 */
class AlarmChannelHandler(
    private val activity: Activity
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "shift_alarm/alarm"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "schedule" -> handleSchedule(call, result)
            "cancel" -> handleCancel(call, result)
            "scheduleGentle" -> handleScheduleGentle(call, result)
            "cancelGentle" -> handleCancelGentle(call, result)
            "rescheduleAll" -> handleRescheduleAll(call, result)
            "schedulePreAlert" -> handleSchedulePreAlert(call, result)
            "cancelPreAlert" -> handleCancelPreAlert(call, result)
            "getFilesDir" -> result.success(activity.filesDir.absolutePath)

            "canScheduleExactAlarms" ->
                result.success(PermissionHelper.canScheduleExactAlarms(activity))
            "requestExactAlarmPermission" -> {
                PermissionHelper.requestExactAlarmPermission(activity)
                result.success(null)
            }
            "canUseFullScreenIntent" ->
                result.success(PermissionHelper.canUseFullScreenIntent(activity))
            "openFullScreenIntentSettings" -> {
                PermissionHelper.openFullScreenIntentSettings(activity)
                result.success(null)
            }
            "areNotificationsEnabled" ->
                result.success(PermissionHelper.areNotificationsEnabled(activity))
            "openNotificationSettings" -> {
                PermissionHelper.openAppNotificationSettings(activity)
                result.success(null)
            }
            "isIgnoringBatteryOptimizations" ->
                result.success(PermissionHelper.isIgnoringBatteryOptimizations(activity))
            "requestIgnoreBatteryOptimizations" -> {
                PermissionHelper.requestIgnoreBatteryOptimizations(activity)
                result.success(null)
            }
            "canDrawOverlays" ->
                result.success(PermissionHelper.canDrawOverlays(activity))
            "openOverlaySettings" -> {
                PermissionHelper.openOverlaySettings(activity)
                result.success(null)
            }
            "openAppDetailsSettings" -> {
                PermissionHelper.openAppDetails(activity)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleSchedule(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Number>("id")?.toInt()
        val triggerAtMillis = call.argument<Number>("triggerAtMillis")?.toLong()
        if (id == null || triggerAtMillis == null) {
            result.error("ARG", "missing id/triggerAtMillis", null)
            return
        }
        AlarmScheduler.schedule(
            context = activity,
            id = id,
            triggerAtMillis = triggerAtMillis,
            title = call.argument<String>("title") ?: "",
            body = call.argument<String>("body") ?: "",
            accentBg = call.argument<Number>("accentBg")?.toInt()
                ?: AlarmScheduler.DEFAULT_ACCENT_BG,
            accentFg = call.argument<Number>("accentFg")?.toInt()
                ?: AlarmScheduler.DEFAULT_ACCENT_FG,
            shiftName = call.argument<String>("shiftName") ?: "",
            startTime = call.argument<String>("startTime") ?: "",
            date = call.argument<String>("date") ?: "",
            note = call.argument<String>("note") ?: ""
        )
        result.success(null)
    }

    private fun handleCancel(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Number>("id")?.toInt()
        if (id == null) {
            result.error("ARG", "missing id", null)
            return
        }
        AlarmScheduler.cancel(activity, id)
        result.success(null)
    }

    private fun handleScheduleGentle(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Number>("id")?.toInt()
        val triggerAtMillis = call.argument<Number>("triggerAtMillis")?.toLong()
        if (id == null || triggerAtMillis == null) {
            result.error("ARG", "missing id/triggerAtMillis", null)
            return
        }
        AlarmScheduler.scheduleGentle(
            context = activity,
            id = id,
            triggerAtMillis = triggerAtMillis,
            title = call.argument<String>("title") ?: "",
            body = call.argument<String>("body") ?: ""
        )
        result.success(null)
    }

    private fun handleCancelGentle(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Number>("id")?.toInt()
        if (id == null) {
            result.error("ARG", "missing id", null)
            return
        }
        AlarmScheduler.cancelGentle(activity, id)
        result.success(null)
    }

    private fun handleSchedulePreAlert(call: MethodCall, result: MethodChannel.Result) {
        val alarmId = call.argument<Number>("alarmId")?.toInt()
        val triggerAtMillis = call.argument<Number>("triggerAtMillis")?.toLong()
        if (alarmId == null || triggerAtMillis == null) {
            result.error("ARG", "missing alarmId/triggerAtMillis", null)
            return
        }
        PreAlertScheduler.schedule(
            context = activity,
            alarmId = alarmId,
            triggerAtMillis = triggerAtMillis,
            title = call.argument<String>("title") ?: "",
            body = call.argument<String>("body") ?: "",
            date = call.argument<String>("date") ?: "",
            shiftName = call.argument<String>("shiftName") ?: "",
            startTime = call.argument<String>("startTime") ?: "",
            note = call.argument<String>("note") ?: ""
        )
        result.success(null)
    }

    private fun handleCancelPreAlert(call: MethodCall, result: MethodChannel.Result) {
        val alarmId = call.argument<Number>("alarmId")?.toInt()
        if (alarmId == null) {
            result.error("ARG", "missing alarmId", null)
            return
        }
        PreAlertScheduler.cancel(activity, alarmId)
        result.success(null)
    }

    /**
     * 三通道全量重排與對帳（全鬧鐘／只通知／響鬧預告）。
     * 僅當三個清單結構均完整時才執行 `cancelAllExcept` 清除幽靈排程；
     * 單筆排程異常時因該 id 已先加入 keep，不會誤刪既有排程也不會阻塞對帳。
     */
    private fun handleRescheduleAll(call: MethodCall, result: MethodChannel.Result) {
        var completed = true
        val fullKeep = mutableSetOf<Int>()
        val gentleKeep = mutableSetOf<Int>()

        @Suppress("UNCHECKED_CAST")
        val rawAlarms = call.argument<List<Map<String, Any>>>("alarms")
        if (rawAlarms == null) completed = false
        for (a in rawAlarms ?: emptyList()) {
            val id = (a["id"] as? Number)?.toInt()
            val triggerAtMillis = (a["triggerAtMillis"] as? Number)?.toLong()
            if (id == null || triggerAtMillis == null) {
                completed = false
                AlarmDebugLog.append(activity, "[RESCHEDULE_FAIL] full arg")
                continue
            }
            fullKeep.add(id)
            try {
                AlarmScheduler.schedule(
                    context = activity,
                    id = id,
                    triggerAtMillis = triggerAtMillis,
                    title = a["title"] as? String ?: "",
                    body = a["body"] as? String ?: "",
                    accentBg = (a["accentBg"] as? Number)?.toInt()
                        ?: AlarmScheduler.DEFAULT_ACCENT_BG,
                    accentFg = (a["accentFg"] as? Number)?.toInt()
                        ?: AlarmScheduler.DEFAULT_ACCENT_FG,
                    shiftName = a["shiftName"] as? String ?: "",
                    startTime = a["startTime"] as? String ?: "",
                    date = a["date"] as? String ?: "",
                    note = a["note"] as? String ?: ""
                )
            } catch (_: Exception) {
                AlarmDebugLog.append(activity, "[RESCHEDULE_FAIL] full id=$id")
            }
        }

        @Suppress("UNCHECKED_CAST")
        val rawGentle = call.argument<List<Map<String, Any>>>("gentleAlarms")
        if (rawGentle == null) completed = false
        for (a in rawGentle ?: emptyList()) {
            val id = (a["id"] as? Number)?.toInt()
            val triggerAtMillis = (a["triggerAtMillis"] as? Number)?.toLong()
            if (id == null || triggerAtMillis == null) {
                completed = false
                AlarmDebugLog.append(activity, "[RESCHEDULE_FAIL] gentle arg")
                continue
            }
            gentleKeep.add(id)
            try {
                AlarmScheduler.scheduleGentle(
                    context = activity,
                    id = id,
                    triggerAtMillis = triggerAtMillis,
                    title = a["title"] as? String ?: "",
                    body = a["body"] as? String ?: ""
                )
            } catch (_: Exception) {
                AlarmDebugLog.append(activity, "[RESCHEDULE_FAIL] gentle id=$id")
            }
        }

        @Suppress("UNCHECKED_CAST")
        val rawPreAlerts = call.argument<List<Map<String, Any>>>("preAlerts")
        if (rawPreAlerts == null) {
            completed = false
            AlarmDebugLog.append(activity, "[RESCHEDULE_FAIL] preAlerts 鍵缺失")
        } else {
            PreAlertScheduler.rescheduleAll(activity, rawPreAlerts)
        }

        if (completed) {
            AlarmScheduler.cancelAllExcept(activity, fullKeep, gentleKeep)
        } else {
            AlarmDebugLog.append(
                activity, "[RESCHEDULE_SKIP_PRUNE] 清單殘缺，今次不對帳"
            )
        }
        result.success(null)
    }
}
