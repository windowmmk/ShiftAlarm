import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftalarm/domain/base58.dart';
import 'package:shiftalarm/domain/config_io.dart';
import 'package:shiftalarm/domain/shift_store.dart';

/// 資料靜默蒸發嘅永久防線。
///
/// 每一條測試都係「重現舊 bug」嘅最小案例：喺修好之前，呢啲案例會
/// **靜靜**通過或者靜靜失敗（無異常、無提示、用戶幾百天排班一夜消失）。
/// 所以斷言一定要寫明「其他日子仍然要載入得到」，唔可以只斷言「唔拋異常」。
void main() {
  /// 起一個乾淨 store。
  Future<ShiftStore> freshStore([Map<String, Object>? initial]) async {
    SharedPreferences.setMockInitialValues(initial ?? {});
    final prefs = await SharedPreferences.getInstance();
    final store = ShiftStore(prefs);
    await store.load();
    return store;
  }

  ShiftDef def(String id, String name, String code, String start, String end) =>
      ShiftDef(
        id: id,
        name: name,
        code: code,
        startTime: start,
        endTime: end,
        alarms: [
          ShiftAlarm(id: 'a1', label: '開工鬧鐘', offsetMinutes: -60),
        ],
      );

  /// 手砌一段 version = 2 嘅緊湊報文（v2 **冇** defId 欄位）。
  /// 用嚟證明「舊 SA2 口令碼仍然導入得」—— 呢個係換機復原嘅唯一通道，
  /// 一封死就等於用戶冇辦法救返自己嘅排班。
  String buildV2Code() {
    final bb = BytesBuilder();
    bb.addByte(2); // version 2
    bb.addByte(1); // 1 個班次
    bb.addByte(6); // start 06:00
    bb.addByte(0);
    bb.addByte(12); // end 12:00
    bb.addByte(0);
    bb.addByte(0); // clockFlags
    bb.addByte(0); // customAlarmCount
    final codeBytes = utf8.encode('06');
    bb.addByte(codeBytes.length);
    bb.add(codeBytes);
    final nameBytes = utf8.encode('早更');
    bb.addByte(nameBytes.length);
    bb.add(nameBytes);
    bb.addByte(0); // abbr 同 name 相同 → 0 長度
    bb.addByte(1); // 1 個場所
    final venueBytes = utf8.encode('A1');
    bb.addByte(venueBytes.length);
    bb.add(venueBytes);

    final data = bb.toBytes();
    final out = BytesBuilder();
    final crcBd = ByteData(4)..setUint32(0, computeCrc32(data), Endian.big);
    out.add(crcBd.buffer.asUint8List());
    final tsBd = ByteData(4)..setUint32(0, 1700000000, Endian.big);
    out.add(tsBd.buffer.asUint8List());
    out.add(data);
    return 'SA2:${base58Encode(out.toBytes())}';
  }

  group('P0-1 排班一天壞資料唔可以拖死整本', () {
    test('一天 shiftId 型別錯 → 其他天仍然載入，壞嘅被略過並計數', () async {
      final store = await freshStore({
        'shift_defs': jsonEncode({
          'sA': {
            'name': '早更',
            'abbr': '早',
            'code': 'A',
            'startTime': '06:00',
            'endTime': '12:00',
          },
          'sB': {
            'name': '夜更',
            'abbr': '夜',
            'code': 'B',
            'startTime': '18:00',
            'endTime': '00:00',
          },
        }),
        'assignments': jsonEncode({
          '2026-10-01': {'shiftId': 'sA', 'note': 'A1'},
          // 壞資料：shiftId 被寫成數字（舊版會令整份 assignments 變 {}）
          '2026-10-05': {'shiftId': 123},
          '2026-10-06': {'shiftId': 'sB', 'note': 'B1'},
        }),
      });

      // 關鍵斷言：另外兩天必須仲喺度
      expect(store.assignments.length, 2);
      expect(store.assignments['2026-10-01']!.shiftId, 'sA');
      expect(store.assignments['2026-10-01']!.note, 'A1');
      expect(store.assignments['2026-10-06']!.shiftId, 'sB');
      // 壞嘅那天被略過，而且有計數（唔係靜靜消失）
      expect(store.assignments.containsKey('2026-10-05'), isFalse);
      expect(store.lastDroppedEntries, 1);
      expect(store.lastLoadWarning, isNotNull);
    });

    test('排班 JSON 被截斷（"[{"）→ 唔清空、備份原字串、唔覆蓋原 key', () async {
      final store = await freshStore({
        'shift_defs': jsonEncode({
          'sA': {
            'name': '早更',
            'abbr': '早',
            'code': 'A',
            'startTime': '06:00',
            'endTime': '12:00',
          },
        }),
        'assignments': '[{', // 寫入途中斷電／被截斷
      });

      expect(store.assignments, isEmpty);
      expect(store.lastLoadWarning, isNotNull);

      // 原始字串必須備份到另一個 key
      final backups = store.prefs
          .getKeys()
          .where((k) => k.startsWith('assignments_corrupt_'))
          .toList();
      expect(backups.length, 1);
      expect(store.prefs.getString(backups.first), '[{');

      // 原 key 唔准被覆蓋：就算之後做一次「無變化嘅儲存」都唔可以清走
      await store.unassign('2026-10-01');
      expect(store.prefs.getString('assignments'), '[{');
    });

    test('字串 shiftId 但對唔上班次（孤兒）→ 保留原值，唔刪用戶資料', () async {
      final store = await freshStore({
        'shift_defs': jsonEncode({
          'sA': {
            'name': '早更',
            'abbr': '早',
            'code': 'A',
            'startTime': '06:00',
            'endTime': '12:00',
          },
        }),
        'assignments': jsonEncode({
          '2026-10-02': {'shiftId': 'sGone', 'note': 'A2'},
        }),
      });

      // 孤兒 ≠ 壞資料：班次定義唔見咗，但用戶嘅場所備註仍然有價值
      expect(store.assignments.length, 1);
      expect(store.assignments['2026-10-02']!.shiftId, 'sGone');
      expect(store.assignments['2026-10-02']!.note, 'A2');
    });
  });

  group('P0-2 一個班次定義壞唔可以拖死整個班次清單', () {
    test('某個 def 的 startTime 係數字 → 其他 def 仍然載入得到', () async {
      final store = await freshStore({
        'shift_defs': jsonEncode({
          'sA': {
            'name': '早更',
            'abbr': '早',
            'code': 'A',
            'startTime': '06:00',
            'endTime': '12:00',
          },
          // 壞資料：舊版把 offsetMinutes 之類寫成數字
          'sB': {
            'name': '怪更',
            'abbr': '怪',
            'code': 'B',
            'startTime': 600,
            'endTime': 1200,
          },
          'sC': {
            'name': '夜更',
            'abbr': '夜',
            'code': 'C',
            'startTime': '18:00',
            'endTime': '00:00',
          },
        }),
      });

      // 舊版：`as String?` 拋 TypeError，外層 catch 令 defs 變成 {}
      expect(store.defs.length, 3);
      expect(store.defs['sA']!.startTime, '06:00');
      expect(store.defs['sC']!.startTime, '18:00');
      expect(store.defs['sC']!.endTime, '00:00');
      // 壞欄位退回安全預設，唔會變成「睇落似真」嘅鬼時間
      expect(store.defs['sB']!.startTime, '00:00');
      expect(store.defs['sB']!.endTime, '00:00');
      // 班次本身仍然存在（用戶仍然可以喺班次管理頁改返時間）
      expect(store.defs['sB']!.name, '怪更');
    });
  });

  group('P1-6 場所清單型別唔符唔可以令清單歸零', () {
    test('venues 存成 JSON 字串 → 仍然還原成兩個場所', () async {
      final store = await freshStore({'venues': '["A","B"]'});
      expect(store.venues, ['A', 'B']);
    });

    test('venues 係正常 List<String> → 照舊讀得到', () async {
      final store = await freshStore({
        'venues': <String>['A1', '', '  ', 'B1'],
      });
      expect(store.venues, ['A1', 'B1']);
    });
  });

  group('P1-7 刪班次唔可以留低孤兒排班', () {
    test('removeDef 清走引用佢嘅排班，並回傳被清掉嘅日期', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ShiftStore(prefs);
      await store.load();
      await store.replaceAllDefs({
        'sA': def('sA', '早更', 'A', '06:00', '12:00'),
        'sB': def('sB', '夜更', 'B', '18:00', '00:00'),
      });
      await store.assign('2026-10-03', 'sA', note: 'A1');
      await store.assign('2026-10-01', 'sA', note: 'A2');
      await store.assign('2026-10-02', 'sB', note: 'B1');

      final removed = await store.removeDef('sA');

      expect(removed, ['2026-10-01', '2026-10-03']);
      expect(store.defs.containsKey('sA'), isFalse);
      expect(store.assignments.containsKey('2026-10-01'), isFalse);
      expect(store.assignments.containsKey('2026-10-03'), isFalse);
      // 其他班次嘅排班唔受影響
      expect(store.assignments['2026-10-02']!.shiftId, 'sB');

      // 持久化：重開 store 都唔應該見到孤兒
      final reloaded = ShiftStore(prefs);
      await reloaded.load();
      expect(reloaded.assignments.length, 1);
      expect(reloaded.assignments['2026-10-02']!.shiftId, 'sB');
    });

    test('removeDef 對冇人用嘅班次回傳空清單', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ShiftStore(prefs);
      await store.load();
      await store.replaceAllDefs({
        'sA': def('sA', '早更', 'A', '06:00', '12:00'),
      });
      final removed = await store.removeDef('sA');
      expect(removed, isEmpty);
      expect(store.defs, isEmpty);
    });
  });

  group('P0-3 導入配置後排班唔可以變成「未知班次」', () {
    test('v3 端到端：export → 清空 → import，排班仍然指向正確班次', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ShiftStore(prefs);
      await store.load();

      // 故意用「唔符合 v2 推導規則」嘅 id（v2 會推成 sA／sB）
      await store.replaceAllDefs({
        'alpha': def('alpha', '早更', 'A', '06:00', '12:00'),
        'beta': def('beta', '夜更', 'B', '18:00', '00:00'),
      });
      await store.replaceAllVenues(['A1', 'B1']);
      await store.assign('2026-10-01', 'alpha', note: 'A1');
      await store.assign('2026-10-02', 'beta', note: 'B1');

      final code = exportConfigCode(store);

      // 模擬換機：班次／場所清空（排班記錄仍然喺 prefs）
      await store.replaceAllDefs({});
      await store.replaceAllVenues([]);
      expect(store.defs, isEmpty);

      await importConfigText(store, code);

      // 班次 id 必須原封不動
      expect(store.defs.keys.toSet(), {'alpha', 'beta'});
      // 關鍵：排班仍然解析得到正確班次（舊版會全部變孤兒）
      final a = store.assignments['2026-10-01']!;
      expect(store.defs[a.shiftId]!.name, '早更');
      expect(store.defs[a.shiftId]!.code, 'A');
      final b = store.assignments['2026-10-02']!;
      expect(store.defs[b.shiftId]!.name, '夜更');
      expect(store.venues, ['A1', 'B1']);

      // 重開一次（真實換機流程：load 之後排班唔可以被當成孤兒清走）
      final reloaded = ShiftStore(prefs);
      await reloaded.load();
      expect(reloaded.assignments.length, 2);
      final ra = reloaded.assignments['2026-10-01']!;
      expect(reloaded.defs[ra.shiftId]!.name, '早更');
      expect(reloaded.lastLoadWarning, isNull);
    });

    test('v2 舊口令碼仍然導入得，並靠 code 反推原 id 搬排班', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ShiftStore(prefs);
      await store.load();

      // 舊機：id 係 'legacy06'（唔符合 v2 推導規則），code 係 '06'
      await store.replaceAllDefs({
        'legacy06': def('legacy06', '早更', '06', '06:00', '12:00'),
      });
      await store.assign('2026-10-01', 'legacy06', note: 'A1');

      final v2Code = buildV2Code();
      // 先確認真係讀得到（v2 冇 defId）
      final preview = previewConfig(v2Code);
      expect(preview.shifts, 1);
      expect(preview.venues, 1);
      expect(preview.names, ['早更']);

      await importConfigText(store, v2Code);

      // v2 嘅 id 係推導出嚟：code '06' → 's06'
      expect(store.defs.keys.toSet(), {'s06'});
      expect(store.defs['s06']!.name, '早更');
      // 排班必須由 'legacy06' 搬到 's06'，唔可以變孤兒
      expect(store.assignments['2026-10-01']!.shiftId, 's06');
      expect(store.assignments['2026-10-01']!.note, 'A1');
      expect(store.venues, ['A1']);

      final reloaded = ShiftStore(prefs);
      await reloaded.load();
      expect(reloaded.assignments['2026-10-01']!.shiftId, 's06');
      expect(reloaded.defs['s06']!.name, '早更');
    });

    test('v3 口令碼長度仍然守得住（< 200 字元）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ShiftStore(prefs);
      await store.load();
      await store.replaceAllDefs(ShiftStore.samplePresetDefs());
      await store.replaceAllVenues(ShiftStore.samplePresetVenues());
      final code = exportConfigCode(store);
      expect(code.length, lessThan(200));
    });
  });
}
