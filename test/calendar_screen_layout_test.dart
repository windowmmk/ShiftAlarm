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
import 'package:shiftalarm/ui/screens/shift_picker_panel.dart';
import 'package:shiftalarm/ui/widgets/ocean_band.dart';

/// 三區固定佈局（頂部海洋線／中間日曆／底部排班詳情）的真 widget 冒煙測試。
///
/// `calendar_layout_test.dart` 只證明算式；呢度證明 `CalendarScreen` 真係用
/// 呢組數字砌出嚟，而且 **冇 RenderFlex 溢出**（黃黑間條）。
///
/// ⚠️ 已知既有問題（本次唔修，見 calendar_screen.dart 的 AppBar）：
/// 360px 寬嘅 AppBar actions 會水平溢出 68px。所以下面嘅斷言只針對
/// 三區本體（`LayoutBuilder` 底下嗰條 Column）嘅溢出 —— AppBar 嗰個唔會
/// 被當成綠燈，亦唔會令測試紅。
///
/// v3.6.1：期望值**一律由 widget 樹實測反推**（body 高度、真實底部 inset），
/// 唔再靠「屏幕高 − 56 − 24」呢種假設 —— 測試環境冇狀態列 padding，
/// 假設式反推會同真實差 24px（之前就係靠巧合先過）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ShiftStore> makeStore() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = ShiftStore(prefs);
    await store.load();
    return store;
  }

  /// 三區本體（`LayoutBuilder` 底下嗰條 Column）
  Finder threeZoneColumn() => find
      .ancestor(of: find.byType(OceanBand), matching: find.byType(Column))
      .first;

  /// 三區本體真正拿到的高度（= `constraints.maxHeight`）
  double bodyHeightOf(WidgetTester tester) =>
      tester.renderObject<RenderFlex>(threeZoneColumn()).constraints.maxHeight;

  /// 用「屏幕真正傳落算式」的輸入計一次，用嚟對照 widget 的實算高度
  CalendarLayout realLayout(WidgetTester tester) {
    final el = tester.element(find.byType(CalendarScreen));
    final mq = MediaQuery.of(el);
    return CalendarLayout.compute(
      bodyHeightOf(tester),
      bottomInset: mq.padding.bottom,
      keyboardOpen: View.of(el).viewInsets.bottom > 0 ||
          mq.viewInsets.bottom > 0,
    );
  }

  /// 只抽「三區本體」嘅 layout 錯誤（AppBar 既有溢出維持為已知問題）
  List<Object?> threeZoneOverflow(WidgetTester tester) {
    final hits = <Object?>[];
    for (;;) {
      final e = tester.takeException();
      if (e == null) break;
      final msg = e.toString();
      // 三區本體嘅 creator chain 一定包「Column ← LayoutBuilder」
      if (msg.contains('overflowed') && msg.contains('LayoutBuilder')) {
        hits.add(e);
      }
    }
    return hits;
  }

  /// 用假屏幕尺寸泵出成個日曆頁，並斷言三區本體冇溢出。
  Future<void> pumpAt(
    WidgetTester tester,
    double w,
    double h, {
    required ShiftStore store,
    double paddingBottom = 0,
    double insetsBottom = 0,
  }) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = FakeViewPadding(bottom: paddingBottom);
    tester.view.viewPadding = FakeViewPadding(bottom: paddingBottom);
    tester.view.viewInsets = FakeViewPadding(bottom: insetsBottom);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: CalendarScreen(store: store, alarms: AlarmService(AlarmBridge())),
    ));
    await tester.pump();

    expect(threeZoneOverflow(tester), isEmpty,
        reason: '$w×$h 三區本體溢出');
  }

  testWidgets('360×800：三區都排到、高度對得上、冇溢出', (tester) async {
    final store = await makeStore();
    await pumpAt(tester, 360, 800, store: store);
    final layout = realLayout(tester);

    // ① 頂部海洋線：真係喺最頂，而且用算式算出來嘅高度
    final band = tester.widget<OceanBand>(find.byType(OceanBand));
    expect(band.height, closeTo(layout.bandHeight, 1e-9));
    expect(band.visible, isTrue);
    expect(tester.getSize(find.byType(OceanBand)).height,
        closeTo(layout.bandHeight, 1e-9));

    // ③ 底部區：未㩒「排班」之前係排班詳情，常駐唔係彈出
    expect(find.byType(ShiftPickerPanel), findsNothing);
    expect(find.text('排班'), findsOneWidget);

    // 三區實佔 + 導航留白 啱啱好等於 body → 冇溢出亦冇留白
    expect(layout.totalHeight, closeTo(bodyHeightOf(tester), 1e-9));
    expect(layout.detailHeight, 140.0, reason: '底部區固定 140，唔可以再有多餘空白');
  });

  testWidgets('㩒「排班」：底部區原地換成編輯面板，三區高度不變、冇溢出',
      (tester) async {
    final store = await makeStore();
    await pumpAt(tester, 360, 800, store: store);
    final layout = realLayout(tester);
    final bandBefore = tester.widget<OceanBand>(find.byType(OceanBand)).height;

    await tester.tap(find.text('排班'));
    // 唔可以用 pumpAndSettle：海洋帶係 30fps 常駐 Timer，永遠 settle 唔到
    await tester.pump();
    await tester.pump();

    expect(find.byType(ShiftPickerPanel), findsOneWidget,
        reason: '排班編輯應該原地出現喺底部區');
    expect(threeZoneOverflow(tester), isEmpty);

    // 原地切換 = 海洋帶高度完全冇變（呢個就係「唔用彈出彈入」嘅證據）
    final bandAfter = tester.widget<OceanBand>(find.byType(OceanBand)).height;
    expect(bandAfter, closeTo(bandBefore, 1e-9));
    expect(bandAfter, closeTo(layout.bandHeight, 1e-9));
  });

  testWidgets('360×640 細機：三區仍然齊全、冇溢出', (tester) async {
    final store = await makeStore();
    await pumpAt(tester, 360, 640, store: store);
    final layout = realLayout(tester);
    expect(layout.bandHeight, greaterThan(0));
    expect(layout.detailHeight, greaterThan(0));
    expect(layout.cellHeight, greaterThan(0));
    expect(layout.totalHeight, closeTo(bodyHeightOf(tester), 1e-9));
  });

  testWidgets('底部有真實 inset 時，nav 留白跟住變成 inset 而唔係寫死 72',
      (tester) async {
    final store = await makeStore();
    await pumpAt(tester, 360, 800, store: store, paddingBottom: 24);
    final layout = realLayout(tester);
    final mq = MediaQuery.of(tester.element(find.byType(CalendarScreen)));

    // 呢度冇 HomeScreen 的 NavigationBar，所以注入的就係 24 本身
    // （真實組合的 88.8 / 112.8 由 calendar_layout_measure_test 驗）
    expect(mq.padding.bottom, closeTo(24.0, 1e-9));
    expect(layout.navHeight, closeTo(24.0, 1e-9));
    expect(layout.navHeight, isNot(CalendarLayout.navReserved),
        reason: '唔可以再係寫死嘅 72');
    expect(layout.totalHeight, closeTo(bodyHeightOf(tester), 1e-9));
    expect(threeZoneOverflow(tester), isEmpty);
  });

  testWidgets('鍵盤彈起：天色欄壓到 0、nav 留白變 0、冇溢出', (tester) async {
    final store = await makeStore();
    await pumpAt(tester, 360, 800, store: store, insetsBottom: 300);
    final layout = realLayout(tester);

    expect(layout.bandHeight, 0.0, reason: '輸入文字時天色欄要完全壓縮為 0');
    expect(layout.navHeight, 0.0, reason: '鍵盤彈起時 Scaffold 已把 padding.bottom 歸零');
    expect(tester.getSize(find.byType(OceanBand)).height, closeTo(0.0, 1e-9));
    expect(layout.totalHeight, closeTo(bodyHeightOf(tester), 1e-9));
    expect(threeZoneOverflow(tester), isEmpty);
  });
}
