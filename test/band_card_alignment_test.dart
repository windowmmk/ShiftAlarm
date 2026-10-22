// 天色帶 ↔ 日曆卡「成套」永久防線（v3.6.3 新增）
//
// 背景：兩張卡原本用**相反**嘅嵌套順序算寬度 ——
//   - `OceanBand._buildBand()` 係 `Padding → Center → ConstrainedBox`（先縮再夾）
//     → 實寬 = min(W − 16, 480)
//   - 日曆區係 `Center → ConstrainedBox → Padding`（先夾再縮）
//     → 內容寬 = min(W, 480) − 16
//
// 兩條式喺 W ≤ 480 時都係 W − 16，所以**手機上完全睇唔出**；
// 但 W > 480 就分叉，W ≥ 496 時每邊穩定差 8px（480 vs 464）。
// Web PWA 開喺桌面瀏覽器正好踩中 —— 即係「一體性唔夠」嘅其中一個真因。
//
// 而 `app_theme.dart` 嘅 `kOceanBandMaxWidth` 注釋仲寫住「與月曆一致，寬屏居中」，
// 即係**注釋話一致、代碼實際唔一致**。呢個測試就係用真 widget 量兩條邊，
// 令呢句話冇得再講大話。
//
// ⚠️ 技術注意（踩過嘅坑，唔好改返）：
//   - 任何用 `context.tokens` 嘅頁面必須 `theme: buildAppTheme()`，
//     否則 `_TypeError: Null check operator used on a null value`。
//   - 海洋帶有 30fps 常駐 `Timer.periodic`，`pumpAndSettle()` 會永遠 timeout
//     → 一律用兩次 `tester.pump()`。
//   - 要泵**真實嘅 `CalendarScreen`** 而唔係手砌兩張卡：只有行同一條
//     `CalendarLayout` + `Center/ConstrainedBox/Padding` 鏈，先測得到對齊。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftalarm/alarm/alarm_bridge.dart';
import 'package:shiftalarm/domain/alarm_service.dart';
import 'package:shiftalarm/domain/shift_store.dart';
import 'package:shiftalarm/theme/app_theme.dart';
import 'package:shiftalarm/ui/screens/calendar_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 兩張卡的 Key：加喺 `OceanBand` 嘅容器同日曆區嘅容器上，
  /// 冇 Key 就量唔到（唔可以靠 `find.byType(Container)`，一頁有幾十個）。
  const bandKey = Key('ocean-band-card');
  const gridKey = Key('calendar-grid-card');

  // 320/360/412 = 主流手機（≤480，對齊本來就成立，用嚟守住唔好改壞）；
  // 900 = Web PWA 桌面闊屏（**呢個先係會出事嗰個**）。
  const widths = <double>[320.0, 360.0, 412.0, 900.0];

  Future<ShiftStore> makeStore() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = ShiftStore(prefs);
    await store.load();
    for (final def in ShiftStore.testDefaults().values) {
      await store.addDef(def);
    }
    return store;
  }

  Future<void> pumpAt(WidgetTester tester, double w, ShiftStore store) async {
    tester.view.physicalSize = Size(w, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: CalendarScreen(store: store, alarms: AlarmService(AlarmBridge())),
    ));
    // 海洋帶 30fps Timer：唔可以 pumpAndSettle，只 pump 兩次
    await tester.pump();
    await tester.pump();
    while (tester.takeException() != null) {}
  }

  for (final w in widths) {
    testWidgets('${w.toInt()}px：天色帶與日曆卡左右對齊、同寬', (tester) async {
      final store = await makeStore();
      await pumpAt(tester, w, store);

      expect(find.byKey(bandKey), findsOneWidget,
          reason: '天色帶容器必須帶 Key，否則測唔到對齊');
      expect(find.byKey(gridKey), findsOneWidget,
          reason: '日曆卡容器必須帶 Key，否則測唔到對齊');

      final band = tester.getRect(find.byKey(bandKey));
      final grid = tester.getRect(find.byKey(gridKey));

      expect(band.left, closeTo(grid.left, 0.01),
          reason: '${w.toInt()}px 左邊唔齊（天色帶 ${band.left} vs 日曆卡 ${grid.left}）');
      expect(band.right, closeTo(grid.right, 0.01),
          reason: '${w.toInt()}px 右邊唔齊（天色帶 ${band.right} vs 日曆卡 ${grid.right}）');
      expect(band.width, closeTo(grid.width, 0.01),
          reason: '${w.toInt()}px 闊度唔同（天色帶 ${band.width} vs 日曆卡 ${grid.width}）');
    });
  }

  testWidgets('闊屏 900px：兩張卡都係 464 寬（= min(W,480) − 16），唔係 480',
      (tester) async {
    final store = await makeStore();
    await pumpAt(tester, 900.0, store);

    final band = tester.getRect(find.byKey(bandKey));
    final grid = tester.getRect(find.byKey(gridKey));

    // 舊路線 `Padding → Center → ConstrainedBox` 會令天色帶出 480，
    // 而日曆卡出 464 —— 呢條就係專登用**具體數字**鎖死佢，
    // 淨係「兩者相等」唔夠：兩邊一齊錯（都變 480）都會通過。
    expect(band.width, closeTo(464.0, 0.01),
        reason: '闊屏天色帶必須係 min(W,480) − 16 = 464，實得 ${band.width}');
    expect(grid.width, closeTo(464.0, 0.01),
        reason: '闊屏日曆卡必須係 min(W,480) − 16 = 464，實得 ${grid.width}');
  });

  testWidgets('兩張卡之間嘅垂直間距 = kOceanBandGap（成套嘅呼吸位）',
      (tester) async {
    final store = await makeStore();
    await pumpAt(tester, 360.0, store);

    final band = tester.getRect(find.byKey(bandKey));
    final grid = tester.getRect(find.byKey(gridKey));

    expect(grid.top - band.bottom, closeTo(kOceanBandGap, 0.01),
        reason: '天色帶底到日曆卡頂必須啱啱 $kOceanBandGap，實得 ${grid.top - band.bottom}');
  });

  testWidgets('日曆卡底色要夠深：空白格（84% 白）疊上去仍然睇到格線', (tester) async {
    final store = await makeStore();
    await pumpAt(tester, 360.0, store);

    final card = tester.widget<Container>(find.byKey(gridKey));
    final cardColor = (card.decoration! as BoxDecoration).color!;

    // 空白格 = `Colors.white.withValues(alpha: 0.84)` 疊喺卡片底色上。
    // 疊完之後同卡片嘅通道差 = 0.84 × (255 − 卡片通道值)，呢個就係「格線睇唔睇到」。
    const double cellAlpha = 0.84;
    // `Color.red` 已 deprecated，改用 `(*.r * 255.0).round().clamp(0, 255)`
    // 以免 `flutter analyze` 多報一條 deprecated_member_use。
    final cardRed = (cardColor.r * 255.0).round().clamp(0, 255).toDouble();
    final diff = cellAlpha * (255.0 - cardRed);

    // 12 係實證門檻（見 `kCalendarPageBg` 嘅註釋）：
    //   - #F8FAFC（PRD 原值）得 6.7 → 月曆變白板，格線消失；
    //   - #EDF2F7（現頁面底色）得 15.1 → 清楚；
    //   - #E3EAF1（本輪日曆卡）得 23.5 → 更清楚。
    // 純白 #FFFFFF 會得 **0**，即係成個月曆消失 —— 呢條就係擋住佢。
    expect(diff, greaterThanOrEqualTo(12.0),
        reason: '日曆卡底色太淺（$cardColor），空白格同卡片只差 ${diff.toStringAsFixed(1)}'
            '/255，格線會睇唔見（門檻 12）');
  });

  testWidgets('日曆卡有底色同描邊（睇得出係一張卡，唔係散格）', (tester) async {
    final store = await makeStore();
    await pumpAt(tester, 360.0, store);

    final card = tester.widget<Container>(find.byKey(gridKey));
    final dec = card.decoration;
    expect(dec, isA<BoxDecoration>(), reason: '日曆卡必須有 BoxDecoration');
    final box = dec! as BoxDecoration;
    expect(box.color, isNotNull, reason: '日曆卡必須有底色，否則同頁面糊成一片');
    expect(box.border, isNotNull, reason: '日曆卡必須有描邊，同天色帶成套');
    expect((box.borderRadius as BorderRadius?)?.topLeft.x,
        closeTo(kOceanBandRadius, 0.01),
        reason: '日曆卡圓角必須同天色帶一樣係 $kOceanBandRadius');

    final bandBox =
        (tester.widget<Container>(find.byKey(bandKey)).decoration!
            as BoxDecoration);
    expect(bandBox.border, isNotNull, reason: '天色帶必須有描邊，同日曆卡成套');
    expect((bandBox.borderRadius as BorderRadius?)?.topLeft.x,
        closeTo(kOceanBandRadius, 0.01));
  });
}
