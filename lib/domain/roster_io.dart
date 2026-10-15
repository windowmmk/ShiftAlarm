/// 排班表導出與導入模組：支援 Base58 報文協議與傳統 CSV 雙模相容
/// - 外部協議報文頭：SHIFTROSTER:v1:crc=<CRC32>:len=<長度>:days=<天數>:ts=<時間戳>:<Base58>
/// - 內部數據結構：魔數、時間戳、項目列表（日期、代號、場所、備註）
/// - 雙模支援：貼上 Base58 口令或 CSV 文字均可無縫解析
library;

import 'dart:convert';

import 'base58.dart';
import 'config_io.dart' show computeCrc32;
import 'csv_import.dart';
import 'shift_store.dart';

/// 排班報文頭協議標識與快速檢查（用於剪貼簿自動辨識）
class RosterPacketHeader {
  static const String protocol = 'SHIFTROSTER';
  static const String version = 'v1';
  static const String prefix = '$protocol:$version:';

  /// 快速檢查文字是否符合排班報文頭（零成本避免誤報）
  static bool matches(String text) {
    final clean = text.trim().replaceAll(RegExp(r'\s+'), '');
    return clean.startsWith(prefix) || clean.startsWith('$protocol:');
  }
}

/// 快速檢查文字是否為合法的排班報文（供剪貼簿即時偵測使用）
bool isRosterPacket(String text) => RosterPacketHeader.matches(text);

/// 導出排班表為可序列化的 Map
Map<String, dynamic> exportRoster(ShiftStore store, {DateTime? month}) {
  final prefix = month != null
      ? '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}'
      : null;

  final items = <Map<String, dynamic>>[];
  for (final e in store.assignments.entries) {
    if (prefix == null || e.key.startsWith(prefix)) {
      final def = store.defs[e.value.shiftId];
      final remark = store.remarks[e.key] ?? '';
      items.add({
        'date': e.key,
        'code': def?.code ?? '',
        'shiftName': def?.name ?? '',
        'slot': def != null ? '${def.startTime}-${def.endTime}' : '',
        'venue': e.value.note,
        if (remark.isNotEmpty) 'remark': remark,
      });
    }
  }
  items.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

  final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return {
    'app': 'ShiftAlarmRoster',
    'version': 1,
    'header': {
      'magic': 'SHIFTALARM_ROSTER',
      'version': 1,
      'timestamp': nowTs,
      'daysCount': items.length,
      if (prefix != null) 'month': prefix,
    },
    'items': items,
  };
}

/// 導出為帶有完整協議報文頭（魔數、版本、CRC32、長度、天數、時間戳）的 Base58 排班口令碼：
/// 格式：`SHIFTROSTER:v1:crc=<CRC32>:len=<長度>:days=<天數>:ts=<時間戳>:<Base58>`
String exportRosterCode(ShiftStore store, {DateTime? month}) {
  final map = exportRoster(store, month: month);
  final jsonStr = jsonEncode(map);
  final bytes = utf8.encode(jsonStr);
  final crcHex = computeCrc32(bytes).toRadixString(16).padLeft(8, '0');
  final byteLen = bytes.length;
  final days = (map['items'] as List).length;
  final ts = (map['header'] as Map)['timestamp'];
  final b58 = base58Encode(bytes);
  return 'SHIFTROSTER:v1:crc=$crcHex:len=$byteLen:days=$days:ts=$ts:$b58';
}

/// 排班報文解析詳細結果
class DecodedRosterResult {
  final CsvImportResult importResult;
  final String? crcHex;
  final int? byteLen;
  final DateTime? exportTime;
  final bool crcVerified;
  final bool isPacket; // true: 報文口令, false: 純 CSV 文字

  const DecodedRosterResult({
    required this.importResult,
    this.crcHex,
    this.byteLen,
    this.exportTime,
    this.crcVerified = false,
    this.isPacket = false,
  });
}

/// 解析排班文字：自動判斷 Base58 報文口令、Base64 相容口令，或傳統 CSV
DecodedRosterResult decodeRosterText(
    String text, Map<String, ShiftDef> defs) {
  final rawTrimmed = text.trim();
  if (rawTrimmed.isEmpty) {
    return DecodedRosterResult(
      importResult: CsvImportResult([], ['內容係空嘅']),
    );
  }

  final cleanText = rawTrimmed.replaceAll(RegExp(r'\s+'), '');

  // 1. 判斷帶報文頭的標準排班協議：SHIFTROSTER:v1:...
  if (cleanText.startsWith('SHIFTROSTER:v1:') ||
      cleanText.startsWith('SHIFTROSTER:')) {
    final parts = cleanText.split(':');
    if (parts.length >= 3) {
      String? expectedCrc;
      int? expectedLen;
      DateTime? exportTime;
      String payload = '';

      if (parts[1] == 'v1') {
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
        payload = parts.last;
      } else {
        payload = parts.sublist(1).join(':');
      }

      // 優先 Base58 解碼，若失敗嘗試 Base64
      List<int>? bytes;
      try {
        bytes = base58Decode(payload);
      } catch (_) {}

      if (bytes == null || bytes.isEmpty) {
        try {
          var b64 = payload.replaceAll('-', '+').replaceAll('_', '/');
          while (b64.length % 4 != 0) {
            b64 += '=';
          }
          bytes = base64Decode(b64);
        } catch (_) {}
      }

      if (bytes == null || bytes.isEmpty) {
        return DecodedRosterResult(
          importResult: CsvImportResult([], ['排班報文損壞，無法解碼']),
        );
      }

      // 長度檢驗
      if (expectedLen != null && bytes.length != expectedLen) {
        return DecodedRosterResult(
          importResult: CsvImportResult(
              [], ['報文長度不符（預期 $expectedLen 字節，實為 ${bytes.length} 字節），內容被截斷']),
        );
      }

      // CRC32 校驗
      var crcOk = false;
      if (expectedCrc != null) {
        final actualCrc = computeCrc32(bytes).toRadixString(16).padLeft(8, '0');
        if (actualCrc != expectedCrc) {
          return DecodedRosterResult(
            importResult: CsvImportResult([], ['報文校驗碼不符（內容可能損壞或未完整複製）']),
          );
        }
        crcOk = true;
      }

      try {
        final jsonStr = utf8.decode(bytes);
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic> && decoded['items'] is List) {
          final items = decoded['items'] as List;
          final valid = <CsvImportRow>[];
          final errors = <String>[];

          // 建立比對映射表
          final codeMap = <String, String>{};
          final slotMap = <String, String>{};
          for (final def in defs.values) {
            if (def.code.isNotEmpty) codeMap[def.code.toUpperCase()] = def.id;
            final slotKey = '${normalizeSlot(def.startTime)}-${normalizeSlot(def.endTime)}';
            slotMap[slotKey] = def.id;
          }

          for (final item in items) {
            if (item is! Map) continue;
            final date = item['date'] as String? ?? '';
            final code = (item['code'] as String? ?? '').trim();
            final slot = (item['slot'] as String? ?? '').trim();
            var venue = (item['venue'] as String? ?? '').trim();
            var remark = (item['remark'] as String? ?? '').trim();

            if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
              errors.add('$date：日期格式無效');
              continue;
            }

            // 匹配班次
            String? shiftId;
            if (code.isNotEmpty) {
              shiftId = codeMap[code.toUpperCase()];
            }
            if (shiftId == null && slot.isNotEmpty) {
              final norm = normalizeSlot(slot);
              if (norm != null) shiftId = slotMap[norm];
            }
            if (shiftId == null) {
              // 嘗試從 defs 中按 ID 或名稱查找
              for (final def in defs.values) {
                if (def.name == item['shiftName']) {
                  shiftId = def.id;
                  break;
                }
              }
            }

            if (shiftId == null) {
              errors.add('$date：代號「$code」找不到對應的班次');
              continue;
            }

            if (abbrUnits(venue) > 4) {
              if (remark.isEmpty) remark = venue;
              venue = truncateAbbr(venue);
            }

            valid.add(CsvImportRow(date, shiftId, venue, remark));
          }

          return DecodedRosterResult(
            importResult: CsvImportResult(valid, errors),
            crcHex: expectedCrc,
            byteLen: bytes.length,
            exportTime: exportTime,
            crcVerified: crcOk,
            isPacket: true,
          );
        }
      } catch (_) {
        return DecodedRosterResult(
          importResult: CsvImportResult([], ['排班報文格式異常，無法解析數據體']),
        );
      }
    }
  }

  // 2. Fallback: 傳統 CSV 文字解析（相容 Excel 複製或手打格式）
  final csvRes = parseRosterCsv(rawTrimmed, defs);
  return DecodedRosterResult(
    importResult: csvRes,
    isPacket: false,
  );
}
