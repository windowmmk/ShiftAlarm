// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../domain/config_io.dart';
import '../../domain/roster_io.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';

/// 顯示二維碼／分享連結切換彈窗。
Future<void> showQrShareDialog({
  required BuildContext context,
  required String title,
  required String code,
  required String shareUrl,
}) async {
  var isUrlMode = true;
  final messenger = ScaffoldMessenger.of(context);
  final fg2 = context.tokens.neutralFg2;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        final currentData = isUrlMode ? shareUrl : code;
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.qr_code_2, color: Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
                    onSelectionChanged: (s) => setD(() => isUrlMode = s.first),
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
                        ? '相機、微信或瀏覽器掃描後，打開網址即可一鍵套用'
                        : '供 App 內快速辨識讀取的分享口令',
                    style: TextStyle(fontSize: 12.5, color: fg2),
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
                  messenger.showSnackBar(
                    const SnackBar(content: Text('已複製分享網址連結！')),
                  );
                }
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              icon: const Icon(Icons.link, size: 16),
              label: const Text(
                '複製網址連結',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// 導出排班口令（`SR2:`）彈窗：支援切換當月／全部排班、自動複製與 QR 分享。
Future<void> showExportRosterDialog({
  required BuildContext context,
  required ShiftStore store,
}) async {
  final now = DateTime.now();
  final selectedMonth = DateTime(now.year, now.month, 1);
  var exportAll = false;
  final messenger = ScaffoldMessenger.of(context);

  final initialCode = exportRosterCode(store, month: selectedMonth);
  try {
    await Clipboard.setData(ClipboardData(text: initialCode));
  } catch (_) {}
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        final t = ctx.tokens;
        final code = exportRosterCode(
          store,
          month: exportAll ? null : selectedMonth,
        );
        final assignmentCount = exportAll
            ? store.assignments.length
            : store.assignments.keys.where((k) {
                final p =
                    '${selectedMonth.year.toString().padLeft(4, '0')}-${selectedMonth.month.toString().padLeft(2, '0')}';
                return k.startsWith(p);
              }).length;

        void switchScope(bool all) {
          setD(() => exportAll = all);
          final updated = exportRosterCode(
            store,
            month: all ? null : selectedMonth,
          );
          Clipboard.setData(ClipboardData(text: updated));
        }

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
                            '${selectedMonth.year}年${selectedMonth.month}月',
                          ),
                          selected: !exportAll,
                          onSelected: (val) {
                            if (val) switchScope(false);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('全部排班'),
                          selected: exportAll,
                          onSelected: (val) {
                            if (val) switchScope(true);
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
                        const Icon(
                          Icons.check_circle,
                          size: 16,
                          color: Color(0xFF2E7D32),
                        ),
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
                    '發送給同事或換新手機貼上，即可一秒還原排班：',
                    style: TextStyle(fontSize: 13, color: t.neutralFg),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: t.neutralBg2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: t.neutralStroke),
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
                final url = 'https://windowmmk.github.io/ShiftAlarm/?r=$code';
                showQrShareDialog(
                  context: ctx,
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
              label: const Text(
                '二維碼 / 連結',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (ctx.mounted) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('已再次複製排班口令到剪貼簿')),
                  );
                }
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                backgroundColor: t.brand,
              ),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text(
                '複製口令',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// 導出配置口令（`SA2:`）彈窗：自動複製並提供二維碼／連結分享。
Future<void> showExportConfigDialog({
  required BuildContext context,
  required ShiftStore store,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final code = exportConfigCode(store);
  try {
    await Clipboard.setData(ClipboardData(text: code));
  } catch (_) {}
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final t = ctx.tokens;
      return AlertDialog(
        title: const Text('導出配置口令'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '口令已自動複製到剪貼簿！可直接貼到備忘錄或發送給同事：',
              style: TextStyle(fontSize: 13, color: t.neutralFg2),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.neutralBg2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.neutralStroke),
              ),
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: SelectableText(
                  code,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '包含 ${store.defs.length} 個班次、${store.venues.length} 個地點',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
              final url = 'https://windowmmk.github.io/ShiftAlarm/?c=$code';
              showQrShareDialog(
                context: ctx,
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
            label: const Text(
              '二維碼 / 連結',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (ctx.mounted) {
                messenger.showSnackBar(
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
              backgroundColor: t.brand,
            ),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text(
              '複製口令',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    },
  );
}
