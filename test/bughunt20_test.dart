import 'package:flutter_test/flutter_test.dart';
import 'package:shiftalarm/domain/alarm_service.dart';
import 'package:shiftalarm/domain/csv_import.dart';
import 'package:shiftalarm/domain/shift_store.dart';

/// 第二十輪 Bug Hunt 新增測試
Map<String, ShiftDef> _defs() => ShiftStore.testDefaults();

void main() {
  group('CSV BOM', () {
    test('BOM 頭唔好搞死第一行', () {
      // Excel／記事本存 UTF-8 常帶 BOM，貼上嚟第一行日期會多個 \uFEFF
      const csv = '\uFEFF2026-10-15,00-06,A1\n2026-10-16,06-12,B1';
      final r = parseRosterCsv(csv, _defs());
      expect(r.errors, isEmpty,
          reason: 'BOM 應該被 strip，第一行唔應該報錯: ${r.errors}');
      expect(r.valid.length, 2);
      expect(r.valid[0].date, '2026-10-15');
    });
    test('BOM＋空行混合', () {
      const csv = '\uFEFF\n2026-10-15,00-06,A1\n';
      final r = parseRosterCsv(csv, _defs());
      expect(r.errors, isEmpty);
      expect(r.valid.length, 1);
    });
  });

  group('CSV CRLF', () {
    test('Windows CRLF 唔應該影響解析', () {
      const csv = '2026-10-15,00-06,A1\r\n2026-10-16,06-12,B1\r\n';
      final r = parseRosterCsv(csv, _defs());
      expect(r.errors, isEmpty, reason: '${r.errors}');
      expect(r.valid.length, 2);
      expect(r.valid[0].venue, 'A1'); // \r 要被 trim 走
    });
  });

  group('CSV 尾逗號', () {
    test('行尾多個逗號唔當錯', () {
      final r = parseRosterCsv('2026-10-15,00-06,A1,', _defs());
      expect(r.errors, isEmpty);
      expect(r.valid.single.venue, 'A1');
    });
    test('場所欄空＋尾逗號', () {
      final r = parseRosterCsv('2026-10-15,00-06,,', _defs());
      expect(r.errors, isEmpty);
      expect(r.valid.single.venue, '');
    });
  });

  group('場所超長＋備註去重', () {
    test('超長場所：venue 截 4 字，remark 係全文', () {
      final r = parseRosterCsv('2026-10-15,00-06,STATION_EAST', _defs());
      expect(r.valid.single.venue, 'STAT');
      expect(r.valid.single.remark, 'STATION_EAST');
    });
    test('全形字超長：按 rune 截，唔斬開', () {
      // 5 個中文字 = 10 單位 > 4，要截到 2 個字（4 單位）
      final r = parseRosterCsv('2026-10-15,00-06,新界總辦公區', _defs());
      expect(r.valid.single.venue.runes.length, 2);
      expect(r.valid.single.remark, '新界總辦公區');
    });
  });

  group('alarm id 唔撞', () {
    test('10 個鬧鐘 id 全部唔同', () {
      final ids = <int>{};
      for (var i = 0; i < 10; i++) {
        ids.add(AlarmService.alarmIdFor('2026-10-15', i));
      }
      expect(ids.length, 10);
    });
    test('唔同日期 id 唔同', () {
      final a = AlarmService.alarmIdFor('2026-10-15', 0);
      final b = AlarmService.alarmIdFor('2026-10-16', 0);
      expect(a, isNot(b));
    });
    test('id 唔超過 32-bit（PendingIntent requestCode 上限）', () {
      // 20261231*10+9 = 202612319 < 2^31
      final id = AlarmService.alarmIdFor('2026-12-31', 9);
      expect(id, lessThan(2147483648));
    });
  });

  group('跨日鬧鐘顯示', () {
    test('00:00 -60 → 23:00 前一日', () {
      final (hhmm, d) = AlarmService.alarmClockParts('00:00', -60);
      expect(hhmm, '23:00');
      expect(d, -1);
    });
    test('00:00 -1440 → 00:00 前一日（剛好一日）', () {
      final (hhmm, d) = AlarmService.alarmClockParts('00:00', -1440);
      expect(hhmm, '00:00');
      expect(d, -1);
    });
    test('18:00 +360 → 00:00 後一日', () {
      final (hhmm, d) = AlarmService.alarmClockParts('18:00', 360);
      expect(hhmm, '00:00');
      expect(d, 1);
    });
    test('06:00 -360 → 00:00 當日（啱啱午夜唔算前一日）', () {
      final (hhmm, d) = AlarmService.alarmClockParts('06:00', -360);
      expect(hhmm, '00:00');
      expect(d, 0);
    });
  });
}
