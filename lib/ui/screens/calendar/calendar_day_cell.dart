// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/holidays.dart';
import '../../../domain/shift_store.dart';
import '../../../theme/app_theme.dart';

/// 120ms 堅實微觸感（微縮放 1.0 -> 0.965 -> 1.0）日曆格包裝元件。
class HapticCell extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const HapticCell({
    super.key,
    required this.child,
    required this.onTap,
  });

  @override
  State<HapticCell> createState() => _HapticCellState();
}

class _HapticCellState extends State<HapticCell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.965)
            .chain(CurveTween(curve: Curves.easeInQuad)),
        weight: 38,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.965, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 62,
      ),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap() {
    _ctrl.forward(from: 0.0);
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}

/// 單一日曆格：顯示日期、班次縮寫、地點短碼、公眾假期頂線與今日呼吸圈。
class CalendarDayCell extends StatelessWidget {
  final ShiftStore store;
  final DateTime date;
  final DateTime today;
  final DateTime selectedDate;
  final int activeYear;
  final int activeMonth;
  final int row;
  final int col;
  final AnimationController cardFloatAnimCtrl;
  final AnimationController todayPulseCtrl;
  final VoidCallback onTap;

  const CalendarDayCell({
    super.key,
    required this.store,
    required this.date,
    required this.today,
    required this.selectedDate,
    required this.activeYear,
    required this.activeMonth,
    required this.row,
    required this.col,
    required this.cardFloatAnimCtrl,
    required this.todayPulseCtrl,
    required this.onTap,
  });

  static (Color, Color) _surgeColorsFor(ShiftTokens t, ShiftDef? def) {
    if (def == null) return (t.brand, const Color(0xFFFDE047));
    final hour = int.tryParse(def.startTime.split(':').firstOrNull ?? '') ?? 12;
    if (hour >= 5 && hour < 11) {
      return (const Color(0xFFEA580C), const Color(0xFFFBBF24));
    }
    if (hour >= 11 && hour < 15) {
      return (const Color(0xFF0284C7), const Color(0xFF38BDF8));
    }
    if (hour >= 15 && hour < 21) {
      return (const Color(0xFFE11D48), const Color(0xFFF472B6));
    }
    return (const Color(0xFF6366F1), const Color(0xFF00F0FF));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final day = date.day;
    final key = ShiftStore.ymd(date);
    final assignment = store.assignments[key];
    final def = assignment != null ? store.defs[assignment.shiftId] : null;
    final note = assignment?.note ?? '';
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final isSelected = date.year == selectedDate.year &&
        date.month == selectedDate.month &&
        date.day == selectedDate.day;
    final isCurrentMonth =
        date.year == activeYear && date.month == activeMonth;
    final holiday = holidayName(date);

    final slot = def != null ? t.slotForTime(def.startTime) : null;
    final baseFg = slot?.fg ?? t.neutralFg;

    final Color cellBg;
    final Color borderColor;
    final Color dateColor;
    final Color abbrColor;
    final Color noteColor;

    if (isCurrentMonth) {
      cellBg = def != null
          ? slot!.bg.withValues(alpha: 0.88)
          : Colors.white.withValues(alpha: 0.84);
      borderColor = isSelected
          ? t.brand
          : (isToday
              ? t.brand.withValues(alpha: 0.85)
              : (slot?.border ?? t.neutralStroke).withValues(alpha: 0.65));
      dateColor = holiday != null ? t.danger : baseFg;
      abbrColor = baseFg;
      noteColor = baseFg;
    } else {
      cellBg = def != null
          ? slot!.bg.withValues(alpha: 0.40)
          : Colors.white.withValues(alpha: 0.35);
      borderColor = (slot?.border ?? t.neutralStroke).withValues(alpha: 0.30);
      dateColor = holiday != null
          ? t.danger.withValues(alpha: 0.52)
          : t.neutralFg.withValues(alpha: 0.42);
      abbrColor = (slot?.fg ?? t.neutralFg).withValues(alpha: 0.55);
      noteColor = (slot?.fg ?? t.neutralFg2).withValues(alpha: 0.48);
    }

    // 導入排班波浪式流光推進（自底排斜向上浮入）
    final bool isWaveSurging =
        cardFloatAnimCtrl.isAnimating && isCurrentMonth && def != null;
    double sheenT = 0.0;
    if (isWaveSurging) {
      final waveStart = (((5 - row) * 0.09 + col * 0.032)).clamp(0.0, 0.65);
      final waveEnd = (waveStart + 0.35).clamp(0.0, 1.0);
      final animVal = cardFloatAnimCtrl.value;
      if (animVal >= waveStart && animVal < waveEnd) {
        sheenT = ((animVal - waveStart) / (waveEnd - waveStart)).clamp(0.0, 1.0);
      }
    }

    final (shiftFxPrimary, shiftFxAccent) = _surgeColorsFor(t, def);

    BoxShadow? surgeGlowShadow;
    if (isWaveSurging && sheenT > 0.03 && sheenT < 0.97) {
      final pulse = (1.0 - (sheenT - 0.5).abs() * 2.0).clamp(0.0, 1.0);
      surgeGlowShadow = BoxShadow(
        color: shiftFxPrimary.withValues(alpha: 0.55 * pulse),
        blurRadius: 16.0 * pulse,
        spreadRadius: 1.5 * pulse,
        offset: Offset(0, 6.0 * pulse),
      );
    }

    Widget cell = Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: cellBg,
        border: Border.all(
          color: borderColor,
          width: (isSelected || isToday) ? 1.5 : 1.0,
        ),
        borderRadius: BorderRadius.circular(9),
        boxShadow: [?surgeGlowShadow],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 17.0,
                          fontWeight: FontWeight.w500,
                          color: dateColor,
                          height: 1.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: def != null
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              truncateAbbr(def.abbr),
                              style: TextStyle(
                                fontSize: 17.0,
                                fontWeight: FontWeight.w600,
                                color: abbrColor,
                                height: 1.0,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: (def != null && note.isNotEmpty)
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              truncateAbbr(note),
                              style: TextStyle(
                                fontSize: 17.0,
                                fontWeight: FontWeight.normal,
                                color: noteColor,
                                height: 1.0,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
          if (holiday != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 2.8,
              child: Container(
                decoration: BoxDecoration(
                  color: isCurrentMonth
                      ? t.danger
                      : t.danger.withValues(alpha: 0.50),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3.0),
                  ),
                ),
              ),
            ),
          if (isWaveSurging && sheenT > 0.01 && sheenT < 0.99)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Transform.translate(
                    offset: Offset((sheenT * 2.4 - 1.2) * 55.0, 0),
                    child: Transform.rotate(
                      angle: 0.22,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              shiftFxPrimary.withValues(alpha: 0.40),
                              shiftFxAccent.withValues(alpha: 0.60),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.40, 0.60, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    // 今日呼吸圈：僅包覆今日一格的外陰影，避免整個月曆隨 60fps 重建。
    if (isToday && isCurrentMonth) {
      final Widget baseCell = cell;
      cell = AnimatedBuilder(
        animation: todayPulseCtrl,
        child: baseCell,
        builder: (context, child) {
          final pulseVal = todayPulseCtrl.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: t.brand.withValues(alpha: 0.12 + 0.26 * pulseVal),
                  blurRadius: 4.0 + 3.0 * pulseVal,
                  spreadRadius: 0.5 + 1.2 * pulseVal,
                ),
              ],
            ),
            child: child,
          );
        },
      );
    }

    return HapticCell(onTap: onTap, child: cell);
  }
}
