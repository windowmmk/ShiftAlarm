import 'package:flutter/services.dart';

/// 原生鬧鐘橋（Dart 側）
/// 對應 Android 實現：MainActivity 註冊 MethodChannel('shift_alarm/alarm')
class AlarmSchedule {
  final int id; // alarms 表主鍵，原生側用嚟識別 PendingIntent
  final int triggerAtMillis;
  final String title;
  final String body;

  /// 時段 accent 色（ARGB int，嚟自 ShiftTokens 對應時段色；原生側全屏鬧鐘用）
  final int accentBg;
  final int accentFg;

  /// 顯示用：更名／開工時間／日期／場所（原生全屏鬧鐘副標題用）
  final String shiftName;
  final String startTime;
  final String date;
  final String note;

  const AlarmSchedule({
    required this.id,
    required this.triggerAtMillis,
    required this.title,
    required this.body,
    this.accentBg = 0xFF0078D4,
    this.accentFg = 0xFFFFFFFF,
    this.shiftName = '',
    this.startTime = '',
    this.date = '',
    this.note = '',
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'triggerAtMillis': triggerAtMillis,
        'title': title,
        'body': body,
        'accentBg': accentBg,
        'accentFg': accentFg,
        'shiftName': shiftName,
        'startTime': startTime,
        'date': date,
        'note': note,
      };
}

/// 「只通知」輕量提醒（唔用全屏／前台服務／MediaPlayer）
class GentleAlarmSchedule {
  final int id;
  final int triggerAtMillis;
  final String title;
  final String body;

  const GentleAlarmSchedule({
    required this.id,
    required this.triggerAtMillis,
    required this.title,
    required this.body,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'triggerAtMillis': triggerAtMillis,
        'title': title,
        'body': body,
      };
}

/// 響鬧預告排程（第三條通道）。
/// 每個 enabled **而且係真正鬧鐘**（`notificationOnly == false`）嘅鬧鐘，
/// 喺真正觸發前 1 小時，由原生側掛一條 ongoing 通知喺狀態欄，並以倒計時
/// 顯示仲有幾耐響。
///
/// ⚠️ 純通知類鬧鐘（打卡開工／收工、使用者自建嘅「只通知」）**唔排預告**，
/// 過濾喺 `AlarmService.onAssigned` / `syncOnLaunch` 兩處做（v3.6.1 裁示）。
///
/// `alarmId` 係**原始鬧鐘 id**（未加偏移）：+900000 同 −60 分鐘都由原生側做，
/// 令 id 公式只有一個權威轉換點（Kotlin `PreAlertScheduler.preAlertId`）。
class PreAlertSchedule {
  /// 原始鬧鐘 id（= alarmBaseId(ymd) * 10 + index）
  final int alarmId;

  /// 鬧鐘**觸發**時刻（不是預告時刻）
  final int triggerAtMillis;

  final String title;
  final String body;

  /// 以下四個只為 P2-2（點擊跳日期）預留，現階段原生側只寫入 log 不消費。
  final String date;
  final String shiftName;
  final String startTime;
  final String note;

  const PreAlertSchedule({
    required this.alarmId,
    required this.triggerAtMillis,
    required this.title,
    required this.body,
    this.date = '',
    this.shiftName = '',
    this.startTime = '',
    this.note = '',
  });

  Map<String, Object?> toMap() => {
        'alarmId': alarmId,
        'triggerAtMillis': triggerAtMillis,
        'title': title,
        'body': body,
        'date': date,
        'shiftName': shiftName,
        'startTime': startTime,
        'note': note,
      };
}

class AlarmBridge {
  static const MethodChannel _ch = MethodChannel('shift_alarm/alarm');

  /// 排一次精確鬧鐘（同 id 重複 schedule 會覆蓋舊嘅）
  Future<void> schedule({
    required int id,
    required int triggerAtMillis,
    required String title,
    required String body,
    int accentBg = 0xFF0078D4,
    int accentFg = 0xFFFFFFFF,
    String shiftName = '',
    String startTime = '',
    String date = '',
    String note = '',
  }) {
    return _ch.invokeMethod('schedule', {
      'id': id,
      'triggerAtMillis': triggerAtMillis,
      'title': title,
      'body': body,
      'accentBg': accentBg,
      'accentFg': accentFg,
      'shiftName': shiftName,
      'startTime': startTime,
      'date': date,
      'note': note,
    });
  }

  /// 取消指定鬧鐘
  Future<void> cancel(int id) => _ch.invokeMethod('cancel', {'id': id});

  /// 排一個「只通知」輕量提醒（setExactAndAllowWhileIdle＋普通通知，
  /// 唔用全屏、唔用前台服務、唔用 MediaPlayer）
  Future<void> scheduleGentle({
    required int id,
    required int triggerAtMillis,
    required String title,
    required String body,
  }) {
    return _ch.invokeMethod('scheduleGentle', {
      'id': id,
      'triggerAtMillis': triggerAtMillis,
      'title': title,
      'body': body,
    });
  }

  /// 取消指定只通知提醒（連通知一併清除）
  Future<void> cancelGentle(int id) =>
      _ch.invokeMethod('cancelGentle', {'id': id});

  /// 排一條響鬧預告（原生側負責 +900000 與 −60 分鐘）
  Future<void> schedulePreAlert(PreAlertSchedule s) =>
      _ch.invokeMethod('schedulePreAlert', s.toMap());

  /// 取消響鬧預告（PendingIntent 與通知一併清）
  Future<void> cancelPreAlert(int alarmId) =>
      _ch.invokeMethod('cancelPreAlert', {'alarmId': alarmId});

  /// 原生 filesDir 絕對路徑（CrashApp.kt 寫 crash.log 嘅目錄）
  Future<String> getFilesDir() async {
    final r = await _ch.invokeMethod<String>('getFilesDir');
    return r ?? '';
  }

  /// 重排全部（開機後／App 啟動時保險用）。Dart 傳完整列表，原生側逐個 schedule。
  /// full 走全鬧鐘流程，gentle 走只通知流程，preAlerts 走響鬧預告流程。
  ///
  /// 第三個參數為 required，令漏傳即刻編譯失敗（唔會靜默冇預告）。
  ///
  /// 原生側處理完三個列表之後會**三條通道各自對帳**（v3.6.2 起）：
  /// 把「上次排過、今次清單冇」嘅 id 連 AlarmManager 排程一齊清走，避免幽靈
  /// 鬧鐘／幽靈通知。所以傳入嘅三個列表必須係**完整嘅現況**，唔可以傳部分
  /// 清單——漏咗嘅會被當成「唔再存在」而取消。
  ///
  /// 原生側有保護：只要今次有任何一條排唔到（例如精確鬧鐘權限被撤銷），
  /// 佢會跳過對帳，寧願留低幽靈都唔會誤殺一個本來有效嘅鬧鐘。
  Future<void> rescheduleAll(
          List<AlarmSchedule> full,
          List<GentleAlarmSchedule> gentle,
          List<PreAlertSchedule> preAlerts) =>
      _ch.invokeMethod('rescheduleAll', {
        'alarms': full.map((a) => a.toMap()).toList(),
        'gentleAlarms': gentle.map((a) => a.toMap()).toList(),
        'preAlerts': preAlerts.map((p) => p.toMap()).toList(),
      });

  /// Android 12+ 是否已授權精確鬧鐘
  Future<bool> canScheduleExactAlarms() async {
    final r = await _ch.invokeMethod<bool>('canScheduleExactAlarms');
    return r ?? false;
  }

  /// 打開系統設定頁，等用戶授權精確鬧鐘
  Future<void> requestExactAlarmPermission() =>
      _ch.invokeMethod('requestExactAlarmPermission');

  /// API 34+ 是否已允許全屏通知（低版本一律 true）
  Future<bool> canUseFullScreenIntent() async {
    final r = await _ch.invokeMethod<bool>('canUseFullScreenIntent');
    return r ?? true;
  }

  /// 打開全屏通知授權設定頁
  Future<void> openFullScreenIntentSettings() =>
      _ch.invokeMethod('openFullScreenIntentSettings');

  /// 通知權限是否已開
  Future<bool> areNotificationsEnabled() async {
    final r = await _ch.invokeMethod<bool>('areNotificationsEnabled');
    return r ?? false;
  }

  /// 打開 App 通知設定頁
  Future<void> openNotificationSettings() =>
      _ch.invokeMethod('openNotificationSettings');

  /// 是否已忽略電池優化（無限制）
  Future<bool> isIgnoringBatteryOptimizations() async {
    final r = await _ch.invokeMethod<bool>('isIgnoringBatteryOptimizations');
    return r ?? false;
  }

  /// 請求忽略電池優化
  Future<void> requestIgnoreBatteryOptimizations() =>
      _ch.invokeMethod('requestIgnoreBatteryOptimizations');

  /// 是否允許背景彈出視窗（SYSTEM_ALERT_WINDOW）
  Future<bool> canDrawOverlays() async {
    final r = await _ch.invokeMethod<bool>('canDrawOverlays');
    return r ?? false;
  }

  /// 打開懸浮窗授權設定頁
  Future<void> openOverlaySettings() =>
      _ch.invokeMethod('openOverlaySettings');

  /// 打開應用詳情設定頁（自啟動等人手開嘅項目用）
  Future<void> openAppDetailsSettings() =>
      _ch.invokeMethod('openAppDetailsSettings');
}
