// 產生 README 用的 demo 截圖（真實 UI 渲染）。
//
// 用法（由專案根目錄執行，逐項執行以確保獨立視窗狀態）：
//   flutter test tool/gen_screenshots_test.dart --plain-name home
//   flutter test tool/gen_screenshots_test.dart --plain-name stats
//   flutter test tool/gen_screenshots_test.dart --plain-name shifts
//   flutter test tool/gen_screenshots_test.dart --plain-name settings
// 產物：docs/screenshots/*.png
//
// 支援跨平台中文字型自動偵測（Linux NotoSansCJK / WenQuanYi 與 Windows Deng）。
// ignore_for_file: invalid_use_of_visible_for_testing_member
library;

import 'dart:io';
import 'dart:ui' as ui;

// ignore: deprecated_member_use
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
import 'package:shiftalarm/ui/screens/settings_screen.dart';
import 'package:shiftalarm/ui/screens/shift_manage_screen.dart';
import 'package:shiftalarm/ui/screens/stats_screen.dart';

const String _outDir = 'docs/screenshots';
const String _cjkFamily = 'CjkFallback';
const double _w = 360.0;
const double _h = 800.0;
const double _pixelRatio = 2.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home', (tester) async {
    await _ensureFonts(tester);
    final store = await _makeStore();
    await _shot(
      tester,
      '01-home',
      HomeScreen(store: store, alarms: AlarmService(AlarmBridge())),
    );
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
    await _shot(
      tester,
      '03-shifts',
      ShiftManageScreen(store: store, alarms: AlarmService(AlarmBridge())),
    );
    exit(0);
  });

  testWidgets('settings', (tester) async {
    await _ensureFonts(tester);
    final store = await _makeStore();
    await _shot(
      tester,
      '04-settings',
      SettingsScreen(store: store, alarms: AlarmService(AlarmBridge())),
    );
    exit(0);
  });
}

String _materialFont(String name) {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || root.isEmpty) {
    throw StateError('讀不到 FLUTTER_ROOT 環境變數，請經由 `flutter test` 執行。');
  }
  return '$root/bin/cache/artifacts/material_fonts/$name';
}

/// 跨平台尋找系統繁體中文字型（支援 Linux / macOS / Windows）。
List<String> _findCjkFontPaths() {
  final candidates = <List<String>>[
    // Linux Noto Sans CJK (Ubuntu fonts-noto-cjk)
    [
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
    ],
    [
      '/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc',
      '/usr/share/fonts/noto-cjk/NotoSansCJK-Bold.ttc',
    ],
    ['/usr/share/fonts/truetype/wqy/wqy-microhei.ttc'],
    ['/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc'],
    // Windows 等線
    ['C:/Windows/Fonts/Deng.ttf', 'C:/Windows/Fonts/Dengb.ttf'],
    // macOS PingFang
    ['/System/Library/Fonts/PingFang.ttc'],
  ];

  for (final group in candidates) {
    final existing = group.where((p) => File(p).existsSync()).toList();
    if (existing.isNotEmpty) return existing;
  }

  // 環境變數覆寫（供 CI 自訂字型路徑）
  final envPath = Platform.environment['SHIFTALARM_CJK_FONT'];
  if (envPath != null && envPath.isNotEmpty && File(envPath).existsSync()) {
    return [envPath];
  }

  throw StateError('找不到系統中文字型，請安裝 fonts-noto-cjk 或設定 SHIFTALARM_CJK_FONT。');
}

bool _fontsLoaded = false;

Future<void> _ensureFonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  await tester.runAsync(() async {
    await _loadFontFamily('Roboto', [
      _materialFont('roboto-regular.ttf'),
      _materialFont('roboto-medium.ttf'),
      _materialFont('roboto-bold.ttf'),
    ]);
    await _loadFontFamily(
      'MaterialIcons',
      [_materialFont('MaterialIcons-Regular.otf')],
    );
    await _loadFontFamily(_cjkFamily, _findCjkFontPaths());
  });
  _fontsLoaded = true;
}

Future<void> _loadFontFamily(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('字型檔案不存在：$path');
    }
    loader.addFont(
      Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
    );
  }
  await loader.load();
}

ThemeData _theme() {
  const latin = 'Roboto';
  final base = buildAppTheme();
  return base.copyWith(
    textTheme: base.textTheme
        .apply(fontFamily: latin, fontFamilyFallback: const [_cjkFamily]),
    primaryTextTheme: base.primaryTextTheme
        .apply(fontFamily: latin, fontFamilyFallback: const [_cjkFamily]),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: latin,
        fontFamilyFallback: const [_cjkFamily],
      ),
      toolbarTextStyle: base.appBarTheme.toolbarTextStyle?.copyWith(
        fontFamily: latin,
        fontFamilyFallback: const [_cjkFamily],
      ),
    ),
  );
}

Future<ShiftStore> _makeStore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = ShiftStore(prefs);
  await store.load();

  for (final def in ShiftStore.testDefaults().values) {
    await store.addDef(def);
  }

  for (final extra in <ShiftDef>[
    ShiftDef(
      id: 'sOC',
      name: 'On-call',
      code: 'OC',
      startTime: '09:00',
      endTime: '18:00',
      alarms: [
        ShiftAlarm(id: 'oc1', label: '開工前 15 分鐘', offsetMinutes: -15),
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

  const pattern = <String?>['s06', 's06', 's12', 's12', 's18', 's18', null];
  const venues = <String>['A1', 'B2', 'C1', 'A2'];

  final now = DateTime.now();
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final mm = now.month.toString().padLeft(2, '0');

  for (var d = 1; d <= daysInMonth; d++) {
    final shiftId = pattern[(d - 1) % pattern.length];
    if (shiftId == null) continue;
    final dd = d.toString().padLeft(2, '0');
    await store.assign(
      '${now.year}-$mm-$dd',
      shiftId,
      note: venues[d % venues.length],
    );
  }

  await store.setRemark('${now.year}-$mm-08', '交接班提早 15 分鐘');
  await store.setRemark('${now.year}-$mm-16', '帶新人');

  return store;
}

void _applyFontFallback(WidgetTester tester) {
  const fallback = [_cjkFamily];
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

Future<void> _shot(WidgetTester tester, String name, Widget child) async {
  tester.view.physicalSize = const Size(_w, _h);
  tester.view.devicePixelRatio = 1.0;

  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme(),
      home: RepaintBoundary(key: boundaryKey, child: child),
    ),
  );
  await tester.pump();
  await tester.pump();
  tester.takeException();

  _applyFontFallback(tester);
  await tester.pump();

  final boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: _pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes =
      data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

  final out = File('$_outDir/$name.png');
  if (!out.parent.existsSync()) {
    out.parent.createSync(recursive: true);
  }
  out.writeAsBytesSync(bytes);

  // ignore: avoid_print
  print(
    '[SHOT] ${out.path} ${bytes.lengthInBytes} bytes '
    '${image.width}x${image.height}',
  );
}
