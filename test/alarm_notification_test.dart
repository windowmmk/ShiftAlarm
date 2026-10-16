import 'package:flutter_test/flutter_test.dart';
import 'package:shiftalarm/domain/alarm_service.dart';
import 'package:shiftalarm/domain/shift_store.dart';

void main() {
  group('AlarmService.formatAlarmBody 推送及全屏文案人性化格式化', () {
    test('收工打卡鬧鐘（clockOutId）：顯示打卡提醒與實際收工時刻，去除延後分鐘數', () {
      final alarm = ShiftAlarm.clockOutFor('07:00', '15:00'); // offset = 480
      final body = AlarmService.formatAlarmBody(
        startTime: '07:00',
        endTime: '15:00',
        alarm: alarm,
        note: '總部大樓',
      );
      expect(body, '收工時間到了，記得打卡！ (15:00) · 地點：總部大樓');
      expect(body.contains('延後'), isFalse);
      expect(body.contains('480'), isFalse);
    });

    test('收工打卡鬧鐘：無地點備註時不顯示地點後綴', () {
      final alarm = ShiftAlarm.clockOutFor('09:00', '18:00'); // offset = 540
      final body = AlarmService.formatAlarmBody(
        startTime: '09:00',
        endTime: '18:00',
        alarm: alarm,
        note: '',
      );
      expect(body, '收工時間到了，記得打卡！ (18:00)');
    });

    test('自訂收工/下班標籤鬧鐘自動識別為收工提醒', () {
      final alarm = ShiftAlarm(
        id: 'a3',
        label: '下午下班',
        offsetMinutes: 480,
      );
      final body = AlarmService.formatAlarmBody(
        startTime: '08:00',
        endTime: '16:00',
        alarm: alarm,
        note: '車間B',
      );
      expect(body, '收工時間到了，記得打卡！ (16:00) · 地點：車間B');
    });

    test('開工打卡鬧鐘（clockInId）：顯示開工打卡提醒與開工時刻', () {
      final alarm = ShiftAlarm.clockIn();
      final body = AlarmService.formatAlarmBody(
        startTime: '07:00',
        endTime: '15:00',
        alarm: alarm,
        note: '一號站點',
      );
      expect(body, '開工時間到了，記得打卡！ (07:00) · 地點：一號站點');
    });

    test('自訂開工打卡/上班打卡標籤鬧鐘自動識別為開工提醒', () {
      final alarm = ShiftAlarm(
        id: 'a0',
        label: '上班打卡',
        offsetMinutes: 0,
      );
      final body = AlarmService.formatAlarmBody(
        startTime: '08:30',
        endTime: '17:30',
        alarm: alarm,
      );
      expect(body, '開工時間到了，記得打卡！ (08:30)');
    });

    test('起床/班次提醒鬧鐘：顯示班次時間範圍與地點，不顯示提前/延後位移字眼', () {
      final alarm = ShiftAlarm(
        id: 'a1',
        label: '開工鬧鐘',
        offsetMinutes: -60, // 提前 60 分鐘
      );
      final body = AlarmService.formatAlarmBody(
        startTime: '07:00',
        endTime: '15:00',
        alarm: alarm,
        note: '總部',
      );
      expect(body, '班次時間：07:00–15:00 · 地點：總部');
      expect(body.contains('提前'), isFalse);
      expect(body.contains('60'), isFalse);
    });

    test('起床鬧鐘在無結束時間時平穩回退', () {
      final alarm = ShiftAlarm(
        id: 'a1',
        label: '起床鬧鐘',
        offsetMinutes: -30,
      );
      final body = AlarmService.formatAlarmBody(
        startTime: '06:00',
        endTime: '',
        alarm: alarm,
        note: '總部',
      );
      expect(body, '班次時間：06:00 · 地點：總部');
    });

    test('跨午夜班次（如通宵夜班 23:00–07:00）收工打卡時間計算精準', () {
      final alarm = ShiftAlarm.clockOutFor('23:00', '07:00'); // 480 分鐘
      final body = AlarmService.formatAlarmBody(
        startTime: '23:00',
        endTime: '07:00',
        alarm: alarm,
        note: '機房',
      );
      expect(body, '收工時間到了，記得打卡！ (07:00) · 地點：機房');
    });
  });
}
