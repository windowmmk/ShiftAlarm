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

/// 區間內有排班嘅一日
class ShiftRecord {
  final String ymd; // '2026-10-15'
  final String shiftId;
  final String venue; // note（場所），可為空字串
  final int slotIndex; // 0–3

  const ShiftRecord({
    required this.ymd,
    required this.shiftId,
    required this.slotIndex,
    this.venue = '',
  });
}

class StatsResult {
  final DateRange range;
  final int workDays; // 返工日數
  final List<int> slotDays; // 長度 4：各時段日數
  final List<MapEntry<String, int>> venueCounts; // 場所 → 次數，按次數降序

  const StatsResult({
    required this.range,
    required this.workDays,
    required this.slotDays,
    required this.venueCounts,
  });

  int get totalDays => range.totalDays;

  /// 總工時：每更 6 小時
  int get workHours => workDays * 6;

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
StatsResult computeStats(DateRange range, List<ShiftRecord> records) {
  final start =
      DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  final seen = <String>{};
  final slotDays = [0, 0, 0, 0];
  final venues = <String, int>{};
  for (final r in records) {
    if (!_inRange(r.ymd, start, end)) continue;
    if (!seen.add(r.ymd)) continue;
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
  );
}
