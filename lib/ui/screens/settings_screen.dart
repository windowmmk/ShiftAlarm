import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/alarm_service.dart';
import '../../domain/config_io.dart';
import '../../domain/csv_import.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';
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

  // ── CSV 導入 ──────────────────────────────────────
  // 格式：每行 YYYY-MM-DD,slot,venue，例如 2026-10-15,00-06,A1
  // slot 必須 match 到某個 ShiftDef 嘅時間範圍（HH-HH 或 HH:mm-HH:mm）

  static int _accentBg(ShiftDef def) =>
      const ShiftTokens().slotForTime(def.startTime).bg.toARGB32();
  static int _accentFg(ShiftDef def) =>
      const ShiftTokens().slotForTime(def.startTime).fg.toARGB32();

  Future<void> _openImport() async {
    final ctrl = TextEditingController();
    CsvImportResult? preview;
    var importing = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('導入排班（CSV）'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('每行：YYYY-MM-DD,代號,場所',
                      style: TextStyle(
                          fontSize: 12,
                          color: context.tokens.neutralFg2)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: ctrl,
                    maxLines: 8,
                    minLines: 4,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '貼上 CSV…',
                    ),
                    style: const TextStyle(
                        fontSize: 13, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {
                      setD(() => preview = parseRosterCsv(ctrl.text, widget.store.defs));
                    },
                    child: const Text('解析預覽'),
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: 8),
                    _buildImportPreview(preview!),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            FilledButton(
              onPressed: (preview == null ||
                      preview!.valid.isEmpty ||
                      importing)
                  ? null
                  : () async {
                      setD(() => importing = true);
                      final rows = preview!.valid;
                      // 批次寫入 store（一次性持久化，避免反覆全量寫入 SharedPreferences）
                      await widget.store.assignBatch([
                        for (final r in rows)
                          (
                            ymd: r.date,
                            shiftId: r.shiftId,
                            note: r.venue,
                            remark: r.remark
                          )
                      ]);
                      var done = 0;
                      for (final r in rows) {
                        final def = widget.store.defs[r.shiftId];
                        if (def == null) continue;
                        try {
                          await widget.alarms.onAssigned(
                            r.date,
                            def,
                            accentBg: _accentBg(def),
                            accentFg: _accentFg(def),
                            note: r.venue,
                          );
                          done++;
                        } catch (_) {}
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('導入完成：$done 日')),
                        );
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF424242),
                foregroundColor: Colors.white,
              ),
              child: Text(importing ? '導入緊…' : '確認導入'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  Widget _buildImportPreview(CsvImportResult r) {
    final t = context.tokens;
    final overwrite = r.valid
        .where((row) => widget.store.assignments.containsKey(row.date))
        .length;
    final dates = r.valid.map((e) => e.date).toList()..sort();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.neutralBg2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('有效 ${r.valid.length} 行',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (dates.isNotEmpty)
            Text('${dates.first} ～ ${dates.last}',
                style:
                    TextStyle(fontSize: 12, color: t.neutralFg2)),
          if (overwrite > 0)
            Text('其中 $overwrite 日已有排班，會被覆蓋',
                style: TextStyle(fontSize: 12, color: t.danger)),
          if (r.errors.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('跳過 ${r.errors.length} 行：',
                style: TextStyle(fontSize: 12, color: t.danger)),
            for (final e in r.errors.take(5))
              Text(e,
                  style: TextStyle(fontSize: 11, color: t.danger)),
            if (r.errors.length > 5)
              Text('…仲有 ${r.errors.length - 5} 行',
                  style: TextStyle(fontSize: 11, color: t.danger)),
          ],
        ],
      ),
    );
  }

  // ── 配置導出／導入 ──────────────────────────────
  // 班次定義＋場所清單，Base64 口令碼格式（相容 JSON）。重裝／換機導入即可還原。

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
              '包含 ${widget.store.defs.length} 個班次、${widget.store.venues.length} 個場所',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('關閉'),
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
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('再複製一次'),
          ),
        ],
      ),
    );
  }

  /// 導入配置：貼上 Base64 口令或 JSON → 預覽 → 確認寫入（清空現有班次／場所）。
  Future<void> _openConfigImport() async {
    final ctrl = TextEditingController();
    ({int shifts, int venues, List<String> names})? preview;
    String? error;
    var importing = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('導入配置口令'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '貼上之前導出的配置口令（亦相容 JSON 格式）。\n注意：會清空現有班次和場所！',
                    style: TextStyle(
                        fontSize: 12, color: context.tokens.neutralFg2),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: ctrl,
                    maxLines: 6,
                    minLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '貼上配置口令（SHIFTALARM:…）或 JSON…',
                    ),
                    style: const TextStyle(
                        fontSize: 11, fontFamily: 'monospace'),
                    onChanged: (_) {
                      setD(() {
                        error = null;
                        preview = null;
                        if (ctrl.text.trim().isEmpty) return;
                        try {
                          preview = previewConfig(ctrl.text);
                        } on ConfigImportException catch (e) {
                          error = e.message;
                        } catch (_) {
                          error = '口令格式無效';
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  if (error != null)
                    Text(error!,
                        style: TextStyle(
                            fontSize: 12,
                            color: context.tokens.danger)),
                  if (preview != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: context.tokens.neutralBg2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${preview!.shifts} 個班次、${preview!.venues} 個場所',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (preview!.names.isNotEmpty)
                            Text(
                              preview!.names.join('、'),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: context.tokens.neutralFg2),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            FilledButton(
              onPressed: (preview == null || importing)
                  ? null
                  : () async {
                      setD(() => importing = true);
                      try {
                        await importConfigText(
                            widget.store, ctrl.text);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '配置導入完成：${preview!.shifts} 個班次、'
                                '${preview!.venues} 個場所',
                              ),
                            ),
                          );
                        }
                      } on ConfigImportException catch (e) {
                        setD(() {
                          importing = false;
                          error = e.message;
                        });
                      } catch (e) {
                        setD(() {
                          importing = false;
                          error = '導入失敗：$e';
                        });
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF424242),
                foregroundColor: Colors.white,
              ),
              child: Text(importing ? '導入緊…' : '確認導入'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  void _openAbout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('關於'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('排班鬧鐘'),
            const SizedBox(height: 8),
            const Text(
              '為輪班人士設計嘅排班＋鬧鐘 App。本地排班、原生系統鬧鐘、純離線——無帳號、無網絡、無追蹤。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text('版本 3.0.0', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            const SelectableText(
              'https://github.com/windowmmk/ShiftAlarm',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
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
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('導入排班（CSV）'),
            subtitle: const Text('貼上 YYYY-MM-DD,代號,場所'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openImport,
          ),
          const Divider(height: 1),
          const _SectionHeader('配置'),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('導出配置口令'),
            subtitle: const Text('班次＋場所，一鍵複製口令碼'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _exportConfig,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('導入配置口令'),
            subtitle: const Text('貼上口令碼一秒還原'),
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
