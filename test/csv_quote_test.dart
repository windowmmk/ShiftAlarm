import 'package:flutter_test/flutter_test.dart';
import 'package:shiftalarm/domain/csv_import.dart';
import 'package:shiftalarm/domain/shift_store.dart';

/// CSV 引號／全角逗號解析（P2-10）永久防線。
///
/// 舊版 `line.split(',')` 的兩個後果：
/// 1. 備註欄用引號包住但內含半角逗號 → 被切開，後面欄位全部錯位。
/// 2. 用戶由微信／中文版 Excel 貼上時分隔符係全角逗號 `，` → 整行變一欄
///    → 報「格式唔啱」，一個都導入唔到。
Map<String, ShiftDef> _defsA() => {
      'sA': ShiftDef(
        id: 'sA',
        name: '早班',
        code: 'A',
        startTime: '06:00',
        endTime: '12:00',
        alarms: [
          ShiftAlarm(id: 'a1', label: '開工鬧鐘', offsetMinutes: -30),
        ],
      ),
    };

void main() {
  group('splitCsvLine 欄位切分', () {
    test('簡單半角逗號（向後兼容）', () {
      expect(splitCsvLine('a,b,c'), ['a', 'b', 'c']);
    });

    test('引號內半角逗號唔切', () {
      expect(splitCsvLine('a,"b,c",d'), ['a', 'b,c', 'd']);
    });

    test('全角逗號視為分隔符', () {
      expect(splitCsvLine('a，b，c'), ['a', 'b', 'c']);
    });

    test('引號內全角逗號唔切（引號內係內容）', () {
      expect(splitCsvLine('a,"b，c"'), ['a', 'b，c']);
    });

    test('引號內 "" 轉義成一個字面雙引號', () {
      expect(splitCsvLine('a,"他說""你好"""'), ['a', '他說"你好"']);
    });

    test('尾隨空欄保留（場所可以留空）', () {
      expect(splitCsvLine('a,b,'), ['a', 'b', '']);
    });

    test('空字串回一個空欄', () {
      expect(splitCsvLine(''), ['']);
    });

    test('未閉合引號：食到行尾，唔會爆', () {
      expect(splitCsvLine('a,"b,c'), ['a', 'b,c']);
    });

    test('引號內含換行以外的空白原樣保留', () {
      expect(splitCsvLine('a,"早班 有津貼"'), ['a', '早班 有津貼']);
    });

    test('整行已有半角逗號 → 全角逗號視為內容（唔會多切一刀）', () {
      expect(splitCsvLine('a,b，c'), ['a', 'b，c']);
    });

    test('整行冇半角逗號 → 全角逗號當分隔符', () {
      expect(splitCsvLine('a，b，c'), ['a', 'b', 'c']);
    });
  });

  group('parseRosterCsv 引號與全角逗號', () {
    test('引號內半角逗號：備註完整保留', () {
      final r = parseRosterCsv('2026-10-05,A,"早班, 有津貼"', _defsA());
      expect(r.errors, isEmpty);
      expect(r.valid.length, 1);
      // 場所超 4 單位 → 截成場所＋全文入備註（既有設計）
      expect(r.valid.single.venue, '早班');
      expect(r.valid.single.remark, '早班, 有津貼',
          reason: '舊版逗號會被切走，備註只剩「早班」');
    });

    test('引號內半角逗號但場所夠短：唔截、唔切', () {
      final r = parseRosterCsv('2026-10-05,A,"A,B"', _defsA());
      expect(r.errors, isEmpty);
      expect(r.valid.single.venue, 'A,B');
      expect(r.valid.single.remark, '');
    });

    test('全角逗號分隔：正確解析出 3 欄', () {
      final r = parseRosterCsv('2026-10-05，A，早班', _defsA());
      expect(r.errors, isEmpty, reason: '舊版整行變一欄，會報格式唔啱');
      expect(r.valid.length, 1);
      expect(r.valid.single.date, '2026-10-05');
      expect(r.valid.single.shiftId, 'sA');
      expect(r.valid.single.venue, '早班');
      expect(r.valid.single.remark, '');
    });

    test('全角逗號＋引號內半角逗號混合', () {
      final r = parseRosterCsv('2026-10-05，A，"早班, 有津貼"', _defsA());
      expect(r.errors, isEmpty);
      expect(r.valid.single.remark, '早班, 有津貼');
    });

    test('"" 轉義：備註為 他說"你好"', () {
      final r = parseRosterCsv('2026-10-05,A,"他說""你好"""', _defsA());
      expect(r.errors, isEmpty);
      expect(r.valid.single.remark, '他說"你好"');
      expect(r.valid.single.venue, '他說');
    });

    test('純半角逗號簡單 CSV 行為不變（零回歸）', () {
      final r = parseRosterCsv(
        '2026-10-05,A,A1\n2026-10-06,A,B1\n',
        _defsA(),
      );
      expect(r.errors, isEmpty);
      expect(r.valid.length, 2);
      expect(r.valid[0].venue, 'A1');
      expect(r.valid[1].date, '2026-10-06');
      expect(r.valid[1].venue, 'B1');
    });

    test('缺欄位仍然報錯（唔會因為引號而靜靜過關）', () {
      final r = parseRosterCsv('2026-10-05', _defsA());
      expect(r.valid, isEmpty);
      expect(r.errors.single, contains('格式唔啱'));
    });

    test('引號包住代號都對得上', () {
      final r = parseRosterCsv('2026-10-05,"A","A1"', _defsA());
      expect(r.errors, isEmpty);
      expect(r.valid.single.shiftId, 'sA');
      expect(r.valid.single.venue, 'A1');
    });

    test('場所本身含全角逗號：半角格式下唔會被切走（資料保真）', () {
      // 半角逗號已經夠切欄，所以「A，B」入面嘅全角逗號係場所內容
      final r = parseRosterCsv('2026-10-05,A,A，B', _defsA());
      expect(r.errors, isEmpty);
      expect(r.valid.single.venue, 'A，B');
      expect(r.valid.single.remark, '');
    });

    test('場所含全角逗號＋引號包住：一樣保真', () {
      final r = parseRosterCsv('2026-10-05,A,"A，B"', _defsA());
      expect(r.errors, isEmpty);
      expect(r.valid.single.venue, 'A，B');
    });

    test('混合分隔符（同一行半角＋全角並用）→ 報錯，唔會靜靜猜錯', () {
      final r = parseRosterCsv('2026-10-05，A,B', _defsA());
      expect(r.valid, isEmpty);
      expect(r.errors.single, contains('日期'));
    });
  });
}
