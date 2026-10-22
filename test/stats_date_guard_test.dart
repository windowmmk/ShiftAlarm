import 'package:flutter_test/flutter_test.dart';
import 'package:shiftalarm/domain/stats.dart';

/// 統計日期邊界防線（P1-5）。
///
/// **重現舊 bug 的關鍵**：舊版 `_inRange` 有做 `\d{2}` 格式檢查，所以
/// 「缺前導零」其實已經被擋住；真正嘅漏洞係**冇驗證日子真偽**——
/// `DateTime(2026, 2, 30)` 會靜默進位成 3 月 2 日，於是該筆被計入
/// **錯誤區間**（工時／返工日數靜默計多）。
/// 所以下面刻意用「區間落喺進位後嘅月份」嘅寫法，才真正重現舊 bug。
void main() {
  DateRange october() => DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31));
  DateRange february() =>
      DateRange(DateTime(2026, 2, 1), DateTime(2026, 2, 28));
  DateRange march() => DateRange(DateTime(2026, 3, 1), DateTime(2026, 3, 31));
  DateRange may() => DateRange(DateTime(2026, 5, 1), DateTime(2026, 5, 31));

  ShiftRecord rec(
    String ymd, {
    int minutes = 480,
    int slot = 1,
    String venue = '',
  }) =>
      ShiftRecord(
        ymd: ymd,
        shiftId: 's06',
        slotIndex: slot,
        venue: venue,
        durationMinutes: minutes,
      );

  group('isValidYmd 嚴格驗證', () {
    test('真實存在嘅日期通過（含閏日）', () {
      expect(isValidYmd('2026-10-05'), isTrue);
      expect(isValidYmd('2024-02-29'), isTrue); // 2024 係閏年
      expect(isValidYmd('2026-01-01'), isTrue);
      expect(isValidYmd('2026-12-31'), isTrue);
      expect(isValidYmd('  2026-10-05  '), isTrue, reason: '容許前後空白');
    });

    test('格式啱但日子唔存在 → 非法（靠 DateTime 回讀擋住）', () {
      expect(isValidYmd('2026-02-30'), isFalse);
      expect(isValidYmd('2026-02-29'), isFalse); // 2026 唔係閏年
      expect(isValidYmd('2026-04-31'), isFalse);
      expect(isValidYmd('2026-06-31'), isFalse);
      expect(isValidYmd('2026-13-01'), isFalse);
      expect(isValidYmd('2026-00-10'), isFalse);
      expect(isValidYmd('2026-10-00'), isFalse);
    });

    test('缺前導零／分隔符唔啱／空字串 → 非法', () {
      expect(isValidYmd('2026-2-1'), isFalse);
      expect(isValidYmd('2026-2-01'), isFalse);
      expect(isValidYmd('2026-02-1'), isFalse);
      expect(isValidYmd('26-02-01'), isFalse);
      expect(isValidYmd('2026/02/01'), isFalse);
      expect(isValidYmd('2026-02-01T00:00'), isFalse);
      expect(isValidYmd(''), isFalse);
      expect(isValidYmd('   '), isFalse);
      expect(isValidYmd('聽日'), isFalse);
    });
  });

  group('P1-5 computeStats 唔會把非法日期計入任何區間', () {
    test('2026-02-30 唔會被計入 3 月（舊版會當成 3 月 2 日）', () {
      final r = computeStats(march(), [rec('2026-02-30')]);
      expect(r.workDays, 0, reason: '舊版這裡係 1（進位成 3 月 2 日）');
      expect(r.totalMinutes, 0);
      expect(r.slotDays.reduce((a, b) => a + b), 0);
    });

    test('2026-04-31 唔會被計入 5 月（舊版會當成 5 月 1 日）', () {
      final r = computeStats(may(), [rec('2026-04-31', venue: 'A1')]);
      expect(r.workDays, 0, reason: '舊版這裡係 1（進位成 5 月 1 日）');
      expect(r.totalMinutes, 0);
      expect(r.venueCounts, isEmpty);
    });

    test('2026-2-30（缺前導零＋唔存在）→ 一律跳過', () {
      final r = computeStats(october(), [rec('2026-2-30'), rec('2026-10-05')]);
      expect(r.workDays, 1);
      expect(r.totalMinutes, 480);
      expect(r.slotDays.reduce((a, b) => a + b), 1);
    });

    test('2026-02-30（前導零齊全但仍然非法）→ 唔計入 2 月', () {
      final r = computeStats(february(), [rec('2026-02-30'), rec('2026-02-10')]);
      expect(r.workDays, 1);
      expect(r.totalMinutes, 480);
    });

    test('2026-2-1（缺前導零）行為明確一致：視為非法並跳過', () {
      final r = computeStats(february(), [rec('2026-2-1'), rec('2026-02-01')]);
      expect(r.workDays, 1, reason: '只有格式規範嘅 2026-02-01 計入');
      expect(r.totalMinutes, 480);
      expect(r.slotDays.reduce((a, b) => a + b), 1);
    });

    test('2026-13-01 唔會被計入 2027 年 1 月', () {
      final jan2027 =
          DateRange(DateTime(2027, 1, 1), DateTime(2027, 1, 31));
      final r = computeStats(jan2027, [rec('2026-13-01')]);
      expect(r.workDays, 0);
    });

    test('單一筆爛日期唔會令整個統計爆掉（其他日子照計）', () {
      final r = computeStats(october(), [
        rec('2026-10-01', minutes: 600, venue: 'A1'),
        rec('爛日期'),
        rec('2026-02-30'),
        rec('2026-10-02', minutes: 300, venue: 'B1', slot: 3),
      ]);
      expect(r.workDays, 2);
      expect(r.totalMinutes, 900);
      expect(r.slotDays[1], 1);
      expect(r.slotDays[3], 1);
      expect(r.venueCounts.length, 2);
      expect(r.restDays, r.totalDays - 2);
    });
  });

  group('正常資料零回歸', () {
    test('合法日期區間邊界（含頭尾）仍然計入', () {
      final r = computeStats(october(), [
        rec('2026-10-01'),
        rec('2026-10-31'),
        rec('2026-09-30'),
        rec('2026-11-01'),
      ]);
      expect(r.workDays, 2, reason: '閉區間含頭尾，區間外兩筆要排除');
      expect(r.totalMinutes, 960);
    });

    test('同一日多筆只計一次（工時口徑一致）', () {
      final r = computeStats(october(), [
        rec('2026-10-05', minutes: 480),
        rec('2026-10-05', minutes: 240, slot: 2),
      ]);
      expect(r.workDays, 1);
      expect(r.totalMinutes, 480);
    });

    test('負時長當 0（唔會倒扣）', () {
      final r = computeStats(october(), [rec('2026-10-05', minutes: -120)]);
      expect(r.workDays, 1);
      expect(r.totalMinutes, 0);
    });
  });
}
