import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../domain/alarm_service.dart';
import '../../domain/config_io.dart';
import '../../domain/csv_import.dart';
import '../../domain/roster_io.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';
import '../dialogs/unified_import_dialog.dart';
import 'permission_check_screen.dart';

/// 設置 tab：權限檢查／測試鬧鐘／CSV 導入／關於。
class SettingsScreen extends StatefulWidget {
  final ShiftStore store;
  final AlarmService alarms;

  const SettingsScreen({super.key, required this.store, required this.alarms});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {

  // ── 測試鬧鐘 ──────────────────────────────────────
  // 彈選擇（15 秒／1 分鐘），經 alarm_bridge 排測試鬧鐘。
  // 固定 id 99999999，同日期派生嘅更次鬧鐘 id（YYYYMMDD）唔會撞。
  Future<void> _testAlarm() async {
    final choice = await showDialog<Duration>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('測試鬧鐘'),
        content: const Text('幾耐之後響？'),
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
          SnackBar(content: Text('測試鬧鐘已排：$label後響，試下鎖屏等佢')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('排程失敗：$e')));
      }
    }
  }

  /// 測試「只通知」：15 秒後經 scheduleGentle 彈通知（唔響鬧鐘）。
  /// 固定 id 99999998，同測試鬧鐘（99999999）唔撞。
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
          const SnackBar(content: Text('已排只通知測試：15 秒後彈，試下鎖屏等佢')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('排程失敗：$e')));
      }
    }
  }

  // ── 排班表導出／導入 ──────────────────────────────
  // 支援 Base58 口令碼（包含魔數、CRC32、長度與天數驗證）與傳統 CSV 雙模相容。

  static int _accentBg(ShiftDef def) =>
      const ShiftTokens().slotForTime(def.startTime).bg.toARGB32();
  static int _accentFg(ShiftDef def) =>
      const ShiftTokens().slotForTime(def.startTime).fg.toARGB32();

  Future<void> _showQrDialog({
    required BuildContext parentContext,
    required String title,
    required String code,
    required String shareUrl,
  }) async {
    var isUrlMode = true;

    await showDialog<void>(
      context: parentContext,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final currentData = isUrlMode ? shareUrl : code;
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.qr_code_2, color: Color(0xFF2E7D32)),
                const SizedBox(width: 8),
                Text(title),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          label: Text('網址連結'),
                          icon: Icon(Icons.link, size: 16),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text('純口令碼'),
                          icon: Icon(Icons.key, size: 16),
                        ),
                      ],
                      selected: {isUrlMode},
                      onSelectionChanged: (s) =>
                          setD(() => isUrlMode = s.first),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: QrImageView(
                        data: currentData,
                        version: QrVersions.auto,
                        size: 200.0,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isUrlMode
                          ? '相機、微信或瀏覽器掃描後，打開網址可一鍵套用'
                          : '供 App 內快速辨識讀取的分享口令',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: parentContext.tokens.neutralFg2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('關閉', style: TextStyle(fontSize: 14)),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: shareUrl));
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      const SnackBar(content: Text('已複製分享網址連結！')),
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                icon: const Icon(Icons.link, size: 16),
                label: const Text('複製網址連結',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportRoster() async {
    final now = DateTime.now();
    DateTime? selectedMonth = DateTime(now.year, now.month, 1);
    var exportAll = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final code = exportRosterCode(
            widget.store,
            month: exportAll ? null : selectedMonth,
          );
          final byteLen = utf8.encode(code).length;
          final assignmentCount = exportAll
              ? widget.store.assignments.length
              : widget.store.assignments.keys.where((k) {
                  final p =
                      '${selectedMonth!.year.toString().padLeft(4, '0')}-${selectedMonth!.month.toString().padLeft(2, '0')}';
                  return k.startsWith(p);
                }).length;

          return AlertDialog(
            title: const Text('導出排班口令'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: Text(
                                '${selectedMonth!.year}年${selectedMonth!.month}月'),
                            selected: !exportAll,
                            onSelected: (val) {
                              if (val) setD(() => exportAll = false);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('全部排班'),
                            selected: exportAll,
                            onSelected: (val) {
                              if (val) setD(() => exportAll = true);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFA5D6A7)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              size: 16, color: Color(0xFF2E7D32)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '包含 $assignmentCount 日排班，已自動複製到剪貼簿！',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF2E7D32),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '發給同事或換新手機貼上，即可一秒還原排班：',
                      style: TextStyle(
                          fontSize: 13, color: context.tokens.neutralFg),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: context.tokens.neutralBg2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.tokens.neutralStroke),
                      ),
                      child: SelectableText(
                        code,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(64, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: const Text('關閉', style: TextStyle(fontSize: 13.5)),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  final url =
                      'https://windowmmk.github.io/ShiftAlarm/?r=$code';
                  _showQrDialog(
                    parentContext: context,
                    title: '排班分享二維碼',
                    code: code,
                    shareUrl: url,
                  );
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.qr_code, size: 16),
                label: const Text('二維碼 / 連結',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已再次複製排班口令到剪貼簿')),
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  backgroundColor: context.tokens.brand,
                ),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('複製口令',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openImport() async {
    await showUnifiedImportDialog(
      context: context,
      store: widget.store,
      alarms: widget.alarms,
      onImportDone: () => setState(() {}),
    );
  }

  // ── 配置導出／導入 ──────────────────────────────
  // 班次定義＋地點清單，Base64 口令碼格式（相容 JSON）。重裝／換機導入即可還原。

  /// 導出配置：生成 Base64 口令碼，彈窗展示並複製到剪貼簿。
  Future<void> _exportConfig() async {
    final code = exportConfigCode(widget.store);
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('導出配置口令'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '口令已自動複製到剪貼簿！可直接貼到備忘錄或發送給同事：',
              style: TextStyle(
                  fontSize: 13, color: context.tokens.neutralFg2),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.tokens.neutralBg2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.tokens.neutralStroke),
              ),
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: SelectableText(
                  code,
                  style: const TextStyle(
                      fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '包含 ${widget.store.defs.length} 個班次、${widget.store.venues.length} 個地點',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(64, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: const Text('關閉', style: TextStyle(fontSize: 13.5)),
          ),
          OutlinedButton.icon(
            onPressed: () {
              final url =
                  'https://windowmmk.github.io/ShiftAlarm/?c=$code';
              _showQrDialog(
                parentContext: context,
                title: '配置分享二維碼',
                code: code,
                shareUrl: url,
              );
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.qr_code, size: 16),
            label: const Text('二維碼 / 連結',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('配置口令已重新複製到剪貼簿！'),
                    duration: Duration(seconds: 2),
                  ),
                );
                Navigator.pop(ctx);
              }
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              backgroundColor: context.tokens.brand,
            ),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('複製口令',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// 導入配置：呼叫統一導入彈窗（自動辨識 SA2 口令並校驗 CRC32）。
  Future<void> _openConfigImport() async {
    await showUnifiedImportDialog(
      context: context,
      store: widget.store,
      alarms: widget.alarms,
      onImportDone: () => setState(() {}),
    );
  }

  void _openAbout() {
    final t = context.tokens;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: t.brand,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'S',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ShiftAlarm 排班鬧鐘',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: t.neutralFg,
                  ),
                ),
                Text(
                  '版本 3.3.6 (Build 22)',
                  style: TextStyle(
                    fontSize: 12,
                    color: t.neutralFg2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F1FC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFB6D3F9)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 16, color: t.brand),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '100% 純離線 · 零網絡權限 · 零追蹤',
                        style: TextStyle(
                          fontSize: 12,
                          color: t.brand,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '專為輪班人士量身打造的極致隱私排班日曆與精確鬧鐘。瑞士精密工藝排版，原生底層鬧鐘喚醒，支援極簡二進制口令協議。',
                style: TextStyle(
                  fontSize: 13,
                  color: t.neutralFg,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: t.neutralBg2,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: t.neutralStroke),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.code, size: 15, color: t.neutralFg2),
                        const SizedBox(width: 6),
                        Text(
                          '開源代碼庫 (GitHub)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: t.neutralFg,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      'https://github.com/windowmmk/ShiftAlarm',
                      style: TextStyle(
                        fontSize: 12,
                        color: t.brand,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                backgroundColor: t.brand,
                foregroundColor: Colors.white,
              ),
              child: const Text('知道了',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設置')),
      body: ListView(
        children: [
          if (isNativeAlarmSupported) ...[
            const _SectionHeader('本機'),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('權限檢查'),
              subtitle: const Text('鬧鐘／通知／電池／全屏權限自檢'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PermissionCheckScreen(
                          bridge: widget.alarms.bridge,
                          alarms: widget.alarms,
                          store: widget.store,
                        ),
                  ),
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.alarm_add),
              title: const Text('測試鬧鐘'),
              subtitle: const Text('15 秒或 1 分鐘後響'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _testAlarm,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('測試只通知'),
              subtitle: const Text('15 秒後彈通知（唔響鬧鐘）'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _testGentle,
            ),
            const Divider(height: 1),
          ],
          const _SectionHeader('排班表'),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('導出排班口令'),
            subtitle: const Text('當月或全部排班，一鍵複製 SR2: 極簡口令'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _exportRoster,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('導入排班（口令 / CSV）'),
            subtitle: const Text('支援 SR2: 口令碼或純 CSV 文字'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openImport,
          ),
          const Divider(height: 1),
          const _SectionHeader('配置'),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('導出配置口令'),
            subtitle: const Text('班次＋地點，一鍵複製 SA2: 口令碼'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _exportConfig,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('導入配置口令'),
            subtitle: const Text('貼上 SA2: 口令碼一秒還原'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openConfigImport,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.info_outlined),
            title: const Text('關於'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openAbout,
          ),
        ],
      ),
    );
  }
}

/// 設置頁分區小標題
class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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
