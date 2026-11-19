// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../config.dart';
import '../../theme/app_theme.dart';

/// 顯示「關於 ShiftAlarm」資訊彈窗（支援大字體捲動與 320px 窄屏無溢出）。
void showShiftAlarmAboutDialog(BuildContext context) {
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
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ShiftAlarm 排班鬧鐘',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: t.neutralFg,
                  ),
                ),
                Text(
                  kAppVersionDisplay,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: t.neutralFg2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
        ),
        child: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
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
                  '專為輪班人士量身打造的極致隱私排班日曆與精確鬧鐘。極簡現代排版，原生底層鬧鐘喚醒，支援極簡二進制口令協議。',
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
                          Flexible(
                            child: Text(
                              '開源程式碼庫 (GitHub)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: t.neutralFg,
                              ),
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
            child: const Text(
              '知道了',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    ),
  );
}
