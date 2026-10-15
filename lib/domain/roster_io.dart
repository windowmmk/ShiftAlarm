/// 排班表導出與導入模組：支援最新極簡 SR2 Base58 報文協議與純 CSV 雙模相容
/// - 外部協議報文頭：SR2:<Base58>（CRC32 與時間戳內嵌二進制，長度約 150-250 字元）
/// - 雙模支援：貼上 SR2 口令或純 CSV 文字均可無縫解析
library;

import 'dart:convert';
import 'dart:typed_data';

import 'base58.dart';
import 'config_io.dart' show computeCrc32;
import 'csv_import.dart';
import 'shift_store.dart';

/// 排班報文頭協議標識與快速檢查（用於剪貼簿自動辨識）
class RosterPacketHeader {
  static const String prefix = 'SR2:';

  /// 快速檢查文字是否符合排班報文頭（零成本避免誤報）
  static bool matches(String text) {
    final clean = text.trim().replaceAll(RegExp(r'\s+'), '');
    return clean.startsWith('SR2:');
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

/// 導出為帶有極簡協議報文頭（SR2:<Base58>）的極速緊湊 Base58 排班口令碼：
/// 報文頭內化打包：CRC32（4 字節）與時間戳（4 字節）直接嵌入二進制數據體，
/// 外部前綴僅 4 字元（SR2:），整月排班長度由 3500+ 字元壓縮至 200~240 字元！
String exportRosterCode(ShiftStore store, {DateTime? month}) {
  final dataBytes = encodeCompactRoster(store, month: month);
  final crc = computeCrc32(dataBytes);
  final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  final bb = BytesBuilder();
  final crcBd = ByteData(4)..setUint32(0, crc, Endian.big);
  bb.add(crcBd.buffer.asUint8List());

  final tsBd = ByteData(4)..setUint32(0, nowTs, Endian.big);
  bb.add(tsBd.buffer.asUint8List());

  bb.add(dataBytes);

  final packetBytes = bb.toBytes();
  final b58 = base58Encode(packetBytes);
  return 'SR2:$b58';
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

/// 解析緊湊排班數據體（v2）
DecodedRosterResult _parseCompactRosterPayload({
  required Uint8List dataBytes,
  required Map<String, ShiftDef> defs,
  required String? crcHex,
  required int byteLen,
  required DateTime? exportTime,
  required bool crcVerified,
}) {
  try {
    var offset = 0;
    final version = dataBytes[offset++];
    if (version != 2) {
      return DecodedRosterResult(
        importResult: CsvImportResult([], ['不支援的排班協議版本: $version']),
      );
    }

    final countBd = ByteData.sublistView(dataBytes, offset, offset + 2);
    final count = countBd.getUint16(0, Endian.big);
    offset += 2;

    final valid = <CsvImportRow>[];
    final errors = <String>[];

    final codeMap = <String, String>{};
    for (final def in defs.values) {
      if (def.code.isNotEmpty) codeMap[def.code.toUpperCase()] = def.id;
    }

    for (int i = 0; i < count; i++) {
      final yBd = ByteData.sublistView(dataBytes, offset, offset + 2);
      final y = yBd.getUint16(0, Endian.big);
      offset += 2;
      final m = dataBytes[offset++];
      final d = dataBytes[offset++];
      final date =
          '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';

      final codeLen = dataBytes[offset++];
      final code = utf8.decode(dataBytes.sublist(offset, offset + codeLen));
      offset += codeLen;

      final venueLen = dataBytes[offset++];
      var venue = utf8.decode(dataBytes.sublist(offset, offset + venueLen));
      offset += venueLen;

      final remarkLen = dataBytes[offset++];
      var remark = utf8.decode(dataBytes.sublist(offset, offset + remarkLen));
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
      crcHex: crcHex,
      byteLen: byteLen,
      exportTime: exportTime,
      crcVerified: crcVerified,
      isPacket: true,
    );
  } catch (_) {
    return DecodedRosterResult(
      importResult: CsvImportResult([], ['緊湊排班報文格式異常，無法解析數據體']),
    );
  }
}

/// 解析排班文字：僅支援極簡 SR2 報文口令或傳統 CSV
DecodedRosterResult decodeRosterText(
    String text, Map<String, ShiftDef> defs) {
  final rawTrimmed = text.trim();
  if (rawTrimmed.isEmpty) {
    return DecodedRosterResult(
      importResult: CsvImportResult([], ['內容係空嘅']),
    );
  }

  final cleanText = rawTrimmed.replaceAll(RegExp(r'\s+'), '');

  // 1. 極簡 v2 排班協議：SR2:<Base58>
  if (cleanText.startsWith('SR2:')) {
    final payload = cleanText.substring(4);
    List<int>? bytes;
    try {
      bytes = base58Decode(payload);
    } catch (_) {}

    if (bytes == null || bytes.length < 11) {
      return DecodedRosterResult(
        importResult: CsvImportResult([], ['極簡排班口令數據損壞或長度不足']),
      );
    }

    final u8 = Uint8List.fromList(bytes);
    final expectedCrc =
        ByteData.sublistView(u8, 0, 4).getUint32(0, Endian.big);
    final tsSec =
        ByteData.sublistView(u8, 4, 8).getUint32(0, Endian.big);
    final exportTime = DateTime.fromMillisecondsSinceEpoch(tsSec * 1000);
    final dataBytes = Uint8List.sublistView(u8, 8);

    final actualCrc = computeCrc32(dataBytes);
    if (actualCrc != expectedCrc) {
      return DecodedRosterResult(
        importResult: CsvImportResult([], ['報文校驗碼不符（內容可能損壞或未完整複製）']),
      );
    }

    return _parseCompactRosterPayload(
      dataBytes: dataBytes,
      defs: defs,
      crcHex: expectedCrc.toRadixString(16).padLeft(8, '0'),
      byteLen: bytes.length,
      exportTime: exportTime,
      crcVerified: true,
    );
  }

  // 2. 傳統純 CSV 文字解析（相容 Excel 複製或手打格式）
  final csvRes = parseRosterCsv(rawTrimmed, defs);
  return DecodedRosterResult(
    importResult: csvRes,
    isPacket: false,
  );
}
