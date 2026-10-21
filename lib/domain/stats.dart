/// 排班統計純函數：零 Flutter 依賴，可單元測試。
/// UI 層（stats_screen.dart）只負責由 ShiftStore 組裝 [ShiftRecord]＋畫圖。
library;

/// 統計區間（按顯示順序）
enum StatsRange {
  thisMonth, // 本月：當月1號 → 今日
  last7Days, // 最近7天：今日往前7天（含今日）
  last30Days, // 近1月：往前30天（含今日）
  last90Days, // 近3月：往前90天（含今日）
  last365Days, // 近1年：往前365天（含今日）
  yearToDate, // 今年起：1月1日 → 今日
  lastYear, // 去年全年：去年1/1 – 12/31
}

/// 閉區間 [start, end]，年月日精度。
class DateRange {
  final DateTime start;
  final DateTime end;

  const DateRange(this.start, this.end);

  /// 區間總天數（含頭尾）
  int get totalDays => end.difference(_day(start)).inDays + 1;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
}

extension StatsRangeX on StatsRange {
  String get label => switch (this) {
        StatsRange.thisMonth => '本月',
        StatsRange.last7Days => '最近7天',
        StatsRange.last30Days => '近1月',
        StatsRange.last90Days => '近3月',
        StatsRange.last365Days => '近1年',
        StatsRange.yearToDate => '今年起',
        StatsRange.lastYear => '去年全年',
      };

  /// 按「今日」計出區間（閉區間，含頭尾）。
  DateRange range(DateTime today) {
    final t = DateTime(today.year, today.month, today.day);
    DateTime ago(int n) => t.subtract(Duration(days: n));
    return switch (this) {
      StatsRange.thisMonth => DateRange(DateTime(t.year, t.month, 1), t),
      StatsRange.last7Days => DateRange(ago(6), t),
      StatsRange.last30Days => DateRange(ago(29), t),
      StatsRange.last90Days => DateRange(ago(89), t),
      StatsRange.last365Days => DateRange(ago(364), t),
      StatsRange.yearToDate => DateRange(DateTime(t.year, 1, 1), t),
      StatsRange.lastYear =>
        DateRange(DateTime(t.year - 1, 1, 1), DateTime(t.year - 1, 12, 31)),
    };
  }
}

/// 時段標籤（順序對應 slotIndex 0–3）
const List<String> slotLabels = ['00–06', '06–12', '12–18', '18–00'];

/// 按開工鐘點取時段序號（規則同 app_theme slotForHour 一致）
int slotIndexForHour(int hour) {
  if (hour < 6) return 0;
  if (hour < 12) return 1;
  if (hour < 18) return 2;
  return 3;
}

/// 按 "HH:mm" 取時段序號
int slotIndexForTime(String hhmm) {
  final hour = int.tryParse(hhmm.split(':').firstOrNull ?? '') ?? 0;
  return slotIndexForHour(hour.clamp(0, 23));
}

/// 嚴格 "HH:mm" 解析：必須剛好兩段、兩位數字、h 0–23、m 0–59。
/// 不合格式回 null，**永不拋異常**。
///
/// 刻意比 `ShiftDef.durationMinutes`（`shift_store.dart`，寬鬆版）嚴格：
/// 寬鬆版用 `int.tryParse` + `% 1440`，'09:60' 會被讀成 10:00、
/// '24:00' 會被讀成 0:00。那套寬鬆規則用於「由爛設定推一個盡量可用的
/// 收工打卡 offset」，可以接受；但統計頁要把分鐘數顯示給使用者看，
/// 寧可顯示 0 也不可以顯示一個憑空捏造的精確數字。
final RegExp _hhmmRe = RegExp(r'^([01][0-9]|2[0-3]):([0-5][0-9])$');

/// 'HH:mm' → 當日分鐘數（0–1439）；格式非法回 null（不拋異常）
int? _parseHm(String raw) {
  final m = _hhmmRe.firstMatch(raw.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  return h * 60 + min;
}

/// 班次時長（分鐘）。支援跨午夜（22:00→06:00 = 480）；設定非法回 0。
///
/// 規則：
/// - `e > s` → `e − s`
/// - `e < s` → `e + 1440 − s`（跨午夜）
/// - `e == s` → **0**
/// - 任一解析失敗 → 0
///
/// 關於 `e == s` 的取捨：同起同訖有兩種可能解讀——「未設定」或「24 小時班」。
/// 這裡刻意取「未設定 → 0」，不放大成 1440。理由：24 小時班在排班 App 中
/// 幾乎不存在，而「使用者清空了結束時間」是常見的中間狀態；若放大成 24 小時，
/// 統計頁會在設定尚未填完的瞬間顯示一個暴增的假工時，比顯示 0 更誤導。
int shiftDurationMinutes(String startTime, String endTime) {
  final s = _parseHm(startTime);
  final e = _parseHm(endTime);
  if (s == null || e == null) return 0;
  if (e > s) return e - s;
  if (e < s) return e + 1440 - s;
  return 0;
}

/// 區間內有排班嘅一日
class ShiftRecord {
  final String ymd; // '2026-10-15'
  final String shiftId;
  final String venue; // note（場所），可為空字串
  final int slotIndex; // 0–3

  /// 該更實際時長（分鐘）。由呼叫端用 [shiftDurationMinutes] 算好傳入。
  ///
  /// 刻意設為 **required** 而非給預設值：讓每個呼叫端在編譯期被迫交代真實時長。
  /// 若給預設 360，日後新增呼叫端忘記傳就會靜默退回「每更 6 小時」的舊 bug，
  /// 而那種 bug 在測試裡看不出來（因為測試也會忘記傳）。
  final int durationMinutes;

  const ShiftRecord({
    required this.ymd,
    required this.shiftId,
    required this.slotIndex,
    this.venue = '',
    required this.durationMinutes,
  });
}

class StatsResult {
  final DateRange range;
  final int workDays; // 返工日數
  final List<int> slotDays; // 長度 4：各時段日數
  final List<MapEntry<String, int>> venueCounts; // 場所 → 次數，按次數降序

  /// 總工時（分鐘）。同一日多筆只計第一筆（與 [workDays] 口徑一致）。
  final int totalMinutes;

  const StatsResult({
    required this.range,
    required this.workDays,
    required this.slotDays,
    required this.venueCounts,
    required this.totalMinutes,
  });

  int get totalDays => range.totalDays;

  /// 防禦外部誤傳負值；[computeStats] 已保證非負，此處再兜一次。
  int get _safeMinutes => totalMinutes < 0 ? 0 : totalMinutes;

  /// 總工時（小時，向下取整）。僅供相容舊呼叫端，**顯示請用 [durationLabel]**。
  /// 19 小時 30 分會回 19（不是 20），避免「看起多了半小時」的錯覺。
  int get workHours => _safeMinutes ~/ 60;

  /// 顯示用：「19 小時 30 分」；餘數為 0 時只顯示「20 小時」。
  /// 不做千分位、不寫「19.5 小時」——中文語境下「小時＋分」最不易誤讀。
  String get durationLabel {
    final mins = _safeMinutes;
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '$h 小時' : '$h 小時 $m 分';
  }

  /// 休息日數：區間總天數 − 返工日數
  int get restDays => totalDays - workDays;

  /// 某時段佔返工日數百分比（0–100）
  double slotPercent(int slot) =>
      workDays == 0 ? 0 : slotDays[slot] * 100 / workDays;
}

final _ymdRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

bool _inRange(String ymd, DateTime start, DateTime end) {
  final m = _ymdRe.firstMatch(ymd.trim());
  if (m == null) return false;
  final d = DateTime(
      int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  return !d.isBefore(start) && !d.isAfter(end);
}

/// 由區間＋排班紀錄計統計：
/// - 區間外嘅紀錄忽略；同一日多筆只計一次；空場所唔入場所分佈。
/// - 總工時按每筆 `durationMinutes` 累加，負值當 0。
StatsResult computeStats(DateRange range, List<ShiftRecord> records) {
  final start =
      DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  final seen = <String>{};
  final slotDays = [0, 0, 0, 0];
  final venues = <String, int>{};
  var totalMinutes = 0;
  for (final r in records) {
    if (!_inRange(r.ymd, start, end)) continue;
    // 同一日多筆只計一次——工時累加必須在這一關之後，
    // 否則同日重複紀錄會把總工時翻倍（同 workDays 口徑不一致）。
    if (!seen.add(r.ymd)) continue;
    if (r.durationMinutes > 0) totalMinutes += r.durationMinutes;
    slotDays[r.slotIndex.clamp(0, 3)]++;
    final v = r.venue.trim();
    if (v.isNotEmpty) venues[v] = (venues[v] ?? 0) + 1;
  }
  final sorted = venues.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return StatsResult(
    range: range,
    workDays: seen.length,
    slotDays: slotDays,
    venueCounts: sorted,
    totalMinutes: totalMinutes,
  );
}
