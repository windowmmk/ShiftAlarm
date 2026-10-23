// 產生 README 用的 demo 截圖 —— **真實 UI 渲染**，唔係示意圖。
//
// 用法（由專案根目錄執行）：
//   export NO_PROXY="localhost,127.0.0.1,::1"   # 否則 flutter_tester 連唔上
//   flutter test tool/gen_screenshots_test.dart
// 產物：docs/screenshots/*.png
//
// ⚠️ 點解放喺 `tool/` 而唔係 `test/`：
//    全量 `flutter test` 只跑 `test/` 目錄，所以呢個檔唔會入 CI、唔會產生
//    golden 比對，亦唔會因為換咗 Flutter 版本嘅字型渲染差異而令 CI 變紅。
//
// ⚠️ 兩個踩過嘅坑（改壞咗截圖會變方格 / 空白）：
//    1. 測試環境預設字型係 **Ahem**（每個字都渲染成實心方格），
//       必須手動 `FontLoader` 載入真字型，否則中文全部變方格。
//       拉丁用 Flutter SDK 自帶嘅 Roboto，中文 fallback 到 Windows 嘅「等線」
//       （`Deng.ttf`）—— 揀佢而唔係 `msyh.ttc`，因為 FontLoader 食唔到 .ttc。
//    2. 天色帶有 30fps 常駐 `Timer.periodic`，`pumpAndSettle()` 會永遠 timeout，
//       一律只 `pump()` 兩次。
// ⚠️ 呢個檔本質上就係一個 test（要 `flutter test` 嘅渲染環境先截到圖），
//    所以用 `@visibleForTesting` 嘅 API 係正當嘅，唔應該當成違規。
// ignore_for_file: invalid_use_of_visible_for_testing_member
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftalarm/alarm/alarm_bridge.dart';
import 'package:shiftalarm/domain/alarm_service.dart';
import 'package:shiftalarm/domain/shift_store.dart';
import 'package:shiftalarm/theme/app_theme.dart';
import 'package:shiftalarm/ui/screens/home_screen.dart';
import 'package:shiftalarm/ui/screens/shift_manage_screen.dart';
import 'package:shiftalarm/ui/screens/stats_screen.dart';

const String _outDir = 'docs/screenshots';

/// 進度標記檔：卡死時（進程唔會退出、log 都唔會 flush）仍然可以靠呢個檔
/// 睇到最後行到邊一步，唔使靠估。
final File _probe = File('tool/_progress.txt');

void _mark(String s) {
  try {
    _probe.writeAsStringSync('$s\n', mode: FileMode.append);
  } catch (_) {
    // 探測用途，寫唔到就算
  }
}

/// 截圖尺寸：主流手機 360×800，輸出 2 倍圖（720×1600）方便 README 縮放。
const double _w = 360.0;
const double _h = 800.0;
const double _pixelRatio = 2.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ⚠️ test 名用**英文**：Git Bash 傳中文參數畀 `flutter.bat` 會觸發 MSYS
  //    路徑轉換，搞到 `'C:\Users\window\WorkBuddy' is not recognized`，
  //    咁就冇得用 `--plain-name` 單跑某一張。
  //
  // ⚠️ **一張圖一個 test、每次一個進程**，唔可以三個 test 連著跑：
  //    實測第二次 `pumpWidget`（把首頁連同天色帶嘅 30fps `Timer.periodic`
  //    一齊換走）會**永久 hang** —— 舊 tree 未 dispose 完，新 frame 等唔到。
  //    所以每個 test 拍完自己嗰張就直接 `exit(0)`，用 `--plain-name` 分三次跑。
  //
  // ⚠️ `exit(0)` 唔係偷懶：天色帶常駐 periodic timer 令 `flutter_test` 收尾嘅
  //    fake-async 靜止檢查永遠唔會完成，進程唔會自己退出。截圖喺 exit 之前
  //    已經 `writeAsBytesSync` 落咗磁碟，唔會有半張圖。
  testWidgets('home', (tester) async {
    await _ensureFonts(tester);
    final store = await _makeStore();
    await _shot(tester, '01-home',
        HomeScreen(store: store, alarms: AlarmService(AlarmBridge())));
    exit(0);
  });

  testWidgets('stats', (tester) async {
    await _ensureFonts(tester);
    final store = await _makeStore();
    await _shot(tester, '02-stats', StatsScreen(store: store));
    exit(0);
  });

  testWidgets('shifts', (tester) async {
    await _ensureFonts(tester);
    final store = await _makeStore();
    await _shot(tester, '03-shifts',
        ShiftManageScreen(store: store, alarms: AlarmService(AlarmBridge())));
    exit(0);
  });
}

// ─────────────────────────────────────────────────────────────────────────────

/// Flutter SDK 自帶的 Material 字型路徑。
String _materialFont(String name) {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || root.isEmpty) {
    throw StateError(
        '讀唔到 FLUTTER_ROOT 環境變數，載唔到 Roboto。'
        '要經 `flutter test` 跑，唔好直接用 `dart run`。');
  }
  return '$root/bin/cache/artifacts/material_fonts/$name';
}

/// 字型只需載一次（跨 test 共用同一個 isolate）。
bool _fontsLoaded = false;

/// ⚠️ **必須**包喺 `tester.runAsync` 入面：`FontLoader.load()` 內部會 await
/// 真實嘅 platform channel，而 `testWidgets` 係 fake-async zone ——
/// 直接喺 test body 或 `setUpAll` await 會**永久 deadlock**（實測卡死 4 分鐘以上，
/// 唔係慢，係唔會返）。
Future<void> _ensureFonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  _mark('fonts:start');
  await tester.runAsync(() async {
    _mark('fonts:runasync-enter');
    await _loadFont('Roboto', _materialFont('roboto-regular.ttf'));
    _mark('fonts:roboto');
    await _loadFont('Deng', 'C:/Windows/Fonts/Deng.ttf');
    _mark('fonts:deng');
    // ⚠️ MaterialIcons 同 Roboto 一樣係測試環境**唔會**自動載入，
    //    唔載入的話 AppBar／底部導航／輸入框全部變成方格（Icon 一個都畫唔到）。
    await _loadFont('MaterialIcons', _materialFont('MaterialIcons-Regular.otf'));
    _mark('fonts:icons');

    // ⚠️ 同一 family 要連**粗體**一齊載：只載 regular 嘅話，
    //    `FontWeight.w700` 嘅字喺 fallback 字型搵唔到對應字重，會退返 Ahem
    //    （統計頁「返工／總工時／休息」三個粗體數字就係咁變黑方塊）。
    //    用 `Dengb.ttf`（等線粗體）／`roboto-bold.ttf` 補齊。
    //
    //    順帶記錄試過但**冇用**嘅方法：`FontLoader('Ahem')` 灌真字型
    //    —— 框架內建 Ahem 優先，蓋唔到。
    await _loadFontFamily('Roboto', [
      _materialFont('roboto-regular.ttf'),
      _materialFont('roboto-medium.ttf'),
      _materialFont('roboto-bold.ttf'),
    ]);
    _mark('fonts:roboto-weights');
    await _loadFontFamily('Deng', [
      'C:/Windows/Fonts/Deng.ttf',
      'C:/Windows/Fonts/Dengb.ttf',
    ]);
    _mark('fonts:deng-weights');
  });
  _mark('fonts:done');
  _fontsLoaded = true;
}

Future<void> _loadFont(String family, String path) =>
    _loadFontFamily(family, [path]);

/// 同一 family 可以載多個字重檔（Skia 會按字型檔自身嘅 OS/2 字重去匹配）。
Future<void> _loadFontFamily(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('字型檔案唔存在：$path');
    }
    loader.addFont(
        Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await loader.load();
}

/// 測試環境冇中文字型，要令每段文字都搵得到真字型。
///
/// ⚠️ 有**三層**要補，漏咗任何一層都會見到方格（Ahem）：
///   1. `fontFamily` —— 一大批 `TextStyle` 係 `fontFamily: null`，測試環境會落到
///      Ahem。`ThemeData.copyWith` **冇** `fontFamily` 參數（只有建構子有），
///      所以要經 `TextTheme.apply(fontFamily: ...)` 落。
///   2. `fontFamilyFallback` —— 加中文字型「等線」。
///   3. `appBarTheme.titleTextStyle` —— **唔會**經過 `textTheme.apply`，
///      所以要逐個 `copyWith`，唔改就見到 AppBar 標題係一排黑方塊。
ThemeData _theme() {
  const latin = 'Roboto';
  const cjk = 'Deng';
  final base = buildAppTheme();
  return base.copyWith(
    textTheme: base.textTheme
        .apply(fontFamily: latin, fontFamilyFallback: const [cjk]),
    primaryTextTheme: base.primaryTextTheme
        .apply(fontFamily: latin, fontFamilyFallback: const [cjk]),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
          fontFamily: latin, fontFamilyFallback: const [cjk]),
      toolbarTextStyle: base.appBarTheme.toolbarTextStyle?.copyWith(
          fontFamily: latin, fontFamilyFallback: const [cjk]),
    ),
  );
}

/// 造一份睇落真實的排班資料（唔係空月曆）。
Future<ShiftStore> _makeStore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = ShiftStore(prefs);
  await store.load();
  _mark('store:loaded');

  final defs = ShiftStore.testDefaults();
  for (final def in defs.values) {
    await store.addDef(def);
  }
  _mark('store:defs');

  // 內建只有 4 個班次，班次管理頁會大片留白；加多幾個令 demo 圖睇落係真實排班表。
  for (final extra in <ShiftDef>[
    ShiftDef(
      id: 'sOC',
      name: 'On-call',
      code: 'OC',
      startTime: '09:00',
      endTime: '18:00',
      alarms: [
        ShiftAlarm(id: 'oc1', label: '開工前 15 分鐘', offsetMinutes: -15)
      ],
    ),
    ShiftDef(
      id: 'sTR',
      name: '訓練日',
      abbr: '訓練',
      code: 'TR',
      startTime: '13:00',
      endTime: '18:00',
      alarms: [],
    ),
    ShiftDef(
      id: 'sLV',
      name: '年假',
      abbr: '年假',
      code: 'LV',
      startTime: '09:00',
      endTime: '18:00',
      alarms: [],
    ),
  ]) {
    await store.addDef(extra);
  }
  _mark('store:extra-defs');

  // 早更×2 → 中更×2 → 夜更×2 → 休×1 嘅輪班節奏（睇得出規律又唔係死板）
  const pattern = <String?>['s06', 's06', 's12', 's12', 's18', 's18', null];
  const venues = <String>['A1', 'B2', 'C1', 'A2'];

  final now = DateTime.now();
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final mm = now.month.toString().padLeft(2, '0');

  for (var d = 1; d <= daysInMonth; d++) {
    final shiftId = pattern[(d - 1) % pattern.length];
    if (shiftId == null) continue; // 休息日留空
    final dd = d.toString().padLeft(2, '0');
    await store.assign('${now.year}-$mm-$dd', shiftId,
        note: venues[d % venues.length]);
  }

  // 一兩條備註，等底部詳情區唔係空框
  await store.setRemark('${now.year}-$mm-08', '交接班提早 15 分鐘');
  await store.setRemark('${now.year}-$mm-16', '帶新人');

  return store;
}

/// 把中文字型 fallback 灌入**所有** `RenderParagraph`。
///
/// 為咩要喺 render 層做，而唔係改 theme：
/// `RichText` 嘅 `TextSpan` 一旦自帶 `TextStyle`（例如統計頁「返工／總工時／
/// 休息」三張卡嘅數字），就**唔會**繼承 `DefaultTextStyle`；`fontFamily` 為
/// null 時會落到測試環境嘅默認字體 Ahem（實心方格）。
/// 呢個 style 係 widget 內硬寫嘅，改 `ThemeData` 改唔到；
/// 試過 `FontLoader('Ahem')` 灌真字型都**冇效**（框架內建 Ahem 優先）。
/// 所以喺 render 層統一補 fallback —— 純截圖層補丁，唔使為咗出圖去改產品代碼。
void _applyFontFallback(WidgetTester tester) {
  const fallback = ['Deng'];
  final paragraphs = <RenderParagraph>[];
  void collect(RenderObject node) {
    if (node is RenderParagraph) paragraphs.add(node);
    node.visitChildren(collect);
  }

  collect(tester.binding.renderViews.first);
  for (final p in paragraphs) {
    p.text = _withFallback(p.text, fallback);
  }
}

InlineSpan _withFallback(InlineSpan span, List<String> fallback) {
  if (span is! TextSpan) return span;
  final base = span.style ?? const TextStyle();
  // ⚠️ 淨係補 `fontFamilyFallback` **唔夠**：fallback 只喺「主字體冇呢個字形」
  //    時才用。測試環境主字體係 Ahem，佢**有** ASCII 字形（就係嗰啲實心方塊），
  //    所以數字／英文字母會照樣用 Ahem 畫方塊，只有中文因為 Ahem 冇字形才 fallback
  //    到「等線」——正好對應「中文正常、數字係方塊」嘅現象。
  //    所以主字體都要指定成有真數字字形嘅 Roboto。
  final style = base.fontFamily == null
      ? base.copyWith(fontFamily: 'Roboto', fontFamilyFallback: fallback)
      : base.copyWith(fontFamilyFallback: fallback);
  return TextSpan(
    text: span.text,
    style: style,
    children: span.children?.map((c) => _withFallback(c, fallback)).toList(),
    recognizer: span.recognizer,
    semanticsLabel: span.semanticsLabel,
    locale: span.locale,
    spellOut: span.spellOut,
  );
}

/// 泵一個畫面並截圖，寫到 `docs/screenshots/<name>.png`。
Future<void> _shot(WidgetTester tester, String name, Widget child) async {
  tester.view.physicalSize = const Size(_w, _h);
  tester.view.devicePixelRatio = 1.0;

  final boundaryKey = GlobalKey();
  _mark('$name:pumpWidget');
  await tester.pumpWidget(MaterialApp(
    theme: _theme(),
    home: RepaintBoundary(key: boundaryKey, child: child),
  ));
  _mark('$name:pumped');
  // 天色帶 30fps Timer：唔可以 pumpAndSettle
  await tester.pump();
  await tester.pump();
  _mark('$name:pumped2');
  // ⚠️ 只清一次：StatsScreen 若每幀都再拋，while 會變成無限循環
  //    （試過：卡死 5 分鐘以上唔會返）。
  final err = tester.takeException();
  if (err != null) _mark('$name:exception ${err.runtimeType}');
  _mark('$name:clean');

  // 補字型 fallback（見 `_applyFontFallback` 註釋），再重排一次先截圖
  _applyFontFallback(tester);
  await tester.pump();
  _mark('$name:font-patched');

  final boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: _pixelRatio);
  _mark('$name:toImage ${image.width}x${image.height}');
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes =
      data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

  final out = File('$_outDir/$name.png');
  if (!out.parent.existsSync()) {
    out.parent.createSync(recursive: true);
  }
  out.writeAsBytesSync(bytes);
  _mark('$name:written');

  // ignore: avoid_print
  print('[SHOT] ${out.path} ${bytes.lengthInBytes} bytes '
      '${image.width}x${image.height}');
}
