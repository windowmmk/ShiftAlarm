import 'package:flutter_test/flutter_test.dart';
import 'package:shiftalarm/domain/csv_import.dart';
import 'package:shiftalarm/domain/shift_store.dart';

/// CSV 導入解析：happy path＋爛數據，唔 crash、preview 列清楚。
Map<String, ShiftDef> _defs() => ShiftStore.testDefaults();

void main() {
  group('happy path', () {
    test('標準三行全過', () {
      const csv = '2026-10-15,00-06,A1\n2026-10-16,06-12,B1\n2026-10-17,12-18,';
      final r = parseRosterCsv(csv, _defs());
      expect(r.errors, isEmpty);
      expect(r.valid.length, 3);
      expect(r.valid[0].date, '2026-10-15');
      expect(r.valid[0].shiftId, 's00');
      expect(r.valid[0].venue, 'A1');
      expect(r.valid[2].venue, '');
    });
    test('HH:mm-HH:mm 格式都得', () {
      final r = parseRosterCsv('2026-10-15,00:00-06:00,A1', _defs());
      expect(r.errors, isEmpty);
      expect(r.valid.single.shiftId, 's00');
    });
    test('空檔案唔 crash，回空結果', () {
      final r = parseRosterCsv('', _defs());
      expect(r.valid, isEmpty);
      expect(r.errors, isEmpty);
    });
    test('空行同空白行跳過', () {
      final r = parseRosterCsv('\n  \n2026-10-15,00-06,A1\n', _defs());
      expect(r.errors, isEmpty);
      expect(r.valid.length, 1);
    });
  });

  group('爛數據', () {
    test('亂碼行', () {
      final r = parseRosterCsv('asdkfjhasdf', _defs());
      expect(r.valid, isEmpty);
      expect(r.errors.length, 1);
      expect(r.errors.first, contains('行 1'));
    });
    test('錯日期格式（2月30日唔存在）', () {
      final r = parseRosterCsv('2026-02-30,00-06,A1', _defs());
      expect(r.valid, isEmpty);
      expect(r.errors.single, contains('日期'));
    });
    test('日期亂填', () {
      final r = parseRosterCsv('聽日,00-06,A1', _defs());
      expect(r.valid, isEmpty);
      expect(r.errors.single, contains('日期'));
    });
    test('slot 唔 match 任何班次', () {
      final r = parseRosterCsv('2026-10-15,07-09,A1', _defs());
      expect(r.valid, isEmpty);
      expect(r.errors.single, contains('對唔到'));
    });
    test('slot 格式亂嚟', () {
      final r = parseRosterCsv('2026-10-15,abc,A1', _defs());
      expect(r.valid, isEmpty);
      expect(r.errors.single, contains('對唔到'));
    });
    test('場所超 4 字：截前 4 字＋全文入備註', () {
      final r = parseRosterCsv('2026-10-15,00-06,CAMPUS_NORTH', _defs());
      expect(r.errors, isEmpty);
      expect(r.valid.length, 1);
      expect(r.valid.single.venue, 'CAMP');
      expect(r.valid.single.remark, 'CAMPUS_NORTH');
    });
    test('場所啱啱 4 字：唔截，備註空', () {
      final r = parseRosterCsv('2026-10-15,00-06,ZONE', _defs());
      expect(r.errors, isEmpty);
      expect(r.valid.single.venue, 'ZONE');
      expect(r.valid.single.remark, '');
    });
    test('場所 4 字以下：原樣', () {
      final r = parseRosterCsv('2026-10-15,00-06,A1', _defs());
      expect(r.valid.single.venue, 'A1');
      expect(r.valid.single.remark, '');
    });
    test('超長行（>500字）跳過唔爆', () {
      final long = '2026-10-15,00-06,${'X' * 600}';
      final r = parseRosterCsv(long, _defs());
      expect(r.valid, isEmpty);
      expect(r.errors.single, contains('太長'));
    });
    test('混合：啱嘅入、錯嘅列出', () {
      const csv = '2026-10-15,00-06,A1\n亂碼\n2026-13-45,06-12,B1\n'
          '2026-10-17,12-18,EAST';
      final r = parseRosterCsv(csv, _defs());
      expect(r.valid.length, 2);
      expect(r.errors.length, 2);
    });
  });

  group('normalizeSlot', () {
    test('00-06 → 0-6', () => expect(normalizeSlot('00-06'), '0-6'));
    test('18-00 → 18-0', () => expect(normalizeSlot('18-00'), '18-0'));
    test('00:00-06:00 → 0-6', () => expect(normalizeSlot('00:00-06:00'), '0-6'));
    test('亂碼回 null', () => expect(normalizeSlot('xyz'), isNull));
    test('超出 23 回 null', () => expect(normalizeSlot('25-26'), isNull));
  });
}
