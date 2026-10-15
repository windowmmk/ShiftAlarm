import 'package:flutter_test/flutter_test.dart';
import 'package:shiftalarm/domain/alarm_service.dart';

/// 鬧鐘實際響鐘時間（顯示用）edge cases：
/// trigger = 開工分鐘數 + offset，normalize 到 0–1439，計日偏移。
void main() {
  group('alarmClockParts', () {
    test('00:00 午夜：offset 0 → 00:00 當日', () {
      expect(AlarmService.alarmClockParts('00:00', 0), ('00:00', 0));
    });
    test('00:00 午夜：offset −1 → 23:59 前一日', () {
      expect(AlarmService.alarmClockParts('00:00', -1), ('23:59', -1));
    });
    test('00:00 午夜：offset −60 → 23:00 前一日', () {
      expect(AlarmService.alarmClockParts('00:00', -60), ('23:00', -1));
    });
    test('00:00 午夜：offset −120 → 22:00 前一日', () {
      expect(AlarmService.alarmClockParts('00:00', -120), ('22:00', -1));
    });
    test('06:00 − 30 → 05:30 當日', () {
      expect(AlarmService.alarmClockParts('06:00', -30), ('05:30', 0));
    });
    test('18:00 ＋ 120（延後）→ 20:00 當日', () {
      expect(AlarmService.alarmClockParts('18:00', 120), ('20:00', 0));
    });
  });

  group('顯示格式：HH:mm 24小時制補零', () {
    test('06:00 唔係 6:00', () {
      expect(AlarmService.alarmClockParts('06:30', -30).$1, '06:00');
    });
    test('00:00 唔係 24:00', () {
      expect(AlarmService.alarmClockParts('00:00', 0).$1, '00:00');
    });
  });

  group('跨日整點', () {
    test('18:00 ＋ 360 → 00:00 後一日', () {
      expect(AlarmService.alarmClockParts('18:00', 360), ('00:00', 1));
    });
  });

  group('剛好一日', () {
    test('offset −1440 → 同一時間前一日', () {
      expect(AlarmService.alarmClockParts('06:00', -1440), ('06:00', -1));
    });
    test('offset ＋1440 → 同一時間後一日', () {
      expect(AlarmService.alarmClockParts('06:00', 1440), ('06:00', 1));
    });
  });

  group('alarmDayLabel', () {
    test('0 → 空（當日唔標）', () {
      expect(AlarmService.alarmDayLabel(0), '');
    });
    test('−1 → 前一日', () {
      expect(AlarmService.alarmDayLabel(-1), '（前一日）');
    });
    test('+1 → 後一日', () {
      expect(AlarmService.alarmDayLabel(1), '（後一日）');
    });
  });

  group('alarmClockText 一行過', () {
    test('00:00 − 60 → 23:00（前一日）', () {
      expect(AlarmService.alarmClockText('00:00', -60), '23:00（前一日）');
    });
    test('18:00 ＋ 360 → 00:00（後一日）', () {
      expect(AlarmService.alarmClockText('18:00', 360), '00:00（後一日）');
    });
    test('06:00 − 30 → 05:30（當日唔標）', () {
      expect(AlarmService.alarmClockText('06:00', -30), '05:30');
    });
  });
}
