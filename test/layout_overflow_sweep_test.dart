// 版面溢出全掃描 —— 永久防線（v3.6.3 新增）
//
// 背景：`test/responsive_overflow_test.dart` 只掃日曆頁。v3.6.2 之後實測發現
// 仲有六個介面在窄屏 + 系統大字體下會出黃黑間條：
//
//   ① 班次編輯頁的「1:1 日曆格預覽」——預覽格本來就係模擬日曆格的真實大小，
//      但文字跟住系統字體放大，於是 320px @1.3x 起就會撐爆個格。
//   ② 「關於」對話框內容不可滾動 —— 大字體用戶永遠睇唔到後半段。
//   ③ 權限自檢頁的標題列（權限名 + 狀態徽章）在窄屏爆邊。
//   ④ 排班操作列第一行（日期 + 地點 + 完成）在窄屏爆邊。
//   ⑤ 導入對話框的「貼上排班內容」列爆邊。
//   ⑥ 二維碼對話框標題（圖示 + 標題字）爆邊。
//   ⑦ 導入對話框底部的按鈕行爆邊。
//
// 呢個測試**掃整棵 render tree 的每一個 `RenderFlex`**，用「子節點總長 > 自身長度」
// 判定溢出，而唔係靠 `takeException()`：
//   - `takeException()` 每次只拿到**一個** exception，同一棵樹同時有幾處溢出就會漏；
//   - 固定高度容器（例如 42px 的按鈕列）內部溢出有時唔會經 `takeException()` 報出嚟，
//     但 render object 的實際尺寸係呃唔到人的。
//
// 覆蓋矩陣：7 個介面 × 寬度 320/360/390/412 × 字體 1.0/1.3/2.0 = 84 個組合。
//
// ⚠️ 技術注意（踩過的坑，唔好改返）：
//   - 任何用 `context.tokens` 的頁面必須 `theme: buildAppTheme()`，
//     否則 `_TypeError: Null check operator used on a null value`。
//   - 海洋帶有 30fps 常駐 `Timer.periodic`，`pumpAndSettle()` 會永遠 timeout
//     → 一律用兩次 `tester.pump()`。
//   - 唔可以只靠 `takeException()` 判斷：pump 完要把它抽乾，免得同一個
//     溢出同時令測試 framework 收工時再紅一次（重複噪音蓋過真正的報告）。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftalarm/alarm/alarm_bridge.dart';
import 'package:shiftalarm/domain/alarm_service.dart';
import 'package:shiftalarm/domain/shift_store.dart';
import 'package:shiftalarm/theme/app_theme.dart';
import 'package:shiftalarm/ui/dialogs/unified_import_dialog.dart';
import 'package:shiftalarm/ui/screens/permission_check_screen.dart';
import 'package:shiftalarm/ui/screens/settings_screen.dart';
import 'package:shiftalarm/ui/screens/shift_manage_screen.dart';
import 'package:shiftalarm/ui/screens/shift_picker_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 320 = 最窄主流（舊機）；360 = 最常見；390/412 = 主流中高階機
  const widths = <double>[320.0, 360.0, 390.0, 412.0];
  // 1.0 = 預設；1.3 = 系統「大」；2.0 = 系統「最大」
  const scales = <double>[1.0, 1.3, 2.0];

  /// 起一個有真實數據的 store：`ShiftStore.defaults()` 在正式版係**空**的
  /// （統一版本唔預設班次），所以測試要用 `testDefaults()` 自己種 4 個班次，
  /// 否則班次編輯頁同操作列只會泵到一個空殼，測唔到任何真版面。
  Future<ShiftStore> makeStore() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = ShiftStore(prefs);
    await store.load();
    for (final def in ShiftStore.testDefaults().values) {
      await store.addDef(def);
    }
    // 種一日排班：令操作列的地點欄、清除按鈕都進入「有值」狀態
    await store.assign('2026-03-15', 's06', note: '總部');
    return store;
  }

  /// 由一個 `RenderFlex` 的後代收集文字，令失敗報告一眼睇得出係邊一行爆。
  ///
  /// `debugCreator` 只會印 widget 名稱同建構位置，仲會被截斷成「Row ← Semantics
  /// ← …」，喺一個畫面有十幾個 Row 的時候根本分唔到。文字內容係最直接的線索。
  String textHint(RenderObject ro) {
    final texts = <String>[];
    void visit(RenderObject node) {
      if (texts.length >= 3) return;
      if (node is RenderParagraph) {
        final t = node.text.toPlainText().replaceAll('\n', ' ').trim();
        if (t.isNotEmpty) {
          texts.add(t.length > 16 ? '${t.substring(0, 16)}…' : t);
        }
        return;
      }
      node.visitChildren(visit);
    }

    ro.visitChildren(visit);
    return texts.isEmpty ? '' : ' 文字[${texts.join(' | ')}]';
  }

  /// 掃描整棵 render tree，回傳所有溢出的 `RenderFlex` 描述。
  ///
  /// 判定方式同 `test/responsive_overflow_test.dart` 的 `overflowReport()` 一致：
  /// 逐個 `RenderFlex` 累加子節點在主轴方向的長度，大過自身長度就係溢出。
  /// 0.6px 係浮點誤差容忍（`Expanded` 平分時會出現 0.2 級誤差）。
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
      if (sum > own + 0.6) {
        hits.add('${horizontal ? "橫" : "直"}向溢出 '
            '${(sum - own).toStringAsFixed(1)}px '
            '（自身 ${own.toStringAsFixed(1)}，子總長 ${sum.toStringAsFixed(1)}）'
            '${textHint(ro)}');
      }
    }
    return hits;
  }

  /// 統一的泵頁面方式：固定 viewport、固定文字縮放、強制 App 主題。
  Future<void> pumpSurface(
    WidgetTester tester,
    double w,
    double h,
    double textScale,
    Widget home,
  ) async {
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
      home: home,
    ));
    // 海洋帶 30fps Timer：唔可以 pumpAndSettle，只 pump 兩次
    await tester.pump();
    await tester.pump();
    // 抽乾 exception：溢出與否由 overflowReport() 統一判定，唔好兩邊都報
    // （同一個溢出如果又經 framework 收工時報一次，會蓋過真正有用的報告）
    while (tester.takeException() != null) {}
  }

  /// 開對話框後同樣要「兩次 pump + 抽乾 exception」。
  Future<void> settleDialog(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    while (tester.takeException() != null) {}
  }

  /// 喺可捲動清單裡搵目標並滾到可見（大字體時「關於」會被推到畫面外）。
  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isEmpty) return;
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: scrollable.first,
      maxScrolls: 40,
    );
    await tester.pump();
  }

  void expectNoOverflow(WidgetTester tester, String label) {
    final hits = overflowReport(tester);
    expect(hits, isEmpty,
        reason: '$label 出現 ${hits.length} 處溢出：\n${hits.join('\n')}');
  }

  // ═════════════ ① 班次編輯頁（含 1:1 日曆格預覽） ═════════════
  group('① ShiftEditScreen：1:1 預覽格與整頁零溢出', () {
    for (final w in widths) {
      for (final ts in scales) {
        testWidgets('${w.toInt()}px × 字體 ${ts}x：零溢出', (tester) async {
          final store = await makeStore();
          final def = store.defs['s06'];
          expect(def, isNotNull, reason: '預設班次 s06 必須存在，否則測唔到預覽格');

          await pumpSurface(
            tester,
            w,
            800,
            ts,
            ShiftEditScreen(
              store: store,
              alarms: AlarmService(AlarmBridge()),
              def: def,
            ),
          );

          expect(find.text('月曆格即時預覽'), findsOneWidget,
              reason: '預覽區必須仍然存在（唔可以靠刪掉 UI 過關）');
          expectNoOverflow(tester, 'ShiftEditScreen ${w.toInt()}px × 字體 ${ts}x');
        });
      }
    }

    // 預覽格的意義就係「同真實日曆格一樣大」：字體放大時尺寸**唔可以**跟住變。
    testWidgets('1:1 預覽格在 2.0x 下尺寸同 1.0x 完全一致', (tester) async {
      final store = await makeStore();
      final def = store.defs['s06'];
      final cellKey = find.byKey(const Key('shift-edit-preview-cell'));

      await pumpSurface(
          tester, 360, 800, 1.0,
          ShiftEditScreen(
              store: store,
              alarms: AlarmService(AlarmBridge()),
              def: def));
      expect(cellKey, findsOneWidget, reason: '預覽格必須帶 Key 先量得到');
      final sizeAt1x = tester.getSize(cellKey);
      final dayAt1x = tester.getSize(find.descendant(
          of: cellKey, matching: find.text('15')));

      await pumpSurface(
          tester, 360, 800, 2.0,
          ShiftEditScreen(
              store: store,
              alarms: AlarmService(AlarmBridge()),
              def: def));
      final sizeAt2x = tester.getSize(cellKey);
      final dayAt2x = tester.getSize(find.descendant(
          of: cellKey, matching: find.text('15')));

      expect(sizeAt2x, sizeAt1x,
          reason: '預覽格本身唔應該隨系統字體縮放（佢係模擬固定大小的日曆格）');
      expect(dayAt2x, dayAt1x,
          reason: '預覽格內文字在 2.0x 下唔可以變大，否則同真實日曆格比例失真');
    });
  });

  // ═════════════ ②⑧ 「關於」對話框 ═════════════
  group('②⑧ 設置頁與「關於」對話框零溢出', () {
    for (final w in widths) {
      for (final ts in scales) {
        testWidgets('${w.toInt()}px × 字體 ${ts}x：設置頁零溢出', (tester) async {
          final store = await makeStore();
          await pumpSurface(
            tester,
            w,
            800,
            ts,
            SettingsScreen(store: store, alarms: AlarmService(AlarmBridge())),
          );
          expectNoOverflow(tester, 'SettingsScreen ${w.toInt()}px × 字體 ${ts}x');
        });

        testWidgets('${w.toInt()}px × 字體 ${ts}x：「關於」對話框零溢出',
            (tester) async {
          final store = await makeStore();
          await pumpSurface(
            tester,
            w,
            800,
            ts,
            SettingsScreen(store: store, alarms: AlarmService(AlarmBridge())),
          );
          await scrollTo(tester, find.text('關於'));
          await tester.tap(find.text('關於'));
          await settleDialog(tester);

          expect(find.text('ShiftAlarm 排班鬧鐘'), findsOneWidget,
              reason: '「關於」對話框必須彈得出');
          // 內容一定要可滾動，否則大字體用戶睇唔到後半段
          expect(
            find.descendant(
                of: find.byType(AlertDialog), matching: find.byType(Scrollable)),
            findsWidgets,
            reason: '「關於」對話框內容必須包住可捲動容器',
          );
          expectNoOverflow(
              tester, '「關於」對話框 ${w.toInt()}px × 字體 ${ts}x');
        });
      }
    }

    // 防線有效性：大字體下滾到底仍然要見到最後一項（證明「睇得到後半段」）
    testWidgets('320px × 2.0x：「關於」內容可以捲到最後一行', (tester) async {
      final store = await makeStore();
      await pumpSurface(
          tester, 320, 800, 2.0,
          SettingsScreen(store: store, alarms: AlarmService(AlarmBridge())));
      await scrollTo(tester, find.text('關於'));
      await tester.tap(find.text('關於'));
      await settleDialog(tester);

      final lastLine = find.text('https://github.com/windowmmk/ShiftAlarm');
      final dialogScrollable = find
          .descendant(
              of: find.byType(AlertDialog), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(lastLine, 80,
          scrollable: dialogScrollable, maxScrolls: 40);
      await tester.pump();
      expect(lastLine, findsOneWidget,
          reason: '2.0x 字體下必須捲得到「關於」內容的最後一行');
      expectNoOverflow(tester, '「關於」對話框 320px × 字體 2.0x（捲到底）');
    });
  });

  // ═════════════ ③ 權限自檢頁 ═════════════
  group('③ PermissionCheckScreen：整頁零溢出', () {
    for (final w in widths) {
      for (final ts in scales) {
        testWidgets('${w.toInt()}px × 字體 ${ts}x：零溢出', (tester) async {
          final store = await makeStore();
          await pumpSurface(
            tester,
            w,
            800,
            ts,
            PermissionCheckScreen(
              bridge: AlarmBridge(),
              alarms: AlarmService(AlarmBridge()),
              store: store,
            ),
          );
          expect(find.text('精確鬧鐘'), findsOneWidget,
              reason: '權限清單必須渲染得到（唔可以靠唔畫過關）');
          expectNoOverflow(
              tester, 'PermissionCheckScreen ${w.toInt()}px × 字體 ${ts}x');
        });
      }
    }
  });

  // ═════════════ ④ 排班操作列 ═════════════
  group('④ ShiftPickerPanel：零溢出', () {
    // 操作列高度由 CalendarLayout.detailHeight 決定（140），用真值泵
    for (final w in widths) {
      for (final ts in scales) {
        testWidgets('${w.toInt()}px × 字體 ${ts}x：零溢出', (tester) async {
          final store = await makeStore();
          await pumpSurface(
            tester,
            w,
            800,
            ts,
            Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 140,
                  width: w,
                  child: ShiftPickerPanel(
                    initialDate: DateTime(2026, 3, 15),
                    store: store,
                    alarms: AlarmService(AlarmBridge()),
                    onClose: () {},
                  ),
                ),
              ),
            ),
          );
          expect(find.text('完成'), findsOneWidget,
              reason: '「完成」按鈕必須仍然存在');
          expectNoOverflow(
              tester, 'ShiftPickerPanel ${w.toInt()}px × 字體 ${ts}x');
        });
      }
    }
  });

  // ═════════════ ⑤⑦⑨ 導入對話框 ═════════════
  group('⑤⑦⑨ 導入對話框零溢出', () {
    for (final w in widths) {
      for (final ts in scales) {
        testWidgets('${w.toInt()}px × 字體 ${ts}x：零溢出', (tester) async {
          final store = await makeStore();
          final alarms = AlarmService(AlarmBridge());
          await pumpSurface(
            tester,
            w,
            800,
            ts,
            Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showUnifiedImportDialog(
                      context: ctx,
                      store: store,
                      alarms: alarms,
                    ),
                    child: const Text('開導入'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('開導入'));
          await settleDialog(tester);

          expect(find.text('導入排班 / 配置'), findsOneWidget,
              reason: '導入對話框必須彈得出');
          expectNoOverflow(
              tester, '導入對話框 ${w.toInt()}px × 字體 ${ts}x');
        });
      }
    }
  });

  // ═════════════ ⑥ 二維碼對話框 ═════════════
  group('⑥ 二維碼對話框零溢出', () {
    for (final w in widths) {
      for (final ts in scales) {
        testWidgets('${w.toInt()}px × 字體 ${ts}x：零溢出', (tester) async {
          final store = await makeStore();
          await pumpSurface(
            tester,
            w,
            800,
            ts,
            SettingsScreen(store: store, alarms: AlarmService(AlarmBridge())),
          );
          await scrollTo(tester, find.text('導出排班口令'));
          await tester.tap(find.text('導出排班口令'));
          await settleDialog(tester);

          final qrBtn = find.text('二維碼 / 連結');
          expect(qrBtn, findsOneWidget, reason: '導出對話框必須有二維碼入口');
          await tester.tap(qrBtn);
          await settleDialog(tester);

          expect(find.text('排班分享二維碼'), findsOneWidget,
              reason: '二維碼對話框必須彈得出');
          expectNoOverflow(
              tester, '二維碼對話框 ${w.toInt()}px × 字體 ${ts}x');
        });
      }
    }
  });
}
