// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../domain/alarm_service.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';
import '../dialogs/about_dialog.dart';
import '../dialogs/share_export_dialogs.dart';
import '../dialogs/unified_import_dialog.dart';
import 'permission_check_screen.dart';

/// 設定頁：本機權限自檢與鬧鐘測試、排班／配置口令分享導入與應用程式關於資訊。
class SettingsScreen extends StatefulWidget {
  final ShiftStore store;
  final AlarmService alarms;

  const SettingsScreen({super.key, required this.store, required this.alarms});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _testAlarm() async {
    final choice = await showDialog<Duration>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('測試鬧鐘'),
        content: const Text('要於多久之後響起？'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const Duration(seconds: 15)),
            child: const Text('15 秒後響'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, const Duration(minutes: 1)),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF424242),
              foregroundColor: Colors.white,
            ),
            child: const Text('1 分鐘後響'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final label = choice.inSeconds < 60 ? '15 秒' : '1 分鐘';
    try {
      final triggerAt = DateTime.now().add(choice);
      await widget.alarms.bridge.schedule(
        id: 99999999,
        triggerAtMillis: triggerAt.millisecondsSinceEpoch,
        title: '排班鬧鐘',
        body: '測試鬧鐘：$label後響',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('測試鬧鐘已排程：$label後響，可鎖定螢幕測試')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('排程失敗：$e')));
      }
    }
  }

  Future<void> _testGentle() async {
    try {
      final triggerAt = DateTime.now().add(const Duration(seconds: 15));
      await widget.alarms.bridge.scheduleGentle(
        id: 99999998,
        triggerAtMillis: triggerAt.millisecondsSinceEpoch,
        title: '排班鬧鐘',
        body: '測試只通知：15 秒後彈出',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已排程只通知測試：15 秒後彈出，可鎖定螢幕測試')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('排程失敗：$e')));
      }
    }
  }

  Future<void> _openImport() async {
    await showUnifiedImportDialog(
      context: context,
      store: widget.store,
      alarms: widget.alarms,
      onImportDone: ([_]) => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: kCalendarPageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('設定'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            children: [
              if (isNativeAlarmSupported) ...[
                const _SectionHeader('本機與鬧鐘'),
                _SettingsGroupCard(
                  children: [
                    ListTile(
                      leading: Icon(Icons.shield_outlined, color: t.brand),
                      title: const Text('權限檢查'),
                      subtitle: const Text('鬧鐘／通知／電池／全屏權限自檢'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PermissionCheckScreen(
                              bridge: widget.alarms.bridge,
                              alarms: widget.alarms,
                              store: widget.store,
                            ),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.alarm_add, color: t.neutralFg2),
                      title: const Text('測試鬧鐘'),
                      subtitle: const Text('15 秒或 1 分鐘後響'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _testAlarm,
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.notifications_outlined,
                        color: t.neutralFg2,
                      ),
                      title: const Text('測試只通知'),
                      subtitle: const Text('15 秒後彈出通知（不響鬧鐘）'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _testGentle,
                    ),
                  ],
                ),
              ],
              const _SectionHeader('排班表'),
              _SettingsGroupCard(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.calendar_month_outlined,
                      color: t.brand,
                    ),
                    title: const Text('導出排班口令'),
                    subtitle: const Text('當月或全部排班，一鍵複製 SR2: 極簡口令'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showExportRosterDialog(
                      context: context,
                      store: widget.store,
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.upload_outlined, color: t.neutralFg2),
                    title: const Text('導入排班（口令 / CSV）'),
                    subtitle: const Text('支援 SR2: 口令碼或純 CSV 文字'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openImport,
                  ),
                ],
              ),
              const _SectionHeader('配置'),
              _SettingsGroupCard(
                children: [
                  ListTile(
                    leading: Icon(Icons.key_outlined, color: t.brand),
                    title: const Text('導出配置口令'),
                    subtitle: const Text('班次＋地點，一鍵複製 SA2: 口令碼'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showExportConfigDialog(
                      context: context,
                      store: widget.store,
                    ),
                  ),
                  ListTile(
                    leading:
                        Icon(Icons.file_upload_outlined, color: t.neutralFg2),
                    title: const Text('導入配置口令'),
                    subtitle: const Text('貼上 SA2: 口令碼一秒還原'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openImport,
                  ),
                ],
              ),
              const _SectionHeader('應用程式'),
              _SettingsGroupCard(
                children: [
                  ListTile(
                    leading: Icon(Icons.info_outlined, color: t.neutralFg2),
                    title: const Text('關於'),
                    subtitle: const Text('版本資訊與隱私承諾'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showShiftAlarmAboutDialog(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 設定頁分組圓角卡片（白底＋霧灰描邊＋組內分隔線）。
class _SettingsGroupCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCardStroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 52,
                color: kCardStroke.withValues(alpha: 0.65),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 設定頁分區小標題。
class _SectionHeader extends StatelessWidget {
  final String text;

  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.tokens.neutralFg2,
        ),
      ),
    );
  }
}
