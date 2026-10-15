import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftalarm/domain/base58.dart';
import 'package:shiftalarm/domain/config_io.dart';
import 'package:shiftalarm/domain/shift_store.dart';

/// 配置導入導出：round-trip＋爛數據。
Future<ShiftStore> _freshStore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = ShiftStore(prefs);
  await store.load();
  return store;
}

Future<ShiftStore> _storeWithPreset() async {
  final store = await _freshStore();
  await store.replaceAllDefs(ShiftStore.samplePresetDefs());
  await store.replaceAllVenues(ShiftStore.samplePresetVenues());
  return store;
}

void main() {
  group('export/import round-trip', () {
    test('Map 結構導出與導入還原', () async {
      final store = await _storeWithPreset();
      expect(store.defs.length, 4);
      expect(store.venues.length, 8);

      // 導出 Map
      final json = exportConfig(store);
      expect(json['app'], 'ShiftAlarm');
      expect(json['version'], 1);
      expect((json['shifts'] as List).length, 4);
      expect((json['venues'] as List).length, 8);

      // 清空
      await store.replaceAllDefs({});
      await store.replaceAllVenues([]);
      expect(store.defs, isEmpty);
      expect(store.venues, isEmpty);

      // 導入 Map
      await importConfig(store, json);
      expect(store.defs.length, 4);
      expect(store.venues.length, 8);
      expect(store.defs['s00']!.name, '凌晨更');
      expect(store.defs['s00']!.startTime, '00:00');
      expect(store.defs['s18']!.name, '夜更');
      // 打卡鬧鐘保留
      final alarms = store.defs['s00']!.alarms;
      expect(alarms.any((a) => a.id == 'dk_in'), isTrue);
      expect(alarms.any((a) => a.id == 'dk_out'), isTrue);
      expect(store.venues.contains('A1'), isTrue);
      expect(store.venues.contains('ROOM_1'), isTrue);
    });

    test('preview 解析出數量和名稱', () async {
      final store = await _storeWithPreset();
      final code = exportConfigCode(store);
      final p = previewConfig(code);
      expect(p.shifts, 4);
      expect(p.venues, 8);
      expect(p.names, contains('凌晨更'));
      expect(p.names, contains('夜更'));
    });

    test('導入後 reload 持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ShiftStore(prefs);
      await store.load();
      await store.replaceAllDefs(ShiftStore.samplePresetDefs());
      await store.replaceAllVenues(ShiftStore.samplePresetVenues());
      final code = exportConfigCode(store);

      // 新 store（同一個 prefs）導入
      final store2 = ShiftStore(prefs);
      await store2.load();
      await importConfigText(store2, code);
      expect(store2.defs.length, 4);

      // 再開一個 store 讀返（驗持久化）
      final store3 = ShiftStore(prefs);
      await store3.load();
      expect(store3.defs.length, 4);
      expect(store3.venues.length, 8);
    });

    test('帶協議報文頭的 SA2: 極簡二進制 Base58 口令碼導出、長度壓減、校驗與導入還原', () async {
      final store = await _storeWithPreset();
      final code = exportConfigCode(store);

      // 1. 報文頭格式與剪貼簿快速偵測檢查
      expect(isConfigPacket(code), isTrue);
      expect(code.startsWith('SA2:'), isTrue);
      final payload = code.substring(4);
      expect(isBase58(payload), isTrue);

      // 2. 極簡長度壓減檢驗：由原本 2000+ 字元壓縮至 200 字元以內！
      expect(code.length, lessThan(200));

      // 3. 報文頭預覽與 CRC32 校驗
      final p = previewConfig(code);
      expect(p.shifts, 4);
      expect(p.venues, 8);
      expect(p.crcVerified, isTrue);
      expect(p.crcHex, isNotNull);
      expect(p.exportTime, isNotNull);

      // 4. 通訊軟體折行與空格容錯（模擬微信/備忘錄自動換行）
      final wrappedCode = code.replaceRange(30, 30, '\n  \t  ');
      final pWrapped = previewConfig(wrappedCode);
      expect(pWrapped.shifts, 4);
      expect(pWrapped.crcVerified, isTrue);

      // 5. 清空現有資料
      await store.replaceAllDefs({});
      await store.replaceAllVenues([]);

      // 6. 導入還原
      await importConfigText(store, wrappedCode);
      expect(store.defs.length, 4);
      expect(store.venues.length, 8);
      expect(store.defs['s00']!.name, '凌晨更');
    });

    test('報文頭校驗碼防篡改與防截斷驗證', () async {
      final store = await _storeWithPreset();
      final code = exportConfigCode(store);

      // 篡改 Base58 數據內容（模擬資料損壞或惡意竄改）
      final payload = code.substring(4);
      final tamperedPayload =
          (payload.startsWith('1') ? '2' : '1') + payload.substring(1);
      final tamperedCode = 'SA2:$tamperedPayload';
      expect(() => previewConfig(tamperedCode),
          throwsA(isA<ConfigImportException>()));

      // 截斷 Base58 數據（模擬複製不全）
      final truncated = code.substring(0, code.length - 15);
      expect(() => previewConfig(truncated),
          throwsA(isA<ConfigImportException>()));
    });

    test('網址 Hash 參數提取與還原', () async {
      final store = await _storeWithPreset();
      final code = exportConfigCode(store);
      final shareUrl = 'https://windowmmk.github.io/ShiftAlarm/#c=$code';
      final uri = Uri.parse(shareUrl);
      final fragment = uri.fragment;
      expect(fragment.startsWith('c='), isTrue);
      final extracted = Uri.decodeComponent(fragment.substring(2));
      expect(extracted, equals(code));
      final p = previewConfig(extracted);
      expect(p.shifts, 4);
      expect(p.venues, 8);
    });
  });

  group('爛數據與非 SA2 格式拒絕', () {
    test('空字符串拋錯', () async {
      final store = await _freshStore();
      expect(() => importConfigText(store, ''),
          throwsA(isA<ConfigImportException>()));
      expect(() => importConfigText(store, '   '),
          throwsA(isA<ConfigImportException>()));
    });

    test('非 SA2 前綴字串拋錯', () async {
      final store = await _freshStore();
      expect(() => importConfigText(store, 'not json{{'),
          throwsA(isA<ConfigImportException>()));
      expect(() => importConfigText(store, '{"app":"ShiftAlarm"}'),
          throwsA(isA<ConfigImportException>()));
      expect(() => importConfigText(store, 'SHIFTALARM:old_token'),
          throwsA(isA<ConfigImportException>()));
    });

    test('Map 導入：錯 app 標記拋錯', () async {
      final store = await _freshStore();
      expect(
          () => importConfig(
              store, {'app': 'Other', 'version': 1, 'shifts': [], 'venues': []}),
          throwsA(isA<ConfigImportException>()));
    });

    test('Map 導入：冇有效班次拋錯', () async {
      final store = await _freshStore();
      expect(
          () => importConfig(store,
              {'app': 'ShiftAlarm', 'version': 1, 'shifts': [], 'venues': []}),
          throwsA(isA<ConfigImportException>()));
    });

    test('preview 非 SA2 口令拋錯', () {
      expect(
          () => previewConfig('{{{'), throwsA(isA<ConfigImportException>()));
      expect(() => previewConfig('{"app":"ShiftAlarm"}'),
          throwsA(isA<ConfigImportException>()));
    });
  });
}
