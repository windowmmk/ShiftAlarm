import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/alarm_service.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';
import '../widgets/top_notification.dart';

/// 緊湊型自適應排班操作列（Shift Toolbar Dock）：
/// 擺在日曆下方，高度適中，絕不擠壓日曆空間，保證日曆 5~6 行 100% 完整可見。
/// - 頂部：日期標籤（可切換上一日／下一日）、當日班次時間與地點兩行高展示、完成關閉按鈕。
/// - 底部：各班次按鈕橫排一字展示（點更即排，自動保存），附帶清除排班（垃圾桶圖示）按鈕。
class ShiftPickerPanel extends StatefulWidget {
  final DateTime initialDate;
  final ShiftStore store;
  final AlarmService alarms;
  final VoidCallback onClose;

  const ShiftPickerPanel({
    super.key,
    required this.initialDate,
    required this.store,
    required this.alarms,
    required this.onClose,
  });

  @override
  State<ShiftPickerPanel> createState() => ShiftPickerPanelState();
}

class ShiftPickerPanelState extends State<ShiftPickerPanel> {
  bool _saving = false;
  bool _dirty = false;

  /// 當前編輯中的日期（上一日／下一日／點擊日曆格切換）
  late DateTime _currentDate;

  late final TextEditingController _noteCtrl;
  late final FocusNode _venueFocus;
  bool _editingVenue = false;

  /// 已點選的班次 ID
  String? _selectedId;

  String get _key => ShiftStore.ymd(_currentDate);
  String get _dateLabel =>
      '${_currentDate.month}月${_currentDate.day}日(${'日一二三四五六'[_currentDate.weekday % 7]})';

  @override
  void initState() {
    super.initState();
    _currentDate = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _noteCtrl = TextEditingController();
    _venueFocus = FocusNode();
    _venueFocus.addListener(() {
      if (!_venueFocus.hasFocus && _editingVenue) {
        _saveInlineVenue();
      }
    });
    _loadDay();
  }

  void _loadDay() {
    _noteCtrl.text = widget.store.assignments[_key]?.note ?? '';
    _editingVenue = false;
    _selectedId = widget.store.assignments[_key]?.shiftId;
    if (_selectedId != null && !widget.store.defs.containsKey(_selectedId)) {
      _selectedId = null;
    }
    _dirty = false;
  }

  @override
  void dispose() {
    if (_editingVenue) {
      _saveInlineVenue();
    }
    if (_dirty && !_saving) {
      _persistCurrent();
    }
    _noteCtrl.dispose();
    _venueFocus.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  bool _checkNoteOk() {
    if (abbrUnits(_noteCtrl.text.trim()) > 4) {
      showTopNotification(
        context,
        '地點請勿超過 4 單位（2 中文字／4 英文字母）',
        icon: Icons.warning_amber_rounded,
        iconColor: Colors.amber,
      );
      return false;
    }
    return true;
  }

  Future<void> _saveInlineVenue() async {
    if (!_editingVenue) return;
    final val = _noteCtrl.text.trim();
    if (abbrUnits(val) > 4) {
      showTopNotification(
        context,
        '地點請勿超過 4 單位（2 中文字／4 英文字母）',
        icon: Icons.warning_amber_rounded,
        iconColor: Colors.amber,
      );
      return;
    }
    if (mounted) setState(() => _editingVenue = false);
    _markDirty();
    await _persistCurrent();
    if (val.isNotEmpty && !widget.store.venues.contains(val)) {
      await widget.store.addVenue(val);
    }
  }

  Future<void> _persistCurrent() async {
    if (!_checkNoteOk()) return;
    final note = _noteCtrl.text.trim();
    final shiftId = _selectedId;
    final assignment = widget.store.assignments[_key];

    if (shiftId != null) {
      final def = widget.store.defs[shiftId];
      if (def == null) return;
      final changedShift = assignment?.shiftId != shiftId;
      final changedNote = (assignment?.note ?? '') != note;
      await widget.store.assign(_key, shiftId, note: note);
      if (changedShift || changedNote) {
        try {
          await widget.alarms.onAssigned(
            _key,
            def,
            accentBg: _slotBg(def),
            accentFg: _slotFg(def),
            note: note,
          );
        } catch (_) {}
      }
    }
    _dirty = false;
  }

  /// 跳去指定日期（上一日／下一日／點擊日曆格）
  Future<void> goToDate(DateTime date) async {
    if (_saving) return;
    if (_editingVenue) {
      await _saveInlineVenue();
    }
    setState(() => _saving = true);
    try {
      await _persistCurrent();
      if (!mounted) return;
      setState(() {
        _currentDate = DateTime(date.year, date.month, date.day);
        _loadDay();
        _saving = false;
      });
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 點更即排：立即指派該班次並持久化
  Future<void> _pick(String shiftId) async {
    if (_saving) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedId = shiftId;
      _saving = true;
    });
    try {
      await _persistCurrent();
      if (mounted) {
        setState(() => _saving = false);
        final def = widget.store.defs[shiftId];
        if (def != null) {
          showTopNotification(context, '已排 ${def.name}');
        }
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 取消排更 / 放假
  Future<void> _unassign() async {
    if (_saving) return;
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    try {
      await widget.store.unassign(_key);
      try {
        await widget.alarms.onUnassigned(_key);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _selectedId = null;
          _noteCtrl.text = '';
          _saving = false;
        });
        showTopNotification(context, '已清除排班');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static int _slotBg(ShiftDef def) =>
      const ShiftTokens().slotForTime(def.startTime).bg.toARGB32();
  static int _slotFg(ShiftDef def) =>
      const ShiftTokens().slotForTime(def.startTime).fg.toARGB32();



  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final assignment = widget.store.assignments[_key];
    final currentId = assignment?.shiftId;
    final currentDef = currentId != null ? widget.store.defs[currentId] : null;
    final slot = currentDef != null ? t.slotForTime(currentDef.startTime) : null;
    final defs = widget.store.sortedDefs();
    final note = _noteCtrl.text.trim();

    return Container(
      decoration: BoxDecoration(
        color: t.neutralBg,
        border: Border(top: BorderSide(color: t.neutralStroke)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 6,
          ),
        ],
      ),
      // v3.6.1：**唔可以**再加底部安全區包裝層，亦唔可以自己再扣
      // `MediaQuery.padding.bottom`。外層第三區（`CalendarLayout.detailHeight`）
      // 已經用**真實** `padding.bottom` 預留咗導航欄高度，呢度再食一次就係
      // 「食兩次」，正是面板溢出的元兇：
      //   手勢導航（inset 88.8）：Column 只剩 36.2 而內容要 100 → 溢出 63.8px
      //   三鍵導航（inset 112.8）：Column 只剩 12.2 → 溢出 87.8px
      // 高度由外層決定，呢度只需鋪滿（`SizedBox.expand`）＋內距。
      child: SizedBox.expand(
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8, left: 10, right: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 第一行：日期標籤、充裕地點展示/設置按鈕、完成按鈕（固定 42px）
              SizedBox(
                height: 42,
                child: Row(
                  children: [
                    Text(
                      _dateLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: t.neutralFg,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 地點輸入欄（原頁面文本框輸入，無彈窗，與入備註方式完全一致）
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: _editingVenue
                            ? TextField(
                                controller: _noteCtrl,
                                focusNode: _venueFocus,
                                maxLines: 1,
                                maxLength: 4,
                                inputFormatters: const [
                                  AbbrUnitLengthFormatter(4)
                                ],
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: t.neutralBg2,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                        color: t.brand, width: 1.5),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  counterText: '',
                                  isDense: true,
                                  hintText: '輸入地點（如總部）',
                                  prefixIcon: Icon(Icons.location_on,
                                      size: 16, color: t.brand),
                                  suffixIcon: IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.check, size: 18),
                                    onPressed: _saveInlineVenue,
                                  ),
                                ),
                                onEditingComplete: _saveInlineVenue,
                              )
                            : GestureDetector(
                                onTap: () {
                                  setState(() => _editingVenue = true);
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (mounted) _venueFocus.requestFocus();
                                  });
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  height: 36,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: note.isNotEmpty
                                        ? t.brand.withValues(alpha: 0.12)
                                        : t.neutralBg2,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: note.isNotEmpty
                                          ? t.brand.withValues(alpha: 0.35)
                                          : t.neutralStroke,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.location_on,
                                        size: 15,
                                        color: note.isNotEmpty
                                            ? t.brand
                                            : t.neutralFg2,
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          note.isNotEmpty
                                              ? note
                                              : '新增地點…',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: note.isNotEmpty
                                                ? FontWeight.w500
                                                : FontWeight.normal,
                                            color: note.isNotEmpty
                                                ? t.brand
                                                : t.neutralFg2,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Icon(
                                        note.isNotEmpty
                                            ? Icons.edit
                                            : Icons.add,
                                        size: 13,
                                        color: note.isNotEmpty
                                            ? t.brand.withValues(alpha: 0.7)
                                            : t.neutralFg2,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 完成退出按鈕
                    FilledButton(
                      onPressed: () {
                        if (_editingVenue) {
                          _saveInlineVenue();
                        }
                        widget.onClose();
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 0),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('完成',
                          style:
                              TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
              // 第二行：橫向排班卡片（點更即排，自動保存，高度固定 58px）
              SizedBox(
                height: 58,
                child: defs.length <= 4
                    ? Row(
                        children: [
                          for (int i = 0; i < defs.length; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            Expanded(
                              child: _compactShiftButton(
                                  t, defs[i], defs[i].id == currentId),
                            ),
                          ],
                          const SizedBox(width: 6),
                          _clearButton(t, currentId),
                        ],
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (int i = 0; i < defs.length; i++) ...[
                              if (i > 0) const SizedBox(width: 6),
                              SizedBox(
                                width: 88,
                                child: _compactShiftButton(
                                    t, defs[i], defs[i].id == currentId),
                              ),
                            ],
                            const SizedBox(width: 6),
                            _clearButton(t, currentId),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactShiftButton(ShiftTokens t, ShiftDef def, bool isCurrent) {
    final slot = t.slotForTime(def.startTime);
    return InkWell(
      onTap: _saving ? null : () => _pick(def.id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: slot.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCurrent ? slot.fg : slot.border,
            width: isCurrent ? 2.5 : 1.0,
          ),
          boxShadow: isCurrent
              ? [
                  BoxShadow(
                    color: slot.fg.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  )
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                def.code.isNotEmpty ? '${def.code} ${def.name}' : def.name,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: slot.fg,
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${def.startTime}–${def.endTime}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                  color: slot.fg.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clearButton(ShiftTokens t, String? currentId) {
    return SizedBox(
      width: 56,
      height: 58,
      child: Tooltip(
        message: '清除此日排更（設為放假）',
        child: OutlinedButton(
          onPressed: (_saving || currentId == null) ? null : _unassign,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 4),
            side: BorderSide(
              color: currentId != null
                  ? t.danger.withValues(alpha: 0.6)
                  : t.neutralStroke,
              width: 1.0,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.delete_outline,
                size: 20,
                color: currentId != null ? t.danger : t.neutralFg2,
              ),
              const SizedBox(height: 2),
              Text(
                '清除',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                  color: currentId != null ? t.danger : t.neutralFg2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
