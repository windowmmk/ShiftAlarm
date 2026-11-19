// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// 彈出年月快速跳轉選擇器；回傳所選 `(year, month)`，取消回 null。
Future<(int, int)?> showYearMonthPickerDialog(
  BuildContext context, {
  required int activeYear,
  required int activeMonth,
}) {
  int selectedYear = activeYear;
  return showDialog<(int, int)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final t = context.tokens;
        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => setDialogState(() => selectedYear--),
                icon: const Icon(Icons.chevron_left),
                tooltip: '上一年',
              ),
              Text(
                '$selectedYear年',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: t.neutralFg,
                ),
              ),
              IconButton(
                onPressed: () => setDialogState(() => selectedYear++),
                icon: const Icon(Icons.chevron_right),
                tooltip: '下一年',
              ),
            ],
          ),
          content: SizedBox(
            width: 280,
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.8,
              ),
              itemCount: 12,
              itemBuilder: (_, i) {
                final month = i + 1;
                final isCurrent =
                    selectedYear == activeYear && month == activeMonth;
                return InkWell(
                  onTap: () => Navigator.pop(ctx, (selectedYear, month)),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isCurrent ? t.brand : t.neutralBg2,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isCurrent ? t.brand : t.neutralStroke,
                      ),
                    ),
                    child: Text(
                      '$month月',
                      style: TextStyle(
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                        color: isCurrent ? Colors.white : t.neutralFg,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  '關閉',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
