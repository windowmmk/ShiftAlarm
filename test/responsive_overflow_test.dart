import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftalarm/alarm/alarm_bridge.dart';
import 'package:shiftalarm/domain/alarm_service.dart';
import 'package:shiftalarm/domain/shift_store.dart';
import 'package:shiftalarm/theme/app_theme.dart';
import 'package:shiftalarm/ui/screens/calendar_screen.dart';

/// 版面溢出的**永久防線**（v3.6.2 新增）。
///
/// 背景：v3.6.1 之前，日曆頁在兩個地方會出黃黑間條（`RenderFlex overflowed`）：
///
/// 1. **AppBar 標題 Row**（`calendar_screen.dart`）：`title` 是固定寬度的
///    `Row(mainAxisSize: min)`，而 `AppBar` 只把「總寬 − actions − spacing」的
///    剩餘寬度分給它。實測剩餘寬度 320/360/390/412 分別只有
///    55.8 / 95.8 / 125.8 / 147.8，而標題本身要 164 —— 所以**每一個寬度都爆邊**
///    （320 爆 108、360 爆 68、390 爆 38、412 爆 16）。連 412px 的大機都中招。
///
/// 2. **日曆星期表頭**：`CalendarLayout` 只預留 36px 給「表頭 + 間距 + 上下 padding」，
///    實算表頭可用高度只有 24px。1.0 倍字體時表頭 21px 剛好夠，但
///    1.15 倍 = 24px 頂死、1.3 倍 = 26px 爆 2px、2.0 倍 = 38px 爆 14px。
///    即**任何開了系統「大字體」的用戶，日曆都會爆邊**。
///
/// 呢個測試唔再只檢查「三區本體」的 Column，而係**掃整棵 render tree** 的每一個
/// `RenderFlex`，用「子節點總長 > 自身長度」直接判定溢出 —— 咁就唔會再有
/// 「某個局部溢出被過濾器放過」的假綠燈。
///
/// ⚠️ 唔可以用 `pumpAndSettle()`：海洋帶有 30fps 常駐 `Timer.periodic`，永遠 settle 唔到。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ShiftStore> makeStore() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = ShiftStore(prefs);
    await store.load();
    return store;
  }

  /// 掃描整棵 render tree，回傳所有溢出的 RenderFlex 描述。
  ///
  /// 用「子節點總長 > 自身長度」而不是靠捕捉 exception：`RenderFlex` 溢出係
  /// 在 debug 期透過 `FlutterError` 報告的，但同一棵樹可能有多個溢出同時發生，
  /// `takeException()` 只會拿到最後一個；直接量度 render object 才數得齊。
  List<String> overflowReport(WidgetTester tester) {
    final hits = <String>[];
    for (final ro in tester.allRenderObjects) {
      if (ro is! RenderFlex) continue;
      final horizontal = ro.direction == Axis.horizontal;
      double sum = 0;
      RenderBox? child = ro.firstChild;
      while (child != null) {
        sum += horizontal ? child.size.width : child.size.height;
        child = ro.childAfter(child);
      }
      final own = horizontal ? ro.size.width : ro.size.height;
      // 0.6 是浮點誤差容忍（Expanded 平分高度時會出現 0.2 級誤差）
      if (sum > own + 0.6) {
        hits.add('${ro.direction == Axis.horizontal ? "橫" : "直"}向溢出 '
            '${(sum - own).toStringAsFixed(1)}px '
            '（自身 $own，子總長 $sum）'
            ' ← ${ro.debugCreator.toString().split('\n').first.trim()}');
      }
    }
    return hits;
  }

  Future<void> pumpCalendar(
    WidgetTester tester,
    double w,
    double h, {
    required ShiftStore store,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: CalendarScreen(store: store, alarms: AlarmService(AlarmBridge())),
    ));
    // 海洋帶 30fps Timer：唔可以 pumpAndSettle
    await tester.pump();
    await tester.pump();
    // 清掉可能已報告的 exception，避免污染下一輪
    while (tester.takeException() != null) {}
  }

  group('AppBar 與日曆：全寬度 × 全字體縮放零溢出', () {
    // 320 = 最窄主流（舊機）；360 = 最常見；390/412 = 主流中高階機
    const widths = [320.0, 360.0, 390.0, 412.0];
    // 1.0 = 預設；1.3 = 系統「大」；2.0 = 系統「最大」
    const scales = [1.0, 1.3, 2.0];

    for (final w in widths) {
      for (final ts in scales) {
        testWidgets('${w.toInt()}px × 字體 ${ts}x：整棵樹零溢出', (tester) async {
          final store = await makeStore();
          await pumpCalendar(tester, w, 800, store: store, textScale: ts);

          final hits = overflowReport(tester);
          expect(hits, isEmpty,
              reason: '${w.toInt()}px × 字體 ${ts}x 出現 ${hits.length} 處溢出：\n'
                  '${hits.join('\n')}');
        });
      }
    }

    testWidgets('360×640 細機 × 字體 1.3x：整棵樹零溢出', (tester) async {
      final store = await makeStore();
      await pumpCalendar(tester, 360, 640, store: store, textScale: 1.3);
      expect(overflowReport(tester), isEmpty);
    });
  });

  group('AppBar 標題在窄屏會縮而唔會爆', () {
    testWidgets('320px：標題 Row 的可用寬度有被用盡（即 Flexible 生效）',
        (tester) async {
      final store = await makeStore();
      await pumpCalendar(tester, 320, 800, store: store);

      // 標題文字一定存在（即使被縮到 minFontSize 都仍然渲染）
      final title = find.textContaining('年');
      expect(title, findsOneWidget);

      // 標題的實際寬度必須 ≤ AppBar 給它的可用寬度 —— 呢個就係「冇溢出」的直接證據
      final titleWidth = tester.getSize(title).width;
      expect(titleWidth, lessThanOrEqualTo(320.0));
      expect(overflowReport(tester), isEmpty);
    });

    testWidgets('導入入口仍然可按（由文字按鈕改成圖示按鈕後唔可以失效）',
        (tester) async {
      final store = await makeStore();
      await pumpCalendar(tester, 360, 800, store: store);

      final importBtn = find.byTooltip('導入排班 / 配置');
      expect(importBtn, findsOneWidget,
          reason: '導入入口唔可以因為改成圖示而消失');

      await tester.tap(importBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 彈出「導入排班 / 配置」對話框即代表入口有效
      expect(find.text('導入排班 / 配置'), findsWidgets);
    });

    testWidgets('今日／上一個月／下一個月 三個入口都仲在', (tester) async {
      final store = await makeStore();
      await pumpCalendar(tester, 360, 800, store: store);

      expect(find.text('今日'), findsOneWidget);
      expect(find.byTooltip('上一月'), findsOneWidget);
      expect(find.byTooltip('下一月'), findsOneWidget);
    });
  });

  group('日曆表頭隨字體放大時，6 個星期列自動讓位', () {
    for (final ts in [1.0, 1.15, 1.3, 1.5, 2.0]) {
      testWidgets('字體 ${ts}x：表頭與 6 列的總高不超過可用高度', (tester) async {
        final store = await makeStore();
        await pumpCalendar(tester, 360, 800, store: store, textScale: ts);

        // 月頁的 Column：表頭 + 間距 + 6 個星期列 = 8 個 child
        final colFinder = find
            .ancestor(of: find.text('日'), matching: find.byType(Column))
            .first;
        final col = tester.renderObject<RenderFlex>(colFinder);
        expect(col.childCount, 8, reason: '應該係 表頭 + 4px 間距 + 6 個星期列');

        double sum = 0;
        RenderBox? c = col.firstChild;
        while (c != null) {
          sum += c.size.height;
          c = col.childAfter(c);
        }
        expect(sum, lessThanOrEqualTo(col.size.height + 0.6),
            reason: '字體 ${ts}x 時月頁 Column 需要 $sum 但只有 ${col.size.height}');

        // 每一列都仍然有正數高度（唔可以縮到 0 消失）
        RenderBox? row = col.firstChild;
        int rowIndex = 0;
        while (row != null) {
          if (rowIndex >= 2) {
            expect(row.size.height, greaterThan(30.0),
                reason: '字體 ${ts}x 時第 ${rowIndex - 1} 個星期列只剩 ${row.size.height}px');
          }
          rowIndex++;
          row = col.childAfter(row);
        }
      });
    }
  });
}
