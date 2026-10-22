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
import 'stats.dart' show isValidYmd;

/// 單一欄位長度上限：協議用 1 字節存長度，所以最多 255 字節。
const int _kMaxFieldBytes = 255;

/// 按 UTF-8 位元組上限安全截斷字串（預設 ≤255 字節）。
///
/// **為什麼唔可以直接 `bytes.sublist(0, 255)`：**
/// UTF-8 一個中文字佔 3 字節、一個 emoji 佔 4 字節，第 255 個字節好可能
/// 正好落在某個多位元組序列的中間（續接字節高位係 `0b10xxxxxx`）。
/// 咁樣切出嚟嘅 bytes 唔係合法 UTF-8：寫入端會寫 255 字節但解碼端
/// `utf8.decode` 會拋錯／回亂碼，而長度字段本身又同實際內容對唔上，
/// 結果係**整份分享碼**（唔止備註）報「格式錯誤」，導入完全失敗。
/// 所以截斷點必須回退到合法序列邊界（回退到該字元的起始字節之前）。
///
/// 截斷係有損（備註會少幾個字），但遠好過整份排班表報廢導入唔到。
/// 呢個係協議限制（長度 1 字節）造成，唔係刻意設計。
Uint8List _truncateUtf8(String s, [int maxBytes = _kMaxFieldBytes]) {
  final bytes = utf8.encode(s);
  if (bytes.length <= maxBytes) return Uint8List.fromList(bytes);
  var end = maxBytes;
  // bytes[end] 係「第一個唔要嘅字節」；若佢係續接字節，即代表切點落喺
  // 某個多位元組字元中間，要一路往前退，直到切點前嘅字節係字元起始字節。
  while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
    end--;
  }
  return Uint8List.fromList(bytes.sublist(0, end));
}

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
    // P1-8：班次 `code` 係選填欄位（見 shift_store.dart `ShiftDef.code`），
    // 用戶可以完全唔填代號。舊版直接攞 code 做導入比對 key，多個空白 code
    // 嘅班次就會撞成同一個 key（全部都係 ''），導入時班次對錯晒。
    // 所以 code 為空時 fallback 用「startTime-endTime」做 key：班次時間係
    // 必填欄位，導入端一樣可以重建同一個字串，唔會撞 key。
    final rawCode = (def?.code ?? '').trim();
    final shiftKey =
        rawCode.isNotEmpty ? rawCode : (def != null ? _slotKeyOf(def) : '');
    final codeBytes = _truncateUtf8(shiftKey);
    bb.addByte(codeBytes.length);
    bb.add(codeBytes);

    final venueBytes = _truncateUtf8(e.value.note);
    bb.addByte(venueBytes.length);
    bb.add(venueBytes);

    final remark = store.remarks[e.key] ?? '';
    // P1-4：備註由 UI 限制 200 字，中文 200 字＝600 字節，遠超 1 字節長度
    // 上限 255。舊版寫 `length.clamp(0,255)` 做長度但 `add(全部 bytes)`，
    // 長度字段同實際內容一對唔上 → 解碼器讀到錯位 → CRC32 不符 →
    // 用戶分享出去嘅**整份**排班表別人都導入唔到。
    // 現在長度同內容都來自同一份截斷後 bytes，兩者永遠一致。
    final remarkBytes = _truncateUtf8(remark);
    bb.addByte(remarkBytes.length);
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

/// 班次時間 key：`startTime-endTime`（例如 `06:00-12:00`）。
///
/// 用於 P1-8：班次 `code` 為空時的 fallback 比對 key。編碼同解碼兩邊
/// 都用同一個函數產生，保證字串格式完全一致（連 `HH:mm` 補零方式都一樣）。
String _slotKeyOf(ShiftDef def) => '${def.startTime}-${def.endTime}';

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

    // 導入端的班次比對表（P1-8）：
    // 1. codeMap：非空 code → shiftId（代號優先，唔分大細楷）
    // 2. slotMap：`startTime-endTime` → shiftId（code 為空時的 fallback，
    //    同編碼端 `_slotKeyOf` 用同一個字串格式）
    final codeMap = <String, String>{};
    final slotMap = <String, String>{};
    for (final def in defs.values) {
      final c = def.code.trim();
      if (c.isNotEmpty) codeMap[c.toUpperCase()] = def.id;
      slotMap[_slotKeyOf(def)] = def.id;
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

      // P1-5：日期驗證。y/m/d 係原始字節，理論上 CRC 已擋住篡改，但舊版
      // 或第三方寫出嘅數據體可能含 `2026-02-30` 呢類「格式啱但日子唔存在」
      // 嘅日期。舊版照收，之後統計就會把呢筆歸入錯區間（DateTime 會自動
      // 進位成 3 月 2 日）。呢度跳過該筆並計入 errors，**唔會**令整份
      // 分享碼導入失敗——其餘日子照樣入到。
      // 注意：一定要讀完 code/venue/remark 之後才 continue，否則 offset 會錯位。
      if (!isValidYmd(date)) {
        errors.add('$date：日期唔存在，已跳過（其餘日子不受影響）');
        continue;
      }

      String? shiftId;
      final key = code.trim();
      if (key.isNotEmpty) {
        // 先按代號（唔分大細楷）
        shiftId = codeMap[key.toUpperCase()];
        // 再按「startTime-endTime」fallback（編碼端 code 為空時寫入嘅 key）
        shiftId ??= slotMap[key];
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
