/// 排班表導出與導入模組：支援 v2 緊湊預編碼 Base58 報文協議、v1 協議與傳統 CSV 雙模相容
/// - 外部協議報文頭：SHIFTROSTER:v2:crc=<CRC32>:len=<長度>:days=<天數>:ts=<時間戳>:<Base58>
/// - 內部數據結構：二進制緊湊預編碼（長度縮減至 150-300 字元！）
/// - 雙模支援：貼上 Base58 口令或 CSV 文字均可無縫解析
library;

import 'dart:convert';
import 'dart:typed_data';

import 'base58.dart';
import 'config_io.dart' show computeCrc32;
import 'csv_import.dart';
import 'shift_store.dart';

/// 排班報文頭協議標識與快速檢查（用於剪貼簿自動辨識）
class RosterPacketHeader {
  static const String protocol = 'SHIFTROSTER';
  static const String version = 'v2';
  static const String prefix = '$protocol:$version:';

  /// 快速檢查文字是否符合排班報文頭（零成本避免誤報）
  static bool matches(String text) {
    final clean = text.trim().replaceAll(RegExp(r'\s+'), '');
    return clean.startsWith('SHIFTROSTER:v2:') ||
        clean.startsWith('SHIFTROSTER:v1:') ||
        clean.startsWith('$protocol:');
  }
}

/// 快速檢查文字是否為合法的排班報文（供剪貼簿即時偵測使用）
bool isRosterPacket(String text) => RosterPacketHeader.matches(text);

/// 二進制緊湊排班預編碼（v2）：大幅去除 JSON 冗餘欄位名，整月排班壓縮至 200-300 字元以內
Uint8List encodeCompactRoster(ShiftStore store, {DateTime? month}) {
  final prefix = month != null
      ? '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}'
      : null;

  final items = <MapEntry<String, ShiftAssignment>>[];
  for (final e in store.assignments.entries) {
    if (prefix == null || e.key.startsWith(prefix)) {
      items.add(e);
    }
  }
  items.sort((a, b) => a.key.compareTo(b.key));

  final bb = BytesBuilder();
  bb.addByte(2); // protocol version 2

  final countBd = ByteData(2)..setUint16(0, items.length, Endian.big);
  bb.add(countBd.buffer.asUint8List());

  for (final e in items) {
    final dParts = e.key.split('-');
    final y = int.tryParse(dParts[0]) ?? 2026;
    final m = int.tryParse(dParts.length > 1 ? dParts[1] : '') ?? 1;
    final d = int.tryParse(dParts.length > 2 ? dParts[2] : '') ?? 1;

    final yBd = ByteData(2)..setUint16(0, y, Endian.big);
    bb.add(yBd.buffer.asUint8List());
    bb.addByte(m.clamp(1, 12));
    bb.addByte(d.clamp(1, 31));

    final def = store.defs[e.value.shiftId];
    final code = def?.code ?? '';
    final codeBytes = utf8.encode(code);
    bb.addByte(codeBytes.length.clamp(0, 255));
    bb.add(codeBytes);

    final venueBytes = utf8.encode(e.value.note);
    bb.addByte(venueBytes.length.clamp(0, 255));
    bb.add(venueBytes);

    final remark = store.remarks[e.key] ?? '';
    final remarkBytes = utf8.encode(remark);
    bb.addByte(remarkBytes.length.clamp(0, 255));
    bb.add(remarkBytes);
  }

  return bb.toBytes();
}

/// 導出排班表為可序列化的 Map（相容舊版與除錯用途）
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

/// 導出為帶有完整協議報文頭（魔數、版本、CRC32、長度、天數、時間戳）的緊湊 Base58 排班口令碼：
/// 格式：`SHIFTROSTER:v2:crc=<CRC32>:len=<長度>:days=<天數>:ts=<時間戳>:<Base58>`
String exportRosterCode(ShiftStore store, {DateTime? month}) {
  final bytes = encodeCompactRoster(store, month: month);
  final crcHex = computeCrc32(bytes).toRadixString(16).padLeft(8, '0');
  final byteLen = bytes.length;
  final days = (ByteData.sublistView(bytes, 1, 3).getUint16(0, Endian.big));
  final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final b58 = base58Encode(bytes);
  return 'SHIFTROSTER:v2:crc=$crcHex:len=$byteLen:days=$days:ts=$nowTs:$b58';
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

/// 解析排班文字：自動判斷 v2 緊湊 Base58 報文口令、v1 報文口令，或傳統 CSV
DecodedRosterResult decodeRosterText(
    String text, Map<String, ShiftDef> defs) {
  final rawTrimmed = text.trim();
  if (rawTrimmed.isEmpty) {
    return DecodedRosterResult(
      importResult: CsvImportResult([], ['內容係空嘅']),
    );
  }

  final cleanText = rawTrimmed.replaceAll(RegExp(r'\s+'), '');

  // 1. 判斷 v2 緊湊二進制報文協議：SHIFTROSTER:v2:...
  if (cleanText.startsWith('SHIFTROSTER:v2:')) {
    final parts = cleanText.split(':');
    if (parts.length >= 4) {
      String? expectedCrc;
      int? expectedLen;
      DateTime? exportTime;
      String payload = '';

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

      List<int>? bytes;
      try {
        bytes = base58Decode(payload);
      } catch (_) {}

      if (bytes == null || bytes.isEmpty) {
        return DecodedRosterResult(
          importResult: CsvImportResult([], ['排班報文損壞，無法解碼']),
        );
      }

      if (expectedLen != null && bytes.length != expectedLen) {
        return DecodedRosterResult(
          importResult: CsvImportResult(
              [], ['報文長度不符（預期 $expectedLen 字節，實為 ${bytes.length} 字節），內容被截斷']),
        );
      }

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
        final u8 = Uint8List.fromList(bytes);
        var offset = 0;
        final version = u8[offset++];
        if (version != 2) {
          return DecodedRosterResult(
            importResult: CsvImportResult([], ['不支援的排班協議版本: $version']),
          );
        }

        final countBd = ByteData.sublistView(u8, offset, offset + 2);
        final count = countBd.getUint16(0, Endian.big);
        offset += 2;

        final valid = <CsvImportRow>[];
        final errors = <String>[];

        final codeMap = <String, String>{};
        final slotMap = <String, String>{};
        for (final def in defs.values) {
          if (def.code.isNotEmpty) codeMap[def.code.toUpperCase()] = def.id;
          final slotKey =
              '${normalizeSlot(def.startTime)}-${normalizeSlot(def.endTime)}';
          slotMap[slotKey] = def.id;
        }

        for (int i = 0; i < count; i++) {
          final yBd = ByteData.sublistView(u8, offset, offset + 2);
          final y = yBd.getUint16(0, Endian.big);
          offset += 2;
          final m = u8[offset++];
          final d = u8[offset++];
          final date =
              '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';

          final codeLen = u8[offset++];
          final code = utf8.decode(u8.sublist(offset, offset + codeLen));
          offset += codeLen;

          final venueLen = u8[offset++];
          var venue = utf8.decode(u8.sublist(offset, offset + venueLen));
          offset += venueLen;

          final remarkLen = u8[offset++];
          var remark = utf8.decode(u8.sublist(offset, offset + remarkLen));
          offset += remarkLen;

          String? shiftId;
          if (code.isNotEmpty) {
            shiftId = codeMap[code.toUpperCase()];
          }
          if (shiftId == null) {
            for (final def in defs.values) {
              if (def.name == code || def.id == code) {
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
      } catch (_) {
        return DecodedRosterResult(
          importResult: CsvImportResult([], ['緊湊排班報文格式異常，無法解析數據體']),
        );
      }
    }
  }

  // 2. 判斷 v1 報文協議：SHIFTROSTER:v1:...
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

      if (expectedLen != null && bytes.length != expectedLen) {
        return DecodedRosterResult(
          importResult: CsvImportResult(
              [], ['報文長度不符（預期 $expectedLen 字節，實為 ${bytes.length} 字節），內容被截斷']),
        );
      }

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

          final codeMap = <String, String>{};
          final slotMap = <String, String>{};
          for (final def in defs.values) {
            if (def.code.isNotEmpty) codeMap[def.code.toUpperCase()] = def.id;
            final slotKey =
                '${normalizeSlot(def.startTime)}-${normalizeSlot(def.endTime)}';
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

            String? shiftId;
            if (code.isNotEmpty) {
              shiftId = codeMap[code.toUpperCase()];
            }
            if (shiftId == null && slot.isNotEmpty) {
              final norm = normalizeSlot(slot);
              if (norm != null) shiftId = slotMap[norm];
            }
            if (shiftId == null) {
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

  // 3. Fallback: 傳統 CSV 文字解析（相容 Excel 複製或手打格式）
  final csvRes = parseRosterCsv(rawTrimmed, defs);
  return DecodedRosterResult(
    importResult: csvRes,
    isPacket: false,
  );
}
