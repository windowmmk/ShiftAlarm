// ignore: deprecated_member_use
import 'package:flutter/material.dart';
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

/// v3.7.0 UI 打磨與文案統一回歸測試：
/// 1. 全站統一純繁體「設定」（不再出現「設置」）。
/// 2. 班次管理頁在名稱與縮寫相同時不重複括號（如「早更」而非「早更（早更）」）。
/// 3. 統計頁「班次分佈」同步顯示班次名稱與時段（如「早更 · 06–12」）。
/// 4. StatsScreen 與 ShiftManageScreen 在 320/360/412px × 1.0x/1.3x/2.0x 零溢出。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ShiftStore> makePopulatedStore() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = ShiftStore(prefs);
    await store.load();
    for (final def in ShiftStore.testDefaults().values) {
      await store.addDef(def);
    }
    final now = DateTime.now();
    final ymd = ShiftStore.ymd(now);
    await store.assign(ymd, 's06', note: 'A1');
    return store;
  }

  test('ShiftDef.displayTitle 去除重複括號但保留相異縮寫', () {
    final same = ShiftDef(
      id: 's06',
      name: '早更',
      abbr: '早更',
      startTime: '06:00',
      endTime: '12:00',
      alarms: [],
    );
    final diff = ShiftDef(
      id: 's00',
      name: '凌晨更',
      abbr: '凌晨',
      startTime: '00:00',
      endTime: '06:00',
      alarms: [],
    );
    expect(same.displayTitle, '早更');
    expect(diff.displayTitle, '凌晨更（凌晨）');
  });

  testWidgets('底部導覽列與設定頁統一顯示「設定」', (tester) async {
    final store = await makePopulatedStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomeScreen(store: store, alarms: AlarmService(AlarmBridge())),
      ),
    );
    await tester.pump();
    expect(find.text('設定'), findsWidgets);
    expect(find.text('設置'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: SettingsScreen(store: store, alarms: AlarmService(AlarmBridge())),
      ),
    );
    await tester.pump();
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('設置'), findsNothing);
  });

  testWidgets('班次管理頁不顯示重複括號', (tester) async {
    final store = await makePopulatedStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home:
            ShiftManageScreen(store: store, alarms: AlarmService(AlarmBridge())),
      ),
    );
    await tester.pump();

    expect(find.text('早更'), findsOneWidget);
    expect(find.text('早更（早更）'), findsNothing);
    expect(find.text('凌晨更（凌晨）'), findsOneWidget);
  });

  testWidgets('統計頁班次分佈同步顯示班次名稱與時段', (tester) async {
    final store = await makePopulatedStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: StatsScreen(store: store),
      ),
    );
    await tester.pump();

    expect(find.text('凌晨更 · 00–06'), findsOneWidget);
    expect(find.text('早更 · 06–12'), findsOneWidget);
    expect(find.text('中更 · 12–18'), findsOneWidget);
    expect(find.text('夜更 · 18–00'), findsOneWidget);
  });

  group('StatsScreen 與 ShiftManageScreen 響應式零溢出防線', () {
    const widths = [320.0, 360.0, 412.0];
    const scales = [1.0, 1.3, 2.0];

    for (final w in widths) {
      for (final ts in scales) {
        testWidgets('StatsScreen ${w.toInt()}px × ${ts}x 零溢出', (tester) async {
          final errors = <FlutterErrorDetails>[];
          final orig = FlutterError.onError;
          addTearDown(() {
            FlutterError.onError = orig;
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          tester.view.physicalSize = Size(w, 800);
          tester.view.devicePixelRatio = 1.0;

          final store = await makePopulatedStore();
          FlutterError.onError = errors.add;
          try {
            await tester.pumpWidget(
              MediaQuery(
                data: MediaQueryData(
                  size: Size(w, 800),
                  textScaler: TextScaler.linear(ts),
                ),
                child: MaterialApp(
                  theme: buildAppTheme(),
                  home: StatsScreen(store: store),
                ),
              ),
            );
            await tester.pump();
            await tester.pump();
          } finally {
            FlutterError.onError = orig;
          }

          final overflows = errors
              .where((e) => e.exceptionAsString().contains('overflowed'))
              .map((e) => e.exceptionAsString())
              .toList();
          expect(overflows, isEmpty,
              reason: 'StatsScreen ${w.toInt()}px × ${ts}x 溢出: $overflows');
        });

        testWidgets('ShiftManageScreen ${w.toInt()}px × ${ts}x 零溢出',
            (tester) async {
          final errors = <FlutterErrorDetails>[];
          final orig = FlutterError.onError;
          addTearDown(() {
            FlutterError.onError = orig;
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          tester.view.physicalSize = Size(w, 800);
          tester.view.devicePixelRatio = 1.0;

          final store = await makePopulatedStore();
          FlutterError.onError = errors.add;
          try {
            await tester.pumpWidget(
              MediaQuery(
                data: MediaQueryData(
                  size: Size(w, 800),
                  textScaler: TextScaler.linear(ts),
                ),
                child: MaterialApp(
                  theme: buildAppTheme(),
                  home: ShiftManageScreen(
                    store: store,
                    alarms: AlarmService(AlarmBridge()),
                  ),
                ),
              ),
            );
            await tester.pump();
            await tester.pump();
          } finally {
            FlutterError.onError = orig;
          }

          final overflows = errors
              .where((e) => e.exceptionAsString().contains('overflowed'))
              .map((e) => e.exceptionAsString())
              .toList();
          expect(overflows, isEmpty,
              reason:
                  'ShiftManageScreen ${w.toInt()}px × ${ts}x 溢出: $overflows');
        });
      }
    }
  });
}
