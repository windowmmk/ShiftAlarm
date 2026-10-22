import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftalarm/domain/calendar_layout.dart';
import 'package:shiftalarm/theme/app_theme.dart';

/// 三區固定佈局（頂部海洋線 / 中間日曆 / 底部排班詳情）的永久防線。
///
/// 目標：任何屏幕高度（任何真實底部 inset、鍵盤開或關）都唔會溢出，而且讓位順序
/// 永遠係「先縮海洋帶 → 再縮底部區 → 最後先縮日曆格」。
///
/// v3.6.1 起 `compute` 多了兩個具名參數：
/// - `bottomInset`：真實 `MediaQuery.padding.bottom`（預設 [CalendarLayout.navReserved]）
/// - `keyboardOpen`：鍵盤彈起時海洋帶直接壓到 0
void main() {
  group('CalendarLayout 常數一致性', () {
    test('海洋帶理想高度 = kOceanBandHeight', () {
      expect(CalendarLayout.oceanMax, kOceanBandHeight);
    });

    test('底部區高度 = 內容實測高 + 卡片固定開銷，啱啱好裝得落又冇餘量', () {
      // 詳情卡固定開銷：margin 4+6 + padding 8+10 + border 1.2×2
      const double chrome = 4.0 + 6.0 + 8.0 + 10.0 + 1.2 * 2; // 30.4
      const double contentNormal = 103.0; // 21 + 6 + 40 + 6 + 30
      const double contentEditing = 109.0; // 備註進編輯態：30 → TextField 36

      expect(CalendarLayout.detailMin, 140.0);
      expect(CalendarLayout.detailMax, CalendarLayout.detailMin,
          reason: 'v3.6.1 起 detailMax == detailMin，讓位鏈第②級變 no-op');
      // ① 一定要裝得落（編輯態都唔可以裁到）
      expect(CalendarLayout.detailMin,
          greaterThanOrEqualTo(contentEditing + chrome));
      // ② 又唔可以多過 1px 餘量（用戶：「余量在底下空白位置，應該用盡」）
      expect(CalendarLayout.detailMin - (contentEditing + chrome),
          lessThanOrEqualTo(1.0));
      // ③ 普通態餘量 ≤ 7px（同上，唔可以再鬆）
      expect(CalendarLayout.detailMin - (contentNormal + chrome),
          lessThanOrEqualTo(7.0));
    });

    test('日曆格理想高度 = 舊版寫死的 75', () {
      expect(CalendarLayout.cellMax, 75.0);
      expect(
        CalendarLayout.gridOverhead + 6 * CalendarLayout.cellMax,
        486.0,
      );
    });
  });

  group('CalendarLayout.compute 實算值（預設 bottomInset = 72）', () {
    test('794px body：三區啱啱好全部理想值（海洋 96 / 底部 140 / 格 75）', () {
      final l = CalendarLayout.compute(794);
      expect(l.bandHeight, CalendarLayout.oceanMax);
      expect(l.detailHeight, CalendarLayout.detailMax);
      expect(l.cellHeight, closeTo(75.0, 1e-9));
      expect(l.navHeight, CalendarLayout.navReserved);
      expect(l.totalHeight, closeTo(794.0, 1e-9));
    });

    test('812px body：底部區唔會再無端多 18px，剩餘全部俾日曆格（78）', () {
      final l = CalendarLayout.compute(812);
      expect(l.bandHeight, CalendarLayout.oceanMax);
      expect(l.detailHeight, 140.0);
      expect(l.cellHeight, closeTo((812 - 72 - 96 - 140 - 36) / 6, 1e-9));
      expect(l.cellHeight, closeTo(78.0, 1e-9));
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

    test('360×800 典型機（body 720）：海洋讓到 56、底部 140，日曆格 69.33', () {
      final l = CalendarLayout.compute(720);
      expect(l.bandHeight, 56.0);
      expect(l.detailHeight, CalendarLayout.detailMin);
      expect(l.cellHeight, closeTo((720 - 72 - 56 - 140 - 36) / 6, 1e-9));
      expect(l.cellHeight, closeTo(69.3333, 1e-3));
      expect(l.totalHeight, closeTo(720.0, 1e-9));
    });

    test('360×640 細機（body 560）：仍然三區齊全、唔溢出', () {
      final l = CalendarLayout.compute(560);
      expect(l.bandHeight, 56.0);
      expect(l.detailHeight, CalendarLayout.detailMin);
      expect(l.cellHeight, greaterThan(40.0));
      expect(l.cellHeight, closeTo((560 - 72 - 56 - 140 - 36) / 6, 1e-9));
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
        expect(l.navHeight, greaterThanOrEqualTo(0));
      }
    });
  });

  group('bottomInset：用真實導航欄高度取代寫死 72', () {
    test('手勢導航 88.8：navHeight 就係 88.8，總高仍然等於 body', () {
      final l = CalendarLayout.compute(720, bottomInset: 88.8);
      expect(l.navHeight, closeTo(88.8, 1e-9));
      expect(l.totalHeight, closeTo(720.0, 1e-9));
    });

    test('三鍵導航 112.8：navHeight 就係 112.8，總高仍然等於 body', () {
      final l = CalendarLayout.compute(720, bottomInset: 112.8);
      expect(l.navHeight, closeTo(112.8, 1e-9));
      expect(l.totalHeight, closeTo(720.0, 1e-9));
    });

    test('鍵盤彈起（Scaffold 已把 padding.bottom 歸零）：navHeight = 0，唔會再空 72', () {
      final l = CalendarLayout.compute(420, bottomInset: 0);
      expect(l.navHeight, 0.0);
      expect(l.totalHeight, closeTo(420.0, 1e-9));
    });

    test('inset 大過 body 時會夾到 body，唔會反過來溢出', () {
      final l = CalendarLayout.compute(50, bottomInset: 200);
      expect(l.navHeight, 50.0);
      expect(l.totalHeight, closeTo(50.0, 1e-9));
    });

    test('負 inset 當 0 處理', () {
      final l = CalendarLayout.compute(720, bottomInset: -30);
      expect(l.navHeight, 0.0);
      expect(l.totalHeight, closeTo(720.0, 1e-9));
    });

    test('導航欄越高，日曆區就越矮（線性、單調）', () {
      double prev = double.infinity;
      for (final inset in <double>[0, 24, 48, 72, 88.8, 112.8]) {
        final l = CalendarLayout.compute(720, bottomInset: inset);
        expect(l.gridHeight, lessThanOrEqualTo(prev + 1e-9),
            reason: 'inset=$inset');
        prev = l.gridHeight;
      }
    });
  });

  group('keyboardOpen：輸入文字時天色欄完全壓縮為 0', () {
    test('keyboardOpen → bandHeight = 0', () {
      for (final h in <double>[400, 500, 720, 900]) {
        final l = CalendarLayout.compute(h, keyboardOpen: true);
        expect(l.bandHeight, 0.0, reason: 'body=$h');
        expect(l.totalHeight, closeTo(h, 1e-9), reason: 'body=$h');
      }
    });

    test('天色欄讓出嚟的高度一毫不少咁全部過俾日曆', () {
      const double body = 720;
      final closed = CalendarLayout.compute(body);
      final open = CalendarLayout.compute(body, keyboardOpen: true);
      expect(open.bandHeight, 0.0);
      expect(closed.bandHeight, greaterThan(0.0));
      expect(open.gridHeight,
          closeTo(closed.gridHeight + closed.bandHeight, 1e-9));
      expect(open.detailHeight, closed.detailHeight);
      expect(open.totalHeight, closeTo(body, 1e-9));
    });

    test('鍵盤態下 band = 0 唔會被「oceanMin 下限」反彈返 56', () {
      final l = CalendarLayout.compute(420, bottomInset: 0, keyboardOpen: true);
      expect(l.bandHeight, 0.0);
      expect(l.detailHeight, CalendarLayout.detailMin);
      expect(l.gridHeight, closeTo(420 - 140, 1e-9));
    });
  });

  group('讓位順序（用戶揀「優先保日曆格大」）', () {
    // 三區齊理想值嘅臨界 body = 96 + 140 + 36 + 6×75 + 72 = 794
    test('空間一唔夠，先縮海洋帶：日曆格同底部區保持不變', () {
      final a = CalendarLayout.compute(793);
      expect(a.bandHeight, 95.0, reason: '海洋帶先讓 1px');
      expect(a.detailHeight, CalendarLayout.detailMax);
      expect(a.cellHeight, closeTo(75.0, 1e-9));

      // 海洋帶讓到下限 56（body 754）之前，日曆格都仲係 75
      final b = CalendarLayout.compute(754);
      expect(b.bandHeight, CalendarLayout.oceanMin);
      expect(b.detailHeight, CalendarLayout.detailMin);
      expect(b.cellHeight, closeTo(75.0, 1e-9));
    });

    test('讓位鏈第②級（底部區）目前係 no-op，但分支保留', () {
      // detailMax == detailMin → 由「海洋帶讓到底」到「body 極細」之間，
      // detailHeight 恆等於 140，唔會再參與讓位。
      for (double h = 400; h <= 1000; h += 1) {
        final l = CalendarLayout.compute(h);
        if (l.gridHeight > 0) {
          expect(l.detailHeight, closeTo(CalendarLayout.detailMin, 1e-9),
              reason: 'body=$h');
        }
      }
    });

    test('海洋帶讓到底之後，日曆格即刻開始縮（中間冇多餘一級）', () {
      final a = CalendarLayout.compute(753);
      expect(a.bandHeight, CalendarLayout.oceanMin);
      expect(a.detailHeight, CalendarLayout.detailMin);
      expect(a.cellHeight, lessThan(75.0));
      expect(a.cellHeight, greaterThan(74.0));
    });
  });

  group('永久防線：任何高度／inset／鍵盤狀態都唔會溢出', () {
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

    test('四種真實 inset（0 / 24 / 88.8 / 112.8）× 鍵盤開關 全部總高 = body', () {
      for (final inset in <double>[0, 24, 88.8, 112.8]) {
        for (final kb in <bool>[false, true]) {
          for (double h = 0; h <= 1400; h += 1) {
            final l = CalendarLayout.compute(
              h,
              bottomInset: inset,
              keyboardOpen: kb,
            );
            expect(l.totalHeight, closeTo(h, 1e-9),
                reason: 'body=$h inset=$inset kb=$kb');
            expect(l.navHeight, lessThanOrEqualTo(h + 1e-9));
          }
        }
      }
    });

    test('非鍵盤態下海洋帶永遠唔會低過 oceanMin（除非連佢都放唔落）', () {
      for (double h = 0; h <= 1400; h += 1) {
        final l = CalendarLayout.compute(h);
        if (l.gridHeight > 0 && l.bandHeight > 0) {
          expect(l.bandHeight, greaterThanOrEqualTo(CalendarLayout.oceanMin),
              reason: 'body=$h');
        }
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

    test('calendar_screen.dart 用真實底部 inset，唔再靠寫死 72', () {
      final src = File('lib/ui/screens/calendar_screen.dart').readAsStringSync();
      expect(src.contains('bottomInset: mq.padding.bottom'), isTrue,
          reason: '必須把 extendBody 注入的真實 padding.bottom 傳落算式');
      expect(src.contains('keyboardOpen: keyboardOpen'), isTrue,
          reason: '鍵盤彈起時要壓縮天色欄');
      expect(src.contains('View.of(context).viewInsets.bottom > 0'), isTrue,
          reason: 'Scaffold 會食掉 body 的 viewInsets.bottom，必須讀未消費的 View');
    });

    test('shift_picker_panel.dart 唔可以再自己扣一次底部安全區', () {
      final src =
          File('lib/ui/screens/shift_picker_panel.dart').readAsStringSync();
      expect(src.contains('SafeArea'), isFalse,
          reason: '外層已預留真實 inset，再食一次就會溢出');
      expect(src.contains('SizedBox.expand'), isTrue);
    });
  });
}
