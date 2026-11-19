// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../../domain/alarm_service.dart';
import '../../../domain/config_io.dart';
import '../../../domain/roster_io.dart';
import '../../../domain/shift_store.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/top_notification.dart';

/// 從網址 Query（`?c=` / `?r=`）或 Hash（`#c=` / `#r=`）提取分享口令。
({String? configCode, String? rosterCode}) extractUrlImportCodes(Uri uri) {
  String? configCode;
  String? rosterCode;

  final q = uri.queryParameters;
  if (q.containsKey('c') && q['c']!.isNotEmpty) {
    configCode = q['c'];
  } else if (q.containsKey('r') && q['r']!.isNotEmpty) {
    rosterCode = q['r'];
  }

  if (configCode == null && rosterCode == null) {
    final fragment = uri.fragment;
    if (fragment.isNotEmpty) {
      if (fragment.startsWith('c=')) {
        configCode = Uri.decodeComponent(fragment.substring(2));
      } else if (fragment.startsWith('r=')) {
        rosterCode = Uri.decodeComponent(fragment.substring(2));
      } else if (isConfigPacket(fragment)) {
        configCode = Uri.decodeComponent(fragment);
      } else if (isRosterPacket(fragment)) {
        rosterCode = Uri.decodeComponent(fragment);
      }
    }
  }

  return (configCode: configCode, rosterCode: rosterCode);
}

/// 彈窗確認並從網址導入班次與地點配置（`SA2:`）。
Future<void> promptUrlConfigImport({
  required BuildContext context,
  required ShiftStore store,
  required String code,
}) async {
  try {
    final p = previewConfig(code);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.link, color: ctx.tokens.brand),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                '網址配置導入',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('偵測到網址分享的班次與地點配置：'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ctx.tokens.neutralBg2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ctx.tokens.neutralStroke),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• 班次數量：${p.shifts} 個（${p.names.join('、')}）',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• 常用地點：${p.venues} 個',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '注意：導入後將覆蓋現有班次與地點設定。是否立即導入？',
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('取消', style: TextStyle(fontSize: 14)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text(
              '確定導入',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await importConfigText(store, code);
      if (context.mounted) {
        showTopNotification(context, '配置已成功導入！');
      }
    }
  } catch (e) {
    if (context.mounted) {
      showTopNotification(
        context,
        '網址配置解析失敗：$e',
        icon: Icons.error_outline,
        iconColor: const Color(0xFFF87171),
      );
    }
  }
}

/// 彈窗確認並從網址導入排班表（`SR2:`）。
Future<void> promptUrlRosterImport({
  required BuildContext context,
  required ShiftStore store,
  required AlarmService alarms,
  required String code,
  required void Function(List<String> dates) onImported,
}) async {
  try {
    final decoded = decodeRosterText(code, store.defs);
    if (decoded.importResult.valid.isEmpty) {
      if (context.mounted) {
        showTopNotification(
          context,
          decoded.importResult.errors.isNotEmpty
              ? decoded.importResult.errors.first
              : '排班資料無效',
          icon: Icons.error_outline,
          iconColor: const Color(0xFFF87171),
        );
      }
      return;
    }

    final count = decoded.importResult.valid.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.link, color: ctx.tokens.brand),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                '網址排班導入',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('偵測到網址分享的排班表（共 $count 天排班）：'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ctx.tokens.neutralBg2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ctx.tokens.neutralStroke),
              ),
              child: Text(
                '• 待導入排班天數：$count 天',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            const Text('是否將此排班表套用至日曆？', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('取消', style: TextStyle(fontSize: 14)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text(
              '套用排班',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await store.assignBatch([
        for (final r in decoded.importResult.valid)
          (ymd: r.date, shiftId: r.shiftId, note: r.venue, remark: r.remark),
      ]);
      if (isNativeAlarmSupported) {
        for (final r in decoded.importResult.valid) {
          final def = store.defs[r.shiftId];
          if (def == null) continue;
          try {
            final slot = const ShiftTokens().slotForTime(def.startTime);
            await alarms.onAssigned(
              r.date,
              def,
              accentBg: slot.bg.toARGB32(),
              accentFg: slot.fg.toARGB32(),
              note: r.venue,
            );
          } catch (_) {}
        }
      }
      if (context.mounted) {
        onImported([for (final r in decoded.importResult.valid) r.date]);
        showTopNotification(context, '成功導入 $count 天排班！');
      }
    }
  } catch (e) {
    if (context.mounted) {
      showTopNotification(
        context,
        '網址排班解析失敗：$e',
        icon: Icons.error_outline,
        iconColor: const Color(0xFFF87171),
      );
    }
  }
}
