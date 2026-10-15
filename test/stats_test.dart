import 'package:flutter_test/flutter_test.dart';
import 'package:shiftalarm/domain/stats.dart';

/// 統計純函數測試：假數據驗區間、日數、百分比、場所排序。
void main() {
  group('區間邊界（今日＝2026-10-14）', () {
    final today = DateTime(2026, 10, 14);

    test('本月：10月1日 → 今日', () {
      final r = StatsRange.thisMonth.range(today);
      expect(r.start, DateTime(2026, 10, 1));
      expect(r.end, DateTime(2026, 10, 14));
      expect(r.totalDays, 14);
    });

    test('最近7天：含今日共7天', () {
      final r = StatsRange.last7Days.range(today);
      expect(r.start, DateTime(2026, 10, 8));
      expect(r.end, DateTime(2026, 10, 14));
      expect(r.totalDays, 7);
    });

    test('近1月：往前30天', () {
      final r = StatsRange.last30Days.range(today);
      expect(r.start, DateTime(2026, 9, 15));
      expect(r.end, DateTime(2026, 10, 14));
      expect(r.totalDays, 30);
    });

    test('近3月：往前90天', () {
      final r = StatsRange.last90Days.range(today);
      expect(r.start, DateTime(2026, 7, 17));
      expect(r.end, DateTime(2026, 10, 14));
      expect(r.totalDays, 90);
    });

    test('近1年：往前365天', () {
      final r = StatsRange.last365Days.range(today);
      expect(r.start, DateTime(2025, 10, 15));
      expect(r.end, DateTime(2026, 10, 14));
      expect(r.totalDays, 365);
    });

    test('今年起：1月1日 → 今日', () {
      final r = StatsRange.yearToDate.range(today);
      expect(r.start, DateTime(2026, 1, 1));
      expect(r.end, DateTime(2026, 10, 14));
      expect(r.totalDays, 287);
    });

    test('去年全年：去年1/1 – 12/31', () {
      final r = StatsRange.lastYear.range(today);
      expect(r.start, DateTime(2025, 1, 1));
      expect(r.end, DateTime(2025, 12, 31));
      expect(r.totalDays, 365);
    });
  });

  group('computeStats', () {
    DateRange tenDays() => DateRange(DateTime(2026, 10, 5), DateTime(2026, 10, 14));

    test('日數／工時／休息：10天區間，排咗6日更', () {
      final r = computeStats(tenDays(), [
        const ShiftRecord(ymd: '2026-10-05', shiftId: 's00', slotIndex: 0),
        const ShiftRecord(ymd: '2026-10-06', shiftId: 's06', slotIndex: 1),
        const ShiftRecord(ymd: '2026-10-08', shiftId: 's12', slotIndex: 2),
        const ShiftRecord(ymd: '2026-10-10', shiftId: 's18', slotIndex: 3),
        const ShiftRecord(ymd: '2026-10-12', shiftId: 's00', slotIndex: 0),
        const ShiftRecord(ymd: '2026-10-14', shiftId: 's06', slotIndex: 1),
      ]);
      expect(r.totalDays, 10);
      expect(r.workDays, 6);
      expect(r.workHours, 36); // 6 × 6
      expect(r.restDays, 4); // 10 − 6
    });

    test('區間外紀錄忽略、同一日多筆只計一次', () {
      final r = computeStats(tenDays(), [
        const ShiftRecord(ymd: '2026-10-04', shiftId: 's00', slotIndex: 0), // 前一日
        const ShiftRecord(ymd: '2026-10-15', shiftId: 's06', slotIndex: 1), // 後一日
        const ShiftRecord(ymd: '2026-10-10', shiftId: 's12', slotIndex: 2),
        const ShiftRecord(ymd: '2026-10-10', shiftId: 's18', slotIndex: 3), // 同日重複
      ]);
      expect(r.workDays, 1);
      expect(r.slotDays, [0, 0, 1, 0]);
    });

    test('班次分佈日數＋百分比', () {
      final r = computeStats(tenDays(), [
        const ShiftRecord(ymd: '2026-10-05', shiftId: 's00', slotIndex: 0),
        const ShiftRecord(ymd: '2026-10-06', shiftId: 's06', slotIndex: 1),
        const ShiftRecord(ymd: '2026-10-08', shiftId: 's06', slotIndex: 1),
        const ShiftRecord(ymd: '2026-10-10', shiftId: 's18', slotIndex: 3),
      ]);
      expect(r.slotDays, [1, 2, 0, 1]);
      expect(r.slotPercent(0), 25.0);
      expect(r.slotPercent(1), 50.0);
      expect(r.slotPercent(2), 0.0);
      expect(r.slotPercent(3), 25.0);
    });

    test('空區間唔除零', () {
      final r = computeStats(tenDays(), []);
      expect(r.workDays, 0);
      expect(r.workHours, 0);
      expect(r.restDays, 10);
      expect(r.slotPercent(0), 0);
    });

    test('場所分佈按次數降序、空場所唔計', () {
      final r = computeStats(tenDays(), [
        const ShiftRecord(ymd: '2026-10-05', shiftId: 's00', slotIndex: 0, venue: 'SITE_A'),
        const ShiftRecord(ymd: '2026-10-06', shiftId: 's06', slotIndex: 1, venue: 'SITE_B'),
        const ShiftRecord(ymd: '2026-10-08', shiftId: 's12', slotIndex: 2, venue: 'SITE_A'),
        const ShiftRecord(ymd: '2026-10-10', shiftId: 's18', slotIndex: 3, venue: ''),
        const ShiftRecord(ymd: '2026-10-12', shiftId: 's00', slotIndex: 0, venue: 'SITE_A'),
      ]);
      expect(r.venueCounts.map((e) => e.key).toList(), ['SITE_A', 'SITE_B']);
      expect(r.venueCounts.map((e) => e.value).toList(), [3, 1]);
    });
  });

  group('slotIndexForTime', () {
    test('四更開工時間對到四段', () {
      expect(slotIndexForTime('00:00'), 0);
      expect(slotIndexForTime('06:00'), 1);
      expect(slotIndexForTime('12:00'), 2);
      expect(slotIndexForTime('18:00'), 3);
    });
    test('邊界鐘點', () {
      expect(slotIndexForTime('05:59'), 0);
      expect(slotIndexForTime('23:59'), 3);
      expect(slotIndexForTime('11:30'), 1);
      expect(slotIndexForTime('17:59'), 2);
    });
    test('爛格式唔 crash，當 00:00', () {
      expect(slotIndexForTime('爛'), 0);
      expect(slotIndexForTime(''), 0);
    });
  });
}
