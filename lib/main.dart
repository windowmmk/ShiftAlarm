import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alarm/alarm_bridge.dart';
import 'domain/alarm_service.dart';
import 'domain/shift_store.dart';
import 'theme/app_theme.dart';
import 'ui/screens/home_screen.dart';

/// 排班鬧鐘 App（原型 v1）
/// 四更固定（00–06／06–12／12–18／18–00），月曆選更，到時經原生鬧鐘響。
/// 持久化：shared_preferences（drift 押後）；無網絡、無帳號。
/// Dart 層未捕捉異常寫入 crash_dart.log（上限 50 則），供權限頁「當機紀錄」查看。
Future<void> main() async {
  // Flutter 框架層錯誤：記 log 之後照原本咁呈現（唔吞）
  FlutterError.onError = (details) {
    _writeDartCrashLog(
        'FlutterError: ${details.exceptionAsString()}\n${details.stack}');
    FlutterError.presentError(details);
  };

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final store = ShiftStore(prefs);
    await store.load();

    final bridge = AlarmBridge();
    final alarms = AlarmService(bridge);

    // 啟動保險：將未響嘅更次鬧鐘交原生側重排（同 id 覆蓋）
    try {
      await alarms.syncOnLaunch(store);
    } catch (_) {
      // 原生橋未就緒都唔阻開 App
    }

    runApp(ShiftAlarmApp(store: store, alarms: alarms));
  }, (error, stack) {
    _writeDartCrashLog('Uncaught: $error\n$stack');
  });
}

/// Dart 層當機紀錄：append 去 crash_dart.log，最多留最後 50 則。
Future<void> _writeDartCrashLog(String text) async {
  if (kIsWeb) {
    debugPrint(text);
    return;
  }
  try {
    // 原生 filesDir（同 CrashApp.kt 寫 crash.log 同一目錄），經 MethodChannel 取
    final dirPath = await AlarmBridge().getFilesDir();
    final f = File('$dirPath/crash_dart.log');
    final ts = DateTime.now().toString().substring(0, 19);
    final entry = '[$ts] ${text.trim()}';
    String existing = '';
    if (await f.exists()) existing = await f.readAsString();
    final parts = <String>[];
    for (final chunk in existing.split('\n---\n')) {
      final t = chunk.trim();
      if (t.isNotEmpty) parts.add(t);
    }
    parts.add(entry);
    final kept =
        parts.length > 50 ? parts.sublist(parts.length - 50) : parts;
    await f.writeAsString('${kept.join('\n---\n')}\n---\n');
  } catch (_) {
    // 寫 log 失敗唔可以再拋
  }
}

class ShiftAlarmApp extends StatelessWidget {
  final ShiftStore store;
  final AlarmService alarms;

  const ShiftAlarmApp({super.key, required this.store, required this.alarms});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '排班鬧鐘',
      theme: buildAppTheme(),
      home: HomeScreen(store: store, alarms: alarms),
    );
  }
}
