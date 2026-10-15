/// 配置導入導出：班次定義＋場所清單，JSON 格式。
///
/// 格式（可讀、方便備份）：
/// ```json
/// {
///   "app": "ShiftAlarm",
///   "version": 1,
///   "shifts": [
///     {
///       "id": "s00",
///       "name": "凌晨更",
///       "abbr": "凌晨",
///       "startTime": "00:00",
///       "endTime": "06:00",
///       "alarms": [...]
///     }
///   ],
///   "venues": ["A1", "B1", ...]
/// }
/// ```
library;

import 'dart:convert';

import 'shift_store.dart';

/// 導出當前配置為可序列化的 Map。
Map<String, dynamic> exportConfig(ShiftStore store) {
  return {
    'app': 'ShiftAlarm',
    'version': 1,
    'shifts': [
      for (final e in store.defs.entries)
        {'id': e.key, ...e.value.toJson()},
    ],
    'venues': List<String>.from(store.venues),
  };
}

/// 導出為 JSON 字符串（pretty print，方便人讀）。
String exportConfigJson(ShiftStore store) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(exportConfig(store));
}

/// 從 Map 導入配置：清空現有班次／場所，寫入導入的。
/// 格式錯誤拋 [ConfigImportException]。
Future<void> importConfig(ShiftStore store, Map<String, dynamic> json) async {
  // 驗證格式
  if (json['app'] != 'ShiftAlarm') {
    throw const ConfigImportException('唔係 ShiftAlarm 配置檔');
  }
  final shiftsRaw = json['shifts'];
  final venuesRaw = json['venues'];
  if (shiftsRaw is! List) {
    throw const ConfigImportException('配置檔缺少 shifts');
  }
  if (venuesRaw is! List) {
    throw const ConfigImportException('配置檔缺少 venues');
  }

  // 解析班次
  final defs = <String, ShiftDef>{};
  for (final e in shiftsRaw) {
    if (e is! Map) continue;
    final m = Map<String, Object?>.from(e);
    final id = m['id'] as String?;
    if (id == null || id.isEmpty) continue;
    try {
      final def = ShiftDef.fromJson(id, m);
      def.normalizeClockAlarms();
      defs[id] = def;
    } catch (_) {
      // 單個班次解析失敗就跳過，唔阻其他
    }
  }
  if (defs.isEmpty) {
    throw const ConfigImportException('配置檔冇有效班次');
  }

  // 解析場所
  final venues = <String>[];
  for (final v in venuesRaw) {
    if (v is String && v.trim().isNotEmpty && !venues.contains(v.trim())) {
      venues.add(v.trim());
    }
  }

  // 寫入（先清後寫）
  await store.replaceAllDefs(defs);
  await store.replaceAllVenues(venues);
}

/// 從 JSON 字符串導入。
Future<void> importConfigJson(ShiftStore store, String text) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw const ConfigImportException('內容係空嘅');
  }
  dynamic decoded;
  try {
    decoded = jsonDecode(trimmed);
  } catch (_) {
    throw const ConfigImportException('JSON 格式唔啱');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const ConfigImportException('JSON 頂層要係 object');
  }
  await importConfig(store, decoded);
}

/// 預覽：從 JSON 字符串解析出班次／場所數量（唔寫入）。
/// 回 (shiftCount, venueCount, shiftNames)。
({int shifts, int venues, List<String> names}) previewConfig(String text) {
  dynamic decoded;
  try {
    decoded = jsonDecode(text.trim());
  } catch (_) {
    throw const ConfigImportException('JSON 格式唔啱');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const ConfigImportException('JSON 格式唔啱');
  }
  final shiftsRaw = decoded['shifts'];
  final venuesRaw = decoded['venues'];
  if (shiftsRaw is! List || venuesRaw is! List) {
    throw const ConfigImportException('配置檔格式唔啱');
  }
  final names = <String>[];
  for (final e in shiftsRaw) {
    if (e is Map) {
      final name = e['name'] as String?;
      if (name != null) names.add(name);
    }
  }
  final venueCount = venuesRaw.whereType<String>().length;
  return (shifts: shiftsRaw.length, venues: venueCount, names: names);
}

class ConfigImportException implements Exception {
  final String message;
  const ConfigImportException(this.message);
  @override
  String toString() => message;
}
