// QA 獨立驗收（v3.6.1）—— 三區佈局算式與真 widget 的實測驗證。
//
// 呢個檔係 QA 自己寫的驗證測試，**唔修改任何既有測試或原始碼**。
// 目標：證明「第三欄空白歸零」「鍵盤彈起時天色欄 = 0」「三區 + 導航 = body」
// 在三種機型 × 三種底部 inset × 鍵盤開關的組合下都成立，並且主動用極端輸入弄壞它。
//
// ⚠️ 唔可以用 `pumpAndSettle()`：`OceanBand` 有 30fps 常駐 Timer，永遠唔會 settle。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftalarm/alarm/alarm_bridge.dart';
import 'package:shiftalarm/domain/alarm_service.dart';
import 'package:shiftalarm/domain/calendar_layout.dart';
import 'package:shiftalarm/domain/shift_store.dart';
import 'package:shiftalarm/theme/app_theme.dart';
import 'package:shiftalarm/ui/screens/home_screen.dart';
import 'package:shiftalarm/ui/screens/shift_picker_panel.dart';
import 'package:shiftalarm/ui/widgets/ocean_band.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════ 第一部分：純算式（CalendarLayout） ═══════════════════

  group('v3.6.1 B6：純算式不變式', () {
    const sizes = <String, double>{
      '360×800 body': 800 - 56,
      '360×640 body': 640 - 56,
      '411×891 body': 891 - 56,
      '極細 body': 50,
      '零 body': 0,
      '極大 body': 2000,
    };
    const insets = <double>[0, 88.8, 112.8];

    for (final entry in sizes.entries) {
      for (final inset in insets) {
        for (final kb in [false, true]) {
          final label = '${entry.key} / inset=$inset / 鍵盤=$kb';
          test(label, () {
            final l = CalendarLayout.compute(
              entry.value,
              bottomInset: inset,
              keyboardOpen: kb,
            );

            // ① 三區 + 導航 = body（不溢出、不留白）
            expect(l.totalHeight, closeTo(entry.value, 1e-9),
                reason: '$label：三區總高必須等於 body 高');

            // ② 每個值都要有限、非負
            for (final v in [
              l.bandHeight,
              l.gridHeight,
              l.cellHeight,
              l.detailHeight,
              l.navHeight
            ]) {
              expect(v.isFinite, isTrue, reason: '$label：出現 NaN / Infinity');
              expect(v, greaterThanOrEqualTo(0), reason: '$label：出現負高度');
            }

            // ③ 鍵盤彈起 → 天色欄完全壓縮為 0
            if (kb) {
              expect(l.bandHeight, 0.0,
                  reason: '$label：鍵盤彈起時天色欄必須為 0（用戶原話「完全壓縮為0」）');
            } else if (entry.value >= 300) {
              // 空間足夠的機型才要求天色欄食滿；極細視窗會按比例讓步（設計如此）
              expect(
                  l.bandHeight,
                  inInclusiveRange(
                      CalendarLayout.oceanMin, CalendarLayout.oceanMax),
                  reason: '$label：非鍵盤態天色欄應落在 [56, 96]');
            }

            // ④ 底部區不超過設計上限
            expect(l.detailHeight, inInclusiveRange(0, CalendarLayout.detailMax));

            // ⑤ 日曆區真的裝得落 6 行（日曆區細過固定開銷時格高只能是 0）
            if (l.gridHeight > CalendarLayout.gridOverhead) {
              expect(6 * l.cellHeight + CalendarLayout.gridOverhead,
                  lessThanOrEqualTo(l.gridHeight + 1e-9),
                  reason: '$label：6 行格高 + 固定開銷不可超過日曆區高');
            }
          });
        }
      }
    }

    test('理想機（411×891 / 手勢 88.8）：天色欄食滿 96、底部區 140、格高有得生長', () {
      final l = CalendarLayout.compute(891 - 56, bottomInset: 88.8);
      expect(l.bandHeight, CalendarLayout.oceanMax);
      expect(l.detailHeight, CalendarLayout.detailMax);
      // 891 高不足以長到 92 上限（要 body ≥ 824 才到），但一定要大過理想 75
      expect(l.cellHeight, greaterThan(CalendarLayout.cellMax));
      expect(l.cellHeight, lessThanOrEqualTo(CalendarLayout.cellGrowMax));
    });

    test('超高屏（body 1000）：格高封頂在 92，多出的位由 Center 分掉', () {
      final l = CalendarLayout.compute(1000, bottomInset: 0);
      expect(l.cellHeight, CalendarLayout.cellGrowMax);
      expect(l.bandHeight, CalendarLayout.oceanMax);
      expect(l.gridHeight, greaterThan(6 * l.cellHeight + CalendarLayout.gridOverhead),
          reason: '剩餘空間留在日曆區內，由 Center 上下平均分掉');
    });

    test('讓位鏈：不夠位時先削天色欄（56 下限），不會先削底部區', () {
      final l = CalendarLayout.compute(700, bottomInset: 0);
      expect(l.detailHeight, CalendarLayout.detailMax,
          reason: '底部區是內容剛需，不可先削');
      expect(l.bandHeight, lessThan(CalendarLayout.oceanMax));
      expect(l.bandHeight, greaterThanOrEqualTo(CalendarLayout.oceanMin));
    });
  });

  group('v3.6.1 B7：極端輸入（主動弄壞）', () {
    test('bodyHeight = 0 / 1 / 50 / 200 都不炸、不出負數', () {
      for (final h in [0.0, 1.0, 50.0, 200.0]) {
        final l = CalendarLayout.compute(h, bottomInset: 0);
        expect(l.totalHeight, closeTo(h, 1e-9), reason: 'body=$h');
        expect(l.bandHeight, greaterThanOrEqualTo(0));
        expect(l.gridHeight, greaterThanOrEqualTo(0));
        expect(l.detailHeight, greaterThanOrEqualTo(0));
      }
    });

    test('inset = 0 / 1000 / 負數：導航留白被夾在 [0, body]', () {
      final zero = CalendarLayout.compute(800, bottomInset: 0);
      expect(zero.navHeight, 0);

      final huge = CalendarLayout.compute(800, bottomInset: 1000);
      expect(huge.navHeight, 800, reason: '留白不可大於 body，否則反過來溢出');
      expect(huge.totalHeight, closeTo(800, 1e-9));
      expect(huge.gridHeight, 0);
      expect(huge.bandHeight, 0, reason: '完全冇位時天色欄與底部區按比例讓步到 0');

      final negative = CalendarLayout.compute(800, bottomInset: -50);
      expect(negative.navHeight, 0, reason: '負 inset 要夾成 0，不可以變成負留白');
      expect(negative.totalHeight, closeTo(800, 1e-9));
    });

    test('bodyHeight 為負：視為 0', () {
      final l = CalendarLayout.compute(-100, bottomInset: 88.8);
      expect(l.totalHeight, 0);
      expect(l.bandHeight, 0);
      expect(l.detailHeight, 0);
      expect(l.navHeight, 0);
    });

    test('常數與 kOceanBandHeight 同步（改名時唔會靜默走位）', () {
      expect(CalendarLayout.oceanMax, kOceanBandHeight);
      expect(CalendarLayout.gridOverhead, 36.0);
      expect(CalendarLayout.cellMax, 75.0);
    });
  });

  // ═══════════════════ 第二部分：真 widget 實測 ═══════════════════

  Future<ShiftStore> makeStore() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = ShiftStore(prefs);
    await store.load();
    return store;
  }

  Finder threeZoneColumn() => find
      .ancestor(of: find.byType(OceanBand), matching: find.byType(Column))
      .first;

  /// 三區 Column 每個 child 的 RenderBox（順序：天色欄 / 日曆 / 底部區 / 導航留白）
  List<RenderBox> zoneBoxes(WidgetTester tester) {
    final flex = tester.renderObject<RenderFlex>(threeZoneColumn());
    final out = <RenderBox>[];
    RenderBox? child = flex.firstChild;
    while (child != null) {
      out.add(child);
      child = flex.childAfter(child);
    }
    return out;
  }

  Rect globalRect(RenderBox box) =>
      box.localToGlobal(Offset.zero) & box.size;

  double bodyHeightOf(WidgetTester tester) =>
      tester.renderObject<RenderFlex>(threeZoneColumn()).constraints.maxHeight;

  /// 底部區「內容」真正畫到幾低。
  ///
  /// 詳情態：白卡**畫出嚟的底邊**（Container 含 margin bottom 6，所以要減 6）。
  /// 編輯態：面板本身鋪滿底部區。
  ///
  /// 只搵底部區裡面嘅元件，避免捉錯別處的捲動區。
  double contentBottomOf(WidgetTester tester) {
    final panel = find.byType(ShiftPickerPanel);
    if (panel.evaluate().isNotEmpty) {
      return tester.getRect(panel.first).bottom;
    }
    final scrollView = find
        .descendant(
            of: threeZoneColumn(), matching: find.byType(SingleChildScrollView))
        .first;
    final card = find.ancestor(of: scrollView, matching: find.byType(Container))
        .first;
    return tester.getRect(card).bottom - 6.0; // margin bottom 6
  }

  /// 白卡內部「內容高 vs 可視高」的餘量（用戶投訴的「底下空白」就是這個數）
  double innerSlackOf(WidgetTester tester) {
    final scrollView = find
        .descendant(
            of: threeZoneColumn(), matching: find.byType(SingleChildScrollView))
        .first;
    final column =
        find.descendant(of: scrollView, matching: find.byType(Column)).first;
    return tester.getRect(scrollView).height - tester.getRect(column).height;
  }

  /// 三區本體嘅 RenderFlex 溢出（AppBar 既有水平溢出屬已知問題，唔計）
  List<String> threeZoneOverflow(WidgetTester tester) {
    final hits = <String>[];
    for (;;) {
      final e = tester.takeException();
      if (e == null) break;
      final msg = e.toString();
      if (msg.contains('overflowed') && msg.contains('LayoutBuilder')) {
        hits.add(msg.split('\n').first);
      }
    }
    return hits;
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    required ShiftStore store,
    required double w,
    required double h,
    required double paddingBottom,
    required double insetsBottom,
  }) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = FakeViewPadding(bottom: paddingBottom);
    tester.view.viewPadding = FakeViewPadding(bottom: paddingBottom);
    tester.view.viewInsets = FakeViewPadding(bottom: insetsBottom);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: HomeScreen(store: store, alarms: AlarmService(AlarmBridge())),
    ));
    await tester.pump();
  }

  const machines = <String, Size>{
    '360×800': Size(360, 800),
    '360×640': Size(360, 640),
    '411×891': Size(411, 891),
  };
  const insetCases = <String, double>{
    'inset0': 0,
    '手勢88.8': 88.8,
    '三鍵112.8': 112.8,
  };

  for (final m in machines.entries) {
    for (final ins in insetCases.entries) {
      for (final kb in [false, true]) {
        final scene = '${m.key} / ${ins.key} / 鍵盤${kb ? '開' : '關'}';
        testWidgets('B6 $scene：三區填滿 body、底部無多餘空白、無溢出',
            (tester) async {
          final store = await makeStore();
          await pumpHome(
            tester,
            store: store,
            w: m.value.width,
            h: m.value.height,
            paddingBottom: ins.value,
            insetsBottom: kb ? 300 : 0,
          );

          final boxes = zoneBoxes(tester);
          final body = bodyHeightOf(tester);
          expect(boxes.length, 4, reason: '$scene：三區 + 導航留白共 4 個 child');

          // ① 三區 + nav 總和 == bodyHeight（不溢出、不留白）
          final sum =
              boxes.map((b) => b.size.height).reduce((a, b) => a + b);
          expect(sum, closeTo(body, 0.01), reason: '$scene：總和必須等於 body');

          // ② 溢出檢查
          expect(threeZoneOverflow(tester), isEmpty, reason: '$scene：三區溢出');

          // ③ 鍵盤開 → 天色欄高度 0
          if (kb) {
            expect(boxes[0].size.height, 0.0,
                reason: '$scene：鍵盤彈起時天色欄（zone1）必須是 0');
          }

          // ④ 底部區內容底 → 可用區底（導航留白頂）
          final navTop = globalRect(boxes[3]).top;
          final zone3Bottom = globalRect(boxes[2]).bottom;
          expect(zone3Bottom, closeTo(navTop, 0.01),
              reason: '$scene：底部區底與導航留白頂必須相接');

          final contentBottom = contentBottomOf(tester);
          final gap = navTop - contentBottom;

          // 內容不可被導航欄／鍵盤蓋住
          expect(contentBottom, lessThanOrEqualTo(navTop + 0.5),
              reason: '$scene：內容底($contentBottom) 越過可用區底($navTop)');
          // 底部不可留大空白（用戶投訴的 40–70px）
          expect(gap, greaterThanOrEqualTo(-0.5),
              reason: '$scene：內容超出可用區（gap=$gap）');
          expect(gap, lessThanOrEqualTo(7.0),
              reason: '$scene：底部區留白過多（gap=$gap）');

          // ⑤ 白卡內部餘量：用戶原話「第三欄…尚有余量在底下空白位置，應該用盡」
          final slack = innerSlackOf(tester);
          expect(slack, greaterThanOrEqualTo(-0.5),
              reason: '$scene：白卡內容溢出可視區（slack=$slack）');
          expect(slack, lessThanOrEqualTo(8.0),
              reason: '$scene：白卡內部底部空白過多（slack=$slack）');
        });
      }
    }
  }

  testWidgets('B6 排班編輯態：ShiftPickerPanel 在 140px 內不溢出（三種機型 × 三種 inset）',
      (tester) async {
    for (final m in machines.entries) {
      for (final ins in insetCases.entries) {
        final store = await makeStore();
        await pumpHome(
          tester,
          store: store,
          w: m.value.width,
          h: m.value.height,
          paddingBottom: ins.value,
          insetsBottom: 0,
        );

        // 進入排班編輯態（原地切換，高度不變）
        await tester.tap(find.text('排班'));
        await tester.pump();

        expect(find.byType(ShiftPickerPanel), findsOneWidget,
            reason: '${m.key}/${ins.key}：應切到排班編輯態');

        final boxes = zoneBoxes(tester);
        expect(boxes[2].size.height, CalendarLayout.detailMax,
            reason: '${m.key}/${ins.key}：編輯態底部區高度不變（原地切換）');

        // 面板本身不可溢出（溢出會被 ClipRect 靜默裁掉，所以必須捉 exception）
        final overflow = threeZoneOverflow(tester);
        expect(overflow, isEmpty,
            reason: '${m.key}/${ins.key}：排班面板溢出 → ${overflow.join(' | ')}');

        // 面板底不可超出可用區
        final navTop = globalRect(boxes[3]).top;
        final panelRect = tester.getRect(find.byType(ShiftPickerPanel));
        expect(panelRect.bottom, lessThanOrEqualTo(navTop + 0.5),
            reason: '${m.key}/${ins.key}：面板被導航欄蓋住');

        // 面板內容要食到底（只可以有 padding 8 的固定留白）
        final innerColumn = find
            .descendant(
                of: find.byType(ShiftPickerPanel), matching: find.byType(Column))
            .first;
        final innerBottom = tester.getRect(innerColumn).bottom;
        expect(panelRect.bottom - innerBottom, closeTo(8.0, 1.0),
            reason: '${m.key}/${ins.key}：面板底部留白應為 padding 8，'
                '實際 ${(panelRect.bottom - innerBottom).toStringAsFixed(1)}');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }
  });

  testWidgets('B6 編輯態 + 鍵盤彈起：天色欄 0、三區仍填滿 body、面板不溢出',
      (tester) async {
    final store = await makeStore();
    await pumpHome(
      tester,
      store: store,
      w: 360,
      h: 800,
      paddingBottom: 88.8,
      insetsBottom: 0,
    );
    await tester.tap(find.text('排班'));
    await tester.pump();

    // 模擬鍵盤彈起（例如點備註輸入框）
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.pump();

    final boxes = zoneBoxes(tester);
    expect(boxes[0].size.height, 0.0, reason: '輸入文字時天色欄必須完全壓縮為 0');
    expect(threeZoneOverflow(tester), isEmpty);
    final sum = boxes.map((b) => b.size.height).reduce((a, b) => a + b);
    expect(sum, closeTo(bodyHeightOf(tester), 0.01));
  });
}
