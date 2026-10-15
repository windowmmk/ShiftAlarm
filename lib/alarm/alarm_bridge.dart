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

  /// 原生 filesDir 絕對路徑（CrashApp.kt 寫 crash.log 嘅目錄）
  Future<String> getFilesDir() async {
    final r = await _ch.invokeMethod<String>('getFilesDir');
    return r ?? '';
  }

  /// 重排全部（開機後／App 啟動時保險用）。Dart 傳完整列表，原生側逐個 schedule。
  /// full 走全鬧鐘流程，gentle 走只通知流程。
  Future<void> rescheduleAll(
          List<AlarmSchedule> full, List<GentleAlarmSchedule> gentle) =>
      _ch.invokeMethod('rescheduleAll', {
        'alarms': full.map((a) => a.toMap()).toList(),
        'gentleAlarms': gentle.map((a) => a.toMap()).toList(),
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
