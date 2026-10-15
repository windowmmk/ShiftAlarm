import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    test('導出→清空→導入，還原班次和場所', () async {
      final store = await _storeWithPreset();
      expect(store.defs.length, 4);
      expect(store.venues.length, 8);

      // 導出
      final json = exportConfig(store);
      expect(json['app'], 'ShiftAlarm');
      expect(json['version'], 1);
      expect((json['shifts'] as List).length, 4);
      expect((json['venues'] as List).length, 8);

      final jsonStr = exportConfigJson(store);
      expect(jsonStr.contains('凌晨更'), isTrue);

      // 清空
      await store.replaceAllDefs({});
      await store.replaceAllVenues([]);
      expect(store.defs, isEmpty);
      expect(store.venues, isEmpty);

      // 導入
      await importConfigJson(store, jsonStr);
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
      final jsonStr = exportConfigJson(store);
      final p = previewConfig(jsonStr);
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
      final jsonStr = exportConfigJson(store);

      // 新 store（同一個 prefs）導入
      final store2 = ShiftStore(prefs);
      await store2.load();
      await importConfigJson(store2, jsonStr);
      expect(store2.defs.length, 4);

      // 再開一個 store 讀返（驗持久化）
      final store3 = ShiftStore(prefs);
      await store3.load();
      expect(store3.defs.length, 4);
      expect(store3.venues.length, 8);
    });

    test('Base64 口令碼導出與導入還原', () async {
      final store = await _storeWithPreset();
      final code = exportConfigCode(store);
      expect(code.startsWith('SHIFTALARM:'), isTrue);

      // preview 支援口令碼
      final p = previewConfig(code);
      expect(p.shifts, 4);
      expect(p.venues, 8);

      // 清空
      await store.replaceAllDefs({});
      await store.replaceAllVenues([]);

      // 口令碼導入
      await importConfigText(store, code);
      expect(store.defs.length, 4);
      expect(store.venues.length, 8);
      expect(store.defs['s00']!.name, '凌晨更');
    });

    test('iOS 智慧標點（中文引號）自動容錯修正', () async {
      final store = await _storeWithPreset();
      final jsonStr = exportConfigJson(store);
      // 模擬 iOS 鍵盤自動替換雙引號為中文字型彎引號
      final smartQuoted = jsonStr.replaceAll('"', '“');
      final p = previewConfig(smartQuoted);
      expect(p.shifts, 4);
      expect(p.venues, 8);
    });
  });

  group('爛數據', () {
    test('空字符串拋錯', () async {
      final store = await _freshStore();
      expect(() => importConfigJson(store, ''),
          throwsA(isA<ConfigImportException>()));
      expect(() => importConfigJson(store, '   '),
          throwsA(isA<ConfigImportException>()));
    });

    test('唔係 JSON 拋錯', () async {
      final store = await _freshStore();
      expect(() => importConfigJson(store, 'not json{{'),
          throwsA(isA<ConfigImportException>()));
    });

    test('錯 app 標記拋錯', () async {
      final store = await _freshStore();
      expect(
          () => importConfigJson(
              store, '{"app":"Other","version":1,"shifts":[],"venues":[]}'),
          throwsA(isA<ConfigImportException>()));
    });

    test('冇有效班次拋錯', () async {
      final store = await _freshStore();
      expect(
          () => importConfigJson(store,
              '{"app":"ShiftAlarm","version":1,"shifts":[],"venues":[]}'),
          throwsA(isA<ConfigImportException>()));
    });

    test('preview 爛 JSON 拋錯', () {
      expect(
          () => previewConfig('{{{'), throwsA(isA<ConfigImportException>()));
    });

    test('preview 缺字段拋錯', () {
      expect(() => previewConfig('{"app":"ShiftAlarm"}'),
          throwsA(isA<ConfigImportException>()));
    });
  });
}
