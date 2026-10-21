import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shift_time.dart';

/// 縮寫單位：全形字＝2，半形字＝1
int abbrUnits(String s) {
  var units = 0;
  for (final rune in s.runes) {
    units += rune > 0xFF ? 2 : 1;
  }
  return units;
}

/// 按單位截到 ≤ maxUnits（預設 ≤4，即 2 全形／4 半形）
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

/// 輸入過濾器：限制輸入內容不超過指定單位（全形＝2，半形＝1，預設 ≤4）
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
/// offsetMinutes：相對開工時間嘅分鐘數，負數＝提早，正數＝延後。
/// notificationOnly：true＝只發普通通知（唔響鬧鐘聲、唔彈全屏），false＝全鬧鐘。
class ShiftAlarm {
  String id; // 班次內唯一，如 a1／a2
  String label; // 如「開工鬧鐘」、「收工打卡」
  int offsetMinutes;
  bool notificationOnly;
  bool enabled;

  /// 每個班次最多鬧鐘數（含開工／收工打卡，保證 id 在 32-bit 範圍）
  static const int maxAlarmsPerShift = 10;

  /// 固定打卡鬧鐘 id（唔佔 a1／a2… 序列，唔影響 10 個上限嘅 index 方案）
  static const String clockInId = 'dk_in';
  static const String clockOutId = 'dk_out';

  /// 固定打卡鬧鐘：用戶只可以開／關，唔可以改名／改時間／刪除。
  bool get isClockAlarm => id == clockInId || id == clockOutId;

  /// 開工打卡：班次開始整點，只通知。
  static ShiftAlarm clockIn() => ShiftAlarm(
        id: clockInId,
        label: '開工打卡',
        offsetMinutes: 0,
        notificationOnly: true,
        enabled: false,
      );

  /// 收工打卡：班次結束整點（offset＝班次時長，動態算），只通知。
  static ShiftAlarm clockOutFor(String startTime, String endTime) =>
      ShiftAlarm(
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
        id: j['id'] as String? ?? 'a1',
        label: j['label'] as String? ?? '鬧鐘',
        offsetMinutes: (j['offsetMinutes'] as num?)?.toInt() ?? -60,
        notificationOnly: j['notificationOnly'] as bool? ?? false,
        enabled: j['enabled'] as bool? ?? true,
      );

  ShiftAlarm copy() => ShiftAlarm(
        id: id,
        label: label,
        offsetMinutes: offsetMinutes,
        notificationOnly: notificationOnly,
        enabled: enabled,
      );
}

/// 班次定義＋月曆指派，全部存 shared_preferences JSON。
/// defs: {"s00": {"name": "凌晨更", "abbr": "凌晨", "startTime": "00:00",
///         "endTime": "06:00", "alarms": [...]}, ...}
/// assignments: {"2026-10-15": {"shiftId": "s06", "note": "A1"}, ...}
/// （舊版 defs 有 advanceMinutes、assignments value 係 String，load() 兼容）
class ShiftDef {
  final String id;
  String name;
  String abbr; // 縮寫（≤4 單位）
  String code; // 代號（≤4 英數字，CSV 導入匹配用，預設空白）
  String startTime; // 可改（班次管理頁）
  String endTime; // 可改
  List<ShiftAlarm> alarms;

  ShiftDef({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.alarms,
    String? abbr,
    String? code,
  })  : abbr = abbr ?? truncateAbbr(name),
        code = code ?? '';

  Map<String, Object?> toJson() => {
        'name': name,
        'abbr': abbr,
        'code': code,
        'startTime': startTime,
        'endTime': endTime,
        'alarms': alarms.map((a) => a.toJson()).toList(),
      };

  static ShiftDef fromJson(String id, Map<String, Object?> j) {
    final name = j['name'] as String? ?? id;
    // 鬧鐘列表：新格式讀 alarms；舊格式由 advanceMinutes 遷移
    List<ShiftAlarm> alarms = [];
    final rawAlarms = j['alarms'];
    if (rawAlarms is List) {
      for (final e in rawAlarms) {
        if (e is Map) {
          alarms.add(ShiftAlarm.fromJson(Map<String, Object?>.from(e)));
        }
      }
    }
    if (alarms.isEmpty) {
      final adv = (j['advanceMinutes'] as num?)?.toInt() ?? 60;
      alarms = [
        ShiftAlarm(
            id: 'a1',
            label: '開工鬧鐘',
            offsetMinutes: -adv,
            notificationOnly: false,
            enabled: true)
      ];
    }
    return ShiftDef(
      id: id,
      name: name,
      startTime: j['startTime'] as String? ?? '00:00',
      endTime: j['endTime'] as String? ?? '00:00',
      alarms: alarms,
      abbr: j['abbr'] as String? ?? truncateAbbr(name),
      code: j['code'] as String? ?? '',
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
      );

  /// 班次時長（分鐘）：收工早過開工視為跨日（如 18:00–00:00 → 360）。
  /// startTime == endTime 屬無效（UI 層唔畀存），呢度回 0。
  ///
  /// v3.5.0 起委派 [shiftDurationMinutes]（`shift_time.dart`），全專案只剩一份
  /// 時長規則；本方法保留為公開 API（`clockin_test`、UI 都在用），行為不變。
  static int durationMinutes(String startTime, String endTime) =>
      shiftDurationMinutes(startTime, endTime);

  /// 確保固定打卡鬧鐘存在且欄位正確。
  /// 只修 label／offsetMinutes／notificationOnly，用戶嘅 enabled 開關原樣保留；
  /// dk_out 嘅 offset 永遠＝當下班次時長（跟開工／收工時間走）。
  /// 冪等，可安全重複呼叫。
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

/// 單日指派：更次＋場所備注
class ShiftAssignment {
  final String shiftId;
  String note; // 場所／備注（≤4 單位）

  ShiftAssignment(this.shiftId, [this.note = '']);

  Map<String, Object?> toJson() => {'shiftId': shiftId, 'note': note};

  static ShiftAssignment? fromJson(Object? v, Set<String> validIds) {
    if (v is String) {
      // 舊格式：value 直接係 shiftId
      return validIds.contains(v) ? ShiftAssignment(v, '') : null;
    }
    if (v is Map) {
      final m = Map<String, Object?>.from(v);
      final sid = m['shiftId'] as String?;
      if (sid == null || !validIds.contains(sid)) return null;
      return ShiftAssignment(sid, m['note'] as String? ?? '');
    }
    return null;
  }
}

class ShiftStore extends ChangeNotifier {
  static const _kDefs = 'shift_defs';
  static const _kAssignments = 'assignments';
  static const _kRemarks = 'remarks';
  static const _kVenues = 'venues';

  /// 場所清單：統一版本無預設（用戶自己建或導入配置）。
  static List<String> defaultVenues() => [];

  /// 班次預設：統一版本無預設（用戶自己建或導入配置）。
  static Map<String, ShiftDef> defaults() => {};

  /// 測試用：方便單元測試起數據。
  @visibleForTesting
  static Map<String, ShiftDef> testDefaults() => _builtinDefaults();

  /// 測試預設班次（供單元測試用）。
  @visibleForTesting
  static Map<String, ShiftDef> samplePresetDefs() => _builtinDefaults();

  /// 測試預設場所（供單元測試用，通用代號）。
  @visibleForTesting
  static List<String> samplePresetVenues() => [
        'A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'ROOM_1', 'ROOM_2',
      ];

  static Map<String, ShiftDef> _builtinDefaults() {
    return {
        's00': ShiftDef(
            id: 's00',
            name: '凌晨更',
            code: '00',
            startTime: '00:00',
            endTime: '06:00',
            alarms: [
              ShiftAlarm(
                  id: 'a1',
                  label: '開工鬧鐘',
                  offsetMinutes: -60,
                  notificationOnly: false,
                  enabled: true),
              ShiftAlarm.clockIn(),
              ShiftAlarm.clockOutFor('00:00', '06:00'),
            ]),
        's06': ShiftDef(
            id: 's06',
            name: '早更',
            code: '06',
            startTime: '06:00',
            endTime: '12:00',
            alarms: [
              ShiftAlarm(
                  id: 'a1',
                  label: '開工鬧鐘',
                  offsetMinutes: -60,
                  notificationOnly: false,
                  enabled: true),
              ShiftAlarm.clockIn(),
              ShiftAlarm.clockOutFor('06:00', '12:00'),
            ]),
        's12': ShiftDef(
            id: 's12',
            name: '中更',
            code: '12',
            startTime: '12:00',
            endTime: '18:00',
            alarms: [
              ShiftAlarm(
                  id: 'a1',
                  label: '開工鬧鐘',
                  offsetMinutes: -60,
                  notificationOnly: false,
                  enabled: true),
              ShiftAlarm.clockIn(),
              ShiftAlarm.clockOutFor('12:00', '18:00'),
            ]),
        's18': ShiftDef(
            id: 's18',
            name: '夜更',
            code: '18',
            startTime: '18:00',
            endTime: '00:00',
            alarms: [
              ShiftAlarm(
                  id: 'a1',
                  label: '開工鬧鐘',
                  offsetMinutes: -60,
                  notificationOnly: false,
                  enabled: true),
              ShiftAlarm.clockIn(),
              ShiftAlarm.clockOutFor('18:00', '00:00'),
            ]),
      };
  }

  final SharedPreferences prefs;
  Map<String, ShiftDef> defs = {};
  Map<String, ShiftAssignment> assignments = {}; // ymd → 指派
  /// 每日獨立備註：ymd → 備註文字。同 shiftId、note（場所）完全獨立，
  /// 無排更都可以有備註；轉更／取消排班唔會清走佢。
  Map<String, String> remarks = {};
  /// 場所清單（自動補全＋班次管理頁可管理；打過嘅新場所會自動加入）
  List<String> venues = [];

  ShiftStore(this.prefs);

  Future<void> load() async {
    final d = defaults();
    try {
      final raw = prefs.getString(_kDefs);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in j.entries) {
          if (e.value is Map) {
            final id = e.key;
            // 已有預設就合併覆蓋；自定義班次直接加入
            d[id] = ShiftDef.fromJson(id, Map<String, Object?>.from(e.value as Map));
          }
        }
      }
    } catch (_) {}
    defs = d;
    _invalidateDefsCache();
    // 舊數據可能冇打卡鬧鐘，load 時補上並修好 offset（唔即時寫回，
    // 下次 updateDef／addDef 先持久化）。
    for (final def in defs.values) {
      def.normalizeClockAlarms();
    }
    try {
      final raw = prefs.getString(_kAssignments);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final ids = d.keys.toSet();
        final parsed = <String, ShiftAssignment>{};
        for (final e in j.entries) {
          final a = ShiftAssignment.fromJson(e.value, ids);
          if (a != null) parsed[e.key] = a;
        }
        assignments = parsed;
      }
    } catch (_) {
      assignments = {};
    }
    try {
      final raw = prefs.getString(_kRemarks);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final parsed = <String, String>{};
        for (final e in j.entries) {
          if (e.value is String && (e.value as String).trim().isNotEmpty) {
            parsed[e.key] = e.value as String;
          }
        }
        remarks = parsed;
      }
    } catch (_) {
      remarks = {};
    }
    try {
      final rawList = prefs.getStringList(_kVenues);
      // 只有從未儲存過（null）先用預設；用戶主動刪到空＝佢嘅選擇，唔好重置
      venues = rawList == null
          ? defaultVenues()
          : rawList.where((v) => v.trim().isNotEmpty).toList();
    } catch (_) {
      venues = defaultVenues();
    }
    notifyListeners();
  }

  Future<void> _saveDefs() =>
      prefs.setString(_kDefs, jsonEncode(defs.map((k, v) => MapEntry(k, v.toJson()))));

  Future<void> _saveAssignments() =>
      prefs.setString(_kAssignments, jsonEncode(assignments.map((k, v) => MapEntry(k, v.toJson()))));

  List<ShiftDef>? _cachedSortedDefs;

  void _invalidateDefsCache() {
    _cachedSortedDefs = null;
  }

  /// 按開工時間排序嘅班次列表（揀更卡、日曆 legend、班次管理頁用）
  List<ShiftDef> sortedDefs() {
    if (_cachedSortedDefs != null) return _cachedSortedDefs!;
    final list = defs.values.toList();
    int hms(String hhmm) {
      final p = hhmm.split(':');
      final h = int.tryParse(p.isNotEmpty ? p[0] : '') ?? 0;
      final m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
      return h * 60 + m;
    }
    list.sort((a, b) => hms(a.startTime).compareTo(hms(b.startTime)));
    return _cachedSortedDefs = list;
  }

  /// 改班次定義（名／縮寫／時間／鬧鐘列表）
  Future<void> updateDef(String id,
      {String? name,
      String? abbr,
      String? code,
      String? startTime,
      String? endTime,
      List<ShiftAlarm>? alarms}) async {
    final d = defs[id];
    if (d == null) return;
    if (name != null && name.trim().isNotEmpty) d.name = name.trim();
    if (abbr != null && abbr.trim().isNotEmpty) d.abbr = abbr.trim();
    if (code != null) d.code = code.trim();
    if (startTime != null && _validHhmm(startTime)) d.startTime = startTime;
    if (endTime != null && _validHhmm(endTime)) d.endTime = endTime;
    if (alarms != null && alarms.isNotEmpty) d.alarms = alarms;
    // 改時間後收工打卡 offset 要跟住班次時長重算；缺咗就補返。
    d.normalizeClockAlarms();
    _invalidateDefsCache();
    await _saveDefs();
    notifyListeners();
  }

  static bool _validHhmm(String s) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
    if (m == null) return false;
    final h = int.tryParse(m.group(1)!) ?? -1;
    final min = int.tryParse(m.group(2)!) ?? -1;
    return h >= 0 && h < 24 && min >= 0 && min < 60;
  }

  /// 新增班次
  Future<void> addDef(ShiftDef def) async {
    def.normalizeClockAlarms();
    defs[def.id] = def;
    _invalidateDefsCache();
    await _saveDefs();
    notifyListeners();
  }

  /// 刪除班次（呼叫方負責先取消相關鬧鐘＋清指派）
  Future<void> removeDef(String id) async {
    defs.remove(id);
    _invalidateDefsCache();
    await _saveDefs();
    notifyListeners();
  }

  Future<void> assign(String ymd, String shiftId, {String note = ''}) async {
    if (!defs.containsKey(shiftId)) return;
    assignments[ymd] = ShiftAssignment(shiftId, note);
    await _saveAssignments();
    notifyListeners();
  }

  /// 批次指派（CSV 導入用，只觸發一次持久化與通知）
  Future<void> assignBatch(
      List<({String ymd, String shiftId, String note, String remark})> rows) async {
    bool assignmentsDirty = false;
    bool remarksDirty = false;
    for (final r in rows) {
      if (defs.containsKey(r.shiftId)) {
        assignments[r.ymd] = ShiftAssignment(r.shiftId, r.note);
        assignmentsDirty = true;
      }
      if (r.remark.isNotEmpty) {
        final existing = remarks[r.ymd] ?? '';
        if (!existing.contains(r.remark)) {
          final merged =
              existing.isEmpty ? r.remark : '${r.remark}\n$existing';
          var trimmed = merged.trim().replaceAll(RegExp(r'\s+'), ' ');
          if (trimmed.length > maxRemarkLength) {
            trimmed = trimmed.substring(0, maxRemarkLength);
          }
          remarks[r.ymd] = trimmed;
          remarksDirty = true;
        }
      }
    }
    if (assignmentsDirty) await _saveAssignments();
    if (remarksDirty) await prefs.setString(_kRemarks, jsonEncode(remarks));
    if (assignmentsDirty || remarksDirty) notifyListeners();
  }

  Future<void> unassign(String ymd) async {
    assignments.remove(ymd);
    await _saveAssignments();
    notifyListeners();
  }

  /// 批次取消排班（管理頁刪除班次用，只觸發一次持久化與通知）
  Future<void> unassignBatch(List<String> ymds) async {
    if (ymds.isEmpty) return;
    var dirty = false;
    for (final ymd in ymds) {
      if (assignments.remove(ymd) != null) {
        dirty = true;
      }
    }
    if (dirty) {
      await _saveAssignments();
      notifyListeners();
    }
  }

  /// 每日獨立備註（同更次無關）：空字串＝刪除該日備註。
  /// 超長截到 200 字，唔爆版。
  static const int maxRemarkLength = 200;

  Future<void> setRemark(String ymd, String remark) async {
    var r = remark.trim();
    // 換行壓成空格，唔爆兩行詳情板
    r = r.replaceAll(RegExp(r'\s+'), ' ');
    if (r.length > maxRemarkLength) r = r.substring(0, maxRemarkLength);
    if (r.isEmpty) {
      remarks.remove(ymd);
    } else {
      remarks[ymd] = r;
    }
    await prefs.setString(_kRemarks, jsonEncode(remarks));
    notifyListeners();
  }

  /// 地點清單管理：新增（去重）、刪除、改名
  Future<void> addVenue(String v) async {
    v = v.trim();
    if (v.isEmpty || venues.contains(v)) return;
    venues = [...venues, v];
    await prefs.setStringList(_kVenues, venues);
    notifyListeners();
  }

  Future<void> removeVenue(String v) async {
    if (!venues.contains(v)) return;
    venues = venues.where((e) => e != v).toList();
    await prefs.setStringList(_kVenues, venues);
    notifyListeners();
  }

  Future<void> renameVenue(String oldV, String newV) async {
    newV = newV.trim();
    final i = venues.indexOf(oldV);
    if (i < 0 || newV.isEmpty || venues.contains(newV)) return;
    venues = [...venues]..[i] = newV;
    await prefs.setStringList(_kVenues, venues);
    notifyListeners();
  }

  /// 配置導入用：整批替換班次定義（清空後寫入）。
  /// 注意：唔清排班指派；指派到已刪班次嘅日子會喺下次 load 時自動過濾。
  Future<void> replaceAllDefs(Map<String, ShiftDef> newDefs) async {
    defs = Map<String, ShiftDef>.from(newDefs);
    _invalidateDefsCache();
    await _saveDefs();
    notifyListeners();
  }

  /// 配置導入用：整批替換地點清單。
  Future<void> replaceAllVenues(List<String> newVenues) async {
    venues = List<String>.from(newVenues);
    await prefs.setStringList(_kVenues, venues);
    notifyListeners();
  }

  static String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
