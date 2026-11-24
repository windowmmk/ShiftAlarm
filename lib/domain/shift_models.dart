import 'package:flutter/services.dart';

import 'shift_time.dart';

/// 縮寫單位：全形字＝2，半形字＝1。
int abbrUnits(String s) {
  var units = 0;
  for (final rune in s.runes) {
    units += rune > 0xFF ? 2 : 1;
  }
  return units;
}

/// 按單位截到 ≤ [maxUnits]（預設 ≤4，即 2 全形／4 半形）。
String truncateAbbr(String s, [int maxUnits = 4]) {
  var units = 0;
  final buf = StringBuffer();
  for (final rune in s.runes) {
    final u = rune > 0xFF ? 2 : 1;
    if (units + u > maxUnits) break;
    units += u;
    buf.writeCharCode(rune);
  }
  return buf.toString();
}

/// 型別寬容讀取字串：任何非 null 值轉為字串，null 保留 null。
///
/// 避免舊版或外部寫入的 JSON 欄位型別不符時拋出 `TypeError` 導致整份資料歸零。
String? readJsonText(Object? v) {
  if (v == null) return null;
  return v is String ? v : v.toString();
}

/// 型別寬容讀取整數：接受 num 與數字字串，其餘回 null。
int? readJsonInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// 型別寬容讀取布林：接受 bool、0/1、'true'/'false'。
bool? readJsonBool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return null;
}

/// 型別寬容讀取 `'HH:mm'`：型別錯或格式異常時退回 [fallback]。
String readJsonHhmmOr(Object? v, String fallback) {
  final s = readJsonText(v);
  if (s == null) return fallback;
  return hmToMinutes(s) == null ? fallback : s.trim();
}

/// 輸入過濾器：限制輸入內容不超過指定單位（全形＝2，半形＝1，預設 ≤4）。
class AbbrUnitLengthFormatter extends TextInputFormatter {
  final int maxUnits;

  const AbbrUnitLengthFormatter([this.maxUnits = 4]);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (abbrUnits(newValue.text) <= maxUnits) {
      return newValue;
    }
    final truncated = truncateAbbr(newValue.text, maxUnits);
    return TextEditingValue(
      text: truncated,
      selection: TextSelection.collapsed(offset: truncated.length),
    );
  }
}

/// 單個鬧鐘設定（一個班次可有多個）。
///
/// - [offsetMinutes]：相對開工時間的分鐘數，負數＝提前，正數＝延後。
/// - [notificationOnly]：true＝只發普通通知（不響鬧鐘聲、不彈全屏），false＝全鬧鐘。
class ShiftAlarm {
  String id;
  String label;
  int offsetMinutes;
  bool notificationOnly;
  bool enabled;

  /// 每個班次最多鬧鐘數（含開工／收工打卡，保證 id 在 32-bit 範圍）。
  static const int maxAlarmsPerShift = 10;

  /// 固定打卡鬧鐘 id（不佔 a1／a2… 序列，不影響 10 個上限的 index 方案）。
  static const String clockInId = 'dk_in';
  static const String clockOutId = 'dk_out';

  /// 固定打卡鬧鐘：用戶只能開／關，不可改名／改時間／刪除。
  bool get isClockAlarm => id == clockInId || id == clockOutId;

  /// 開工打卡：班次開始整點，只通知。
  static ShiftAlarm clockIn() => ShiftAlarm(
        id: clockInId,
        label: '開工打卡',
        offsetMinutes: 0,
        notificationOnly: true,
        enabled: false,
      );

  /// 收工打卡：班次結束整點（offset＝班次時長，動態計算），只通知。
  static ShiftAlarm clockOutFor(String startTime, String endTime) => ShiftAlarm(
        id: clockOutId,
        label: '收工打卡',
        offsetMinutes: ShiftDef.durationMinutes(startTime, endTime),
        notificationOnly: true,
        enabled: false,
      );

  ShiftAlarm({
    required this.id,
    required this.label,
    required this.offsetMinutes,
    this.notificationOnly = false,
    this.enabled = true,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'offsetMinutes': offsetMinutes,
        'notificationOnly': notificationOnly,
        'enabled': enabled,
      };

  static ShiftAlarm fromJson(Map<String, Object?> j) => ShiftAlarm(
        id: readJsonText(j['id']) ?? 'a1',
        label: readJsonText(j['label']) ?? '鬧鐘',
        offsetMinutes: readJsonInt(j['offsetMinutes']) ?? -60,
        notificationOnly: readJsonBool(j['notificationOnly']) ?? false,
        enabled: readJsonBool(j['enabled']) ?? true,
      );

  ShiftAlarm copy() => ShiftAlarm(
        id: id,
        label: label,
        offsetMinutes: offsetMinutes,
        notificationOnly: notificationOnly,
        enabled: enabled,
      );
}

/// 班次定義模型，持久化為 shared_preferences JSON。
class ShiftDef {
  static const String leaveId = '__leave__';

  final String id;
  String name;
  String abbr;
  String code;
  String startTime;
  String endTime;
  List<ShiftAlarm> alarms;
  bool isLeave;

  ShiftDef({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.alarms,
    String? abbr,
    String? code,
    this.isLeave = false,
  })  : abbr = abbr ?? truncateAbbr(name),
        code = code ?? '';

  /// 供列表顯示的名稱：名稱與縮寫相同時不重複括號（如「早更」而非「早更（早更）」）。
  String get displayTitle =>
      abbr.isEmpty || abbr == name ? name : '$name（$abbr）';

  Map<String, Object?> toJson() => {
        'name': name,
        'abbr': abbr,
        'code': code,
        'startTime': startTime,
        'endTime': endTime,
        'alarms': alarms.map((a) => a.toJson()).toList(),
        if (isLeave) 'isLeave': true,
      };

  /// 由 JSON 還原班次定義（全欄位採型別寬容讀取，防單筆壞資料中斷整份清單）。
  static ShiftDef fromJson(String id, Map<String, Object?> j) {
    final name = readJsonText(j['name']) ?? id;
    final isLeave = (readJsonBool(j['isLeave']) ?? false) || id == leaveId;
    List<ShiftAlarm> alarms = [];
    final rawAlarms = j['alarms'];
    if (rawAlarms is List) {
      for (final e in rawAlarms) {
        if (e is Map) {
          try {
            alarms.add(ShiftAlarm.fromJson(Map<String, Object?>.from(e)));
          } catch (_) {
            continue;
          }
        }
      }
    }
    if (alarms.isEmpty && !isLeave) {
      final adv = readJsonInt(j['advanceMinutes']) ?? 60;
      alarms = [
        ShiftAlarm(
          id: 'a1',
          label: '開工鬧鐘',
          offsetMinutes: -adv,
          notificationOnly: false,
          enabled: true,
        ),
      ];
    }
    return ShiftDef(
      id: id,
      name: name,
      startTime: readJsonHhmmOr(j['startTime'], '00:00'),
      endTime: readJsonHhmmOr(j['endTime'], '00:00'),
      alarms: alarms,
      abbr: readJsonText(j['abbr']) ?? truncateAbbr(name),
      code: readJsonText(j['code']) ?? '',
      isLeave: isLeave,
    );
  }

  ShiftDef copy() => ShiftDef(
        id: id,
        name: name,
        startTime: startTime,
        endTime: endTime,
        alarms: alarms.map((a) => a.copy()).toList(),
        abbr: abbr,
        code: code,
        isLeave: isLeave,
      );

  /// 班次時長（分鐘），委派 [shiftDurationMinutes] 維持全專案單一規則。
  static int durationMinutes(String startTime, String endTime) =>
      shiftDurationMinutes(startTime, endTime);

  /// 確保固定打卡鬧鐘存在且欄位正確，並保留用戶的 `enabled` 開關（冪等）。
  void normalizeClockAlarms() {
    ShiftAlarm? byId(String id) {
      for (final a in alarms) {
        if (a.id == id) return a;
      }
      return null;
    }

    final clockIn = byId(ShiftAlarm.clockInId);
    if (clockIn == null) {
      alarms.add(ShiftAlarm.clockIn());
    } else {
      clockIn.label = '開工打卡';
      clockIn.offsetMinutes = 0;
      clockIn.notificationOnly = true;
    }
    final clockOut = byId(ShiftAlarm.clockOutId);
    if (clockOut == null) {
      alarms.add(ShiftAlarm.clockOutFor(startTime, endTime));
    } else {
      clockOut.label = '收工打卡';
      clockOut.offsetMinutes = durationMinutes(startTime, endTime);
      clockOut.notificationOnly = true;
    }
  }
}

/// 單日指派：班次 ID ＋ 地點短碼（≤4 單位）。
class ShiftAssignment {
  final String shiftId;
  String note;

  ShiftAssignment(this.shiftId, [this.note = '']);

  Map<String, Object?> toJson() => {'shiftId': shiftId, 'note': note};

  /// 由 JSON 還原單日指派。
  ///
  /// [validIds] 非空時濾除不存在班次；傳 null 時保留孤兒條目供人工救援。
  static ShiftAssignment? fromJson(Object? v, [Set<String>? validIds]) {
    if (v is String) {
      final sid = v.trim();
      if (sid.isEmpty) return null;
      if (validIds != null && !validIds.contains(sid)) return null;
      return ShiftAssignment(sid, '');
    }
    if (v is Map) {
      final rawSid = v['shiftId'];
      if (rawSid is! String) return null;
      final sid = rawSid.trim();
      if (sid.isEmpty) return null;
      if (validIds != null && !validIds.contains(sid)) return null;
      return ShiftAssignment(sid, readJsonText(v['note']) ?? '');
    }
    return null;
  }
}
