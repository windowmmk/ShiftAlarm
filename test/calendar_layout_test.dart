import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftalarm/domain/calendar_layout.dart';
import 'package:shiftalarm/theme/app_theme.dart';

/// 三區固定佈局（頂部海洋線 / 中間日曆 / 底部排班詳情）的永久防線。
///
/// 目標：任何屏幕高度都唔會溢出，而且讓位順序永遠係
/// 「先縮海洋帶 → 再縮底部區 → 最後先縮日曆格」。
void main() {
  group('CalendarLayout 常數一致性', () {
    test('海洋帶理想高度 = kOceanBandHeight', () {
      expect(CalendarLayout.oceanMax, kOceanBandHeight);
    });

    test('底部區下限容得落詳情卡實測高度（103 + 28.4 邊距 + 編輯態 6）', () {
      expect(CalendarLayout.detailMin, greaterThanOrEqualTo(142.0));
    });

    test('日曆格理想高度 = 舊版寫死的 75', () {
      expect(CalendarLayout.cellMax, 75.0);
      expect(
        CalendarLayout.gridOverhead + 6 * CalendarLayout.cellMax,
        486.0,
      );
    });
  });

  group('CalendarLayout.compute 實算值', () {
    test('812px body：三區啱啱好全部理想值（海洋 96 / 底部 158 / 格 75）', () {
      final l = CalendarLayout.compute(812);
      expect(l.bandHeight, CalendarLayout.oceanMax);
      expect(l.detailHeight, CalendarLayout.detailMax);
      expect(l.cellHeight, closeTo(75.0, 1e-9));
      expect(l.totalHeight, closeTo(812.0, 1e-9));
    });

    test('大屏剩餘空間全部俾日曆，格高生長到 cellGrowMax 就停', () {
      final l = CalendarLayout.compute(1200);
      expect(l.bandHeight, CalendarLayout.oceanMax);
      expect(l.detailHeight, CalendarLayout.detailMax);
      expect(l.cellHeight, CalendarLayout.cellGrowMax);
      // 格高生長到頂之後，再多嘅空間留喺日曆區內由 Center 上下平均分掉
      expect(l.gridHeight, greaterThan(CalendarLayout.gridOverhead + 6 * 92));
      expect(l.totalHeight, closeTo(1200.0, 1e-9));
    });

    test('360×800 典型機（body 720）：海洋讓到 56、底部讓到 142，日曆仍有 69', () {
      final l = CalendarLayout.compute(720);
      expect(l.bandHeight, 56.0);
      expect(l.detailHeight, CalendarLayout.detailMin);
      expect(l.cellHeight, closeTo((720 - 72 - 56 - 142 - 36) / 6, 1e-9));
      expect(l.cellHeight, greaterThan(68.0));
    });

    test('360×640 細機（body 560）：仍然三區齊全、唔溢出', () {
      final l = CalendarLayout.compute(560);
      expect(l.bandHeight, 56.0);
      expect(l.detailHeight, CalendarLayout.detailMin);
      expect(l.cellHeight, greaterThan(40.0));
      expect(l.totalHeight, closeTo(560.0, 1e-9));
    });

    test('極端細視窗（body 100）：海洋帶同底部區等比讓步，總高 = body', () {
      final l = CalendarLayout.compute(100);
      expect(l.gridHeight, 0.0);
      expect(l.totalHeight, closeTo(100.0, 1e-9));
    });

    test('body 0 或負數唔會出負高度', () {
      for (final h in <double>[0, -50]) {
        final l = CalendarLayout.compute(h);
        expect(l.bandHeight, greaterThanOrEqualTo(0));
        expect(l.detailHeight, greaterThanOrEqualTo(0));
        expect(l.gridHeight, greaterThanOrEqualTo(0));
        expect(l.cellHeight, greaterThanOrEqualTo(0));
      }
    });
  });

  group('讓位順序（用戶揀「優先保日曆格大」）', () {
    // 三區齊理想值嘅臨界 body = 96 + 158 + 36 + 6×75 + 72 = 812
    test('空間一唔夠，先縮海洋帶：日曆格同底部區保持不變', () {
      final a = CalendarLayout.compute(811);
      expect(a.bandHeight, 95.0, reason: '海洋帶先讓 1px');
      expect(a.detailHeight, CalendarLayout.detailMax);
      expect(a.cellHeight, closeTo(75.0, 1e-9));

      // 海洋帶讓到下限 56（body 772）之前，日曆格都仲係 75
      final b = CalendarLayout.compute(772);
      expect(b.bandHeight, CalendarLayout.oceanMin);
      expect(b.cellHeight, closeTo(75.0, 1e-9));
    });

    test('海洋帶讓到底之後，先縮底部區：日曆格仍然係 75', () {
      final a = CalendarLayout.compute(771);
      expect(a.bandHeight, CalendarLayout.oceanMin);
      expect(a.detailHeight, 157.0, reason: '底部區開始讓');
      expect(a.cellHeight, closeTo(75.0, 1e-9));

      // 底部區讓到下限 142（body 756）之前，日曆格都仲係 75
      final b = CalendarLayout.compute(756);
      expect(b.detailHeight, CalendarLayout.detailMin);
      expect(b.cellHeight, closeTo(75.0, 1e-9));
    });

    test('兩區都讓到底，日曆格先開始縮', () {
      final a = CalendarLayout.compute(755);
      expect(a.bandHeight, CalendarLayout.oceanMin);
      expect(a.detailHeight, CalendarLayout.detailMin);
      expect(a.cellHeight, lessThan(75.0));
      expect(a.cellHeight, greaterThan(74.0));
    });
  });

  group('永久防線：任何高度都唔會溢出', () {
    test('0 → 1400 逐 1px 掃：總高永遠啱啱好等於 body（唔溢出亦唔留白），且冇負值', () {
      for (double h = 0; h <= 1400; h += 1) {
        final l = CalendarLayout.compute(h);
        expect(
          l.totalHeight,
          closeTo(h, 1e-9),
          reason: 'body=$h 實佔 ${l.totalHeight}',
        );
        expect(l.bandHeight, greaterThanOrEqualTo(0), reason: 'body=$h');
        expect(l.detailHeight, greaterThanOrEqualTo(0), reason: 'body=$h');
        expect(l.cellHeight, greaterThanOrEqualTo(0), reason: 'body=$h');
        expect(l.cellHeight, lessThanOrEqualTo(CalendarLayout.cellGrowMax),
            reason: 'body=$h');
      }
    });

    test('日曆格高隨 body 單調遞增（唔會忽大忽小造成抖動）', () {
      double prev = -1;
      for (double h = 100; h <= 1400; h += 1) {
        final cell = CalendarLayout.compute(h).cellHeight;
        expect(cell + 1e-9, greaterThanOrEqualTo(prev), reason: 'body=$h');
        prev = cell;
      }
    });
  });

  group('永久防線：日曆頁唔可以再有彈出／彈入', () {
    test('calendar_screen.dart 唔含彈出動畫與舊的可見性狀態', () {
      final src = File('lib/ui/screens/calendar_screen.dart').readAsStringSync();
      // 舊版：㩒日期 → AnimatedSize + AnimatedSlide + AnimatedOpacity 由底彈出，
      // 用 _showDetailPanel 控制；今次改版要全部剷走。
      for (final banned in <String>[
        'AnimatedSize',
        'AnimatedSlide',
        'AnimatedOpacity',
        '_showDetailPanel',
        'onVerticalDragUpdate',
      ]) {
        expect(src.contains(banned), isFalse, reason: '仲殘留 $banned');
      }
      // 三區固定：必須由 CalendarLayout 一次算定高度
      expect(src.contains('CalendarLayout.compute'), isTrue);
    });
  });
}
