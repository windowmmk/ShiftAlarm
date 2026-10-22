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

/// 型別寬容讀取：任何值都轉成字串，null 保留 null。
///
/// 為什麼需要：舊版／別處寫入嘅 JSON 可能同今日嘅欄位型別唔一致（例如
/// `startTime` 曾被寫成 int、`shiftId` 被寫成數字）。用 `as String?` 讀會
/// 直接拋 `TypeError`，而外層 catch 會令**整份**清單歸零 —— 一個欄位嘅
/// 型別錯就要用戶賠上全部排班。`toString()` 讀唔到都會照樣讀到，代價只是
/// 值本身唔靚，唔會連累同一個容器嘅其他條目。
String? _text(Object? v) {
  if (v == null) return null;
  return v is String ? v : v.toString();
}

/// 型別寬容讀取整數：接受 num 與數字字串，其餘回 null。
int? _int(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// 型別寬容讀取布林：接受 bool、0/1、'true'/'false'。
bool? _bool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return null;
}

/// 寬容讀取 'HH:mm'：型別錯或者格式壞都退回 [fallback]。
///
/// 為什麼要驗格式：`_text(600)` 會變成 `'600'`，而 `'600'` 喺 [hmToMinutes]
/// 解析失敗（時 600 越界）。留住呢個字串等於留一個「睇落似真」嘅鬼時間，
/// 令收工打卡 offset 靜靜變 0 —— 比直接退回預設更難查。
String _hhmmOr(Object? v, String fallback) {
  final s = _text(v);
  if (s == null) return fallback;
  return hmToMinutes(s) == null ? fallback : s.trim();
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
        id: _text(j['id']) ?? 'a1',
        label: _text(j['label']) ?? '鬧鐘',
        offsetMinutes: _int(j['offsetMinutes']) ?? -60,
        notificationOnly: _bool(j['notificationOnly']) ?? false,
        enabled: _bool(j['enabled']) ?? true,
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

  /// 由 JSON 還原班次定義。
  ///
  /// 所有欄位一律用型別寬容讀取（[`_text`]／[`_int`]／[`_bool`]），
  /// **唔准**用 `as String?`：舊版或別處寫入嘅型別未必同今日一致，
  /// 一次 `TypeError` 就會令呼叫方嘅整個 for-loop 中斷，變成
  /// 「一個班次壞 → 全部班次消失」。
  static ShiftDef fromJson(String id, Map<String, Object?> j) {
    final name = _text(j['name']) ?? id;
    // 鬧鐘列表：新格式讀 alarms；舊格式由 advanceMinutes 遷移
    List<ShiftAlarm> alarms = [];
    final rawAlarms = j['alarms'];
    if (rawAlarms is List) {
      for (final e in rawAlarms) {
        if (e is Map) {
          // 逐個鬧鐘獨立 try/catch：壞一個只掉一個，唔可以連累其他
          try {
            alarms.add(ShiftAlarm.fromJson(Map<String, Object?>.from(e)));
          } catch (_) {
            continue;
          }
        }
      }
    }
    if (alarms.isEmpty) {
      final adv = _int(j['advanceMinutes']) ?? 60;
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
      startTime: _hhmmOr(j['startTime'], '00:00'),
      endTime: _hhmmOr(j['endTime'], '00:00'),
      alarms: alarms,
      abbr: _text(j['abbr']) ?? truncateAbbr(name),
      code: _text(j['code']) ?? '',
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

  /// 由 JSON 還原單日指派。
  ///
  /// [validIds] 有值時，指向唔存在班次嘅條目會回 null（舊行為，供需要
  /// 「只收有效指派」嘅呼叫方用）；傳 null 就完全唔做 id 校驗 ——
  /// `load()` 用呢個模式，因為「班次定義唔見咗」同「條目本身壞掉」係兩件事：
  /// 前者應該留住等人工救援，後者才應該略過。
  ///
  /// 為什麼 `shiftId` 一定要係字串，而 `note` 反而寬容：
  /// - `shiftId` 型別錯（例如被寫成 `123`）＝**壞資料**，讀落去只會變成
  ///   一個永遠對唔上任何班次嘅假 id，所以略過並計數。
  /// - `shiftId` 係字串但對唔上班次＝**孤兒**，資料本身係好嘅（場所備註
  ///   都仲喺），應該原樣保留。
  static ShiftAssignment? fromJson(Object? v, [Set<String>? validIds]) {
    if (v is String) {
      // 舊格式：value 直接係 shiftId
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
      return ShiftAssignment(sid, _text(v['note']) ?? '');
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

  /// 最近一次 [load] 發現嘅資料損壞摘要；null＝一切正常。
  ///
  /// 為什麼要有：本檔最嚴重嘅故障模式係「用戶嘅排班靜靜蒸發，連一句提示
  /// 都冇」—— 用戶只會以為係自己記錯，然後照樣用一個空咗嘅月曆。
  /// UI 將來可以據此顯示「有 N 天資料損壞，已略過」，唔需要改動本檔邏輯。
  String? lastLoadWarning;

  /// 最近一次 [load] 因為條目本身壞掉（型別錯／缺必要欄位）而略過嘅條目數。
  int lastDroppedEntries = 0;

  /// 排班原始 JSON 完全無法解析時嘅隔離旗標。
  /// 喺呢個狀態下唔准用空資料覆蓋原 key（見 [_saveAssignments]）。
  bool _assignmentsQuarantined = false;

  /// 損壞資料備份 key 嘅中綴：`<原 key>_corrupt_<毫秒時間戳>`
  static const String _corruptInfix = '_corrupt_';

  ShiftStore(this.prefs);

  /// 讀一個「本來應該係 JSON 字串」嘅 key，並回傳原始字串。
  ///
  /// 用 `prefs.get` 而唔係 `prefs.getString`：後者喺底層型別唔符時會直接
  /// 拋 `TypeError`，一拋就會連累同一個 try 區塊內其他 key 嘅載入 ——
  /// 呢個正是「一個 key 壞，全部 key 陪葬」嘅放大器。
  String? _readRawJson(String key) {
    final Object? v = prefs.get(key);
    if (v == null) return null;
    if (v is String) return v;
    // 型別唔符（例如被人寫成 List）：盡量序列化返，等下游可以備份／診斷
    try {
      return jsonEncode(v);
    } catch (_) {
      return v.toString();
    }
  }

  /// `jsonDecode` 但唔拋：解析失敗回 null。
  Object? _tryDecodeJson(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  /// 把無法解析嘅原始資料另存到 `<原 key>_corrupt_<毫秒時間戳>`。
  ///
  /// 為什麼要備份：壞資料往往仍然救得返（例如某日 `shiftId` 型別錯咗，
  /// 人手改一個字就得）。靜默清空係不可逆嘅 —— 用戶幾百天排班一夜蒸發，
  /// 冇任何痕跡可以查。寧可留住壞資料等人工救援，都唔可以靜默清空。
  Future<void> _quarantine(String sourceKey, String raw) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    try {
      await prefs.setString('$sourceKey$_corruptInfix$stamp', raw);
    } catch (_) {
      // 備份失敗都唔可以拋：load 唔應該因為備份失敗而中斷，
      // 真正嘅防線係 [_assignmentsQuarantined]（唔覆蓋原 key）。
    }
  }

  /// 場所清單還原。
  ///
  /// 為什麼唔用 `prefs.getStringList`：舊版／別處可能寫成 JSON 字串
  /// （例如 `'["A","B"]'`，底層型別係 `String`）甚至 `List<dynamic>`，
  /// `getStringList` 一拋 `TypeError` 就會被外層 catch 吞掉，整個場所
  /// 清單歸零。呢度自行判斷型別，唔靠 prefs 幫我轉型。
  List<String> _parseVenues(Object? v) {
    if (v == null) return defaultVenues(); // 從未儲存過 → 用預設
    Object? decoded = v;
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return defaultVenues();
      decoded = _tryDecodeJson(s);
    }
    if (decoded is! List) return defaultVenues();
    final out = <String>[];
    for (final e in decoded) {
      final s = _text(e)?.trim() ?? '';
      if (s.isEmpty || out.contains(s)) continue;
      out.add(s);
    }
    return out;
  }

  Future<void> load() async {
    final warnings = <String>[];
    lastDroppedEntries = 0;
    lastLoadWarning = null;

    // ---------- 班次定義 ----------
    final d = defaults();
    final rawDefs = _readRawJson(_kDefs);
    if (rawDefs != null) {
      final decoded = _tryDecodeJson(rawDefs);
      if (decoded is! Map) {
        // 整份 defs 壞掉：備份原字串再用預設繼續，唔可以靜靜當冇事
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
          // 逐個 def 獨立 try/catch：壞一個只掉一個，唔可以中斷整個清單
          try {
            // 已有預設就合併覆蓋；自定義班次直接加入
            d[id] = ShiftDef.fromJson(
                id, Map<String, Object?>.from(e.value as Map));
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
    // 舊數據可能冇打卡鬧鐘，load 時補上並修好 offset（唔即時寫回，
    // 下次 updateDef／addDef 先持久化）。
    for (final def in defs.values) {
      def.normalizeClockAlarms();
    }

    // ---------- 排班指派 ----------
    final rawAssignments = _readRawJson(_kAssignments);
    _assignmentsQuarantined = false;
    if (rawAssignments == null) {
      assignments = {};
    } else {
      final decoded = _tryDecodeJson(rawAssignments);
      if (decoded is! Map) {
        // 整份 JSON 解析唔到（例如被截斷成 "[{"）。備份 + 唔覆蓋原 key。
        await _quarantine(_kAssignments, rawAssignments);
        _assignmentsQuarantined = true;
        warnings.add('排班資料 JSON 無法解析，已備份原資料（未清空）');
        assignments = {};
      } else {
        final parsed = <String, ShiftAssignment>{};
        var dropped = 0;
        var orphan = 0;
        for (final e in decoded.entries) {
          final ymd = e.key.toString();
          // 逐條獨立解析：一條壞只掉一條。之前係整個 for-loop 包一個
          // try/catch，任何一天型別錯就令 assignments 變成 {}，
          // 然後照樣寫回 prefs → 幾百天排班永久消失。
          try {
            // 唔傳 validIds：班次定義唔見咗係「孤兒」而唔係「壞資料」，
            // 唔應該連用戶嘅場所備註一齊靜靜刪走（寧可顯示未知班次）。
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
          assignments = parsed; // 合法嘅「冇排班」，唔算損壞
        } else if (parsed.isEmpty) {
          // 有內容但一條都解析唔到 → 當整份壞：備份 + 唔覆蓋原 key
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
            warnings.add('$orphan 天排班指向唔存在嘅班次（已保留原資料）');
          }
        }
      }
    }

    // ---------- 每日備註 ----------
    final rawRemarks = _readRawJson(_kRemarks);
    if (rawRemarks != null) {
      final decoded = _tryDecodeJson(rawRemarks);
      if (decoded is! Map) {
        await _quarantine(_kRemarks, rawRemarks);
        warnings.add('每日備註 JSON 無法解析，已備份原資料');
      } else {
        final parsed = <String, String>{};
        for (final e in decoded.entries) {
          // 型別寬容：舊版可能有 null／數字備註，唔可以因此放棄整份
          final text = _text(e.value);
          if (text == null || text.trim().isEmpty) continue;
          parsed[e.key.toString()] = text;
        }
        remarks = parsed;
      }
    }

    // ---------- 場所清單 ----------
    venues = _parseVenues(prefs.get(_kVenues));

    lastLoadWarning = warnings.isEmpty ? null : warnings.join('；');
    notifyListeners();
  }

  Future<void> _saveDefs() =>
      prefs.setString(_kDefs, jsonEncode(defs.map((k, v) => MapEntry(k, v.toJson()))));

  Future<void> _saveAssignments() async {
    // 隔離期間（原始 JSON 完全解析唔到）手上嘅 assignments 係「載入失敗
    // 之後嘅空集合」，寫返去就等於用空資料覆蓋用戶嘅原始排班。
    // 寧可暫時唔寫：原 key 留住壞資料，等人工救援。
    // 一旦有真實資料寫入（assignments 非空），就解除隔離正常保存 ——
    // 因為壞資料本身已經備份喺 `_corrupt_*` key。
    if (_assignmentsQuarantined) {
      if (assignments.isEmpty) return;
      _assignmentsQuarantined = false;
    }
    await prefs.setString(
        _kAssignments, jsonEncode(assignments.map((k, v) => MapEntry(k, v.toJson()))));
  }

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

  /// 刪除班次，並同步清走引用佢嘅排班指派。
  ///
  /// 為什麼要一齊清：只刪 `shiftDefs` 唔刪 `assignments`，會留下一堆
  /// 指向唔存在班次嘅記錄 —— 日曆格變成空白／「未知班次」，統計頁靜靜
  /// 少算，而用戶見到嘅係「嗰日明明排過更但冇咗」。呢個係資料完整性問題，
  /// 唔應該推畀每個呼叫端自己記得處理。
  ///
  /// 回傳被清掉嘅日期清單（已排序），等呼叫端可以順手取消／重排鬧鐘。
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

  /// 配置導入用：按 [idMap]（舊 id → 新 id）重寫所有排班嘅 shiftId。
  ///
  /// 為什麼需要：導入配置會整批換走班次定義，新定義嘅 id 未必等於舊嘅
  /// （舊版 SA2 口令碼嘅 id 係即時由 code 推導，唔係由原 store 帶過嚟）。
  /// 唔重寫 `assignments` 就會全部變成孤兒 → 日曆顯示「未知班次」。
  ///
  /// 原子性：先砌好一個全新 map，全部成功先一次過賦值。中途出錯就原封
  /// 不動 —— 唔會出現「一半日子指新 id、一半指舊 id」嘅撕裂狀態（撕裂
  /// 之後就算再導入一次都補唔返，因為已經分唔清邊個係原本嘅值）。
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

  /// 配置導入用：整批替換班次定義（清空後寫入）。
  /// 注意：唔清排班指派 —— 呼叫方（`importConfig`）必須先經
  /// [remapAssignmentShiftIds] 把舊 id 對應到新 id。對應唔上嘅條目會
  /// 原樣保留（寧可顯示未知班次，都唔可以刪用戶資料）。
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
