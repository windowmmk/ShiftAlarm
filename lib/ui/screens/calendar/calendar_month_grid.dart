import 'dart:math' as math;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../../domain/shift_store.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/ocean_import_transition.dart';
import 'calendar_day_cell.dart';

/// 單月固定 6 週（42 格）網格，支援系統大字體自適應高度與導入波浪 3D 俯仰。
class CalendarMonthGrid extends StatelessWidget {
  final ShiftStore store;
  final int year;
  final int month;
  final double cellHeight;
  final DateTime selectedDate;
  final AnimationController cardFloatAnimCtrl;
  final AnimationController todayPulseCtrl;
  final void Function(DateTime date, bool isCurrentMonth) onSelectDate;

  const CalendarMonthGrid({
    super.key,
    required this.store,
    required this.year,
    required this.month,
    required this.cellHeight,
    required this.selectedDate,
    required this.cardFloatAnimCtrl,
    required this.todayPulseCtrl,
    required this.onSelectDate,
  });

  @override
  Widget build(BuildContext context) {
    assert(cellHeight > 0, '格高必須為正數（由 CalendarLayout 實算）');
    final t = context.tokens;
    final firstDay = DateTime(year, month, 1);
    final firstWeekday = firstDay.weekday % 7;
    final firstSunday = DateTime(year, month, 1 - firstWeekday);
    const weekCount = 6;
    final today = DateTime.now();

    final grid = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kOceanBandMaxWidth),
        child: Padding(
          // 垂直留白由外層日曆卡的 kOceanBandGap 提供，此處僅留水平內距以對齊 CalendarLayout.gridOverhead。
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              _weekHeader(t),
              const SizedBox(height: 4),
              for (int w = 0; w < weekCount; w++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(
                      children: [
                        for (int d = 0; d < 7; d++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(right: d < 6 ? 3.0 : 0),
                              child: OceanStaggeredCellTransition(
                                index: w * 7 + d,
                                controller: cardFloatAnimCtrl,
                                mode: OceanImportMode.tidalWave,
                                child: _buildCell(
                                  firstSunday,
                                  w,
                                  d,
                                  today,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (!cardFloatAnimCtrl.isAnimating) return grid;

    final tiltT = math.sin(cardFloatAnimCtrl.value * math.pi);
    final scaleVal = 1.0 - 0.015 * tiltT;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateX(0.08 * tiltT)
        ..translateByDouble(0.0, 6.0 * tiltT, 0.0, 1.0)
        ..scaleByDouble(scaleVal, scaleVal, 1.0, 1.0),
      child: grid,
    );
  }

  Widget _buildCell(DateTime firstSunday, int row, int col, DateTime today) {
    final date = DateTime(
      firstSunday.year,
      firstSunday.month,
      firstSunday.day + row * 7 + col,
    );
    final isCurrentMonth = date.year == year && date.month == month;
    return CalendarDayCell(
      store: store,
      date: date,
      today: today,
      selectedDate: selectedDate,
      activeYear: year,
      activeMonth: month,
      row: row,
      col: col,
      cardFloatAnimCtrl: cardFloatAnimCtrl,
      todayPulseCtrl: todayPulseCtrl,
      onTap: () => onSelectDate(date, isCurrentMonth),
    );
  }

  Widget _weekHeader(ShiftTokens t) {
    const names = ['日', '一', '二', '三', '四', '五', '六'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          for (int d = 0; d < 7; d++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: d < 6 ? 3.0 : 0),
                child: Center(
                  child: Text(
                    names[d],
                    style: TextStyle(
                      fontSize: t.fontCaption,
                      color: t.neutralFg2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
