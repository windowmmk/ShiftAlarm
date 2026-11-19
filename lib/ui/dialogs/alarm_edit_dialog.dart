// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/alarm_service.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';

/// 新增／編輯單個鬧鐘彈窗；取消或校驗失敗回傳 null。
Future<ShiftAlarm?> showAlarmEditDialog(
  BuildContext context, {
  required String startTime,
  ShiftAlarm? src,
}) async {
  final labelCtrl = TextEditingController(text: src?.label ?? '');
  final minCtrl = TextEditingController(
    text: src == null ? '30' : src.offsetMinutes.abs().toString(),
  );
  bool isBefore = src == null ? true : src.offsetMinutes <= 0;
  bool notificationOnly = src?.notificationOnly ?? false;
  bool enabled = src?.enabled ?? true;

  try {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(src == null ? '新增鬧鐘' : '編輯鬧鐘'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: '名稱（如：開工鬧鐘／收工打卡）',
                    border: OutlineInputBorder(),
                  ),
                  maxLength: 12,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('提前')),
                        ButtonSegment(value: false, label: Text('延後')),
                      ],
                      selected: {isBefore},
                      onSelectionChanged: (s) => setD(() => isBefore = s.first),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: minCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setD(() {}),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: '分鐘',
                          border: OutlineInputBorder(),
                          suffixText: '分鐘',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '相對開工時間（延後可用作收工提示）',
                  style: TextStyle(fontSize: 12, color: ctx.tokens.neutralFg2),
                ),
                const SizedBox(height: 8),
                Builder(builder: (_) {
                  final mins = int.tryParse(minCtrl.text) ?? 0;
                  final off = isBefore ? -mins : mins;
                  final clock = AlarmService.alarmClockText(startTime, off);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: ctx.tokens.neutralBg2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '實際響鐘：$clock\n（開工 $startTime ${isBefore ? '提前' : '延後'} $mins 分鐘）',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('全鬧鐘')),
                    ButtonSegment(value: true, label: Text('只通知')),
                  ],
                  selected: {notificationOnly},
                  onSelectionChanged: (s) =>
                      setD(() => notificationOnly = s.first),
                ),
                const SizedBox(height: 4),
                Text(
                  '「只通知」僅發送通知，不響鬧鐘聲、不彈出全屏',
                  style: TextStyle(fontSize: 12, color: ctx.tokens.neutralFg2),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('啟用'),
                  value: enabled,
                  onChanged: (v) => setD(() => enabled = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('確定'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return null;
    final label = labelCtrl.text.trim();
    if (label.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('名稱不可為空')),
        );
      }
      return null;
    }
    final mins = int.tryParse(minCtrl.text.trim()) ?? -1;
    if (mins < 0 || mins > 24 * 60) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('分鐘請輸入 0–1440')),
        );
      }
      return null;
    }
    return ShiftAlarm(
      id: src?.id ?? 'a${DateTime.now().millisecondsSinceEpoch}',
      label: label,
      offsetMinutes: isBefore ? -mins : mins,
      notificationOnly: notificationOnly,
      enabled: enabled,
    );
  } finally {
    labelCtrl.dispose();
    minCtrl.dispose();
  }
}
