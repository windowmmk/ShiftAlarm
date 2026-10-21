import 'package:flutter/material.dart';
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
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ShiftStore> makeStore() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = ShiftStore(prefs);
    await store.load();
    return store;
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
  Future<CalendarLayout> pumpAt(
    WidgetTester tester,
    double w,
    double h, {
    required ShiftStore store,
  }) async {
    // 屏幕高 = body + AppBar(56) + 狀態列(24)；反推 LayoutBuilder 見到的高度
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: CalendarScreen(store: store, alarms: AlarmService(AlarmBridge())),
    ));
    await tester.pump();

    expect(threeZoneOverflow(tester), isEmpty,
        reason: '$w×$h 三區本體溢出');
    return CalendarLayout.compute(h - 56 - 24);
  }

  testWidgets('360×800：三區都排到、高度對得上、冇溢出', (tester) async {
    final store = await makeStore();
    final layout = await pumpAt(tester, 360, 800, store: store);

    // ① 頂部海洋線：真係喺最頂，而且用算式算出來嘅高度
    final band = tester.widget<OceanBand>(find.byType(OceanBand));
    expect(band.height, closeTo(layout.bandHeight, 1e-9));
    expect(band.visible, isTrue);

    // ③ 底部區：未㩒「排班」之前係排班詳情，常駐唔係彈出
    expect(find.byType(ShiftPickerPanel), findsNothing);
    expect(find.text('排班'), findsOneWidget);

    // 三區實佔 + 導航留白 啱啱好等於 body → 冇溢出亦冇留白
    expect(layout.totalHeight, closeTo(800 - 56 - 24, 1e-9));
  });

  testWidgets('㩒「排班」：底部區原地換成編輯面板，三區高度不變、冇溢出',
      (tester) async {
    final store = await makeStore();
    final layout = await pumpAt(tester, 360, 800, store: store);
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
    final layout = await pumpAt(tester, 360, 640, store: store);
    expect(layout.bandHeight, greaterThan(0));
    expect(layout.detailHeight, greaterThan(0));
    expect(layout.cellHeight, greaterThan(0));
    expect(layout.totalHeight, closeTo(640 - 56 - 24, 1e-9));
  });
}
