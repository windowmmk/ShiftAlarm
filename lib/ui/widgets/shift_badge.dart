import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 更次 badge：pill 形，按開工時段上四色；右上角小點表示有鬧鐘。
class ShiftBadge extends StatelessWidget {
  final String label;
  final String timeRange;
  final String startTime; // "HH:mm"，用嚟決定時段色
  final bool hasAlarm;
  final double fontSize;
  final bool showAlarmIcon; // false → 唔畫鬧鐘 icon（日曆格改用右上角小點）

  const ShiftBadge({
    super.key,
    required this.label,
    required this.timeRange,
    required this.startTime,
    this.hasAlarm = false,
    this.fontSize = 11,
    this.showAlarmIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final slot = t.slotForTime(startTime);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: slot.bg,
        border: Border.all(color: slot.border, width: 1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: slot.fg,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isNativeAlarmSupported && hasAlarm && showAlarmIcon)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Icon(Icons.alarm, size: fontSize + 1, color: slot.fg),
            ),
        ],
      ),
    );
  }
}
