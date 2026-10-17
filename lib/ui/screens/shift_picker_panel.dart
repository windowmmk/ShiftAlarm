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
    _loadDay();
  }

  void _loadDay() {
    _noteCtrl.text = widget.store.assignments[_key]?.note ?? '';
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

  /// 彈出地點選擇與輸入對話框
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
            title: Text('設置 $_dateLabel 地點'),
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
                      inputFormatters: const [AbbrUnitLengthFormatter(4)],
                      maxLength: 4,
                      decoration: InputDecoration(
                        labelText: '地點（最多 4 單位）',
                        hintText: '如 總部、A1（2全形/4半形）',
                        counterText: '',
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
                      onChanged: (_) => setD(() {}),
                    ),
                    if (matches.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('快速選擇現有地點：',
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
                        label: Text('新增「${ctrl.text.trim()}」到地點清單'),
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
                  showTopNotification(context, '已清除地點');
                },
                child: const Text('清除地點'),
              ),
              FilledButton(
                onPressed: () {
                  if (abbrUnits(ctrl.text.trim()) > 4) {
                    showTopNotification(
                      context,
                      '地點請勿超過 4 單位（2 中文字／4 英文字母）',
                      icon: Icons.warning_amber_rounded,
                      iconColor: Colors.amber,
                    );
                    return;
                  }
                  _noteCtrl.text = ctrl.text.trim();
                  _markDirty();
                  _persistCurrent();
                  Navigator.pop(ctx);
                  setState(() {});
                  showTopNotification(context, '地點已更新');
                },
                child: const Text('確定'),
              ),
            ],
          );
        },
      ),
    );
  }

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
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 126,
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
                      // 地點按鈕（充裕空間，直接展示與點擊設置）
                      Expanded(
                        child: InkWell(
                          onTap: () => _openVenueDialog(context),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
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
                                  color: note.isNotEmpty ? t.brand : t.neutralFg2,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    note.isNotEmpty ? note : '設置地點',
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
                                  note.isNotEmpty ? Icons.edit : Icons.add,
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
                      const SizedBox(width: 10),
                      // 完成退出按鈕
                      FilledButton(
                        onPressed: widget.onClose,
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
