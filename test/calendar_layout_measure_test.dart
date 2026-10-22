// 底部第三區（排班詳情／排班編輯）的**永久防線**。
//
// v3.6.1 起由「純測量（只 print）」升級為**真斷言**：呢個檔案就係
// 「40–70px 底部空白」同「面板溢出」兩個 bug 的回歸測試。
//
// 所有數字以 `[M]` 前綴 print，方便 grep 對照「修復前／後」。
// 呢個檔案本身就係「量測報告產生器」，print 係交付物，所以整檔豁免 avoid_print
// （否則 `flutter analyze` 會多出幾十條純噪音，蓋過真正的問題）。
//
// 跑法：
//   flutter test test/calendar_layout_measure_test.dart -r expanded
//
// 注意：flutter_test 預設 Ahem 字體，行高 = fontSize（真機 Roboto ≈ 1.17×），
// 所以量到的「內容自然高度」會偏小、空白偏大，報告內要分開講。
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftalarm/alarm/alarm_bridge.dart';
import 'package:shiftalarm/domain/alarm_service.dart';
import 'package:shiftalarm/domain/calendar_layout.dart';
import 'package:shiftalarm/domain/shift_store.dart';
import 'package:shiftalarm/theme/app_theme.dart';
import 'package:shiftalarm/ui/screens/calendar_screen.dart';
import 'package:shiftalarm/ui/screens/home_screen.dart';
import 'package:shiftalarm/ui/screens/shift_picker_panel.dart';
import 'package:shiftalarm/ui/widgets/ocean_band.dart';

/// 詳情卡片的固定裝飾開銷（與 `_detailPanel` 寫死的一致）
const double kMarginV = 4.0 + 6.0; // margin: fromLTRB(12, 4, 12, 6)
const double kPaddingV = 8.0 + 10.0; // padding: fromLTRB(12, 8, 12, 10)
const double kBorderV = 1.2 * 2; // Border.all(width: 1.2)

/// 詳情卡內容自然高（普通態 / 備註編輯態），Ahem 字體下實測
const double kContentNormal = 103.0; // 21 + 6 + 40 + 6 + 30
const double kContentEditing = 109.0; // 備註 30 → TextField 36

/// 排班面板 Column 的內容需要高度（第一行 42 + 第二行 58）
const double kPickerColumnNeed = 100.0;

String f(double v) => v.toStringAsFixed(2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ShiftStore> makeStore() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = ShiftStore(prefs);
    await store.load();
    return store;
  }

  /// 把 pump 期間的例外抽乾，並回傳「三區本體（LayoutBuilder 底下那條 Column）的溢出」
  ///
  /// 360 寬的 AppBar 有既有水平溢出（本次唔修），所以只抽 creator chain 包
  /// `LayoutBuilder` 嘅 RenderFlex 溢出。
  List<String> drain(WidgetTester tester, String scene) {
    final hits = <String>[];
    var n = 0;
    for (;;) {
      final e = tester.takeException();
      if (e == null) break;
      n++;
      final msg = e.toString();
      if (msg.contains('overflowed') && msg.contains('LayoutBuilder')) {
        hits.add(msg.split('\n').first);
      }
      if (n == 1) {
        print('[M] $scene.exception1=${msg.split('\n').first}');
      }
    }
    print('[M] $scene.exceptions=$n threeZoneOverflow=${hits.length}');
    return hits;
  }

  // ───────────────────── 讀出「屏幕真正傳俾算式」的輸入 ─────────────────────

  /// 屏幕傳落算式的底部 inset（= `MediaQuery.padding.bottom`）
  double bottomInsetOf(WidgetTester tester) =>
      MediaQuery.of(tester.element(find.byType(CalendarScreen)))
          .padding
          .bottom;

  /// 鍵盤有冇彈起。`Scaffold` 會食掉 body 的 `viewInsets.bottom`，所以睇 `View`。
  bool keyboardOpenOf(WidgetTester tester) {
    final el = tester.element(find.byType(CalendarScreen));
    return View.of(el).viewInsets.bottom > 0 ||
        MediaQuery.of(el).viewInsets.bottom > 0;
  }

  /// 用同 `CalendarScreen` 完全一樣的輸入計一次佈局（用嚟做期望值）
  CalendarLayout layoutFor(WidgetTester tester, double maxH) =>
      CalendarLayout.compute(
        maxH,
        bottomInset: bottomInsetOf(tester),
        keyboardOpen: keyboardOpenOf(tester),
      );

  // ───────────────────────────── 量測工具 ─────────────────────────────

  Future<void> pumpScreen(
    WidgetTester tester, {
    required double w,
    required double h,
    required ShiftStore store,
    double insetsBottom = 0,
    double paddingBottom = 0,
  }) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = FakeViewPadding(bottom: insetsBottom);
    tester.view.padding = FakeViewPadding(bottom: paddingBottom);
    tester.view.viewPadding = FakeViewPadding(bottom: paddingBottom);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: CalendarScreen(store: store, alarms: AlarmService(AlarmBridge())),
    ));
    await tester.pump();
    drain(tester, 'pump');
  }

  Future<void> setKeyboard(WidgetTester tester, double bottom) async {
    tester.view.viewInsets = FakeViewPadding(bottom: bottom);
    await tester.pump();
    await tester.pump();
    drain(tester, 'kb');
  }

  /// 三區本體（LayoutBuilder 底下那條 Column）真正拿到的高度
  double bodyHeightOf(WidgetTester tester) =>
      tester.renderObject<RenderFlex>(find
          .ancestor(of: find.byType(OceanBand), matching: find.byType(Column))
          .first)
          .constraints
          .maxHeight;

  /// 三區本體（LayoutBuilder 底下那條 Column）的 children
  List<RenderBox> zoneChildren(WidgetTester tester) {
    final colFinder = find
        .ancestor(of: find.byType(OceanBand), matching: find.byType(Column))
        .first;
    return tester.renderObject<RenderFlex>(colFinder).getChildrenAsList();
  }

  /// 量三區本體：bodyHeight、四區實算高度、算式結果
  CalendarLayout reportZones(WidgetTester tester, String scene) {
    final colFinder = find
        .ancestor(of: find.byType(OceanBand), matching: find.byType(Column))
        .first;
    final flex = tester.renderObject<RenderFlex>(colFinder);
    final kids = flex.getChildrenAsList();
    final heights = kids.map((k) => k.size.height).toList();
    final maxH = flex.constraints.maxHeight;
    final layout = layoutFor(tester, maxH);

    print('[M] $scene.bodyMaxHeight=${f(maxH)}');
    print('[M] $scene.columnHeight=${f(flex.size.height)}');
    print('[M] $scene.zoneChildren=${heights.map(f).join(" | ")}');
    print('[M] $scene.formula band=${f(layout.bandHeight)} '
        'grid=${f(layout.gridHeight)} cell=${f(layout.cellHeight)} '
        'detail=${f(layout.detailHeight)} nav=${f(layout.navHeight)} '
        'total=${f(layout.totalHeight)}');
    print('[M] $scene.appBar=${f(tester.getSize(find.byType(AppBar)).height)}');
    print('[M] $scene.pageView=${f(tester.getSize(find.byType(PageView)).height)}');
    print('[M] $scene.oceanBand=${f(tester.getSize(find.byType(OceanBand)).height)}');
    return layout;
  }

  /// 量詳情卡片（非編輯態 / 編輯態都適用）
  void reportDetailCard(WidgetTester tester, String scene, CalendarLayout layout) {
    final scsvFinder = find.byType(SingleChildScrollView);
    print('[M] $scene.scsvCount=${scsvFinder.evaluate().length}');

    final containerFinder = find
        .ancestor(of: scsvFinder.first, matching: find.byType(Container))
        .first;
    final containerSize = tester.getSize(containerFinder);
    final scsvSize = tester.getSize(scsvFinder.first);
    final colFinder =
        find.descendant(of: scsvFinder.first, matching: find.byType(Column)).first;
    final colSize = tester.getSize(colFinder);
    final colRO = tester.renderObject<RenderBox>(colFinder);
    final intrinsic = colRO.getMaxIntrinsicHeight(colSize.width);

    final contentBox = containerSize.height - kBorderV - kPaddingV;
    final blankFull = layout.detailHeight -
        (colSize.height + kMarginV + kPaddingV + kBorderV);
    final blankInner = contentBox - colSize.height;

    print('[M] $scene.detailSizedBox=${f(layout.detailHeight)}');
    print('[M] $scene.whiteContainer=${f(containerSize.height)} '
        '(w=${f(containerSize.width)})');
    print('[M] $scene.scsvBox=${f(scsvSize.height)}');
    print('[M] $scene.contentNatural=${f(colSize.height)} '
        'intrinsic=${f(intrinsic)}');
    print('[M] $scene.contentBoxComputed=${f(contentBox)}');
    print('[M] $scene.BLANK_full(detail-content-margin-padding-border)=${f(blankFull)}');
    print('[M] $scene.BLANK_inner(contentBox-contentNatural)=${f(blankInner)}');

    // 逐個 child 高度，睇邊一行食幾多
    final kids = tester.renderObject<RenderFlex>(colFinder).getChildrenAsList();
    print('[M] $scene.detailRows=${kids.map((k) => f(k.size.height)).join(" | ")}');
  }

  /// 量排班編輯面板
  void reportPicker(WidgetTester tester, String scene, CalendarLayout layout) {
    final panelFinder = find.byType(ShiftPickerPanel);
    print('[M] $scene.panelCount=${panelFinder.evaluate().length}');
    final panelSize = tester.getSize(panelFinder.first);
    print('[M] $scene.detailSizedBox=${f(layout.detailHeight)}');
    print('[M] $scene.panel=${f(panelSize.height)}');

    final expandFinder = find
        .descendant(of: panelFinder.first, matching: find.byType(SizedBox))
        .first;
    print('[M] $scene.sizedBoxExpand=${f(tester.getSize(expandFinder).height)}');

    final padFinder = find.descendant(
      of: panelFinder.first,
      matching: find.byWidgetPredicate((w) =>
          w is Padding &&
          w.padding == const EdgeInsets.only(top: 8, bottom: 8, left: 10, right: 10)),
    );
    print('[M] $scene.padCount=${padFinder.evaluate().length}');
    final padSize = tester.getSize(padFinder.first);
    print('[M] $scene.paddingBox=${f(padSize.height)}');

    final colFinder =
        find.descendant(of: padFinder.first, matching: find.byType(Column)).first;
    final colSize = tester.getSize(colFinder);
    final colRO = tester.renderObject<RenderBox>(colFinder);
    final intrinsic = colRO.getMaxIntrinsicHeight(colSize.width);
    print('[M] $scene.columnBox=${f(colSize.height)} '
        'intrinsic=${f(intrinsic)} '
        'BLANK=${f(colSize.height - intrinsic)}');

    final kids = tester.renderObject<RenderFlex>(colFinder).getChildrenAsList();
    print('[M] $scene.pickerRows=${kids.map((k) => f(k.size.height)).join(" | ")}');
  }

  // ───────────────── 真實組合：HomeScreen + NavigationBar ─────────────────

  Future<void> pumpHome(
    WidgetTester tester, {
    required double w,
    required double h,
    required ShiftStore store,
    double insetsBottom = 0,
    double padTop = 24,
    double padBottom = 24,
  }) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = FakeViewPadding(bottom: insetsBottom);
    tester.view.padding = FakeViewPadding(top: padTop, bottom: padBottom);
    tester.view.viewPadding = FakeViewPadding(top: padTop, bottom: padBottom);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: HomeScreen(store: store, alarms: AlarmService(AlarmBridge())),
    ));
    await tester.pump();
    drain(tester, 'home');
  }

  /// 內容（白卡／面板）畫出嚟嘅底邊（白卡要減返 margin bottom 6）
  double contentBottomOf(WidgetTester tester) {
    final panel = find.byType(ShiftPickerPanel);
    if (panel.evaluate().isNotEmpty) {
      return tester.getRect(panel.first).bottom;
    }
    final cardFinder = find
        .ancestor(of: find.byType(SingleChildScrollView).first,
            matching: find.byType(Container))
        .first;
    return tester.getRect(cardFinder).bottom - 6.0;
  }

  /// 量「第三區底部 → 導航欄頂 / 鍵盤頂」之間真正露出的空白
  void reportGaps(
    WidgetTester tester,
    String scene, {
    required double screenH,
    required double insetsBottom,
  }) {
    final kids = zoneChildren(tester);
    final zone3 = kids[2]; // SizedBox(height: detailHeight)
    final navSpacer = kids[3]; // SizedBox(height: navHeight)

    final zone3Top = zone3.localToGlobal(Offset.zero).dy;
    final navTop = navSpacer.localToGlobal(Offset.zero).dy;
    final navBottom = navTop + navSpacer.size.height;
    print('[M] $scene.zone3Top=${f(zone3Top)} h=${f(zone3.size.height)}');
    print('[M] $scene.navSpacerTop=${f(navTop)} bottom=${f(navBottom)} '
        'h=${f(navSpacer.size.height)}');

    final barFinder = find.byType(NavigationBar);
    print('[M] $scene.navBarCount=${barFinder.evaluate().length}');
    if (barFinder.evaluate().isNotEmpty) {
      final r = tester.getRect(barFinder.first);
      print('[M] $scene.navBarRect top=${f(r.top)} bottom=${f(r.bottom)} '
          'h=${f(r.height)}');
    }

    // 內容（白卡或面板）嘅實際底邊
    final contentBottom = contentBottomOf(tester);
    print('[M] $scene.cardPaintedBottom=${f(contentBottom)}');

    final keyboardTop = screenH - insetsBottom;
    print('[M] $scene.keyboardTop=${f(keyboardTop)}');

    // 內層 body 見到的 MediaQuery（extendBody 會改 padding.bottom）
    final mq = MediaQuery.of(tester.element(find.byType(CalendarScreen)));
    print('[M] $scene.mediaQuery padding.bottom=${f(mq.padding.bottom)} '
        'viewInsets.bottom=${f(mq.viewInsets.bottom)} '
        'viewPadding.bottom=${f(mq.viewPadding.bottom)}');
    print('[M] $scene.view(viewInsets.bottom)='
        '${f(View.of(tester.element(find.byType(CalendarScreen))).viewInsets.bottom)}');
    if (barFinder.evaluate().isNotEmpty) {
      final r = tester.getRect(barFinder.first);
      print('[M] $scene.GAP_contentBottom_to_navBarTop=${f(r.top - contentBottom)} '
          '(負數=內容被導航欄蓋住)');
    }
    print('[M] $scene.GAP_contentBottom_to_keyboardTop=${f(keyboardTop - contentBottom)}');
    print('[M] $scene.GAP_contentBottom_to_screenBottom=${f(screenH - contentBottom)}');
  }

  // ═══════════════════════ 測量場景 M1–M16（證據輸出） ═══════════════════════

  testWidgets('M1 360x800 詳情態', (tester) async {
    final store = await makeStore();
    await pumpScreen(tester, w: 360, h: 800, store: store);
    final layout = reportZones(tester, 'M1');
    reportDetailCard(tester, 'M1', layout);
  });

  testWidgets('M2 360x800 編輯態(排班)', (tester) async {
    final store = await makeStore();
    await pumpScreen(tester, w: 360, h: 800, store: store);
    await tester.tap(find.text('排班'));
    await tester.pump();
    await tester.pump();
    drain(tester, 'M2');
    final layout = reportZones(tester, 'M2');
    reportPicker(tester, 'M2', layout);
  });

  testWidgets('M3 360x800 詳情態+鍵盤300', (tester) async {
    final store = await makeStore();
    await pumpScreen(tester, w: 360, h: 800, store: store);
    await setKeyboard(tester, 300);
    final layout = reportZones(tester, 'M3');
    reportDetailCard(tester, 'M3', layout);
  });

  testWidgets('M4 360x800 編輯態+鍵盤300', (tester) async {
    final store = await makeStore();
    await pumpScreen(tester, w: 360, h: 800, store: store);
    await tester.tap(find.text('排班'));
    await tester.pump();
    await tester.pump();
    drain(tester, 'M4');
    await setKeyboard(tester, 300);
    final layout = reportZones(tester, 'M4');
    reportPicker(tester, 'M4', layout);
  });

  testWidgets('M5 360x800 新增備註(編輯中)', (tester) async {
    final store = await makeStore();
    await pumpScreen(tester, w: 360, h: 800, store: store);
    await tester.tap(find.text('點擊新增備註…'));
    await tester.pump();
    await tester.pump();
    drain(tester, 'M5');
    final layout = reportZones(tester, 'M5');
    reportDetailCard(tester, 'M5', layout);
  });

  testWidgets('M6 360x800 新增備註+鍵盤300', (tester) async {
    final store = await makeStore();
    await pumpScreen(tester, w: 360, h: 800, store: store);
    await tester.tap(find.text('點擊新增備註…'));
    await tester.pump();
    await tester.pump();
    drain(tester, 'M6');
    await setKeyboard(tester, 300);
    final layout = reportZones(tester, 'M6');
    reportDetailCard(tester, 'M6', layout);
  });

  testWidgets('M7 360x800 編輯態+三鍵導航 padding24', (tester) async {
    final store = await makeStore();
    await pumpScreen(tester, w: 360, h: 800, store: store, paddingBottom: 24);
    await tester.tap(find.text('排班'));
    await tester.pump();
    await tester.pump();
    drain(tester, 'M7');
    final layout = reportZones(tester, 'M7');
    reportPicker(tester, 'M7', layout);
  });

  testWidgets('M8 360x640 詳情態', (tester) async {
    final store = await makeStore();
    await pumpScreen(tester, w: 360, h: 640, store: store);
    final layout = reportZones(tester, 'M8');
    reportDetailCard(tester, 'M8', layout);
  });

  testWidgets('M9 360x640 編輯態', (tester) async {
    final store = await makeStore();
    await pumpScreen(tester, w: 360, h: 640, store: store);
    await tester.tap(find.text('排班'));
    await tester.pump();
    await tester.pump();
    drain(tester, 'M9');
    final layout = reportZones(tester, 'M9');
    reportPicker(tester, 'M9', layout);
  });

  testWidgets('M10 360x640 詳情態+鍵盤300', (tester) async {
    final store = await makeStore();
    await pumpScreen(tester, w: 360, h: 640, store: store);
    await setKeyboard(tester, 300);
    final layout = reportZones(tester, 'M10');
    reportDetailCard(tester, 'M10', layout);
  });

  testWidgets('M11 360x640 編輯態+鍵盤300', (tester) async {
    final store = await makeStore();
    await pumpScreen(tester, w: 360, h: 640, store: store);
    await tester.tap(find.text('排班'));
    await tester.pump();
    await tester.pump();
    drain(tester, 'M11');
    await setKeyboard(tester, 300);
    final layout = reportZones(tester, 'M11');
    reportPicker(tester, 'M11', layout);
  });

  testWidgets('M12 真實組合 360x800 詳情態(狀態列24/導航24)', (tester) async {
    final store = await makeStore();
    await pumpHome(tester, w: 360, h: 800, store: store);
    final layout = reportZones(tester, 'M12');
    reportDetailCard(tester, 'M12', layout);
    reportGaps(tester, 'M12', screenH: 800, insetsBottom: 0);
  });

  testWidgets('M13 真實組合 360x800 詳情態+鍵盤300', (tester) async {
    final store = await makeStore();
    await pumpHome(tester, w: 360, h: 800, store: store, padBottom: 0);
    await tester.tap(find.text('點擊新增備註…'));
    await tester.pump();
    await tester.pump();
    drain(tester, 'M13');
    await setKeyboard(tester, 300);
    final layout = reportZones(tester, 'M13');
    reportDetailCard(tester, 'M13', layout);
    reportGaps(tester, 'M13', screenH: 800, insetsBottom: 300);
  });

  testWidgets('M14 真實組合 360x800 編輯態(導航24)', (tester) async {
    final store = await makeStore();
    await pumpHome(tester, w: 360, h: 800, store: store);
    await tester.tap(find.text('排班'));
    await tester.pump();
    await tester.pump();
    drain(tester, 'M14');
    final layout = reportZones(tester, 'M14');
    reportPicker(tester, 'M14', layout);
    reportGaps(tester, 'M14', screenH: 800, insetsBottom: 0);
  });

  testWidgets('M15 真實組合 360x800 編輯態+鍵盤300', (tester) async {
    final store = await makeStore();
    await pumpHome(tester, w: 360, h: 800, store: store, padBottom: 0);
    await tester.tap(find.text('排班'));
    await tester.pump();
    await tester.pump();
    drain(tester, 'M15');
    await setKeyboard(tester, 300);
    final layout = reportZones(tester, 'M15');
    reportPicker(tester, 'M15', layout);
    reportGaps(tester, 'M15', screenH: 800, insetsBottom: 300);
  });

  testWidgets('M16 真實組合 360x800 編輯態(三鍵導航48)', (tester) async {
    final store = await makeStore();
    await pumpHome(tester, w: 360, h: 800, store: store, padBottom: 48);
    await tester.tap(find.text('排班'));
    await tester.pump();
    await tester.pump();
    drain(tester, 'M16');
    final layout = reportZones(tester, 'M16');
    reportPicker(tester, 'M16', layout);
    reportGaps(tester, 'M16', screenH: 800, insetsBottom: 0);
  });

  // ═══════════════ v3.6.1 永久防線：真斷言（a–e 一條都不能少） ═══════════════

  group('永久防線 a：任何真實底部 inset 下，三區 + nav 總和 = bodyHeight', () {
    test('純算式：inset 88.8 / 112.8 逐 px 掃', () {
      for (final inset in <double>[88.8, 112.8]) {
        for (double h = 0; h <= 1400; h += 1) {
          final l = CalendarLayout.compute(h, bottomInset: inset);
          expect(l.totalHeight, closeTo(h, 1e-9),
              reason: 'inset=$inset body=$h');
          expect(l.navHeight, lessThanOrEqualTo(inset + 1e-9));
        }
      }
    });

    testWidgets('真 widget：手勢機 / 三鍵機 三區實佔總和 = body', (tester) async {
      for (final padBottom in <double>[24, 48]) {
        final store = await makeStore();
        await pumpHome(tester, w: 360, h: 800, store: store,
            padBottom: padBottom);
        final kids = zoneChildren(tester);
        final sum = kids.fold<double>(0, (a, k) => a + k.size.height);
        final body = tester
            .renderObject<RenderFlex>(find
                .ancestor(of: find.byType(OceanBand), matching: find.byType(Column))
                .first)
            .constraints
            .maxHeight;
        print('[M] A1 padBottom=$padBottom body=${f(body)} sum=${f(sum)}');
        expect(sum, closeTo(body, 1e-6),
            reason: 'padBottom=$padBottom 三區總和 ${f(sum)} ≠ body ${f(body)}');
      }
    });
  });

  group('永久防線 b：鍵盤彈起時 navHeight = 0', () {
    test('純算式：bottomInset = 0 → navHeight = 0', () {
      for (final h in <double>[300, 420, 500, 720]) {
        expect(CalendarLayout.compute(h, bottomInset: 0).navHeight, 0.0,
            reason: 'body=$h');
      }
    });

    testWidgets('真 widget：鍵盤彈起 → 第四區（nav 留白）高度 = 0', (tester) async {
      final store = await makeStore();
      await pumpHome(tester, w: 360, h: 800, store: store, padBottom: 0);
      await setKeyboard(tester, 300);
      final kids = zoneChildren(tester);
      print('[M] B.navSpacer=${f(kids[3].size.height)} '
          'body=${f(800 - 56 - 24 - 300)}');
      expect(kids[3].size.height, closeTo(0.0, 1e-6),
          reason: '鍵盤彈起時唔應該再留 72px 死白');
    });
  });

  group('永久防線 c：keyboardOpen → bandHeight = 0，讓出的高度全歸日曆', () {
    test('純算式：band = 0 且 grid 多出原 bandHeight', () {
      for (final h in <double>[420, 500, 720, 900]) {
        final closed = CalendarLayout.compute(h, bottomInset: 0);
        final open = CalendarLayout.compute(h, bottomInset: 0, keyboardOpen: true);
        expect(open.bandHeight, 0.0, reason: 'body=$h');
        expect(open.gridHeight,
            closeTo(closed.gridHeight + closed.bandHeight, 1e-9),
            reason: 'body=$h 天色欄讓出的高度要一毫不少過俾日曆');
        expect(open.totalHeight, closeTo(h, 1e-9), reason: 'body=$h');
      }
    });

    testWidgets('真 widget：天色欄高度真係變 0，日曆區食晒剩餘空間', (tester) async {
      final store = await makeStore();
      await pumpHome(tester, w: 360, h: 800, store: store, padBottom: 0);
      final bandBefore = tester.getSize(find.byType(OceanBand)).height;
      final gridBefore = tester.getSize(find.byType(PageView)).height;

      await setKeyboard(tester, 300);

      final bandAfter = tester.getSize(find.byType(OceanBand)).height;
      final gridAfter = tester.getSize(find.byType(PageView)).height;
      final bodyAfter = bodyHeightOf(tester);
      print('[M] C.bandBefore=${f(bandBefore)} bandAfter=${f(bandAfter)} '
          'gridBefore=${f(gridBefore)} gridAfter=${f(gridAfter)} '
          'bodyAfter=${f(bodyAfter)}');
      expect(bandAfter, closeTo(0.0, 1e-6), reason: '輸入文字時天色欄要完全壓縮為 0');
      // 鍵盤彈起時 body 由 720 縮到 420，所以日曆區變矮係正常；
      // 要驗的是「band = 0 之後，除底部區 140 之外全部歸日曆」。
      expect(gridAfter, closeTo(bodyAfter - 140.0, 1e-6),
          reason: 'band=0、nav=0 時日曆區應該食晒 body − detail');
      // 同體積對照：同一 body 下「天色欄讓出的高度」一毫不少咁過俾日曆
      final closedSameBody =
          CalendarLayout.compute(bodyAfter, bottomInset: 0);
      expect(closedSameBody.bandHeight, greaterThan(0.0));
      expect(gridAfter,
          closeTo(closedSameBody.gridHeight + closedSameBody.bandHeight, 1e-6),
          reason: '天色欄讓出的 ${f(closedSameBody.bandHeight)}px 要全歸日曆');
    });
  });

  group('永久防線 d：詳情卡內部餘量 ≤ 7px（普通態）／≤ 1px（備註編輯態）', () {
    double blankOf(WidgetTester tester, CalendarLayout layout) {
      final colFinder = find.descendant(
          of: find.byType(SingleChildScrollView).first,
          matching: find.byType(Column)).first;
      final content = tester.getSize(colFinder).height;
      return layout.detailHeight - (content + kMarginV + kPaddingV + kBorderV);
    }

    testWidgets('普通態：餘量 ≤ 7px（用戶要求「余量應該用盡」）', (tester) async {
      final store = await makeStore();
      await pumpHome(tester, w: 360, h: 800, store: store);
      final layout = reportZones(tester, 'D1');
      reportDetailCard(tester, 'D1', layout);
      final blank = blankOf(tester, layout);
      print('[M] D1.blank=${f(blank)}');
      expect(blank, greaterThanOrEqualTo(0.0), reason: '唔可以唔夠位（會裁到內容）');
      expect(blank, lessThanOrEqualTo(7.0), reason: '底部唔可以再有多過 7px 空白');
    });

    testWidgets('備註編輯態：餘量 ≤ 1px（TextField 36 取代 30）', (tester) async {
      final store = await makeStore();
      await pumpHome(tester, w: 360, h: 800, store: store);
      await tester.tap(find.text('點擊新增備註…'));
      await tester.pump();
      await tester.pump();
      drain(tester, 'D2');
      final layout = reportZones(tester, 'D2');
      reportDetailCard(tester, 'D2', layout);
      final blank = blankOf(tester, layout);
      print('[M] D2.blank=${f(blank)}');
      expect(blank, greaterThanOrEqualTo(0.0));
      expect(blank, lessThanOrEqualTo(1.0));
    });
  });

  group('永久防線 e：排班面板 Column 唔再溢出（實得 ≥ 需要 100）', () {
    Future<void> assertPickerFits(
      WidgetTester tester,
      String scene,
      double padBottom,
    ) async {
      final store = await makeStore();
      await pumpHome(tester, w: 360, h: 800, store: store, padBottom: padBottom);
      await tester.tap(find.text('排班'));
      await tester.pump();
      await tester.pump();
      final overflows = drain(tester, scene);

      final padFinder = find.descendant(
        of: find.byType(ShiftPickerPanel),
        matching: find.byWidgetPredicate((w) =>
            w is Padding &&
            w.padding ==
                const EdgeInsets.only(top: 8, bottom: 8, left: 10, right: 10)),
      );
      final colFinder =
          find.descendant(of: padFinder.first, matching: find.byType(Column)).first;
      final colHeight = tester.getSize(colFinder).height;
      final inset = bottomInsetOf(tester);
      print('[M] $scene.inset=${f(inset)} columnBox=${f(colHeight)} '
          'need=${f(kPickerColumnNeed)}');

      expect(overflows, isEmpty, reason: '$scene 面板溢出：$overflows');
      expect(colHeight, greaterThanOrEqualTo(kPickerColumnNeed),
          reason: '$scene Column 只得 ${f(colHeight)}，內容要 ${f(kPickerColumnNeed)}');
    }

    testWidgets('手勢導航（inset 88.8）：Column 唔再只得 36.2', (tester) async {
      await assertPickerFits(tester, 'E1', 24);
    });

    testWidgets('三鍵導航（inset 112.8）：Column 唔再只得 12.2', (tester) async {
      await assertPickerFits(tester, 'E2', 48);
    });

    testWidgets('鍵盤彈起：面板一樣裝得落', (tester) async {
      final store = await makeStore();
      await pumpHome(tester, w: 360, h: 800, store: store, padBottom: 0);
      await tester.tap(find.text('排班'));
      await tester.pump();
      await tester.pump();
      await setKeyboard(tester, 300);
      final overflows = drain(tester, 'E3');

      final padFinder = find.descendant(
        of: find.byType(ShiftPickerPanel),
        matching: find.byWidgetPredicate((w) =>
            w is Padding &&
            w.padding ==
                const EdgeInsets.only(top: 8, bottom: 8, left: 10, right: 10)),
      );
      final colHeight = tester
          .getSize(find.descendant(of: padFinder.first, matching: find.byType(Column)).first)
          .height;
      print('[M] E3.columnBox=${f(colHeight)}');
      expect(overflows, isEmpty, reason: '鍵盤態面板溢出：$overflows');
      expect(colHeight, greaterThanOrEqualTo(kPickerColumnNeed));
    });
  });

  group('永久防線：底部唔再有 40–70px 死白', () {
    testWidgets('手勢機詳情態：白卡底 → 導航欄頂 只剩卡片自己的 6px margin', (tester) async {
      final store = await makeStore();
      await pumpHome(tester, w: 360, h: 800, store: store);
      reportZones(tester, 'F1');
      reportGaps(tester, 'F1', screenH: 800, insetsBottom: 0);
      final gap =
          tester.getRect(find.byType(NavigationBar).first).top - contentBottomOf(tester);
      print('[M] F1.gap=${f(gap)}');
      // 6.8 = 白卡自己的 margin bottom 6 + 導航欄頂 0.8 邊框；
      // 修復前係 -10（被蓋住）／78（鍵盤彈起時空 78）。
      expect(gap, lessThanOrEqualTo(7.0),
          reason: '白卡底到導航欄頂唔應該再有 40–70px 空白（實測 ${f(gap)}）');
      expect(gap, greaterThanOrEqualTo(-0.5), reason: '唔可以被導航欄蓋住');
    });

    testWidgets('三鍵機詳情態：同上', (tester) async {
      final store = await makeStore();
      await pumpHome(tester, w: 360, h: 800, store: store, padBottom: 48);
      reportZones(tester, 'F2');
      reportGaps(tester, 'F2', screenH: 800, insetsBottom: 0);
      final gap =
          tester.getRect(find.byType(NavigationBar).first).top - contentBottomOf(tester);
      print('[M] F2.gap=${f(gap)}');
      expect(gap, lessThanOrEqualTo(7.0));
      expect(gap, greaterThanOrEqualTo(-0.5));
    });

    testWidgets('鍵盤彈起詳情態：白卡底 → 鍵盤頂 = 0（原本空 78px）', (tester) async {
      final store = await makeStore();
      await pumpHome(tester, w: 360, h: 800, store: store, padBottom: 0);
      await tester.tap(find.text('點擊新增備註…'));
      await tester.pump();
      await tester.pump();
      drain(tester, 'F3');
      await setKeyboard(tester, 300);
      reportZones(tester, 'F3');
      reportGaps(tester, 'F3', screenH: 800, insetsBottom: 300);
      final gap = 800 - 300 - contentBottomOf(tester);
      print('[M] F3.gap=${f(gap)}');
      expect(gap, lessThanOrEqualTo(7.0),
          reason: '鍵盤頂到白卡底唔應該再空 78px（實測 ${f(gap)}）');
      expect(gap, greaterThanOrEqualTo(-0.5));
    });
  });
}
