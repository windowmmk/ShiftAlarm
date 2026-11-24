import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shift_models.dart';

export 'shift_models.dart'
    show
        AbbrUnitLengthFormatter,
        ShiftAlarm,
        ShiftAssignment,
        ShiftDef,
        abbrUnits,
        truncateAbbr;

/// 班次、排班指派、每日備註與地點清單的本機狀態儲存層（shared_preferences JSON）。
class ShiftStore extends ChangeNotifier {
  static const _kDefs = 'shift_defs';
  static const _kAssignments = 'assignments';
  static const _kRemarks = 'remarks';
  static const _kVenues = 'venues';

  /// 損壞資料備份 key 中綴：`<原 key>_corrupt_<毫秒時間戳>`。
  static const String _corruptInfix = '_corrupt_';

  /// 每日獨立備註最大字數上限（防止詳情卡爆版）。
  static const int maxRemarkLength = 200;

  /// 地點清單預設：統一版本無預設（由用戶自行建立或導入）。
  static List<String> defaultVenues() => [];

  /// 班次預設：統一版本無預設（由用戶自行建立或導入）。
  static Map<String, ShiftDef> defaults() => {};

  /// 測試用預設班次集合。
  @visibleForTesting
  static Map<String, ShiftDef> testDefaults() => _builtinDefaults();

  /// 測試用範本班次集合。
  @visibleForTesting
  static Map<String, ShiftDef> samplePresetDefs() => _builtinDefaults();

  /// 測試用範本地點清單。
  @visibleForTesting
  static List<String> samplePresetVenues() => [
        'A1',
        'A2',
        'B1',
        'B2',
        'C1',
        'C2',
        'ROOM_1',
        'ROOM_2',
      ];

  static Map<String, ShiftDef> _builtinDefaults() {
    ShiftDef buildDefault(
      String id,
      String name,
      String code,
      String start,
      String end,
    ) =>
        ShiftDef(
          id: id,
          name: name,
          code: code,
          startTime: start,
          endTime: end,
          alarms: [
            ShiftAlarm(
              id: 'a1',
              label: '開工鬧鐘',
              offsetMinutes: -60,
              notificationOnly: false,
              enabled: true,
            ),
            ShiftAlarm.clockIn(),
            ShiftAlarm.clockOutFor(start, end),
          ],
        );

    return {
      's00': buildDefault('s00', '凌晨更', '00', '00:00', '06:00'),
      's06': buildDefault('s06', '早更', '06', '06:00', '12:00'),
      's12': buildDefault('s12', '中更', '12', '12:00', '18:00'),
      's18': buildDefault('s18', '夜更', '18', '18:00', '00:00'),
    };
  }

  final SharedPreferences prefs;
  Map<String, ShiftDef> defs = {};
  Map<String, ShiftAssignment> assignments = {};

  /// 每日獨立備註（ymd → 備註文字），與排班完全解耦。
  Map<String, String> remarks = {};

  /// 常用地點清單（自動補全與管理頁共用）。
  List<String> venues = [];

  /// 最近一次 [load] 發現的資料損壞摘要；null 表示完全正常。
  String? lastLoadWarning;

  /// 最近一次 [load] 因單筆結構異常而略過的條目數。
  int lastDroppedEntries = 0;

  /// 排班原始 JSON 完全無法解析時的隔離旗標，防止以空資料覆寫原 key。
  bool _assignmentsQuarantined = false;

  List<ShiftDef>? _cachedSortedDefs;

  ShiftStore(this.prefs);

  String? _readRawJson(String key) {
    final Object? v = prefs.get(key);
    if (v == null) return null;
    if (v is String) return v;
    try {
      return jsonEncode(v);
    } catch (_) {
      return v.toString();
    }
  }

  Object? _tryDecodeJson(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _quarantine(String sourceKey, String raw) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    try {
      await prefs.setString('$sourceKey$_corruptInfix$stamp', raw);
    } catch (_) {
      // 備份失敗不得中斷載入流程；原 key 由隔離旗標保護。
    }
  }

  List<String> _parseVenues(Object? v) {
    if (v == null) return defaultVenues();
    Object? decoded = v;
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return defaultVenues();
      decoded = _tryDecodeJson(s);
    }
    if (decoded is! List) return defaultVenues();
    final out = <String>[];
    for (final e in decoded) {
      final s = readJsonText(e)?.trim() ?? '';
      if (s.isEmpty || out.contains(s)) continue;
      out.add(s);
    }
    return out;
  }

  Future<void> load() async {
    final warnings = <String>[];
    lastDroppedEntries = 0;
    lastLoadWarning = null;

    await _loadDefs(warnings);
    await _loadAssignments(warnings);
    await _loadRemarks(warnings);
    venues = _parseVenues(prefs.get(_kVenues));

    lastLoadWarning = warnings.isEmpty ? null : warnings.join('；');
    notifyListeners();
  }

  Future<void> _loadDefs(List<String> warnings) async {
    final d = defaults();
    final rawDefs = _readRawJson(_kDefs);
    if (rawDefs != null) {
      final decoded = _tryDecodeJson(rawDefs);
      if (decoded is! Map) {
        await _quarantine(_kDefs, rawDefs);
        warnings.add('班次定義 JSON 無法解析，已備份原資料');
      } else {
        var dropped = 0;
        for (final e in decoded.entries) {
          final id = e.key.toString();
          if (e.value is! Map) {
            dropped++;
            continue;
          }
          try {
            d[id] = ShiftDef.fromJson(
              id,
              Map<String, Object?>.from(e.value as Map),
            );
          } catch (_) {
            dropped++;
          }
        }
        if (dropped > 0) {
          lastDroppedEntries += dropped;
          warnings.add('$dropped 個班次定義損壞已略過');
        }
      }
    }
    defs = d;
    _invalidateDefsCache();
    for (final def in defs.values) {
      def.normalizeClockAlarms();
    }
  }

  Future<void> _loadAssignments(List<String> warnings) async {
    final rawAssignments = _readRawJson(_kAssignments);
    _assignmentsQuarantined = false;
    if (rawAssignments == null) {
      assignments = {};
      return;
    }
    final decoded = _tryDecodeJson(rawAssignments);
    if (decoded is! Map) {
      await _quarantine(_kAssignments, rawAssignments);
      _assignmentsQuarantined = true;
      warnings.add('排班資料 JSON 無法解析，已備份原資料（未清空）');
      assignments = {};
      return;
    }

    final parsed = <String, ShiftAssignment>{};
    var dropped = 0;
    var orphan = 0;
    for (final e in decoded.entries) {
      final ymd = e.key.toString();
      try {
        final a = ShiftAssignment.fromJson(e.value);
        if (a == null) {
          dropped++;
          continue;
        }
        if (!defs.containsKey(a.shiftId)) orphan++;
        parsed[ymd] = a;
      } catch (_) {
        dropped++;
      }
    }

    if (decoded.isEmpty) {
      assignments = parsed;
    } else if (parsed.isEmpty) {
      await _quarantine(_kAssignments, rawAssignments);
      _assignmentsQuarantined = true;
      lastDroppedEntries += dropped;
      warnings.add('排班資料 $dropped 條全部無法解析，已備份原資料（未清空）');
      assignments = {};
    } else {
      assignments = parsed;
      if (dropped > 0) {
        lastDroppedEntries += dropped;
        warnings.add('$dropped 天排班損壞已略過');
      }
      if (orphan > 0) {
        warnings.add('$orphan 天排班指向不存在的班次（已保留原資料）');
      }
    }
  }

  Future<void> _loadRemarks(List<String> warnings) async {
    final rawRemarks = _readRawJson(_kRemarks);
    if (rawRemarks == null) return;
    final decoded = _tryDecodeJson(rawRemarks);
    if (decoded is! Map) {
      await _quarantine(_kRemarks, rawRemarks);
      warnings.add('每日備註 JSON 無法解析，已備份原資料');
      return;
    }
    final parsed = <String, String>{};
    for (final e in decoded.entries) {
      final text = readJsonText(e.value);
      if (text == null || text.trim().isEmpty) continue;
      parsed[e.key.toString()] = text;
    }
    remarks = parsed;
  }

  Future<void> _saveDefs() => prefs.setString(
        _kDefs,
        jsonEncode(defs.map((k, v) => MapEntry(k, v.toJson()))),
      );

  Future<void> _saveAssignments() async {
    if (_assignmentsQuarantined) {
      if (assignments.isEmpty) return;
      _assignmentsQuarantined = false;
    }
    await prefs.setString(
      _kAssignments,
      jsonEncode(assignments.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  void _invalidateDefsCache() {
    _cachedSortedDefs = null;
  }

  /// 按開工時間排序的班次清單。
  List<ShiftDef> sortedDefs() {
    if (_cachedSortedDefs != null) return _cachedSortedDefs!;
    final list = defs.values.where((d) => !d.isLeave).toList();
    int toMinutes(String hhmm) {
      final p = hhmm.split(':');
      final h = int.tryParse(p.isNotEmpty ? p[0] : '') ?? 0;
      final m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
      return h * 60 + m;
    }

    list.sort((a, b) => toMinutes(a.startTime).compareTo(toMinutes(b.startTime)));
    return _cachedSortedDefs = list;
  }

  /// 更新班次定義（名稱／縮寫／代號／時間／鬧鐘列表）。
  Future<void> updateDef(
    String id, {
    String? name,
    String? abbr,
    String? code,
    String? startTime,
    String? endTime,
    List<ShiftAlarm>? alarms,
  }) async {
    final d = defs[id];
    if (d == null) return;
    if (name != null && name.trim().isNotEmpty) d.name = name.trim();
    if (abbr != null && abbr.trim().isNotEmpty) d.abbr = abbr.trim();
    if (code != null) d.code = code.trim();
    if (startTime != null && _validHhmm(startTime)) d.startTime = startTime;
    if (endTime != null && _validHhmm(endTime)) d.endTime = endTime;
    if (alarms != null && alarms.isNotEmpty) d.alarms = alarms;
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

  /// 新增班次。
  Future<void> addDef(ShiftDef def) async {
    def.normalizeClockAlarms();
    defs[def.id] = def;
    _invalidateDefsCache();
    await _saveDefs();
    notifyListeners();
  }

  /// 刪除班次並同步清除引用它的排班指派，回傳受影響的日期清單（已排序）。
  Future<List<String>> removeDef(String id) async {
    defs.remove(id);
    _invalidateDefsCache();
    await _saveDefs();

    final affected = <String>[
      for (final e in assignments.entries)
        if (e.value.shiftId == id) e.key,
    ]..sort();
    if (affected.isNotEmpty) {
      for (final ymd in affected) {
        assignments.remove(ymd);
      }
      await _saveAssignments();
    }

    notifyListeners();
    return affected;
  }

  /// 取得內建「假期類」班次定義。
  ShiftDef get leaveDef =>
      defs[ShiftDef.leaveId] ??
      ShiftDef(
        id: ShiftDef.leaveId,
        name: '假期',
        abbr: '假期',
        startTime: '00:00',
        endTime: '00:00',
        alarms: const [],
        isLeave: true,
      );

  /// 指派某日班次；若為假期類且尚未註冊，會自動補上內建假期定義。
  Future<void> assign(String ymd, String shiftId, {String note = ''}) async {
    if (shiftId == ShiftDef.leaveId && !defs.containsKey(ShiftDef.leaveId)) {
      defs[ShiftDef.leaveId] = leaveDef;
      await _saveDefs();
    }
    if (!defs.containsKey(shiftId)) return;
    assignments[ymd] = ShiftAssignment(shiftId, note);
    await _saveAssignments();
    notifyListeners();
  }

  /// 批次指派（供口令／CSV 導入使用，僅觸發一次持久化與通知）。
  Future<void> assignBatch(
    List<({String ymd, String shiftId, String note, String remark})> rows,
  ) async {
    bool defsDirty = false;
    bool assignmentsDirty = false;
    bool remarksDirty = false;
    for (final r in rows) {
      if (r.shiftId == ShiftDef.leaveId && !defs.containsKey(ShiftDef.leaveId)) {
        defs[ShiftDef.leaveId] = leaveDef;
        defsDirty = true;
      }
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
    if (defsDirty) await _saveDefs();
    if (assignmentsDirty) await _saveAssignments();
    if (remarksDirty) await prefs.setString(_kRemarks, jsonEncode(remarks));
    if (defsDirty || assignmentsDirty || remarksDirty) notifyListeners();
  }

  Future<void> unassign(String ymd) async {
    assignments.remove(ymd);
    await _saveAssignments();
    notifyListeners();
  }

  /// 批次取消排班（僅觸發一次持久化與通知）。
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

  /// 設定每日獨立備註（空字串代表刪除）。
  Future<void> setRemark(String ymd, String remark) async {
    var r = remark.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (r.length > maxRemarkLength) r = r.substring(0, maxRemarkLength);
    if (r.isEmpty) {
      remarks.remove(ymd);
    } else {
      remarks[ymd] = r;
    }
    await prefs.setString(_kRemarks, jsonEncode(remarks));
    notifyListeners();
  }

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

  /// 配置導入用：原子重寫排班指派的 `shiftId` 映射。
  Future<void> remapAssignmentShiftIds(Map<String, String> idMap) async {
    if (idMap.isEmpty) return;
    final next = <String, ShiftAssignment>{};
    var changed = false;
    for (final e in assignments.entries) {
      final target = idMap[e.value.shiftId];
      if (target == null || target == e.value.shiftId) {
        next[e.key] = e.value;
      } else {
        next[e.key] = ShiftAssignment(target, e.value.note);
        changed = true;
      }
    }
    if (!changed) return;
    assignments = next;
    await _saveAssignments();
    notifyListeners();
  }

  /// 配置導入用：整批替換班次定義（不清空現有排班指派與內建假期類）。
  Future<void> replaceAllDefs(Map<String, ShiftDef> newDefs) async {
    defs = Map<String, ShiftDef>.from(newDefs);
    if (assignments.values.any((a) => a.shiftId == ShiftDef.leaveId) &&
        !defs.containsKey(ShiftDef.leaveId)) {
      defs[ShiftDef.leaveId] = leaveDef;
    }
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
