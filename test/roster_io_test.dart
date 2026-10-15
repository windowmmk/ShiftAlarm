import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftalarm/domain/base58.dart';
import 'package:shiftalarm/domain/roster_io.dart';
import 'package:shiftalarm/domain/shift_store.dart';

Future<ShiftStore> _storeWithSampleRoster() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = ShiftStore(prefs);
  await store.load();
  await store.replaceAllDefs(ShiftStore.samplePresetDefs());
  await store.replaceAllVenues(ShiftStore.samplePresetVenues());

  // 指派 2026 年 10 月排班
  await store.assignBatch([
    (ymd: '2026-10-01', shiftId: 's00', note: 'A1', remark: '月初開工'),
    (ymd: '2026-10-02', shiftId: 's06', note: 'B1', remark: ''),
    (ymd: '2026-10-03', shiftId: 's12', note: 'ROOM_1', remark: '換班'),
    (ymd: '2026-10-04', shiftId: 's18', note: 'A2', remark: ''),
  ]);

  return store;
}

void main() {
  group('Base58 模組測試', () {
    test('位元組陣列編解碼 round-trip', () {
      final sample = [0, 0, 1, 2, 3, 255, 128, 64, 0, 42];
      final encoded = base58Encode(sample);
      expect(isBase58(encoded), isTrue);
      // 前導 0 應為 '1'
      expect(encoded.startsWith('11'), isTrue);

      final decoded = base58Decode(encoded);
      expect(decoded, equals(sample));
    });

    test('空位元組與字串', () {
      expect(base58Encode([]), isEmpty);
      expect(base58Decode(''), isEmpty);
    });

    test('無效 Base58 字元拋錯（如 0, O, I, l 或符號）', () {
      expect(() => base58Decode('1230abc'), throwsFormatException);
      expect(() => base58Decode('123Oabc'), throwsFormatException);
      expect(() => base58Decode('123Iabc'), throwsFormatException);
      expect(() => base58Decode('123labc'), throwsFormatException);
      expect(() => base58Decode('123+abc'), throwsFormatException);
    });
  });

  group('排班表 Base58 口令導出與導入', () {
    test('導出排班口令具備魔數、CRC32、長度與天數', () async {
      final store = await _storeWithSampleRoster();
      final code = exportRosterCode(store);

      expect(isRosterPacket(code), isTrue);
      expect(code.startsWith('SR2:'), isTrue);

      // 極簡緊湊預編碼長度檢驗：4天排班（含自定義中文備註）壓縮至 150 字元以內
      expect(code.length, lessThan(150));

      final payload = code.substring(4);
      expect(isBase58(payload), isTrue);
    });

    test('口令解析預覽、CRC32 驗證與還原導入', () async {
      final store = await _storeWithSampleRoster();
      final code = exportRosterCode(store);

      // 解碼預覽
      final decoded = decodeRosterText(code, store.defs);
      expect(decoded.isPacket, isTrue);
      expect(decoded.crcVerified, isTrue);
      expect(decoded.importResult.valid.length, 4);
      expect(decoded.importResult.errors, isEmpty);
      expect(decoded.exportTime, isNotNull);

      // 清空目前排班
      await store.unassignBatch([
        '2026-10-01',
        '2026-10-02',
        '2026-10-03',
        '2026-10-04',
      ]);
      expect(store.assignments, isEmpty);

      // 執行導入
      await store.assignBatch([
        for (final r in decoded.importResult.valid)
          (ymd: r.date, shiftId: r.shiftId, note: r.venue, remark: r.remark)
      ]);

      expect(store.assignments.length, 4);
      expect(store.assignments['2026-10-01']?.shiftId, 's00');
      expect(store.assignments['2026-10-01']?.note, 'A1');
      expect(store.remarks['2026-10-01'], '月初開工');
    });

    test('通訊軟體換行與空格容錯', () async {
      final store = await _storeWithSampleRoster();
      final code = exportRosterCode(store);

      // 模擬微信或備忘錄在中間插入換行和空格
      final wrapped = code.replaceRange(35, 35, '\n   \r\n\t  ');
      final decoded = decodeRosterText(wrapped, store.defs);

      expect(decoded.isPacket, isTrue);
      expect(decoded.crcVerified, isTrue);
      expect(decoded.importResult.valid.length, 4);
    });

    test('篡改校驗碼防偽測試', () async {
      final store = await _storeWithSampleRoster();
      final code = exportRosterCode(store);

      // 篡改 Base58 數據內容
      final payload = code.substring(4);
      final tamperedPayload =
          (payload.startsWith('1') ? '2' : '1') + payload.substring(1);
      final tampered = 'SR2:$tamperedPayload';
      final decoded = decodeRosterText(tampered, store.defs);
      expect(decoded.importResult.valid, isEmpty);
      expect(decoded.importResult.errors.first, contains('校驗碼不符'));
    });

    test('雙模相容：傳統 CSV 依然正常解析', () async {
      final store = await _storeWithSampleRoster();
      const csv = '''
2026-10-15,00,A1
2026-10-16,06,B1
''';
      final decoded = decodeRosterText(csv, store.defs);
      expect(decoded.isPacket, isFalse);
      expect(decoded.importResult.valid.length, 2);
      expect(decoded.importResult.valid[0].date, '2026-10-15');
      expect(decoded.importResult.valid[0].venue, 'A1');
    });

    test('網址 Hash 與 Query 參數提取與還原', () async {
      final store = await _storeWithSampleRoster();
      final code = exportRosterCode(store);

      // 1. Query parameter (?r=) - 微信防標籤誤判格式
      final queryUrl = 'https://windowmmk.github.io/ShiftAlarm/?r=$code';
      final queryUri = Uri.parse(queryUrl);
      final queryExtracted = queryUri.queryParameters['r'];
      expect(queryExtracted, equals(code));
      final queryDecoded = decodeRosterText(queryExtracted!, store.defs);
      expect(queryDecoded.importResult.valid.length, 4);

      // 2. Hash fragment (#r=) - 向下相容
      final hashUrl = 'https://windowmmk.github.io/ShiftAlarm/#r=$code';
      final hashUri = Uri.parse(hashUrl);
      final fragment = hashUri.fragment;
      expect(fragment.startsWith('r='), isTrue);
      final hashExtracted = Uri.decodeComponent(fragment.substring(2));
      expect(hashExtracted, equals(code));
      final hashDecoded = decodeRosterText(hashExtracted, store.defs);
      expect(hashDecoded.importResult.valid.length, 4);
    });
  });
}
