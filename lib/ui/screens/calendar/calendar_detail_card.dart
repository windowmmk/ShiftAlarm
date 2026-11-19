// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../../domain/holidays.dart';
import '../../../domain/shift_store.dart';
import '../../../theme/app_theme.dart';

/// 日曆頁底部常駐詳情卡（第三區，高度固定由 `CalendarLayout` 控制）。
///
/// 與頂部天色帶、中間日曆卡共用最大寬度、邊框色與圓角視覺系統，
/// 並嚴格維持內部垂直開銷（margin 10 + padding 18 + border 2.4）對齊佈局測試防線。
class CalendarDetailCard extends StatelessWidget {
  final ShiftStore store;
  final DateTime selectedDate;
  final bool editingRemark;
  final TextEditingController remarkCtrl;
  final FocusNode remarkFocus;
  final VoidCallback onOpenPicker;
  final VoidCallback onStartRemarkEdit;
  final VoidCallback onSaveRemark;

  const CalendarDetailCard({
    super.key,
    required this.store,
    required this.selectedDate,
    required this.editingRemark,
    required this.remarkCtrl,
    required this.remarkFocus,
    required this.onOpenPicker,
    required this.onStartRemarkEdit,
    required this.onSaveRemark,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final key = ShiftStore.ymd(selectedDate);
    final assignment = store.assignments[key];
    final def = assignment != null ? store.defs[assignment.shiftId] : null;
    final note = assignment?.note ?? '';
    final remark = store.remarks[key] ?? '';
    final holiday = holidayName(selectedDate);
    const weekdays = ['日', '一', '二', '三', '四', '五', '六'];
    final weekdayName = weekdays[selectedDate.weekday % 7];
    final slot = def != null ? t.slotForTime(def.startTime) : null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kOceanBandMaxWidth),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          margin: const EdgeInsets.fromLTRB(kOceanBandInset, 4, kOceanBandInset, 6),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(kOceanBandRadius),
            border: Border.all(
              color: kCardStroke,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          // 永久防線：系統大字體或內容增高時自動可捲動，絕不 RenderFlex 溢出。
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDateHeaderRow(t, weekdayName, holiday),
                const SizedBox(height: 6),
                _buildShiftRow(t, def, slot, note),
                const SizedBox(height: 6),
                _buildRemarkRow(t, remark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateHeaderRow(
    ShiftTokens t,
    String weekdayName,
    String? holiday,
  ) {
    return Row(
      children: [
        Text(
          '${selectedDate.month}月${selectedDate.day}日',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: t.neutralFg,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '星期$weekdayName',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.normal,
            color: t.neutralFg2,
          ),
        ),
        if (holiday != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: t.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                holiday,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: t.danger,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildShiftRow(
    ShiftTokens t,
    ShiftDef? def,
    SlotColors? slot,
    String note,
  ) {
    return Row(
      children: [
        Expanded(
          child: def != null
              ? Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: slot?.bg ?? t.neutralBg,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: slot?.border ?? t.neutralStroke,
                        ),
                      ),
                      child: Text(
                        def.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: slot?.fg ?? t.neutralFg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${def.startTime}–${def.endTime}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                        color: t.neutralFg,
                      ),
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.location_on, size: 14, color: t.brand),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          note,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.normal,
                            color: t.brand,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                )
              : Text(
                  '未排班',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                    color: t.neutralFg2,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: onOpenPicker,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            minimumSize: const Size(0, 36),
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: const Icon(Icons.edit_calendar, size: 15),
          label: const Text(
            '排班',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildRemarkRow(ShiftTokens t, String remark) {
    if (editingRemark) {
      return SizedBox(
        height: 36,
        child: TextField(
          controller: remarkCtrl,
          focusNode: remarkFocus,
          maxLines: 1,
          maxLength: ShiftStore.maxRemarkLength,
          style: const TextStyle(fontSize: 12.5),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.90),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: t.brand, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            counterText: '',
            isDense: true,
            hintText: '新增備註…',
            prefixIcon:
                Icon(Icons.notes_rounded, size: 15, color: t.neutralFg2),
            suffixIcon: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.check, size: 16),
              onPressed: onSaveRemark,
            ),
          ),
          onEditingComplete: onSaveRemark,
        ),
      );
    }

    return InkWell(
      onTap: onStartRemarkEdit,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: t.neutralBg2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: t.neutralStroke.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.notes_rounded, size: 14, color: t.neutralFg2),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                remark.isEmpty ? '點擊新增備註…' : remark,
                style: TextStyle(
                  fontSize: 12,
                  color: remark.isEmpty ? t.neutralFg2 : t.neutralFg,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
