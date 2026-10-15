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
    final parts = line.split(',');
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
