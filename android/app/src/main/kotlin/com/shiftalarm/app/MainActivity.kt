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
                    // ⚠️ 跨端數字參數一律用 Number 讀，再用 toInt()／toLong() 轉型。
                    // 理由：MethodCall.argument<T> 的實作是 `arguments[key] as? T`，
                    // 而 Flutter 的 StandardMessageCodec 會把落在 [-2^31, 2^31-1] 的
                    // Dart int 編成 INT32（Kotlin 收到 Integer），超出才編成 INT64（Long）。
                    // 若型別參數寫 Int 而實際收到 Long，`as? Int` 會**靜默回 null**
                    // ——不拋異常、不寫 log、編譯器也不會紅，然後這裡走 result.error，
                    // Dart 側 try/catch 吞掉，功能就無聲消失。
                    // 用 Number 當中介，Integer／Long 兩種編碼都吃，成本零。
                    // 本檔再無以 Int 為型別參數的 argument 讀法（保持這個狀態，
                    // 新增 channel method 時照抄本段即可）。
                    val id = (call.argument<Number>("id"))?.toInt()
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
                    // id 用 Number 讀，理由見 "schedule" 分支的說明
                    val id = (call.argument<Number>("id"))?.toInt()
                    if (id == null) {
                        result.error("ARG", "missing id", null)
                    } else {
                        AlarmScheduler.cancel(this, id)
                        result.success(null)
                    }
                }
                "scheduleGentle" -> {
                    // id 用 Number 讀，理由見 "schedule" 分支的說明
                    val id = (call.argument<Number>("id"))?.toInt()
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
                    // id 用 Number 讀，理由見 "schedule" 分支的說明
                    val id = (call.argument<Number>("id"))?.toInt()
                    if (id == null) {
                        result.error("ARG", "missing id", null)
                    } else {
                        AlarmScheduler.cancelGentle(this, id)
                        result.success(null)
                    }
                }
                "rescheduleAll" -> {
                    // completed：今次嘅 keep 清單係咪**可信**。
                    //
                    // 只有 true 才准喺尾段呼叫 AlarmScheduler.cancelAllExcept
                    // 對帳。對帳嘅語意係「註冊表有、今次 keep 冇嘅 id 一律當
                    // 幽靈 cancel」，所以 keep 一旦缺條目，對帳就會把一個
                    // **本來有效、只係今次表達唔到**嘅鬧鐘親手 cancel 走。
                    // 代價係「鬧鐘唔響」，比「留低幽靈」嚴重得多——寧願今次
                    // 唔清，等下一個完整週期。
                    //
                    // ⚠️ 但 completed 只可以標記「**唔知係邊條**」：
                    // 讀唔到 id／triggerAtMillis、或者整個鍵缺失，都屬呢類。
                    // 相反，「排程拋異常」**唔可以**令 completed = false——
                    // 因為嗰個 id 已經入咗 keep（見下面 `keep.add` 刻意放喺
                    // `schedule` **之前**嘅理由）。
                    //
                    // 為什麼要分得咁清（v3.6.2）：如果 per-entry catch 都設
                    // completed = false，一個**持續失敗**嘅條目就會令對帳
                    // 永久停擺。最現實嘅入口係 Android 12 / 12L（API 31–32）
                    // 用戶撤銷「鬧鐘與提醒」權限——該 API 級別根本冇
                    // USE_EXACT_ALARM（API 33 才引入），所以 manifest 加權限
                    // 救唔到佢；於是 `setAlarmClock` 對**每一條**都拋
                    // SecurityException → 每條都 completed = false →
                    // cancelAllExcept 永遠唔跑 → 撤銷權限前嘅幽靈永久清唔掉。
                    var completed = true

                    // 今次排到（或者刻意保留）嘅 id。呢兩個 set 係尾段
                    // `cancelAllExcept` 嘅唯一輸入，亦係對帳嘅**權威**清單。
                    //
                    // 注意：`AlarmScheduler.schedule` 內部而家都會
                    // `AlarmIdRegistry.remember`（任何排得成嘅 id 都要入註冊
                    // 表，否則對帳睇唔到佢），所以呢兩個 set 唔再係唯一嘅
                    // 寫入路徑。仍然要保留佢哋，因為 `cancelAllExcept` 需要
                    // 一個**明確**嘅 keep 集合：註冊表嘅內容可能仲含上一輪
                    // 嘅殘留，直接用註冊表做 keep 就永遠清唔到任何嘢。
                    //
                    // 效能：id 數量受「排班日數 × 每班 ≤ 10 個」限制（實際
                    // 幾十個），SharedPreferences 讀嘅係記憶體快取、寫係
                    // apply() 非同步落盤，整輪成本在毫秒級，唔構成 main
                    // thread 負擔。
                    val fullKeep = mutableSetOf<Int>()
                    val gentleKeep = mutableSetOf<Int>()

                    // ⚠️ 鍵缺失（null）同「有鍵但係空陣列」係兩件完全唔同嘅事：
                    // 前者代表呼叫方根本冇送清單（協議出錯），後者代表 Dart 側
                    // 真係一個鬧鐘都冇。前者唔可以當空清單處理，否則對帳會把
                    // 用戶所有鬧鐘一次過 cancel 光。所以 null → completed = false。
                    @Suppress("UNCHECKED_CAST")
                    val rawAlarms =
                        call.argument<List<Map<String, Any>>>("alarms")
                    if (rawAlarms == null) completed = false
                    val alarms = rawAlarms ?: emptyList()

                    // 每條各自 try/catch（T07-AC4）：使用者撤銷精確鬧鐘授權時
                    // （Android 12+ SCHEDULE_EXACT_ALARM 未授權會拋 SecurityException），
                    // 代價只可以係「冇預告」，絕不可以變成「鬧鐘全部唔響」。
                    for (a in alarms) {
                        // id／triggerAtMillis 喺 try 外面讀：catch 要用 id 寫
                        // log，而喺 try 內宣告嘅 val 喺 catch 睇唔到。
                        val id = (a["id"] as? Number)?.toInt()
                        val triggerAtMillis =
                            (a["triggerAtMillis"] as? Number)?.toLong()
                        if (id == null || triggerAtMillis == null) {
                            // 讀唔到 id／時間 = 呢條冇排到，keep 會缺佢。
                            // 唔可以就咁 continue 當冇事，否則對帳會把舊
                            // 嗰條有效排程 cancel 走。呢個係「唔知係邊條」，
                            // 所以 completed = false 係唯一選擇。
                            completed = false
                            AlarmDebugLog.append(
                                this, "[RESCHEDULE_FAIL] full arg"
                            )
                            continue
                        }
                        // ⚠️ keep.add 一定要喺 `schedule` **之前**（v3.6.2）。
                        // keep 嘅語義係「**唔好掂呢個 id**」。排程失敗時我哋
                        // 最想要嘅正是「保留舊排程」，加進 keep 就正好表達
                        // 呢件事。於是「一條壞 → 只保護佢自己，其餘照 prune
                        // （幽靈清得掉）」；「全部壞 → 全部在 keep → 唔會誤刪
                        // 任何嘢」，結果同 completed = false 一樣，但語義精確
                        // 得多，而且唔會因為一條長期壞掉就令對帳永久停擺。
                        //
                        // 呢個寫法同 PreAlertScheduler.rescheduleAll 一致
                        // （嗰邊都係 `keep.add` 喺 `schedule` 之前）。
                        fullKeep.add(id)
                        try {
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
                            // 刻意**唔**設 completed = false：id 已經喺 keep，
                            // 對帳唔會掂佢，其餘條目照樣清得到幽靈。
                            AlarmDebugLog.append(
                                this, "[RESCHEDULE_FAIL] full id=$id"
                            )
                        }
                    }

                    @Suppress("UNCHECKED_CAST")
                    val rawGentle =
                        call.argument<List<Map<String, Any>>>("gentleAlarms")
                    if (rawGentle == null) completed = false
                    val gentleAlarms = rawGentle ?: emptyList()
                    for (a in gentleAlarms) {
                        val id = (a["id"] as? Number)?.toInt()
                        val triggerAtMillis =
                            (a["triggerAtMillis"] as? Number)?.toLong()
                        if (id == null || triggerAtMillis == null) {
                            // 「唔知係邊條」→ keep 表達唔到 → 唔可以 prune
                            completed = false
                            AlarmDebugLog.append(
                                this, "[RESCHEDULE_FAIL] gentle arg"
                            )
                            continue
                        }
                        // keep.add 喺 schedule 之前，理由同上面 full 迴圈
                        gentleKeep.add(id)
                        try {
                            val title = a["title"] as? String ?: ""
                            val body = a["body"] as? String ?: ""
                            AlarmScheduler.scheduleGentle(
                                this, id, triggerAtMillis, title, body
                            )
                        } catch (_: Exception) {
                            // 唔設 completed = false：id 已喺 keep，對帳唔會
                            // 掂佢（同 full 迴圈同一個理由）
                            AlarmDebugLog.append(
                                this, "[RESCHEDULE_FAIL] gentle id=$id"
                            )
                        }
                    }

                    // 預告要喺 full／gentle 兩個迴圈之後才排：
                    // PreAlertScheduler 嘅 prune 要見到完整狀態才計得出 keep。
                    //
                    // ⚠️ 同 full／gentle 一樣要分清「鍵缺失」同「空清單」：
                    // 空清單要照跑（v3.6.1 裁示——使用者清空排班之後，正需要
                    // 一次 prune 去清走所有殘留預告）；但鍵缺失代表呼叫方根本
                    // 冇送清單，當成空清單就會把用戶所有預告一次過 cancel 光。
                    @Suppress("UNCHECKED_CAST")
                    val rawPreAlerts =
                        call.argument<List<Map<String, Any>>>("preAlerts")
                    if (rawPreAlerts == null) {
                        completed = false
                        AlarmDebugLog.append(
                            this, "[RESCHEDULE_FAIL] preAlerts 鍵缺失"
                        )
                    } else {
                        PreAlertScheduler.rescheduleAll(this, rawPreAlerts)
                    }

                    // 全鬧鐘／只通知兩條通道對帳（v3.6.2）：把「註冊表有、
                    // 今次清單冇」嘅 id cancel 走，令三條通道行為一致。
                    //
                    // 空清單都會照跑——「一個鬧鐘都冇」本身就係最需要清幽靈
                    // 嘅情況（同 Dart `syncOnLaunch` 無條件呼叫 rescheduleAll
                    // 嘅理由一樣）。但殘缺清單一定唔跑，理由見 completed 嘅註釋。
                    if (completed) {
                        AlarmScheduler.cancelAllExcept(
                            this, fullKeep, gentleKeep
                        )
                    } else {
                        AlarmDebugLog.append(
                            this, "[RESCHEDULE_SKIP_PRUNE] 清單殘缺，今次唔對帳"
                        )
                    }
                    result.success(null)
                }
                "schedulePreAlert" -> {
                    // alarmId 用 Number 讀，理由見 "schedule" 分支的說明。
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
                    // alarmId 用 Number 讀，理由見 "schedule" 分支的說明。
                    // 這條尤其要緊：取消失敗 = 幽靈通知永遠留在通知欄，
                    // 比「預告沒排到」更難被使用者察覺（要等到下次看通知欄）。
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
