import 'shift_store.dart';

/// CSV 排班導入解析（純函數，可 unit test）。
/// 格式：每行 `YYYY-MM-DD,code,venue`，例如 `2026-10-15,06,A1`。
/// code 係班次代號（班次管理頁設置，≤4 英數字）；對唔到代號時，
/// 會 fallback 試舊格式嘅時段（HH-HH 或 HH:mm-HH:mm）。

class CsvImportRow {
  final String date; // YYYY-MM-DD
  final String shiftId;
  final String venue; // 已截到 ≤4 字
  final String remark; // 超長場所嘅全文（無就係 ''）
  CsvImportRow(this.date, this.shiftId, this.venue, [this.remark = '']);
}

class CsvImportResult {
  final List<CsvImportRow> valid;
  final List<String> errors; // "行 3：..." 格式
  CsvImportResult(this.valid, this.errors);
}

/// 單行太長（>500 字）直接當錯誤跳過，唔好爆。
const int _kMaxLineLength = 500;

/// 檢查一行「引號外」有冇半角逗號（`""` 轉義會跳過）。
///
/// 用途：決定呢行要唔要連全角逗號 `，` 都當分隔符——詳見 [splitCsvLine]。
bool _hasHalfWidthCommaOutsideQuotes(String line) {
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      // 引號內連續兩個 `""` 係轉義，唔會改變引號狀態
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        i++;
        continue;
      }
      inQuotes = !inQuotes;
      continue;
    }
    if (!inQuotes && ch == ',') return true;
  }
  return false;
}

/// 最小可用嘅 RFC4180 風格欄位切分（P2-10）。
///
/// **為什麼唔可以 `line.split(',')`：**
/// 1. 備註／場所欄用引號包住時可以內含半角逗號（`"早班, 有津貼"`），
///    直接 split 會把一個欄位切成兩個，令後面所有欄位錯位。
/// 2. 用戶由微信／中文版 Excel 貼上時，分隔符可能係**全角逗號 `，`**
///    （U+FF0C）。舊版只認半角逗號，整行會變成一欄 → 解析失敗。
///
/// 規則（刻意保持最小，唔做多行引號等 RFC 全功能）：
/// - `"..."` 包住嘅欄位：內含逗號／全角逗號都唔切，`""` 代表一個字面 `"`。
/// - 全角逗號 `，` 只喺**整行引號外冇任何半角逗號**時才當分隔符。
///   為什麼要咁保守：場所名本身可以含全角逗號（例如「A，B」），如果
///   一律把 `，` 當分隔符，`2026-10-05,00-06,A，B` 會被多切一刀，場所
///   由「A，B」靜靜變成「A」——呢個係比原 bug 更難察覺嘅資料失真。
///   反過來，純全角格式（`2026-10-05，A，早班`）引號外冇半角逗號，
///   所以照樣切得開。混合格式（同一行半角＋全角並用）本身有歧義，
///   會落返「日期格式唔啱」嘅錯誤提示，唔會靜靜猜錯。
/// - 引號外的半角逗號一律係分隔符；未閉合嘅引號當「食到行尾」。
/// - 向後兼容：純半角逗號、無引號嘅簡單 CSV 行為完全不變。
List<String> splitCsvLine(String line) {
  final fullWidthIsSeparator = !_hasHalfWidthCommaOutsideQuotes(line);
  final out = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  var i = 0;
  while (i < line.length) {
    final ch = line[i];
    if (inQuotes) {
      if (ch == '"') {
        // `""` 轉義：引號內連續兩個雙引號＝一個字面雙引號
        if (i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      buf.write(ch);
      i++;
      continue;
    }
    if (ch == '"') {
      inQuotes = true;
      i++;
      continue;
    }
    if (ch == ',' || (fullWidthIsSeparator && ch == '，')) {
      out.add(buf.toString());
      buf.clear();
      i++;
      continue;
    }
    buf.write(ch);
    i++;
  }
  out.add(buf.toString());
  return out;
}

CsvImportResult parseRosterCsv(String text, Map<String, ShiftDef> defs) {
  final valid = <CsvImportRow>[];
  final errors = <String>[];
  // 建 code → shiftId 對照（優先）
  final codeMap = <String, String>{};
  for (final def in defs.values) {
    if (def.code.isNotEmpty) codeMap[def.code.toUpperCase()] = def.id;
  }
  // 建 slot → shiftId 對照（fallback，舊格式）
  final slotMap = <String, String>{};
  for (final def in defs.values) {
    final s = _hourOf(def.startTime);
    final e = _hourOf(def.endTime);
    if (s != null && e != null) slotMap['$s-$e'] = def.id;
  }
  final lines = text.split('\n');
  for (var li = 0; li < lines.length; li++) {
    final line = lines[li].trim();
    if (line.isEmpty) continue;
    if (line.length > _kMaxLineLength) {
      errors.add('行 ${li + 1}：太長（超過 $_kMaxLineLength 字，已跳過）');
      continue;
    }
    // P2-10：用支援引號與全角逗號嘅切分器，唔再用 `line.split(',')`
    final parts = splitCsvLine(line);
    if (parts.length < 2) {
      errors.add('行 ${li + 1}：格式唔啱（要 YYYY-MM-DD,代號,場所）');
      continue;
    }
    final date = parts[0].trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) || !_validDate(date)) {
      errors.add('行 ${li + 1}：日期格式唔啱（$date）');
      continue;
    }
    final codeRaw = parts[1].trim();
    // 先試代號（唔分大細楷），唔得再試舊時段格式
    var shiftId = codeMap[codeRaw.toUpperCase()];
    if (shiftId == null) {
      final slotKey = normalizeSlot(codeRaw);
      if (slotKey != null) shiftId = slotMap[slotKey];
    }
    if (shiftId == null) {
      errors.add('行 ${li + 1}：代號 $codeRaw 對唔到任何班次');
      continue;
    }
    var venue = parts.length > 2 ? parts[2].trim() : '';
    // 場所超 4 單位：截到 ≤4 單位做場所，全文入備註（日曆格設計俾四個字）。
    // 注意：用 abbrUnits（全形＝2），唔係 runes.length，否則中文字會超闊。
    var remark = '';
    if (abbrUnits(venue) > 4) {
      remark = venue;
      venue = truncateAbbr(venue);
    }
    valid.add(CsvImportRow(date, shiftId, venue, remark));
  }
  return CsvImportResult(valid, errors);
}

int? _hourOf(String hhmm) {
  try {
    final p = hhmm.split(':');
    return int.parse(p.isNotEmpty ? p[0] : '');
  } catch (_) {
    return null;
  }
}

/// "00-06" → "0-6"；"00:00-06:00" → "0-6"；其他回 null
String? normalizeSlot(String s) {
  var m = RegExp(r'^(\d{1,2})-(\d{1,2})$').firstMatch(s);
  if (m != null) {
    final a = int.tryParse(m.group(1)!);
    final b = int.tryParse(m.group(2)!);
    if (a == null || b == null || a > 23 || b > 23) return null;
    return '$a-$b';
  }
  m = RegExp(r'^(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})$').firstMatch(s);
  if (m != null) {
    final a = int.tryParse(m.group(1)!);
    final b = int.tryParse(m.group(3)!);
    if (a == null || b == null || a > 23 || b > 23) return null;
    return '$a-$b';
  }
  return null;
}

bool _validDate(String ymd) {
  try {
    final p = ymd.split('-').map(int.parse).toList();
    final d = DateTime(p[0], p[1], p[2]);
    return d.year == p[0] && d.month == p[1] && d.day == p[2];
  } catch (_) {
    return false;
  }
}
