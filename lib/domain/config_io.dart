/// 配置導入導出：班次定義＋場所清單。
/// 支援 Base64 口令碼（SHIFTALARM:開頭）與標準 JSON，徹底杜絕 iOS 智慧標點引號問題。
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

/// 導出為 Base64 口令碼（無換行、無雙引號，iOS / 微信 / 備忘錄複製 100% 不損壞）
String exportConfigCode(ShiftStore store) {
  final map = exportConfig(store);
  final jsonStr = jsonEncode(map);
  final bytes = utf8.encode(jsonStr);
  final b64 = base64Encode(bytes);
  return 'SHIFTALARM:$b64';
}

/// 導出為 JSON 字符串（pretty print，方便人讀）。
String exportConfigJson(ShiftStore store) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(exportConfig(store));
}

/// 解碼配置字串：自動相容 Base64 口令碼與普通 JSON（並修正 iOS 彎引號 “ ”）
Map<String, dynamic> decodeConfigText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw const ConfigImportException('內容係空嘅');
  }

  // 1. 若以 SHIFTALARM: 或 SHIFTALARM:v1: 開頭，或無 JSON 括號，優先按 Base64 解碼
  String payload = trimmed;
  final hasPrefix = payload.startsWith('SHIFTALARM:');
  if (payload.startsWith('SHIFTALARM:v1:')) {
    payload = payload.substring('SHIFTALARM:v1:'.length).trim();
  } else if (hasPrefix) {
    payload = payload.substring('SHIFTALARM:'.length).trim();
  }

  if (hasPrefix || (!payload.startsWith('{') && !payload.startsWith('['))) {
    try {
      final bytes = base64Decode(payload);
      final jsonStr = utf8.decode(bytes);
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      if (hasPrefix) {
        throw const ConfigImportException('配置口令無效或已損壞');
      }
    }
  }

  // 2. 備用語法：相容舊版 JSON，並修正 iOS 智慧標點（中文引號替換）
  try {
    final sanitized = trimmed
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'");
    final decoded = jsonDecode(sanitized);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const ConfigImportException('配置格式唔啱');
  } catch (e) {
    if (e is ConfigImportException) rethrow;
    throw const ConfigImportException('口令或 JSON 格式無效');
  }
}

/// 從 Map 導入配置：清空現有班次／場所，寫入導入的。
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

/// 從任意文字（Base64 口令碼或 JSON 字符串）導入。
Future<void> importConfigText(ShiftStore store, String text) async {
  final decoded = decodeConfigText(text);
  await importConfig(store, decoded);
}

/// 兼容舊呼叫
Future<void> importConfigJson(ShiftStore store, String text) =>
    importConfigText(store, text);

/// 預覽：從口令碼或 JSON 解析出班次／場所數量與名稱（唔寫入）。
({int shifts, int venues, List<String> names}) previewConfig(String text) {
  final decoded = decodeConfigText(text);
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
