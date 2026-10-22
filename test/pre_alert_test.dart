import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftalarm/alarm/alarm_bridge.dart';
import 'package:shiftalarm/domain/alarm_service.dart';
import 'package:shiftalarm/domain/shift_store.dart';

/// 響鬧預告（第三條通道）測試。
///
/// 覆蓋 v3.6.1 兩個改造：
///  (A) 預告只給真正的鬧鐘（`notificationOnly == false`），純通知類唔排。
///  (B) 預告改為狀態欄倒計時，文案唔再寫死「1 小時」。
///
/// 用遠期日期（now + 30 日）避開 `triggerAtFor` 的「已過唔排」邏輯。
String _futureYmd([int daysAhead = 30]) {
  final d = DateTime.now().add(Duration(days: daysAhead));
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// 該日期 06:00 開工、12:00 收工（時長 360 分鐘）。
ShiftDef _def() => ShiftDef(
      id: 'c1',
      name: '早更',
      startTime: '06:00',
      endTime: '12:00',
      alarms: [
        // index 0：真正的鬧鐘 → 應該有預告
        ShiftAlarm(
            id: 'a1', label: '開工鬧鐘', offsetMinutes: -60, enabled: true),
        // index 1：使用者自建的「只通知」鬧鐘 → 唔應該有預告
        ShiftAlarm(
            id: 'a2',
            label: '自訂提醒',
            offsetMinutes: -30,
            notificationOnly: true,
            enabled: true),
        // index 2：開工打卡（固定 notificationOnly: true）→ 唔應該有預告
        ShiftAlarm.clockIn()..enabled = true,
        // index 3：收工打卡（固定 notificationOnly: true）→ 唔應該有預告
        ShiftAlarm.clockOutFor('06:00', '12:00')..enabled = true,
      ],
    );

/// 記錄三條通道呼叫的假橋。全部 override，避免落到真 MethodChannel
/// 拋 `MissingPluginException`（同 `test/clockin_test.dart` 的 `_FakeBridge` 同手法）。
class _FakeBridge extends AlarmBridge {
  final full = <AlarmSchedule>[];
  final gentle = <GentleAlarmSchedule>[];
  final preAlerts = <PreAlertSchedule>[];
  final cancelledPreAlerts = <int>[];
  int rescheduleAllCalls = 0;
  List<PreAlertSchedule> lastPreAlertsArg = const <PreAlertSchedule>[];

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelGentle(int id) async {}

  @override
  Future<void> cancelPreAlert(int alarmId) async {
    cancelledPreAlerts.add(alarmId);
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

  @override
  Future<void> schedulePreAlert(PreAlertSchedule s) async {
    preAlerts.add(s);
  }

  @override
  Future<void> rescheduleAll(
      List<AlarmSchedule> f,
      List<GentleAlarmSchedule> g,
      List<PreAlertSchedule> p) async {
    rescheduleAllCalls++;
    full.addAll(f);
    gentle.addAll(g);
    preAlerts.addAll(p);
    lastPreAlertsArg = p;
  }
}

void main() {
  group('(A) onAssigned：預告只給真正的鬧鐘', () {
    test('4 個 enabled 鬧鐘裡只有 a1（notificationOnly=false）拿到預告', () async {
      final ymd = _futureYmd();
      final fake = _FakeBridge();
      await AlarmService(fake).onAssigned(ymd, _def());

      // 真鬧鐘走全屏通道，其餘三個走只通知通道
      expect(fake.full.length, 1, reason: '只有 a1 走 schedule');
      expect(fake.gentle.length, 3, reason: 'a2／開工打卡／收工打卡走 gentle');

      // 預告只有一條，且屬於 index 0（a1）
      expect(fake.preAlerts.length, 1,
          reason: '打卡與自訂只通知鬧鐘一律唔排預告');
      expect(fake.preAlerts.single.alarmId, AlarmService.alarmIdFor(ymd, 0));
    });

    test('打卡鬧鐘（clockInId / clockOutId）的 alarmId 唔會出現喺預告列表', () async {
      final ymd = _futureYmd();
      final fake = _FakeBridge();
      await AlarmService(fake).onAssigned(ymd, _def());

      final preAlertIds = fake.preAlerts.map((p) => p.alarmId).toSet();
      expect(preAlertIds.contains(AlarmService.alarmIdFor(ymd, 2)), isFalse,
          reason: '開工打卡（index 2）唔應該有預告');
      expect(preAlertIds.contains(AlarmService.alarmIdFor(ymd, 3)), isFalse,
          reason: '收工打卡（index 3）唔應該有預告');
      expect(preAlertIds.contains(AlarmService.alarmIdFor(ymd, 1)), isFalse,
          reason: '使用者自建嘅只通知鬧鐘（index 1）唔應該有預告');
    });

    test('全部鬧鐘都係 notificationOnly → 零預告', () async {
      final ymd = _futureYmd();
      final def = ShiftDef(
        id: 'c2',
        name: '純通知',
        startTime: '06:00',
        endTime: '12:00',
        alarms: [
          ShiftAlarm(
              id: 'a1',
              label: '只通知一',
              offsetMinutes: -60,
              notificationOnly: true,
              enabled: true),
          ShiftAlarm(
              id: 'a2',
              label: '只通知二',
              offsetMinutes: -30,
              notificationOnly: true,
              enabled: true),
          ShiftAlarm.clockIn()..enabled = true,
          ShiftAlarm.clockOutFor('06:00', '12:00')..enabled = true,
        ],
      );
      final fake = _FakeBridge();
      await AlarmService(fake).onAssigned(ymd, def);

      expect(fake.gentle.length, 4);
      expect(fake.preAlerts, isEmpty, reason: '一條真鬧鐘都冇 → 一條預告都唔應該有');
    });
  });

  group('(A) syncOnLaunch：第二條入口同樣要過濾', () {
    test('rescheduleAll 收到的 preAlerts 只有 a1', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ymd = _futureYmd();
      final store = ShiftStore(prefs);
      store.defs = {'c1': _def()};
      store.assignments = {ymd: ShiftAssignment('c1', '')};

      final fake = _FakeBridge();
      await AlarmService(fake).syncOnLaunch(store);

      expect(fake.rescheduleAllCalls, 1);
      expect(fake.lastPreAlertsArg.length, 1,
          reason: 'syncOnLaunch 同 onAssigned 必須行為一致');
      expect(fake.lastPreAlertsArg.single.alarmId,
          AlarmService.alarmIdFor(ymd, 0));
      // 三條通道的數量也要對得上
      expect(fake.full.length, 1);
      expect(fake.gentle.length, 3);
    });

    test('零排班時仍然呼叫 rescheduleAll（對帳 prune 要跑得到）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ShiftStore(prefs);
      store.defs = {'c1': _def()};
      store.assignments = {};

      final fake = _FakeBridge();
      await AlarmService(fake).syncOnLaunch(store);

      expect(fake.rescheduleAllCalls, 1,
          reason: '空 list 也要呼叫，否則原生 prune 唔會跑，舊預告永遠殘留');
      expect(fake.lastPreAlertsArg, isEmpty);
    });
  });

  group('(B) 預告的 triggerAtMillis 係鬧鐘觸發時刻，不是提前 60 分鐘', () {
    test('onAssigned：a1 06:00−60min＝05:00 響 → 預告 triggerAtMillis 就係 05:00', () async {
      final ymd = _futureYmd();
      final def = _def();
      final fake = _FakeBridge();
      await AlarmService(fake).onAssigned(ymd, def);

      final expected = AlarmService.triggerAtFor(ymd, def, def.alarms[0])!;
      final parts = ymd.split('-').map(int.parse).toList();
      expect(expected, DateTime(parts[0], parts[1], parts[2], 5, 0),
          reason: '06:00 開工、offset −60 → 鬧鐘 05:00 響');
      expect(fake.preAlerts.single.triggerAtMillis,
          expected.millisecondsSinceEpoch);
    });

    test('syncOnLaunch：triggerAtMillis 與鬧鐘本身一致', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ymd = _futureYmd();
      final def = _def();
      final store = ShiftStore(prefs);
      store.defs = {'c1': def};
      store.assignments = {ymd: ShiftAssignment('c1', '')};

      final fake = _FakeBridge();
      await AlarmService(fake).syncOnLaunch(store);

      final alarm = AlarmService.triggerAtFor(ymd, def, def.alarms[0])!;
      expect(fake.lastPreAlertsArg.single.triggerAtMillis,
          alarm.millisecondsSinceEpoch);
      // 明確否定「提前 60 分鐘」的誤解：差額必須係 0，唔係 −3600000
      expect(fake.lastPreAlertsArg.single.triggerAtMillis -
              fake.full.single.triggerAtMillis,
          0);
    });

    test('preAlertLeadMinutes 固定 60，且由原生側扣減（Dart 不預扣）', () {
      expect(AlarmService.preAlertLeadMinutes, 60);
    });
  });

  group('(B) 文案唔再寫死剩餘時間', () {
    test('preAlertTitle 只有「班次名 鬧鐘標籤」', () {
      final t = AlarmService.preAlertTitle('早更', '開工鬧鐘');
      expect(t, '早更 開工鬧鐘');
      expect(t.contains('1 小時後'), isFalse);
      expect(t.contains('小時'), isFalse);
    });

    test('preAlertBody 直接串 formatAlarmBody，冇前綴', () {
      final alarmBody = AlarmService.formatAlarmBody(
        startTime: '06:00',
        endTime: '12:00',
        alarm: ShiftAlarm(
            id: 'a1', label: '開工鬧鐘', offsetMinutes: -60, enabled: true),
      );
      final b = AlarmService.preAlertBody(alarmBody);
      expect(b, alarmBody);
      expect(b.contains('仲有 1 小時響'), isFalse);
      expect(b.contains('小時後'), isFalse);
    });

    test('onAssigned 產出的預告標題／內文都唔含剩餘時間字樣', () async {
      final ymd = _futureYmd();
      final fake = _FakeBridge();
      await AlarmService(fake).onAssigned(ymd, _def());

      final p = fake.preAlerts.single;
      expect(p.title, '早更 開工鬧鐘');
      expect(p.body, '班次時間：06:00–12:00');
      expect(p.title.contains('1 小時後'), isFalse);
      expect(p.body.contains('仲有 1 小時響'), isFalse);
    });
  });

  group('id 命名空間互不衝突', () {
    test('preAlertIdOffset 係 900000，且等於 alarmId + 偏移', () {
      final ymd = _futureYmd();
      expect(AlarmService.preAlertIdOffset, 900000);
      expect(AlarmService.preAlertIdFor(ymd, 0),
          AlarmService.alarmIdFor(ymd, 0) + 900000);
      expect(AlarmService.preAlertIdFor(ymd, 9),
          AlarmService.alarmIdFor(ymd, 9) + 900000);
    });

    test('同一日 10 個 index：鬧鐘 id／通知 id／兩個 PendingIntent id 全互斥', () {
      final ymd = _futureYmd();
      final seen = <int>{};
      for (var i = 0; i < ShiftAlarm.maxAlarmsPerShift; i++) {
        final id = AlarmService.alarmIdFor(ymd, i);
        // +500000 gentle dismiss、+800000 預告「知道了」、+850000 預告 content、
        // +900000 預告 AlarmManager requestCode 與 notification id
        for (final candidate in [
          id,
          id + 500000,
          id + 800000,
          id + 850000,
          id + 900000,
        ]) {
          expect(seen.add(candidate), isTrue,
              reason: 'id $candidate 同前面撞咗（index $i）');
        }
      }
      expect(seen.length, ShiftAlarm.maxAlarmsPerShift * 5);
    });

    test('預告 id 永遠唔會等於任何一個鬧鐘 id', () {
      final ymd = _futureYmd();
      final alarmIds = {
        for (var i = 0; i < ShiftAlarm.maxAlarmsPerShift; i++)
          AlarmService.alarmIdFor(ymd, i)
      };
      for (var i = 0; i < ShiftAlarm.maxAlarmsPerShift; i++) {
        expect(alarmIds.contains(AlarmService.preAlertIdFor(ymd, i)), isFalse);
      }
    });
  });

  group('取消路徑：超集全清，唔按 notificationOnly 過濾', () {
    test('onUnassigned 逐個 index 清三條通道（10 個 index 全覆蓋）', () async {
      final ymd = _futureYmd();
      final fake = _FakeBridge();
      await AlarmService(fake).onUnassigned(ymd);

      expect(fake.cancelledPreAlerts.length, ShiftAlarm.maxAlarmsPerShift,
          reason: '取消係排程的超集，index 0–9 全部要清，包括打卡位');
      for (var i = 0; i < ShiftAlarm.maxAlarmsPerShift; i++) {
        expect(fake.cancelledPreAlerts,
            contains(AlarmService.alarmIdFor(ymd, i)));
      }
    });

    test('轉更（onAssigned）會先全清再排，唔會疊加', () async {
      final ymd = _futureYmd();
      final fake = _FakeBridge();
      await AlarmService(fake).onAssigned(ymd, _def());

      expect(fake.cancelledPreAlerts.length, ShiftAlarm.maxAlarmsPerShift,
          reason: 'onAssigned 開頭會 _cancelAllFor');
      expect(fake.preAlerts.length, 1);
    });
  });
}
