import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/alarm_service.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';

/// 緊湊型自適應排班操作列（Shift Toolbar Dock）：
/// 擺在日曆下方，高度僅約 100px，絕不擠壓日曆空間，保證日曆 5~6 行 100% 完整可見。
/// - 頂部：日期標籤（可切換上一日／下一日）、場所快選膠囊、備註膠囊、完成關閉按鈕。
/// - 底部：各班次按鈕橫排一字展示（點更即排，自動保存），附帶清除排班／放假按鈕。
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
  late final TextEditingController _remarkCtrl;

  /// 已點選的班次 ID
  String? _selectedId;

  String get _key => ShiftStore.ymd(_currentDate);
  String get _dateLabel =>
      '${_currentDate.month}月${_currentDate.day}日（${'日一二三四五六'[_currentDate.weekday % 7]}）';

  @override
  void initState() {
    super.initState();
    _currentDate = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _noteCtrl = TextEditingController();
    _remarkCtrl = TextEditingController();
    _loadDay();
  }

  void _loadDay() {
    _noteCtrl.text = widget.store.assignments[_key]?.note ?? '';
    _remarkCtrl.text = widget.store.remarks[_key] ?? '';
    _selectedId = widget.store.assignments[_key]?.shiftId;
    if (_selectedId != null && !widget.store.defs.containsKey(_selectedId)) {
      _selectedId = null;
    }
    _dirty = false;
  }

  @override
  void dispose() {
    if (_dirty && !_saving) {
      _persistCurrent();
    }
    _noteCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  bool _checkNoteOk() {
    if (abbrUnits(_noteCtrl.text.trim()) > 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('場所請唔超過 4 單位（2 中文字／4 英文字母）')),
      );
      return false;
    }
    return true;
  }

  Future<void> _persistCurrent() async {
    if (!_checkNoteOk()) return;
    final note = _noteCtrl.text.trim();
    final shiftId = _selectedId;
    final assignment = widget.store.assignments[_key];

    if (shiftId == null) {
      await widget.store.setRemark(_key, _remarkCtrl.text);
    } else {
      final def = widget.store.defs[shiftId];
      if (def == null) return;
      final changedShift = assignment?.shiftId != shiftId;
      final changedNote = (assignment?.note ?? '') != note;
      await widget.store.assign(_key, shiftId, note: note);
      await widget.store.setRemark(_key, _remarkCtrl.text);
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

  Future<void> _goDay(int delta) =>
      goToDate(_currentDate.add(Duration(days: delta)));

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
      if (mounted) setState(() => _saving = false);
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
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static int _slotBg(ShiftDef def) =>
      const ShiftTokens().slotForTime(def.startTime).bg.toARGB32();
  static int _slotFg(ShiftDef def) =>
      const ShiftTokens().slotForTime(def.startTime).fg.toARGB32();

  List<String> _filterVenues(String q) {
    final matches = widget.store.venues
        .where((v) => v.toLowerCase().contains(q))
        .toList();
    matches.sort((a, b) {
      final ah = a.startsWith('#') ? 1 : 0;
      final bh = b.startsWith('#') ? 1 : 0;
      if (ah != bh) return ah - bh;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return matches;
  }

  /// 彈出場地選擇與輸入對話框
  Future<void> _openVenueDialog(BuildContext context) async {
    final t = context.tokens;
    final ctrl = TextEditingController(text: _noteCtrl.text);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final q = ctrl.text.trim().toLowerCase();
          final matches = _filterVenues(q);
          final isNew = q.isNotEmpty &&
              !widget.store.venues.any((v) => v.toLowerCase() == q);
          return AlertDialog(
            title: Text('設置 $_dateLabel 場所'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: '場所（≤4 單位）',
                        hintText: '如 A1、B2、ROOM_1',
                        border: const OutlineInputBorder(),
                        suffixIcon: ctrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  ctrl.clear();
                                  setD(() {});
                                },
                              )
                            : null,
                      ),
                      maxLength: 12,
                      onChanged: (_) => setD(() {}),
                    ),
                    if (matches.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('快速選擇現有場所：',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final v in matches.take(15))
                            ActionChip(
                              label: Text(v, style: const TextStyle(fontSize: 12)),
                              backgroundColor:
                                  ctrl.text.trim().toUpperCase() == v.toUpperCase()
                                      ? t.brand.withValues(alpha: 0.15)
                                      : t.neutralBg2,
                              onPressed: () {
                                ctrl.text = v;
                                setD(() {});
                              },
                            ),
                        ],
                      ),
                    ],
                    if (isNew) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add, size: 14),
                        label: Text('新增「${ctrl.text.trim()}」到場所清單'),
                        onPressed: () async {
                          await widget.store.addVenue(ctrl.text.trim());
                          setD(() {});
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  ctrl.clear();
                  _noteCtrl.text = '';
                  _markDirty();
                  _persistCurrent();
                  Navigator.pop(ctx);
                  setState(() {});
                },
                child: const Text('清除場所'),
              ),
              FilledButton(
                onPressed: () {
                  if (abbrUnits(ctrl.text.trim()) > 4) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('場所請唔超過 4 單位（2 中文字／4 英文字母）')),
                    );
                    return;
                  }
                  _noteCtrl.text = ctrl.text.trim();
                  _markDirty();
                  _persistCurrent();
                  Navigator.pop(ctx);
                  setState(() {});
                },
                child: const Text('確定'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 彈出備註輸入對話框
  Future<void> _openRemarkDialog(BuildContext context) async {
    final ctrl = TextEditingController(text: _remarkCtrl.text);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('設置 $_dateLabel 備註'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '備註內容（與班次獨立）',
            hintText: '如 換班、請假、特別事項',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          maxLength: 200,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              _remarkCtrl.text = ctrl.text.trim();
              _markDirty();
              _persistCurrent();
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final assignment = widget.store.assignments[_key];
    final currentId = assignment?.shiftId;
    final defs = widget.store.sortedDefs();
    final note = _noteCtrl.text.trim();
    final remark = _remarkCtrl.text.trim();

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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 第一行：日期切換、場所膠囊、備註膠囊、完成按鈕
            Row(
              children: [
                InkWell(
                  onTap: _saving ? null : () => _goDay(-1),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.chevron_left,
                        size: 20, color: t.neutralFg),
                  ),
                ),
                Text(
                  _dateLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.neutralFg,
                  ),
                ),
                InkWell(
                  onTap: _saving ? null : () => _goDay(1),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.chevron_right,
                        size: 20, color: t.neutralFg),
                  ),
                ),
                const SizedBox(width: 4),
                // 場所快選膠囊
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ActionChip(
                          avatar: Icon(Icons.location_on_outlined,
                              size: 14,
                              color: note.isNotEmpty ? t.brand : t.neutralFg2),
                          label: Text(
                            note.isNotEmpty ? note : '場所',
                            style: TextStyle(
                              fontSize: 11,
                              color: note.isNotEmpty ? t.brand : t.neutralFg2,
                              fontWeight: note.isNotEmpty
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _openVenueDialog(context),
                        ),
                        const SizedBox(width: 4),
                        ActionChip(
                          avatar: Icon(Icons.edit_note,
                              size: 14,
                              color:
                                  remark.isNotEmpty ? t.brand : t.neutralFg2),
                          label: Text(
                            remark.isNotEmpty ? '有備註' : '備註',
                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  remark.isNotEmpty ? t.brand : t.neutralFg2,
                              fontWeight: remark.isNotEmpty
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _openRemarkDialog(context),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // 完成退出按鈕
                TextButton(
                  onPressed: widget.onClose,
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('完成',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 第二行：橫向排班卡片（點更即排，自動保存）
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  for (int i = 0; i < defs.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: _compactShiftButton(
                          t, defs[i], defs[i].id == currentId),
                    ),
                  ],
                  const SizedBox(width: 6),
                  // 取消排更 / 放假按鈕
                  SizedBox(
                    width: 44,
                    height: 48,
                    child: Tooltip(
                      message: '清除此日排更',
                      child: OutlinedButton(
                        onPressed:
                            (_saving || currentId == null) ? null : _unassign,
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          side: BorderSide(
                              color: currentId != null
                                  ? t.danger.withValues(alpha: 0.5)
                                  : t.neutralStroke),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Icon(Icons.clear,
                            size: 18,
                            color: currentId != null
                                ? t.danger
                                : t.neutralFg2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                def.code.isNotEmpty ? '${def.code} ${def.name}' : def.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: slot.fg,
                ),
              ),
            ),
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${def.startTime}–${def.endTime}',
                style: TextStyle(
                  fontSize: 10,
                  color: slot.fg.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
