// QA 獨立驗收（v3.6.1）—— 鬧鐘預告三項改動的 Dart 側驗證。
//
// 呢個檔係 QA 自己寫嘅驗證測試，**唔修改任何既有測試或原始碼**。
// 目的：證明「預告只限真鬧鐘」「倒計時終點＝響鬧時刻」「過濾冇漏、取消冇幽靈」，
// 而唔係確認程式碼存在。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftalarm/alarm/alarm_bridge.dart';
import 'package:shiftalarm/domain/alarm_service.dart';
import 'package:shiftalarm/domain/shift_store.dart';

/// 記錄所有原生呼叫嘅假橋（extends 真橋，只覆寫有需要嘅方法）。
class RecordingBridge extends AlarmBridge {
  final List<PreAlertSchedule> preAlerts = [];
  final List<int> cancelledPreAlertIds = [];
  final List<int> cancelledIds = [];
  final List<int> cancelledGentleIds = [];
  final List<AlarmSchedule> full = [];
  final List<GentleAlarmSchedule> gentle = [];

  int rescheduleAllCalls = 0;
  List<PreAlertSchedule> lastReschedulePreAlerts = const [];
  List<AlarmSchedule> lastRescheduleFull = const [];
  List<GentleAlarmSchedule> lastRescheduleGentle = const [];

  @override
  Future<void> schedulePreAlert(PreAlertSchedule s) async {
    preAlerts.add(s);
  }

  @override
  Future<void> cancelPreAlert(int alarmId) async {
    cancelledPreAlertIds.add(alarmId);
  }

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
  }

  @override
  Future<void> cancelGentle(int id) async {
    cancelledGentleIds.add(id);
  }

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
      id: id,
      triggerAtMillis: triggerAtMillis,
      title: title,
      body: body,
      accentBg: accentBg,
      accentFg: accentFg,
      shiftName: shiftName,
      startTime: startTime,
      date: date,
      note: note,
    ));
  }

  @override
  Future<void> scheduleGentle({
    required int id,
    required int triggerAtMillis,
    required String title,
    required String body,
  }) async {
    gentle.add(GentleAlarmSchedule(
      id: id,
      triggerAtMillis: triggerAtMillis,
      title: title,
      body: body,
    ));
  }

  @override
  Future<void> rescheduleAll(
    List<AlarmSchedule> full,
    List<GentleAlarmSchedule> gentle,
    List<PreAlertSchedule> preAlerts,
  ) async {
    rescheduleAllCalls++;
    lastRescheduleFull = List.of(full);
    lastRescheduleGentle = List.of(gentle);
    lastReschedulePreAlerts = List.of(preAlerts);
  }
}

/// 明日 09:00–17:30 的班次，四個鬧鐘：真鬧鐘／自建只通知／開工打卡／收工打卡。
ShiftDef makeDef({
  bool realAlarmEnabled = true,
  bool notifyOnlyEnabled = true,
  bool clockInEnabled = true,
  bool clockOutEnabled = true,
}) {
  return ShiftDef(
    id: 's09',
    name: '早更',
    startTime: '09:00',
    endTime: '17:30',
    alarms: [
      ShiftAlarm(
        id: 'a1',
        label: '開工鬧鐘',
        offsetMinutes: -30,
        notificationOnly: false,
        enabled: realAlarmEnabled,
      ),
      ShiftAlarm(
        id: 'a2',
        label: '自建提醒',
        offsetMinutes: -15,
        notificationOnly: true,
        enabled: notifyOnlyEnabled,
      ),
      ShiftAlarm.clockIn()..enabled = clockInEnabled,
      ShiftAlarm.clockOutFor('09:00', '17:30')..enabled = clockOutEnabled,
    ],
  );
}

String tomorrowYmd() {
  final d = DateTime.now().add(const Duration(days: 1));
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

DateTime tomorrowAt(int hour, int minute) {
  final d = DateTime.now().add(const Duration(days: 1));
  return DateTime(d.year, d.month, d.day, hour, minute);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v3.6.1 A1：預告只限真鬧鐘（notificationOnly == false）', () {
    test('onAssigned：四個鬧鐘只有真鬧鐘排預告', () async {
      final bridge = RecordingBridge();
      final service = AlarmService(bridge);
      final ymd = tomorrowYmd();
      final def = makeDef();

      await service.onAssigned(ymd, def);

      // 只通知類（自建 + 開工 + 收工）走 gentle，真鬧鐘走全鬧鐘
      expect(bridge.gentle.length, 3,
          reason: '自建只通知 + 開工打卡 + 收工打卡 應走 gentle 通道');
      expect(bridge.full.length, 1, reason: '只有一個真鬧鐘');
      // 預告：只有真鬧鐘
      expect(bridge.preAlerts.length, 1,
          reason: '打卡與自建只通知鬧鐘都不應該排預告（用戶原話：提前通知只限鬧鐘）');

      final base = AlarmService.alarmBaseId(ymd);
      expect(bridge.preAlerts.single.alarmId, base * 10 + 0,
          reason: '預告必須掛在真鬧鐘（index 0）身上');
    });

    test('syncOnLaunch：rescheduleAll 的 preAlerts 只有真鬧鐘', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ShiftStore(prefs);
      await store.load();
      await store.addDef(makeDef());
      final ymd = tomorrowYmd();
      await store.assign(ymd, 's09');

      final bridge = RecordingBridge();
      final service = AlarmService(bridge);
      await service.syncOnLaunch(store);

      expect(bridge.rescheduleAllCalls, 1);
      expect(bridge.lastRescheduleGentle.length, 3);
      expect(bridge.lastRescheduleFull.length, 1);
      expect(bridge.lastReschedulePreAlerts.length, 1,
          reason: '啟動對帳亦不可以把打卡預告排回去');
      expect(bridge.lastReschedulePreAlerts.single.alarmId,
          AlarmService.alarmBaseId(ymd) * 10);
    });

    test('全部鬧鐘都係只通知：preAlerts 必須完全空（唔可以靠 Kotlin 再過濾）', () async {
      final bridge = RecordingBridge();
      final service = AlarmService(bridge);
      final def = makeDef(realAlarmEnabled: false);
      await service.onAssigned(tomorrowYmd(), def);

      expect(bridge.preAlerts, isEmpty);
      expect(bridge.gentle.length, 3, reason: '三個只通知鬧鐘仍然要排');
    });

    test('disabled 的真鬧鐘亦唔排預告（enabled 過濾先於通道過濾）', () async {
      final bridge = RecordingBridge();
      final service = AlarmService(bridge);
      final def = makeDef(realAlarmEnabled: false, notifyOnlyEnabled: false);
      await service.onAssigned(tomorrowYmd(), def);
      expect(bridge.preAlerts, isEmpty);
      expect(bridge.full, isEmpty);
    });
  });

  group('v3.6.1 A3：倒計時終點＝真鬧鐘響鬧時刻', () {
    test('triggerAtMillis 逐毫秒等於開工時間 + offset（不是 leadAt、不是 now+1s）', () async {
      final bridge = RecordingBridge();
      final service = AlarmService(bridge);
      final ymd = tomorrowYmd();
      await service.onAssigned(ymd, makeDef());

      final expected = tomorrowAt(8, 30); // 09:00 − 30 分鐘
      final actual = bridge.preAlerts.single.triggerAtMillis;

      expect(actual, expected.millisecondsSinceEpoch,
          reason: '倒計時終點必須是 08:30 響鬧時刻本身');
      expect(actual, isNot(expected.subtract(const Duration(minutes: 60))
          .millisecondsSinceEpoch),
          reason: '不可以傳 leadAt（07:30），否則倒數會提早一小時歸零');
      expect(actual - DateTime.now().millisecondsSinceEpoch,
          greaterThan(const Duration(hours: 12).inMilliseconds),
          reason: '不可以傳 now + 1s（分支 2 的派發時刻），否則倒計時永遠顯示 00:00:01');
    });

    test('syncOnLaunch 與 onAssigned 算出同一個終點', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ShiftStore(prefs);
      await store.load();
      await store.addDef(makeDef());
      final ymd = tomorrowYmd();
      await store.assign(ymd, 's09');

      final b1 = RecordingBridge();
      await AlarmService(b1).onAssigned(ymd, makeDef());
      final b2 = RecordingBridge();
      await AlarmService(b2).syncOnLaunch(store);

      expect(b2.lastReschedulePreAlerts.single.triggerAtMillis,
          b1.preAlerts.single.triggerAtMillis);
    });

    test('提前量與 id 偏移常數與 Kotlin 對齊（60 分鐘 / 900000）', () {
      expect(AlarmService.preAlertLeadMinutes, 60);
      expect(AlarmService.preAlertIdOffset, 900000);
      expect(AlarmService.preAlertIdFor('2026-10-22', 3),
          AlarmService.alarmIdFor('2026-10-22', 3) + 900000);
    });
  });

  group('v3.6.1 A2：取消路徑不留幽靈', () {
    test('onAssigned 先清 10 個 index 的預告（覆蓋升級前殘留）', () async {
      final bridge = RecordingBridge();
      final service = AlarmService(bridge);
      final ymd = tomorrowYmd();
      await service.onAssigned(ymd, makeDef());

      final base = AlarmService.alarmBaseId(ymd);
      final expectedIds = [
        for (var i = 0; i < ShiftAlarm.maxAlarmsPerShift; i++) base * 10 + i
      ];
      expect(bridge.cancelledPreAlertIds.toSet().containsAll(expectedIds), isTrue,
          reason: '每個 index 的預告 id 都要清，否則升級前的打卡預告會留低');
      expect(bridge.cancelledIds, contains(base),
          reason: '舊制 base id 幽靈亦要清');
    });

    test('真鬧鐘改成只通知：舊預告被取消且不再重排', () async {
      final bridge = RecordingBridge();
      final service = AlarmService(bridge);
      final ymd = tomorrowYmd();

      await service.onAssigned(ymd, makeDef());
      expect(bridge.preAlerts.length, 1);
      bridge.preAlerts.clear();
      bridge.cancelledPreAlertIds.clear();

      // 使用者把真鬧鐘改成「只通知」
      final def = makeDef();
      def.alarms[0].notificationOnly = true;
      await service.onAssigned(ymd, def);

      expect(bridge.preAlerts, isEmpty, reason: '改成只通知後不應再有預告');
      final base = AlarmService.alarmBaseId(ymd);
      expect(bridge.cancelledPreAlertIds, contains(base * 10),
          reason: '原本的預告必須在同一輪被取消，否則會掛著倒數到一個已改性質的鬧鐘');
    });

    test('刪更（onUnassigned）清走該日全部預告 id', () async {
      final bridge = RecordingBridge();
      final service = AlarmService(bridge);
      final ymd = tomorrowYmd();
      await service.onUnassigned(ymd);

      final base = AlarmService.alarmBaseId(ymd);
      for (var i = 0; i < ShiftAlarm.maxAlarmsPerShift; i++) {
        expect(bridge.cancelledPreAlertIds, contains(base * 10 + i));
      }
    });

    test('排班清空後 syncOnLaunch 仍然呼叫 rescheduleAll（觸發原生 prune）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ShiftStore(prefs);
      await store.load();

      final bridge = RecordingBridge();
      await AlarmService(bridge).syncOnLaunch(store);

      expect(bridge.rescheduleAllCalls, 1,
          reason: '三個 list 全空都必須呼叫，否則原生 prune 永遠不會清走殘留預告');
      expect(bridge.lastReschedulePreAlerts, isEmpty);
    });
  });

  group('v3.6.1 A2/A5：預告文案不再寫死剩餘時間', () {
    test('標題無「1 小時後」前綴、內文無「仲有 1 小時響」', () async {
      final bridge = RecordingBridge();
      await AlarmService(bridge).onAssigned(tomorrowYmd(), makeDef());
      final s = bridge.preAlerts.single;

      expect(s.title, '早更 開工鬧鐘');
      expect(s.title.contains('小時'), isFalse);
      expect(s.body.contains('小時後'), isFalse);
      expect(s.body.contains('仲有'), isFalse,
          reason: '剩餘時間交由 chronometer 實時渲染，文案寫死會同倒計時矛盾');
      expect(s.body, contains('班次時間：09:00–17:30'));
    });

    test('備註（地點）照樣帶入預告內文', () async {
      final bridge = RecordingBridge();
      await AlarmService(bridge)
          .onAssigned(tomorrowYmd(), makeDef(), note: 'A 座大堂');
      expect(bridge.preAlerts.single.body, contains('A 座大堂'));
    });
  });
}
