import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftalarm/alarm/alarm_bridge.dart';
import 'package:shiftalarm/domain/alarm_service.dart';
import 'package:shiftalarm/domain/shift_store.dart';

/// 打卡鬧鐘（開工打卡／收工打卡）測試。
/// 用遠期日期（2026-11-xx）避開 triggerAtFor「已過唔排」嘅邏輯。
Map<String, ShiftDef> _defs() => ShiftStore.testDefaults();

ShiftAlarm _byId(ShiftDef def, String id) =>
    def.alarms.firstWhere((a) => a.id == id);

/// 記低 schedule／scheduleGentle 呼叫嘅假橋，驗證打卡走只通知鏈。
class _FakeBridge extends AlarmBridge {
  final full = <AlarmSchedule>[];
  final gentle = <GentleAlarmSchedule>[];

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelGentle(int id) async {}

  @override
  Future<void> schedule({
    required int id,
    required int triggerAtMillis,
    required String title,
    required String body,
    int accentBg = 0xFF0078D4,
    int accentFg = 0xFFFFFFFF,
    String shiftName = '',
    String startTime = '',
    String date = '',
    String note = '',
  }) async {
    full.add(AlarmSchedule(
        id: id, triggerAtMillis: triggerAtMillis, title: title, body: body));
  }

  @override
  Future<void> scheduleGentle({
    required int id,
    required int triggerAtMillis,
    required String title,
    required String body,
  }) async {
    gentle.add(GentleAlarmSchedule(
        id: id, triggerAtMillis: triggerAtMillis, title: title, body: body));
  }
}

void main() {
  group('預設班次包含打卡鬧鐘', () {
    test('四個班次各有開工／收工打卡', () {
      final defs = _defs();
      expect(defs.keys, {'s00', 's06', 's12', 's18'});
      for (final def in defs.values) {
        expect(def.alarms.any((a) => a.id == ShiftAlarm.clockInId), isTrue,
            reason: '${def.id} 缺開工打卡');
        expect(def.alarms.any((a) => a.id == ShiftAlarm.clockOutId), isTrue,
            reason: '${def.id} 缺收工打卡');
      }
    });

    test('預設全部關閉（enabled=false），用戶手動開', () {
      for (final def in _defs().values) {
        expect(_byId(def, ShiftAlarm.clockInId).enabled, isFalse);
        expect(_byId(def, ShiftAlarm.clockOutId).enabled, isFalse);
      }
    });

    test('只通知：唔響鈴唔彈全屏', () {
      for (final def in _defs().values) {
        expect(_byId(def, ShiftAlarm.clockInId).notificationOnly, isTrue);
        expect(_byId(def, ShiftAlarm.clockOutId).notificationOnly, isTrue);
      }
    });

    test('label 固定：開工打卡／收工打卡', () {
      for (final def in _defs().values) {
        expect(_byId(def, ShiftAlarm.clockInId).label, '開工打卡');
        expect(_byId(def, ShiftAlarm.clockOutId).label, '收工打卡');
      }
    });

    test('固定 id 唔佔 a1／a2… 序列', () {
      for (final def in _defs().values) {
        final ids = def.alarms.map((a) => a.id).toSet();
        expect(ids.length, def.alarms.length, reason: 'id 重複');
        expect(ids, contains('a1'));
        expect(ids, contains('dk_in'));
        expect(ids, contains('dk_out'));
        expect(ShiftAlarm.clockInId, isNot(startsWith('a')));
        expect(ShiftAlarm.clockOutId, isNot(startsWith('a')));
      }
    });

    test('開工打卡 offset=0；收工打卡 offset=班次時長（預設 360）', () {
      for (final def in _defs().values) {
        expect(_byId(def, ShiftAlarm.clockInId).offsetMinutes, 0);
        expect(_byId(def, ShiftAlarm.clockOutId).offsetMinutes, 360);
      }
    });
  });

  group('班次時長（動態算，唔寫死 360）', () {
    test('00:00–06:00 → 360', () {
      expect(ShiftDef.durationMinutes('00:00', '06:00'), 360);
    });
    test('18:00–00:00 跨日 → 360', () {
      expect(ShiftDef.durationMinutes('18:00', '00:00'), 360);
    });
    test('自訂 8 小時 09:00–17:00 → 480', () {
      expect(ShiftDef.durationMinutes('09:00', '17:00'), 480);
    });
    test('22:30–06:30 跨日 → 480', () {
      expect(ShiftDef.durationMinutes('22:30', '06:30'), 480);
    });
  });

  group('打卡實際觸發時間', () {
    test('開工打卡＝班次 startTime（s00 跨午夜：2026-11-02 00:00）', () {
      final def = _defs()['s00']!;
      final t = AlarmService.triggerAtFor(
          '2026-11-02', def, _byId(def, ShiftAlarm.clockInId));
      expect(t, DateTime(2026, 11, 2, 0, 0));
    });

    test('收工打卡＝班次 endTime（s00 → 同日 06:00）', () {
      final def = _defs()['s00']!;
      final t = AlarmService.triggerAtFor(
          '2026-11-02', def, _byId(def, ShiftAlarm.clockOutId));
      expect(t, DateTime(2026, 11, 2, 6, 0));
    });

    test('收工打卡跨日（s18 18:00–00:00 → 翌日 00:00）', () {
      final def = _defs()['s18']!;
      final t = AlarmService.triggerAtFor(
          '2026-11-02', def, _byId(def, ShiftAlarm.clockOutId));
      expect(t, DateTime(2026, 11, 3, 0, 0));
    });

    test('自訂 8 小時班次：收工打卡 offset 480，觸發 17:00', () {
      final def = ShiftDef(
        id: 'c1',
        name: '自訂',
        startTime: '09:00',
        endTime: '17:00',
        alarms: [ShiftAlarm.clockIn(), ShiftAlarm.clockOutFor('09:00', '17:00')],
      );
      final out = _byId(def, ShiftAlarm.clockOutId);
      expect(out.offsetMinutes, 480);
      expect(AlarmService.triggerAtFor('2026-11-02', def, out),
          DateTime(2026, 11, 2, 17, 0));
      expect(
          AlarmService.triggerAtFor(
              '2026-11-02', def, _byId(def, ShiftAlarm.clockInId)),
          DateTime(2026, 11, 2, 9, 0));
    });
  });

  group('開關切換持久化', () {
    test('enabled 寫入後 reload 讀得返', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ShiftStore(prefs);
      await store.load();
      await store.replaceAllDefs(ShiftStore.testDefaults());

      final alarms =
          store.defs['s06']!.alarms.map((a) => a.copy()).toList();
      alarms
          .firstWhere((a) => a.id == ShiftAlarm.clockInId)
          .enabled = true;
      alarms
          .firstWhere((a) => a.id == ShiftAlarm.clockOutId)
          .enabled = true;
      await store.updateDef('s06', alarms: alarms);

      final store2 = ShiftStore(prefs);
      await store2.load();
      final def = store2.defs['s06']!;
      expect(_byId(def, ShiftAlarm.clockInId).enabled, isTrue);
      expect(_byId(def, ShiftAlarm.clockOutId).enabled, isTrue);
      // 固定欄位唔會被 normalize 整壞
      expect(_byId(def, ShiftAlarm.clockInId).offsetMinutes, 0);
      expect(_byId(def, ShiftAlarm.clockInId).label, '開工打卡');
      expect(_byId(def, ShiftAlarm.clockInId).notificationOnly, isTrue);
      expect(_byId(def, ShiftAlarm.clockOutId).offsetMinutes, 360);
      expect(_byId(def, ShiftAlarm.clockOutId).label, '收工打卡');
    });

    test('JSON 存嘅就係普通 ShiftAlarm（唔使加欄位）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ShiftStore(prefs);
      await store.load();
      await store.replaceAllDefs(ShiftStore.testDefaults());
      await store.updateDef('s06',
          alarms:
              store.defs['s06']!.alarms.map((a) => a.copy()).toList());
      final raw = prefs.getString('shift_defs')!;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final alarms = (j['s06'] as Map)['alarms'] as List;
      final ids = alarms.map((e) => (e as Map)['id']).toSet();
      expect(ids, contains('dk_in'));
      expect(ids, contains('dk_out'));
      final dkOut = alarms
          .firstWhere((e) => (e as Map)['id'] == 'dk_out') as Map;
      expect(dkOut['offsetMinutes'], 360);
      expect(dkOut['notificationOnly'], isTrue);
      expect(dkOut['enabled'], isFalse);
    });
  });

  group('改班次時間後重排', () {
    test('updateDef 改時間 → 收工打卡 offset 跟住班次時長變', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ShiftStore(prefs);
      await store.load();
      await store.replaceAllDefs(ShiftStore.testDefaults());

      // s06 06:00–12:00 改成 07:00–13:00（時長照舊 360）
      await store.updateDef('s06', startTime: '07:00', endTime: '13:00');
      final def = store.defs['s06']!;
      expect(_byId(def, ShiftAlarm.clockOutId).offsetMinutes, 360);
      expect(
          AlarmService.triggerAtFor('2026-11-02', def,
              _byId(def, ShiftAlarm.clockInId)),
          DateTime(2026, 11, 2, 7, 0));
      expect(
          AlarmService.triggerAtFor('2026-11-02', def,
              _byId(def, ShiftAlarm.clockOutId)),
          DateTime(2026, 11, 2, 13, 0));
    });

    test('改時長 → 收工打卡 offset 動態重算（6 小時改 8 小時）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ShiftStore(prefs);
      await store.load();
      await store.replaceAllDefs(ShiftStore.testDefaults());

      await store.updateDef('s12', startTime: '12:00', endTime: '20:00');
      final def = store.defs['s12']!;
      expect(_byId(def, ShiftAlarm.clockOutId).offsetMinutes, 480);
      expect(
          AlarmService.triggerAtFor('2026-11-02', def,
              _byId(def, ShiftAlarm.clockOutId)),
          DateTime(2026, 11, 2, 20, 0));
    });
  });

  group('舊數據遷移', () {
    test('load 舊 JSON（冇 dk_*）自動補上打卡鬧鐘', () async {
      SharedPreferences.setMockInitialValues({
        'shift_defs': jsonEncode({
          's06': {
            'name': '早更',
            'abbr': '早更',
            'startTime': '06:00',
            'endTime': '12:00',
            'alarms': [
              {
                'id': 'a1',
                'label': '開工鬧鐘',
                'offsetMinutes': -60,
                'notificationOnly': false,
                'enabled': true,
              },
            ],
          },
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = ShiftStore(prefs);
      await store.load();
      final def = store.defs['s06']!;
      expect(def.alarms.length, 3);
      expect(_byId(def, ShiftAlarm.clockInId).enabled, isFalse);
      expect(_byId(def, ShiftAlarm.clockOutId).offsetMinutes, 360);
      // 原有鬧鐘唔受影響
      expect(_byId(def, 'a1').offsetMinutes, -60);
      expect(_byId(def, 'a1').notificationOnly, isFalse);
    });
  });

  group('10 個上限計數包含打卡', () {
    test('8 個自訂＋2 個固定＝10，鬧鐘 id 全部唔同', () {
      final alarms = <ShiftAlarm>[
        for (var i = 1; i <= 8; i++)
          ShiftAlarm(
              id: 'a$i',
              label: '鬧鐘$i',
              offsetMinutes: -i * 10,
              enabled: true),
        ShiftAlarm.clockIn(),
        ShiftAlarm.clockOutFor('06:00', '12:00'),
      ];
      expect(alarms.length, 10);
      final def = ShiftDef(
          id: 'c1',
          name: '滿',
          startTime: '06:00',
          endTime: '12:00',
          alarms: alarms);
      final ids = <int>{};
      for (var i = 0; i < def.alarms.length && i < 10; i++) {
        ids.add(AlarmService.alarmIdFor('2026-11-02', i));
      }
      expect(ids.length, 10);
      // UI 新增掣 disable 條件：_alarms.length >= 10
      expect(def.alarms.length >= 10, isTrue);
    });

    test('超過 10 個只排前 10（打卡唔會整爆排程）', () async {
      final alarms = <ShiftAlarm>[
        for (var i = 1; i <= 9; i++)
          ShiftAlarm(
              id: 'a$i',
              label: '鬧鐘$i',
              offsetMinutes: -i * 10,
              enabled: true),
        ShiftAlarm.clockIn()..enabled = true,
        ShiftAlarm.clockOutFor('06:00', '12:00')..enabled = true,
      ];
      expect(alarms.length, 11);
      final def = ShiftDef(
          id: 'c1',
          name: '超',
          startTime: '06:00',
          endTime: '12:00',
          alarms: alarms);
      final fake = _FakeBridge();
      await AlarmService(fake).onAssigned('2026-11-02', def);
      expect(fake.full.length + fake.gentle.length, 10);
    });
  });

  group('打卡走只通知鏈（alarm_service 零改動）', () {
    test('onAssigned：開工／收工打卡 → scheduleGentle，全鬧鐘 → schedule', () async {
      final defs = _defs();
      final def = defs['s06']!;
      final alarms = def.alarms.map((a) => a.copy()).toList();
      alarms.firstWhere((a) => a.id == ShiftAlarm.clockInId).enabled = true;
      alarms.firstWhere((a) => a.id == ShiftAlarm.clockOutId).enabled = true;
      final live = ShiftDef(
          id: def.id,
          name: def.name,
          startTime: def.startTime,
          endTime: def.endTime,
          alarms: alarms);

      final fake = _FakeBridge();
      await AlarmService(fake).onAssigned('2026-11-02', live);

      // a1 全鬧鐘走 schedule
      expect(fake.full.length, 1);
      expect(fake.full.single.triggerAtMillis,
          DateTime(2026, 11, 2, 5, 0).millisecondsSinceEpoch);
      // 兩個打卡走 scheduleGentle，時間＝開工／收工整點
      expect(fake.gentle.length, 2);
      final byTitle = {for (final g in fake.gentle) g.title: g};
      expect(
          byTitle['早更 開工打卡']!.triggerAtMillis,
          DateTime(2026, 11, 2, 6, 0).millisecondsSinceEpoch);
      expect(
          byTitle['早更 收工打卡']!.triggerAtMillis,
          DateTime(2026, 11, 2, 12, 0).millisecondsSinceEpoch);
    });
  });

  group('ShiftStore assignBatch 批次指派', () {
    test('批次指派與備註成功寫入且不覆蓋既有備註', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ShiftStore(prefs);
      store.defs = _defs();

      await store.assignBatch([
        (ymd: '2026-11-01', shiftId: 's06', note: 'SITE_A', remark: '備註1'),
        (ymd: '2026-11-02', shiftId: 's12', note: 'SITE_B', remark: ''),
      ]);

      expect(store.assignments['2026-11-01']?.shiftId, 's06');
      expect(store.assignments['2026-11-01']?.note, 'SITE_A');
      expect(store.remarks['2026-11-01'], '備註1');

      expect(store.assignments['2026-11-02']?.shiftId, 's12');
      expect(store.assignments['2026-11-02']?.note, 'SITE_B');
      expect(store.remarks.containsKey('2026-11-02'), isFalse);
    });
  });
}
