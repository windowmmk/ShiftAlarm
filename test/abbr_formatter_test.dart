import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftalarm/domain/shift_store.dart';

void main() {
  group('abbrUnits 單位長度計算（全形=2，半形=1）', () {
    test('空字串為 0 單位', () {
      expect(abbrUnits(''), 0);
    });

    test('純半形 ASCII 字元（英文、數字、符號、空格）每個計 1 單位', () {
      expect(abbrUnits('A'), 1);
      expect(abbrUnits('1'), 1);
      expect(abbrUnits('z'), 1);
      expect(abbrUnits(' '), 1);
      expect(abbrUnits('#'), 1);
      expect(abbrUnits('ROOM'), 4);
      expect(abbrUnits('Shift 1'), 7);
    });

    test('純全形 CJK 漢字及全形標點符號每個計 2 單位', () {
      expect(abbrUnits('早'), 2);
      expect(abbrUnits('夜'), 2);
      expect(abbrUnits('早班'), 4);
      expect(abbrUnits('總部大樓'), 8);
      expect(abbrUnits('，'), 2);
      expect(abbrUnits('（'), 2);
    });

    test('中英數混排單位累加正確', () {
      // 'A'(1) + '班'(2) = 3
      expect(abbrUnits('A班'), 3);
      // 'A'(1) + '1'(1) + '房'(2) = 4
      expect(abbrUnits('A1房'), 4);
      // '早'(2) + ' '(1) + '1'(1) = 4
      expect(abbrUnits('早 1'), 4);
      // '總'(2) + '部'(2) + 'A'(1) = 5
      expect(abbrUnits('總部A'), 5);
    });
  });

  group('truncateAbbr 按單位上限截斷', () {
    test('空字串截斷回傳空字串', () {
      expect(truncateAbbr(''), '');
      expect(truncateAbbr('', 4), '');
    });

    test('未達上限或剛好達上限時保持原樣', () {
      expect(truncateAbbr('早', 4), '早'); // 2 <= 4
      expect(truncateAbbr('早班', 4), '早班'); // 4 <= 4
      expect(truncateAbbr('ABCD', 4), 'ABCD'); // 4 <= 4
      expect(truncateAbbr('A1', 4), 'A1'); // 2 <= 4
      expect(truncateAbbr('A班', 4), 'A班'); // 3 <= 4
    });

    test('純半形字串超出上限截斷', () {
      expect(truncateAbbr('ABCDE', 4), 'ABCD');
      expect(truncateAbbr('12345678', 4), '1234');
    });

    test('純全形漢字超出上限截斷', () {
      expect(truncateAbbr('總部大樓', 4), '總部'); // 4 單位 (2字)
      expect(truncateAbbr('第一分部大樓', 4), '第一'); // 4 單位 (2字)
    });

    test('中英混排跨邊界截斷：不拆散全形字元導致超長', () {
      // 'A'(1) + '班'(2) = 3; 次字 '長'(2) 加埋變 5 > 4，應停在 'A班'
      expect(truncateAbbr('A班長', 4), 'A班');
      // '總'(2) + '部'(2) = 4; 次字 'A'(1) 加埋變 5 > 4，停在 '總部'
      expect(truncateAbbr('總部A', 4), '總部');
    });

    test('自訂 maxUnits 截斷限制', () {
      expect(truncateAbbr('總部大樓', 2), '總');
      expect(truncateAbbr('ABCDEF', 2), 'AB');
      expect(truncateAbbr('總部大樓', 6), '總部大');
      expect(truncateAbbr('總部大樓', 8), '總部大樓');
    });
  });

  group('AbbrUnitLengthFormatter 輸入控制器', () {
    test('合規長度輸入不變更 TextEditingValue', () {
      const formatter = AbbrUnitLengthFormatter(4);
      const oldValue = TextEditingValue.empty;
      const newValue = TextEditingValue(
        text: '早班',
        selection: TextSelection.collapsed(offset: 2),
      );
      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, '早班');
      expect(result.selection.baseOffset, 2);
    });

    test('超長輸入自動截斷並將游標修正至末尾', () {
      const formatter = AbbrUnitLengthFormatter(4);
      const oldValue = TextEditingValue(
        text: '總部',
        selection: TextSelection.collapsed(offset: 2),
      );
      // 用戶粘貼或繼續鍵入「大樓」
      const newValue = TextEditingValue(
        text: '總部大樓',
        selection: TextSelection.collapsed(offset: 4),
      );
      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, '總部');
      expect(result.selection.baseOffset, 2);
    });

    test('中英混排輸入超長時正確截斷', () {
      const formatter = AbbrUnitLengthFormatter(4);
      const oldValue = TextEditingValue.empty;
      const newValue = TextEditingValue(
        text: 'A班組長',
        selection: TextSelection.collapsed(offset: 4),
      );
      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, 'A班');
      expect(result.selection.baseOffset, 2);
    });
  });
}
