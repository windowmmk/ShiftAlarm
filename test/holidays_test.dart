import 'package:flutter_test/flutter_test.dart';
import 'package:shiftalarm/domain/holidays.dart';

/// 澳門公眾假期靜態表：已知日期對得上；格式＋口徑不變形。
void main() {
  group('macauHolidays', () {
    test('2026 已知假期', () {
      expect(macauHolidays['2026-01-01'], '元旦');
      expect(macauHolidays['2026-02-17'], '農曆正月初一');
      expect(macauHolidays['2026-04-03'], '耶穌受難日');
      expect(macauHolidays['2026-05-01'], '勞動節');
      expect(macauHolidays['2026-10-01'], '中華人民共和國國慶日');
      expect(macauHolidays['2026-12-08'], '聖母無原罪瞻禮');
      expect(macauHolidays['2026-12-20'], '澳門特別行政區成立紀念日');
      expect(macauHolidays['2026-12-25'], '聖誕節');
    });

    test('2027 已知假期', () {
      expect(macauHolidays['2027-01-01'], '元旦');
      expect(macauHolidays['2027-02-06'], '農曆正月初一');
      expect(macauHolidays['2027-05-01'], '勞動節');
      expect(macauHolidays['2027-10-01'], '中華人民共和國國慶日');
      expect(macauHolidays['2027-12-25'], '聖誕節');
    });

    test('補假日計入', () {
      expect(macauHolidays['2026-04-06'], '復活節前日的補假');
      expect(macauHolidays['2026-05-25'], '佛誕節的補假');
      expect(macauHolidays['2027-12-27'], '聖誕節的補假');
    });

    test('下午豁免計入', () {
      expect(macauHolidays['2026-02-16'], '農曆除夕（下午豁免）');
      expect(macauHolidays['2026-12-31'], '除夕（下午豁免）');
    });

    test('非假期返 null', () {
      expect(macauHolidays['2026-10-14'], isNull);
      expect(macauHolidays['2027-06-01'], isNull);
    });

    test('全部 key 都係合法 YYYY-MM-DD 日期', () {
      expect(macauHolidays, isNotEmpty);
      final seen = <String>{};
      for (final k in macauHolidays.keys) {
        expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(k), isTrue,
            reason: 'key 格式：$k');
        expect(seen.add(k), isTrue, reason: '重複 key：$k');
        final parts = k.split('-').map(int.parse).toList();
        // DateTime 會 normalize 爛日期，round-trip 對唔上即係爛
        final d = DateTime(parts[0], parts[1], parts[2]);
        final back =
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        expect(back, k, reason: '非法日期：$k');
      }
      for (final v in macauHolidays.values) {
        expect(v.trim(), isNotEmpty);
      }
    });
  });

  group('holidayName', () {
    test('假期日返名', () {
      expect(holidayName(DateTime(2026, 10, 1)), '中華人民共和國國慶日');
      expect(holidayName(DateTime(2027, 2, 6)), '農曆正月初一');
    });

    test('非假期日返 null', () {
      expect(holidayName(DateTime(2026, 10, 14)), isNull);
    });

    test('個位數月日補零', () {
      expect(holidayName(DateTime(2026, 1, 1)), '元旦');
      expect(holidayName(DateTime(2026, 5, 1)), '勞動節');
    });
  });
}
