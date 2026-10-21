import 'package:flutter_test/flutter_test.dart';
import 'package:shiftalarm/domain/shift_store.dart';
import 'package:shiftalarm/domain/shift_time.dart';

/// `shift_time.dart` 是**全專案唯一**一份班次時長規則：
/// 打卡鬧鐘的 dk_out offset（`ShiftDef.durationMinutes`）與統計頁的總工時
/// 都必須經此。這個檔案除了驗語意，更重要是釘住「兩邊一致」這件事——
/// 若日後有人把委派改回獨立實作，下面的 `ShiftDef.durationMinutes` 對照組會紅。
void main() {
  group('hmToMinutes', () {
    test('標準寫法', () {
      expect(hmToMinutes('00:00'), 0);
      expect(hmToMinutes('09:00'), 540);
      expect(hmToMinutes('17:30'), 1050);
      expect(hmToMinutes('23:59'), 1439);
    });

    test('無補零寫法照收（保留舊版寬容度）', () {
      expect(hmToMinutes('9'), 540);
      expect(hmToMinutes('09:0'), 540);
      expect(hmToMinutes('9:5'), 545);
      expect(hmToMinutes(' 09:00 '), 540); // 前後空白容許
    });

    test('多於兩段：只取前兩段（沿用舊版行為）', () {
      expect(hmToMinutes('09:00:00'), 540);
    });

    test('時分越界回 null', () {
      expect(hmToMinutes('24:00'), isNull);
      expect(hmToMinutes('09:60'), isNull);
      expect(hmToMinutes('25:00'), isNull);
      expect(hmToMinutes('09:99'), isNull);
      expect(hmToMinutes('-1:00'), isNull);
    });

    test('無法解析回 null', () {
      expect(hmToMinutes(''), isNull);
      expect(hmToMinutes('abc'), isNull);
      expect(hmToMinutes(':30'), isNull);
      expect(hmToMinutes('09:xx'), isNull);
    });
  });

  group('shiftDurationMinutes', () {
    test('同日', () {
      expect(shiftDurationMinutes('09:00', '17:00'), 480);
      expect(shiftDurationMinutes('09:00', '17:30'), 510);
    });

    test('跨午夜', () {
      expect(shiftDurationMinutes('00:00', '06:00'), 360);
      expect(shiftDurationMinutes('18:00', '00:00'), 360);
      expect(shiftDurationMinutes('22:00', '06:00'), 480);
      expect(shiftDurationMinutes('22:30', '06:30'), 480);
      expect(shiftDurationMinutes('23:59', '00:01'), 2);
    });

    test('同起同訖 → 0（不放大成 24 小時）', () {
      expect(shiftDurationMinutes('00:00', '00:00'), 0);
      expect(shiftDurationMinutes('08:00', '08:00'), 0);
    });

    test('任一時間非法 → 0', () {
      expect(shiftDurationMinutes('abc', '17:00'), 0);
      expect(shiftDurationMinutes('09:00', 'abc'), 0);
      expect(shiftDurationMinutes('24:00', '17:00'), 0);
      expect(shiftDurationMinutes('09:00', '09:60'), 0);
      expect(shiftDurationMinutes('', ''), 0);
    });

    test('回傳值恆在 0–1439（不會負數）', () {
      for (final c in [
        ('00:00', '00:00'),
        ('23:59', '00:00'),
        ('00:00', '23:59'),
        ('12:00', '11:59'),
      ]) {
        final v = shiftDurationMinutes(c.$1, c.$2);
        expect(v, greaterThanOrEqualTo(0), reason: '$c');
        expect(v, lessThan(1440), reason: '$c');
      }
    });
  });

  group('與 ShiftDef.durationMinutes 完全一致（防止委派被改回獨立實作）', () {
    test('六個代表案例兩邊相同', () {
      for (final c in [
        ('00:00', '06:00'),
        ('18:00', '00:00'),
        ('09:00', '17:00'),
        ('22:30', '06:30'),
        ('9', '17:00'),
        ('22:00', '06:00'),
      ]) {
        expect(
          shiftDurationMinutes(c.$1, c.$2),
          ShiftDef.durationMinutes(c.$1, c.$2),
          reason: 'case=$c',
        );
      }
    });

    test('時長直接餵給統計：8.5 小時班 → 510 分鐘', () {
      final minutes = shiftDurationMinutes('09:00', '17:30');
      expect(minutes, 510);
      expect(ShiftDef.durationMinutes('09:00', '17:30'), 510);
    });
  });
}
