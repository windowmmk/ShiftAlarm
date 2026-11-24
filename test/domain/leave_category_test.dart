// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftalarm/alarm/alarm_bridge.dart';
import 'package:shiftalarm/domain/alarm_service.dart';
import 'package:shiftalarm/domain/config_io.dart';
import 'package:shiftalarm/domain/roster_io.dart';
import 'package:shiftalarm/domain/shift_store.dart';
import 'package:shiftalarm/theme/app_theme.dart';
import 'package:shiftalarm/ui/screens/shift_picker_panel.dart';
import 'package:shiftalarm/ui/screens/stats_screen.dart';

class _TrackingAlarmService extends AlarmService {
  final List<String> unassignedYmds = [];

  _TrackingAlarmService() : super(AlarmBridge());

  @override
  Future<void> onUnassigned(String ymd) async {
    unassignedYmds.add(ymd);
  }
}

Future<ShiftStore> _makeStore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = ShiftStore(prefs);
  await store.load();
  for (final d in ShiftStore.testDefaults().values) {
    await store.addDef(d);
  }
  return store;
}

void main() {
  group('假期類領域邏輯與序列化', () {
    test('ShiftDef.fromJson / toJson 保留 isLeave 且不自動注入開工鬧鐘', () {
      final def = ShiftDef(
        id: ShiftDef.leaveId,
        name: '假期',
        abbr: '假期',
        startTime: '00:00',
        endTime: '00:00',
        alarms: const [],
        isLeave: true,
      );
      final json = def.toJson();
      expect(json['isLeave'], isTrue);

      final restored = ShiftDef.fromJson(ShiftDef.leaveId, json);
      expect(restored.isLeave, isTrue);
      expect(restored.alarms, isEmpty);
      expect(restored.copy().isLeave, isTrue);
    });

    test('assign 假期類自動註冊 leaveDef，sortedDefs 排除假期類', () async {
      final store = await _makeStore();
      await store.assign('2026-11-24', ShiftDef.leaveId, note: '進修假');

      expect(store.defs.containsKey(ShiftDef.leaveId), isTrue);
      expect(store.defs[ShiftDef.leaveId]!.isLeave, isTrue);
      expect(store.sortedDefs().any((d) => d.isLeave), isFalse);
      expect(store.assignments['2026-11-24']!.shiftId, ShiftDef.leaveId);
      expect(store.assignments['2026-11-24']!.note, '進修假');
    });

    test('replaceAllDefs 與 assignBatch 保留內建假期類', () async {
      final store = await _makeStore();
      await store.assign('2026-11-24', ShiftDef.leaveId, note: '年假');
      await store.replaceAllDefs(ShiftStore.testDefaults());
      expect(store.defs.containsKey(ShiftDef.leaveId), isTrue);

      final store2 = await _makeStore();
      await store2.assignBatch([
        (ymd: '2026-11-25', shiftId: ShiftDef.leaveId, note: '進修假', remark: ''),
      ]);
      expect(store2.defs.containsKey(ShiftDef.leaveId), isTrue);
      expect(store2.assignments['2026-11-25']!.note, '進修假');
    });

    test('SA2 配置導出排除 __leave__，SR2 與 CSV 完整往返保留自訂假期名', () async {
      final store = await _makeStore();
      await store.assign('2026-11-10', 's06', note: 'A1');
      await store.assign('2026-11-24', ShiftDef.leaveId, note: '進修假');

      final exportedCfg = exportConfig(store);
      final shifts = exportedCfg['shifts'] as List;
      expect(
        shifts.any((s) => (s as Map)['id'] == ShiftDef.leaveId),
        isFalse,
      );
      final sa2 = exportConfigCode(store);
      final decodedCfg = decodeConfigText(sa2);
      expect(decodedCfg.crcVerified, isTrue);
      final cfgShifts = decodedCfg.data['shifts'] as List;
      expect(
        cfgShifts.any((s) => (s as Map)['id'] == ShiftDef.leaveId),
        isFalse,
      );

      final sr2 = exportRosterCode(store, month: DateTime(2026, 11));
      final targetStore = await _makeStore();
      final decodedRoster = decodeRosterText(sr2, targetStore.defs);
      expect(decodedRoster.importResult.errors, isEmpty);
      final leaveRow = decodedRoster.importResult.valid
          .firstWhere((r) => r.date == '2026-11-24');
      expect(leaveRow.shiftId, ShiftDef.leaveId);
      expect(leaveRow.venue, '進修假');

      final csvDecoded = decodeRosterText(
        '2026-11-26,假期,進修假',
        targetStore.defs,
      );
      expect(csvDecoded.importResult.errors, isEmpty);
      expect(csvDecoded.importResult.valid.single.shiftId, ShiftDef.leaveId);
      expect(csvDecoded.importResult.valid.single.venue, '進修假');
    });
  });

  group('假期類 UI 與統計隔離', () {
    testWidgets('ShiftPickerPanel 可選擇自訂假期、取消鬧鐘、並可切換回一般班次',
        (tester) async {
      final store = await _makeStore();
      final alarms = _TrackingAlarmService();

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SizedBox(
              height: 150,
              child: ShiftPickerPanel(
                initialDate: DateTime(2026, 11, 24),
                store: store,
                alarms: alarms,
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('假期'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '進修假');
      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();

      expect(store.assignments['2026-11-24']!.shiftId, ShiftDef.leaveId);
      expect(store.assignments['2026-11-24']!.note, '進修假');
      expect(alarms.unassignedYmds, contains('2026-11-24'));
      expect(find.text('進修假'), findsWidgets);

      // 由「進修假」（6 單位）切換為一般工作班次，不應受地點 4 單位校驗阻擋
      await tester.tap(find.text('早更'));
      await tester.pumpAndSettle();
      expect(store.assignments['2026-11-24']!.shiftId, 's06');
      expect(store.assignments['2026-11-24']!.note, isEmpty);
      expect(store.venues, isNot(contains('進修假')));
    });

    testWidgets('StatsScreen 不將假期類計入返工日數或地點分佈，且 320x2.0x 零溢出',
        (tester) async {
      final now = DateTime.now();
      final mm = now.month.toString().padLeft(2, '0');
      final store = await _makeStore();
      await store.assign('${now.year}-$mm-01', 's06', note: 'A1');
      await store.assign('${now.year}-$mm-02', ShiftDef.leaveId, note: '年假');
      await store.assign('${now.year}-$mm-03', ShiftDef.leaveId, note: '進修假');

      final errors = <FlutterErrorDetails>[];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(d);
      try {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: MaterialApp(
              theme: buildAppTheme(),
              home: StatsScreen(store: store),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('年假'), findsNothing);
        expect(find.text('進修假'), findsNothing);
        expect(find.text('6 小時'), findsOneWidget);
      } finally {
        FlutterError.onError = oldHandler;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
      expect(
        errors.where((e) => e.toString().contains('overflowed')),
        isEmpty,
      );
    });
  });
}
