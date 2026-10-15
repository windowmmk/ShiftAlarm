/// 配置導入導出：班次定義＋場所清單。
/// 採用標準工業級協議報文結構：
/// - 外部協議報文頭：魔數（SHIFTALARM）:版本（v1）:CRC32校驗碼:報文長度:時間戳:Payload
/// - 內部數據報文頭：魔數、版本、班次數、場所數、生成時間
/// 支援多層容錯（自動清除換行、自動補齊Padding、相容舊版與 iOS 彎引號修正）。
library;

import 'dart:convert';

/// 報文頭協議標識與快速檢查（用於剪貼簿自動比對與監聽）
class ConfigPacketHeader {
  static const String protocol = 'SHIFTALARM';
  static const String version = 'v1';
  static const String prefix = '$protocol:$version:';

  /// 快速檢查文字是否符合配置報文頭（用於剪貼簿快速監聽與比對，零成本避免誤報）
  static bool matches(String text) {
    final clean = text.trim().replaceAll(RegExp(r'\s+'), '');
    return clean.startsWith(prefix) || clean.startsWith('$protocol:');
  }
}

/// 快速檢查文字是否為合法的配置報文（供剪貼簿即時偵測使用）
bool isConfigPacket(String text) => ConfigPacketHeader.matches(text);

/// 計算標準 IEEE 802.3 CRC32 校驗碼，用於報文完整性驗證
int computeCrc32(List<int> bytes) {
  int crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (int i = 0; i < 8; i++) {
      if ((crc & 1) != 0) {
        crc = (crc >>> 1) ^ 0xEDB88320;
      } else {
        crc >>>= 1;
      }
    }
  }
  return (~crc) & 0xFFFFFFFF;
}

/// 導出當前配置為可序列化的 Map（包含內部報文頭與數據體）
Map<String, dynamic> exportConfig(ShiftStore store) {
  final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return {
    'app': 'ShiftAlarm',
    'version': 1,
    'header': {
      'magic': 'SHIFTALARM_CONFIG',
      'version': 1,
      'timestamp': nowTs,
      'shiftCount': store.defs.length,
      'venueCount': store.venues.length,
    },
    'shifts': [
      for (final e in store.defs.entries)
        {'id': e.key, ...e.value.toJson()},
    ],
    'venues': List<String>.from(store.venues),
  };
}

/// 導出為帶有完整協議報文頭（魔數、版本、CRC32、長度、時間戳）的 Base64 口令碼：
/// 格式：`SHIFTALARM:v1:crc=<CRC32>:len=<字節數>:ts=<時間戳>:<Base64>`
String exportConfigCode(ShiftStore store) {
  final map = exportConfig(store);
  final jsonStr = jsonEncode(map);
  final bytes = utf8.encode(jsonStr);
  final crcHex = computeCrc32(bytes).toRadixString(16).padLeft(8, '0');
  final byteLen = bytes.length;
  final ts = (map['header'] as Map)['timestamp'];
  final b64 = base64Encode(bytes);
  return 'SHIFTALARM:v1:crc=$crcHex:len=$byteLen:ts=$ts:$b64';
}

/// 導出為 JSON 字符串（pretty print，方便人讀）。
String exportConfigJson(ShiftStore store) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(exportConfig(store));
}

/// 報文解析結果
class DecodedConfigPayload {
  final Map<String, dynamic> data;
  final String? crcHex;
  final int? byteLen;
  final DateTime? exportTime;
  final bool crcVerified;

  const DecodedConfigPayload({
    required this.data,
    this.crcHex,
    this.byteLen,
    this.exportTime,
    this.crcVerified = false,
  });
}

/// 解碼配置字串：驗證外部報文頭、CRC32 校驗、長度檢驗、內部報文頭與數據完整性
DecodedConfigPayload decodeConfigText(String text) {
  final rawTrimmed = text.trim();
  if (rawTrimmed.isEmpty) {
    throw const ConfigImportException('內容係空嘅');
  }

  // 1. 去除所有內部空白與換行符號（針對通訊軟體或備忘錄折行貼上的容錯）
  final cleanText = rawTrimmed.replaceAll(RegExp(r'\s+'), '');

  // 2. 判斷帶報文頭的標準協議：SHIFTALARM:v1:...
  if (cleanText.startsWith('SHIFTALARM:v1:')) {
    final parts = cleanText.split(':');
    // 可能是 SHIFTALARM:v1:crc=...:len=...:ts=...:<b64> 或 SHIFTALARM:v1:<crc>:<b64>
    if (parts.length >= 4) {
      String? expectedCrc;
      int? expectedLen;
      DateTime? exportTime;
      String b64Payload = '';

      if (parts[2].startsWith('crc=')) {
        // 標準完整報文頭格式
        for (int i = 2; i < parts.length - 1; i++) {
          final p = parts[i];
          if (p.startsWith('crc=')) {
            expectedCrc = p.substring(4).toLowerCase();
          } else if (p.startsWith('len=')) {
            expectedLen = int.tryParse(p.substring(4));
          } else if (p.startsWith('ts=')) {
            final sec = int.tryParse(p.substring(3));
            if (sec != null) {
              exportTime = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
            }
          }
        }
        b64Payload = parts.last;
      } else {
        // 簡易版 SHIFTALARM:v1:<crc>:<payload>
        expectedCrc = parts[2].toLowerCase();
        b64Payload = parts.sublist(3).join(':');
      }

      // 容錯：URL-safe 與末尾補齊 '='
      b64Payload = b64Payload.replaceAll('-', '+').replaceAll('_', '/');
      while (b64Payload.length % 4 != 0) {
        b64Payload += '=';
      }

      final List<int> bytes;
      try {
        bytes = base64Decode(b64Payload);
      } catch (_) {
        throw const ConfigImportException('報文頭校驗失敗：Base64 數據損壞');
      }

      // 長度檢驗
      if (expectedLen != null && bytes.length != expectedLen) {
        throw ConfigImportException(
            '報文長度校驗失敗（預期 $expectedLen 字節，實測 ${bytes.length} 字節），內容被截斷');
      }

      // CRC32 校驗
      var crcOk = false;
      if (expectedCrc != null) {
        final actualCrc = computeCrc32(bytes).toRadixString(16).padLeft(8, '0');
        if (actualCrc != expectedCrc) {
          throw const ConfigImportException('報文校驗碼不符（內容不完整或被截斷），請重新複製完整口令');
        }
        crcOk = true;
      }

      try {
        final jsonStr = utf8.decode(bytes);
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          _validateConfigStructure(decoded);
          return DecodedConfigPayload(
            data: decoded,
            crcHex: expectedCrc,
            byteLen: bytes.length,
            exportTime: exportTime,
            crcVerified: crcOk,
          );
        }
      } catch (e) {
        if (e is ConfigImportException) rethrow;
        throw const ConfigImportException('報文數據內容損壞，無法解析');
      }
    }
  }

  // 3. 判斷無完整報文頭的舊版前綴：SHIFTALARM:<payload>
  if (cleanText.startsWith('SHIFTALARM:')) {
    var b64Payload = cleanText.substring('SHIFTALARM:'.length);
    b64Payload = b64Payload.replaceAll('-', '+').replaceAll('_', '/');
    while (b64Payload.length % 4 != 0) {
      b64Payload += '=';
    }
    try {
      final bytes = base64Decode(b64Payload);
      final jsonStr = utf8.decode(bytes);
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        _validateConfigStructure(decoded);
        return DecodedConfigPayload(data: decoded, byteLen: bytes.length);
      }
    } catch (e) {
      if (e is ConfigImportException) rethrow;
      throw const ConfigImportException('配置口令無效或已損壞');
    }
  }

  // 4. 純 Base64 字串判斷（無前綴）
  if (!cleanText.startsWith('{') && !cleanText.startsWith('[')) {
    var b64Payload = cleanText.replaceAll('-', '+').replaceAll('_', '/');
    while (b64Payload.length % 4 != 0) {
      b64Payload += '=';
    }
    try {
      final bytes = base64Decode(b64Payload);
      final jsonStr = utf8.decode(bytes);
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        _validateConfigStructure(decoded);
        return DecodedConfigPayload(data: decoded, byteLen: bytes.length);
      }
    } catch (_) {
      // 嘗試回退到 JSON
    }
  }

  // 5. 備用回退：相容舊版純 JSON，並自動修正 iOS 智慧彎引號（“ ” ‘ ’）
  try {
    final sanitized = rawTrimmed
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'");
    final decoded = jsonDecode(sanitized);
    if (decoded is Map<String, dynamic>) {
      _validateConfigStructure(decoded);
      return DecodedConfigPayload(data: decoded);
    }
    throw const ConfigImportException('配置格式唔啱');
  } catch (e) {
    if (e is ConfigImportException) rethrow;
    throw const ConfigImportException('口令或 JSON 格式無效');
  }
}

/// 內部報文頭與數據結構合法性驗證
void _validateConfigStructure(Map<String, dynamic> json) {
  if (json['app'] != 'ShiftAlarm') {
    throw const ConfigImportException('報文頭標記錯誤：非 ShiftAlarm 配置檔');
  }
  final shiftsRaw = json['shifts'];
  final venuesRaw = json['venues'];
  if (shiftsRaw is! List) {
    throw const ConfigImportException('配置檔缺少 shifts 班次資料');
  }
  if (venuesRaw is! List) {
    throw const ConfigImportException('配置檔缺少 venues 場所資料');
  }
  if (shiftsRaw.isEmpty) {
    throw const ConfigImportException('配置檔冇包含任何班次');
  }

  // 若含有內部報文頭，校驗班次數量冗餘
  final header = json['header'];
  if (header is Map) {
    final expectedShifts = header['shiftCount'] as int?;
    if (expectedShifts != null && shiftsRaw.length != expectedShifts) {
      throw ConfigImportException(
          '內部報文頭校驗失敗：班次數量不符（記錄為 $expectedShifts，實收 ${shiftsRaw.length}）');
    }
  }
}

/// 從 Map 導入配置：清空現有班次／場所，寫入導入的。
Future<void> importConfig(ShiftStore store, Map<String, dynamic> json) async {
  _validateConfigStructure(json);
  final shiftsRaw = json['shifts'] as List;
  final venuesRaw = json['venues'] as List;

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
    } catch (_) {}
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

/// 從任意文字（帶報文頭與 CRC32 校驗碼的 Base64 口令碼或 JSON 字符串）導入。
Future<void> importConfigText(ShiftStore store, String text) async {
  final payload = decodeConfigText(text);
  await importConfig(store, payload.data);
}

/// 兼容舊呼叫
Future<void> importConfigJson(ShiftStore store, String text) =>
    importConfigText(store, text);

/// 預覽結果結構
typedef ConfigPreview = ({
  int shifts,
  int venues,
  List<String> names,
  DateTime? exportTime,
  String? crcHex,
  bool crcVerified,
});

/// 預覽：從報文口令碼或 JSON 解析出班次／場所數量、名稱、生成時間與報文頭校驗狀態
ConfigPreview previewConfig(String text) {
  final payload = decodeConfigText(text);
  final shiftsRaw = payload.data['shifts'] as List;
  final venuesRaw = payload.data['venues'] as List;
  final names = <String>[];
  for (final e in shiftsRaw) {
    if (e is Map) {
      final name = e['name'] as String?;
      if (name != null) names.add(name);
    }
  }
  final venueCount = venuesRaw.whereType<String>().length;
  return (
    shifts: shiftsRaw.length,
    venues: venueCount,
    names: names,
    exportTime: payload.exportTime,
    crcHex: payload.crcHex,
    crcVerified: payload.crcVerified,
  );
}

class ConfigImportException implements Exception {
  final String message;
  const ConfigImportException(this.message);
  @override
  String toString() => message;
}
