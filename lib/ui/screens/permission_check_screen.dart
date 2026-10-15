import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../alarm/alarm_bridge.dart';
import '../../domain/alarm_service.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';

/// 權限自檢清單（MIUI 保命清單）：逐項檢測＋「去開啟」。
class PermissionCheckScreen extends StatefulWidget {
  final AlarmBridge bridge;
  final AlarmService? alarms; // AlarmService（當機後重新排程用）
  final ShiftStore? store; // ShiftStore

  const PermissionCheckScreen(
      {super.key, required this.bridge, this.alarms, this.store});

  @override
  State<PermissionCheckScreen> createState() => _PermissionCheckScreenState();
}

class _PermItem {
  final String title;
  final String desc;
  final Future<bool> Function()? check; // null = 唔能檢測，純指引
  final Future<void> Function() action;
  final String actionLabel;
  /// 人手指引步驟（null＝唔顯示）
  final List<String>? steps;
  /// 手動確認嘅 SharedPreferences key（null＝唔支援手動確認）
  final String? manualConfirmKey;
  bool? ok;
  bool checking = true;
  bool manualOk = false;

  _PermItem({
    required this.title,
    required this.desc,
    this.check,
    required this.action,
    required this.actionLabel,
    this.steps,
    this.manualConfirmKey,
  });
}

class _PermissionCheckScreenState extends State<PermissionCheckScreen> {
  late final List<_PermItem> _items;
  List<String> _crashEntries = [];
  bool _crashLoaded = false;

  @override
  void initState() {
    super.initState();
    final b = widget.bridge;
    _items = [
      _PermItem(
        title: '精確鬧鐘',
        desc: '冇佢鬧鐘唔會準時響。',
        check: b.canScheduleExactAlarms,
        action: b.requestExactAlarmPermission,
        actionLabel: '去開啟',
      ),
      _PermItem(
        title: '通知權限',
        desc: '鬧鐘靠高優先級通知彈出。',
        check: b.areNotificationsEnabled,
        action: b.openNotificationSettings,
        actionLabel: '去開啟',
      ),
      _PermItem(
        title: '通知設置',
        desc: '開系統通知設置：懸浮通知／聲音／鎖屏顯示／各 Channel。',
        check: null,
        action: b.openNotificationSettings,
        actionLabel: '去設置',
      ),
      _PermItem(
        title: '全屏通知',
        desc: '允許通知強制彈全屏，熄屏都睇到。',
        check: b.canUseFullScreenIntent,
        action: b.openFullScreenIntentSettings,
        actionLabel: '去開啟',
      ),
      _PermItem(
        title: '電池無限制',
        desc: '唔畀系統為慳電殺掉鬧鐘。',
        check: b.isIgnoringBatteryOptimizations,
        action: b.requestIgnoreBatteryOptimizations,
        actionLabel: '去開啟',
      ),
      _PermItem(
        title: '背景彈出視窗',
        desc: 'MIUI「在背景執行時顯示彈出視窗」，熄屏彈窗用。',
        check: b.canDrawOverlays,
        action: b.openOverlaySettings,
        actionLabel: '去開啟',
      ),
      _PermItem(
        title: '鎖定螢幕通知顯示',
        desc: 'MIUI 呢項系統檢測唔到，要人手開。開咗熄屏先睇到鬧鐘全屏彈窗。',
        check: null,
        action: b.openAppDetailsSettings,
        actionLabel: '去應用詳情',
        steps: const [
          '開啟手機「設置」',
          '進入本 App「應用詳情」',
          '進入「通知管理」',
          '「鎖定螢幕通知顯示」選「允許」',
        ],
        manualConfirmKey: 'perm_confirmed_lockscreen_notify',
      ),
      _PermItem(
        title: '自啟動',
        desc: '應用詳情 → 自啟動 → 開啟。系統檢測唔到，要人手開。',
        check: null,
        action: b.openAppDetailsSettings,
        actionLabel: '去應用詳情',
      ),
      _PermItem(
        title: '鎖定喺最近任務',
        desc: '喺多工畫面將排班鬧鐘卡片上滑鎖定，唔好畀一鍵清理殺掉。',
        check: null,
        action: b.openAppDetailsSettings,
        actionLabel: '去應用詳情',
      ),
    ];
    _checkAll();
    _loadCrashLogs();
    _loadManualConfirms();
  }

  /// 讀返用戶手動確認過嘅權限項（SharedPreferences）。
  Future<void> _loadManualConfirms() async {
    final prefs = await SharedPreferences.getInstance();
    var changed = false;
    for (final item in _items) {
      final k = item.manualConfirmKey;
      if (k != null && prefs.getBool(k) == true && !item.manualOk) {
        item.manualOk = true;
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  /// 用戶㩒「我已開啟」：記住，下次開 App 唔使再㩒。
  Future<void> _confirmManual(_PermItem item) async {
    final k = item.manualConfirmKey;
    if (k == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(k, true);
    if (mounted) {
      setState(() => item.manualOk = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已記住，唔使再㩒')),
      );
    }
  }

  /// 讀兩個當機紀錄檔（原生 crash.log＋Dart crash_dart.log），最新置頂。
  Future<void> _loadCrashLogs() async {
    final out = <String>[];
    try {
      final dirPath = await widget.bridge.getFilesDir();
      for (final name in const ['crash.log', 'crash_dart.log']) {
        final f = File('$dirPath/$name');
        if (await f.exists()) {
          final text = await f.readAsString();
          final parts = <String>[];
          for (final chunk in text.split('\n---\n')) {
            final t = chunk.trim();
            if (t.isNotEmpty) parts.add(t);
          }
          for (final p in parts.reversed) {
            out.add('[$name]\n$p');
          }
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _crashEntries = out;
        _crashLoaded = true;
      });
    }
  }

  /// 當機後回收：重新排程所有未來鬧鐘（經 AlarmService.syncOnLaunch）。
  Future<void> _rescheduleAfterCrash() async {
    final alarms = widget.alarms;
    final store = widget.store;
    if (alarms == null || store == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法重排（缺少服務）')),
        );
      }
      return;
    }
    try {
      await alarms.syncOnLaunch(store);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已重新排程所有未來鬧鐘')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('重排失敗：$e')));
      }
    }
  }

  Future<void> _clearCrashLogs() async {    try {
      final dirPath = await widget.bridge.getFilesDir();
      for (final name in const ['crash.log', 'crash_dart.log']) {
        final f = File('$dirPath/$name');
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _crashEntries = [];
        _crashLoaded = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('當機紀錄已清除')),
      );
    }
  }

  Future<void> _checkAll() async {
    for (final item in _items) {
      if (item.check == null) {
        item.checking = false;
        continue;
      }
      try {
        item.ok = await item.check!();
      } catch (_) {
        item.ok = null;
      }
      item.checking = false;
      if (mounted) setState(() {});
    }
    if (mounted) setState(() {});
  }

  Future<void> _open(_PermItem item) async {
    try {
      await item.action();
    } catch (_) {}
    // 返嚟後重檢
    await Future.delayed(const Duration(milliseconds: 500));
    if (item.check != null) {
      try {
        item.ok = await item.check!();
      } catch (_) {}
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final okCount = _items.where((e) => e.ok == true).length;
    final checkable = _items.where((e) => e.check != null).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('權限自檢'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新檢測',
            onPressed: () {
              for (final e in _items) {
                e.checking = true;
                e.ok = null;
              }
              setState(() {});
              _checkAll();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: const Color(0xFFEBF3FA),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '已開 $okCount／$checkable 項可檢測權限。鬧鐘要準時響，尤其係熄屏，下面幾項最好全開。',
                style:
                    TextStyle(fontSize: t.fontBody, color: t.neutralFg),
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final item in _items) _row(t, item),
          const SizedBox(height: 8),
          _crashLogSection(t),
        ],
      ),
    );
  }

  /// 當機紀錄區塊：讀 crash.log＋crash_dart.log，最新置頂，monospace 可捲動。
  Widget _crashLogSection(ShiftTokens t) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('當機紀錄',
                    style: TextStyle(
                        fontSize: t.fontBody, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text('原生＋Dart 未捕捉異常',
                    style: TextStyle(
                        fontSize: t.fontCaption, color: t.neutralFg2)),
                const Spacer(),
                TextButton(
                  onPressed: _rescheduleAfterCrash,
                  child: const Text('重新排程'),
                ),
                TextButton(
                  onPressed: _clearCrashLogs,
                  child: const Text('清除'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_crashLoaded)
              Text('載入緊…',
                  style:
                      TextStyle(fontSize: t.fontCaption, color: t.neutralFg2))
            else if (_crashEntries.isEmpty)
              Text('暫無當機紀錄',
                  style:
                      TextStyle(fontSize: t.fontCaption, color: t.neutralFg2))
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 320),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: t.neutralBg2,
                  border: Border.all(color: t.neutralStroke),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _crashEntries.join('\n\n'),
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11, height: 1.4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(ShiftTokens t, _PermItem item) {
    final IconData icon;
    final Color iconColor;
    final String status;
    if (item.check == null && item.manualOk) {
      icon = Icons.check_circle;
      iconColor = const Color(0xFF166534);
      status = '已確認';
    } else if (item.check == null) {
      icon = Icons.info_outline;
      iconColor = t.brand;
      status = '人手開啟';
    } else if (item.checking) {
      icon = Icons.hourglass_empty;
      iconColor = t.neutralFg2;
      status = '檢測緊…';
    } else if (item.ok == true) {
      icon = Icons.check_circle;
      iconColor = const Color(0xFF166534);
      status = '已開';
    } else {
      icon = Icons.error_outline;
      iconColor = const Color(0xFFBC4B09);
      status = '未開';
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(item.title,
                          style: TextStyle(
                              fontSize: t.fontBody,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: item.check == null
                              ? (item.manualOk
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFEBF3FA))
                              : (item.ok == true
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFFFF9F5)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(status,
                            style: TextStyle(
                                fontSize: t.fontCaption,
                                color: t.neutralFg2)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(item.desc,
                      style: TextStyle(
                          fontSize: t.fontCaption, color: t.neutralFg2)),
                  if (item.steps != null) ...[
                    const SizedBox(height: 6),
                    for (var i = 0; i < item.steps!.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('${i + 1}. ${item.steps![i]}',
                            style: TextStyle(
                                fontSize: t.fontCaption,
                                color: t.neutralFg)),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.tonal(
                  onPressed: () => _open(item),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE0E0E0),
                    foregroundColor: const Color(0xFF424242),
                  ),
                  child: Text(item.actionLabel),
                ),
                if (item.manualConfirmKey != null && !item.manualOk)
                  TextButton(
                    onPressed: () => _confirmManual(item),
                    child: const Text('我已開啟'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
