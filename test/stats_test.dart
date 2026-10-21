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
        const ShiftRecord(
            ymd: '2026-10-05',
            shiftId: 's00',
            slotIndex: 0,
            durationMinutes: 360),
        const ShiftRecord(
            ymd: '2026-10-06',
            shiftId: 's06',
            slotIndex: 1,
            durationMinutes: 360),
        const ShiftRecord(
            ymd: '2026-10-08',
            shiftId: 's12',
            slotIndex: 2,
            durationMinutes: 360),
        const ShiftRecord(
            ymd: '2026-10-10',
            shiftId: 's18',
            slotIndex: 3,
            durationMinutes: 360),
        const ShiftRecord(
            ymd: '2026-10-12',
            shiftId: 's00',
            slotIndex: 0,
            durationMinutes: 360),
        const ShiftRecord(
            ymd: '2026-10-14',
            shiftId: 's06',
            slotIndex: 1,
            durationMinutes: 360),
      ]);
      expect(r.totalDays, 10);
      expect(r.workDays, 6);
      expect(r.workHours, 36); // 6 × 6（每筆 360 分鐘）——舊行為回歸鎖
      expect(r.totalMinutes, 2160);
      expect(r.restDays, 4); // 10 − 6
    });

    test('區間外紀錄忽略、同一日多筆只計一次', () {
      final r = computeStats(tenDays(), [
        const ShiftRecord(
            ymd: '2026-10-04',
            shiftId: 's00',
            slotIndex: 0,
            durationMinutes: 360), // 前一日
        const ShiftRecord(
            ymd: '2026-10-15',
            shiftId: 's06',
            slotIndex: 1,
            durationMinutes: 360), // 後一日
        const ShiftRecord(
            ymd: '2026-10-10',
            shiftId: 's12',
            slotIndex: 2,
            durationMinutes: 360),
        const ShiftRecord(
            ymd: '2026-10-10',
            shiftId: 's18',
            slotIndex: 3,
            durationMinutes: 360), // 同日重複
      ]);
      expect(r.workDays, 1);
      expect(r.slotDays, [0, 0, 1, 0]);
      expect(r.totalMinutes, 360); // 同日重複只計第一筆
    });

    test('班次分佈日數＋百分比', () {
      final r = computeStats(tenDays(), [
        const ShiftRecord(
            ymd: '2026-10-05',
            shiftId: 's00',
            slotIndex: 0,
            durationMinutes: 360),
        const ShiftRecord(
            ymd: '2026-10-06',
            shiftId: 's06',
            slotIndex: 1,
            durationMinutes: 360),
        const ShiftRecord(
            ymd: '2026-10-08',
            shiftId: 's06',
            slotIndex: 1,
            durationMinutes: 360),
        const ShiftRecord(
            ymd: '2026-10-10',
            shiftId: 's18',
            slotIndex: 3,
            durationMinutes: 360),
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
      expect(r.totalMinutes, 0);
      expect(r.durationLabel, '0 小時');
      expect(r.restDays, 10);
      expect(r.slotPercent(0), 0);
    });

    test('場所分佈按次數降序、空場所唔計', () {
      final r = computeStats(tenDays(), [
        const ShiftRecord(
            ymd: '2026-10-05',
            shiftId: 's00',
            slotIndex: 0,
            venue: 'SITE_A',
            durationMinutes: 360),
        const ShiftRecord(
            ymd: '2026-10-06',
            shiftId: 's06',
            slotIndex: 1,
            venue: 'SITE_B',
            durationMinutes: 360),
        const ShiftRecord(
            ymd: '2026-10-08',
            shiftId: 's12',
            slotIndex: 2,
            venue: 'SITE_A',
            durationMinutes: 360),
        const ShiftRecord(
            ymd: '2026-10-10',
            shiftId: 's18',
            slotIndex: 3,
            venue: '',
            durationMinutes: 360),
        const ShiftRecord(
            ymd: '2026-10-12',
            shiftId: 's00',
            slotIndex: 0,
            venue: 'SITE_A',
            durationMinutes: 360),
      ]);
      expect(r.venueCounts.map((e) => e.key).toList(), ['SITE_A', 'SITE_B']);
      expect(r.venueCounts.map((e) => e.value).toList(), [3, 1]);
    });
  });

  group('shiftDurationMinutes（班次實際長度）', () {
    test('同日：09:00–17:30 → 510 分鐘（8.5 小時）', () {
      expect(shiftDurationMinutes('09:00', '17:30'), 510);
    });

    test('跨午夜：22:00–06:00 → 480 分鐘', () {
      expect(shiftDurationMinutes('22:00', '06:00'), 480);
    });

    test('跨午夜極短：23:59–00:01 → 2 分鐘', () {
      expect(shiftDurationMinutes('23:59', '00:01'), 2);
    });

    test('同起同訖視為未設定 → 0（刻意不放大成 24 小時）', () {
      expect(shiftDurationMinutes('00:00', '00:00'), 0);
      expect(shiftDurationMinutes('08:00', '08:00'), 0);
    });

    test('非法輸入一律回 0，不拋異常', () {
      for (final bad in ['abc', '24:00', '09:60', '', ':30']) {
        expect(shiftDurationMinutes(bad, '17:30'), 0, reason: 'start=$bad');
        expect(shiftDurationMinutes('09:00', bad), 0, reason: 'end=$bad');
      }
      expect(shiftDurationMinutes('', ''), 0);
    });

    test('無補零寫法照收：「9」視為 09:00，與既有打卡鬧鐘語意一致', () {
      // 這條寬容度必須保留：同一支函數也是打卡鬧鐘 dk_out offset 的來源，
      // 把 '9' 打成 0 會令收工鐘在開工時刻響。
      expect(shiftDurationMinutes('9', '17:30'), 510);
      expect(shiftDurationMinutes('09:0', '17:30'), 510);
      // 多於兩段沿用舊版行為：只取前兩段
      expect(shiftDurationMinutes('09:00:00', '17:30'), 510);
    });
  });

  group('StatsResult 工時聚合（實際班次長度）', () {
    DateRange threeDays() =>
        DateRange(DateTime(2026, 10, 5), DateTime(2026, 10, 7));

    test('三個 6.5 小時班 → 1170 分鐘／「19 小時 30 分」／19 小時', () {
      final r = computeStats(threeDays(), [
        const ShiftRecord(
            ymd: '2026-10-05',
            shiftId: 's06',
            slotIndex: 1,
            durationMinutes: 390),
        const ShiftRecord(
            ymd: '2026-10-06',
            shiftId: 's06',
            slotIndex: 1,
            durationMinutes: 390),
        const ShiftRecord(
            ymd: '2026-10-07',
            shiftId: 's06',
            slotIndex: 1,
            durationMinutes: 390),
      ]);
      expect(r.totalMinutes, 1170);
      expect(r.durationLabel, '19 小時 30 分');
      expect(r.workHours, 19); // 向下取整
    });

    test('8 小時 + 12 小時 → 「20 小時」，證明沒有殘留固定 6 小時', () {
      final r = computeStats(threeDays(), [
        const ShiftRecord(
            ymd: '2026-10-05',
            shiftId: 's06',
            slotIndex: 1,
            durationMinutes: 480),
        const ShiftRecord(
            ymd: '2026-10-06',
            shiftId: 's18',
            slotIndex: 3,
            durationMinutes: 720),
      ]);
      expect(r.totalMinutes, 1200);
      expect(r.durationLabel, '20 小時');
      expect(r.workHours, 20);
      // 若仍按 workDays × 6 計算會是 12
      expect(r.workHours, isNot(12));
    });

    test('同一日兩筆不同時長：只計第一筆一次', () {
      final r = computeStats(threeDays(), [
        const ShiftRecord(
            ymd: '2026-10-05',
            shiftId: 's06',
            slotIndex: 1,
            durationMinutes: 480),
        const ShiftRecord(
            ymd: '2026-10-05',
            shiftId: 's18',
            slotIndex: 3,
            durationMinutes: 720), // 同日第二筆，不累加
      ]);
      expect(r.workDays, 1);
      expect(r.totalMinutes, 480);
      expect(r.durationLabel, '8 小時');
    });

    test('時長 0 的紀錄仍然計返工日，但不加分鐘數', () {
      final r = computeStats(threeDays(), [
        const ShiftRecord(
            ymd: '2026-10-05',
            shiftId: 's06',
            slotIndex: 1,
            durationMinutes: 0),
      ]);
      expect(r.workDays, 1);
      expect(r.totalMinutes, 0);
      expect(r.durationLabel, '0 小時');
    });

    test('負時長當 0，不會倒扣總工時', () {
      final r = computeStats(threeDays(), [
        const ShiftRecord(
            ymd: '2026-10-05',
            shiftId: 's06',
            slotIndex: 1,
            durationMinutes: 480),
        const ShiftRecord(
            ymd: '2026-10-06',
            shiftId: 's06',
            slotIndex: 1,
            durationMinutes: -120),
      ]);
      expect(r.totalMinutes, 480);
      expect(r.durationLabel, '8 小時');
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
