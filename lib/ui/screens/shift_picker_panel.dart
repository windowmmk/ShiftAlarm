import 'package:flutter/material.dart';

import '../../domain/alarm_service.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';

/// 排班面板（固定 widget，唔係 bottom sheet）：
/// 擺喺日曆下方嘅 layout 一部分，取代詳情板；絕對唔遮日曆格。
/// - 頂部：日期＋「＜ 上一日」／「下一日 ＞」＋「完成」；撳即先存而家呢日再載入／閂。
/// - 載入該日現有班次／場所／備註；四更卡恒用日曆色；場所用下拉網格補全
///   （唔分大細楷 substring 匹配，5 個一排 chip，㩒即填；新場所自動入清單）。
/// - 閂面板即存（dispose 時 save-if-dirty）。
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

  /// 而家編輯緊嘅日期（上一日／下一日／㩒日曆格會變）
  late DateTime _currentDate;

  late final TextEditingController _noteCtrl;
  late final TextEditingController _remarkCtrl;
  late final FocusNode _venueFocus;

  /// 已點選嘅卡（未確認）；初值＝而家排緊嗰更
  String? _selectedId;

  String get _key => ShiftStore.ymd(_currentDate);
  String get _dateLabel =>
      '${_currentDate.month}月${_currentDate.day}日（${'一二三四五六日'[_currentDate.weekday - 1]}）';

  @override
  void initState() {
    super.initState();
    _currentDate = DateTime(
        widget.initialDate.year, widget.initialDate.month, widget.initialDate.day);
    _noteCtrl = TextEditingController();
    _remarkCtrl = TextEditingController();
    _venueFocus = FocusNode();
    // 失焦 → 延遲隱藏下拉（等 chip onTap 有機會觸發先）
    _venueFocus.addListener(() {
      if (!_venueFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !_venueFocus.hasFocus) setState(() {});
        });
      } else {
        setState(() {});
      }
    });
    _loadDay();
  }

  /// 載入某日現有班次／場所／備註入 controller。
  /// 有班次嗰日顯示當前班次；未排更嗰日唔預選任何班次，用戶必須手動點。
  void _loadDay() {
    _noteCtrl.text = widget.store.assignments[_key]?.note ?? '';
    _remarkCtrl.text = widget.store.remarks[_key] ?? '';
    _selectedId = widget.store.assignments[_key]?.shiftId;
    if (_selectedId != null &&
        !widget.store.defs.containsKey(_selectedId)) {
      _selectedId = null;
    }
    _dirty = false;
  }

  @override
  void dispose() {
    // 閂面板即存（有改過先存）
    if (_dirty && !_saving) {
      // fire-and-forget：dispose 唔可以 await
      _persistCurrent();
    }
    _noteCtrl.dispose();
    _remarkCtrl.dispose();
    _venueFocus.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// 場所合法性：≤4 單位，唔得就 snackbar 提示並返回 false
  bool _checkNoteOk() {
    if (abbrUnits(_noteCtrl.text.trim()) > 4) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('場所請唔超過 4 單位（2 中文字／4 英文字母）')));
      return false;
    }
    return true;
  }

  Future<void> _persistCurrent() async {
    if (!_checkNoteOk()) return;
    final note = _noteCtrl.text.trim();
    // 用戶指正：唔再自動將新場所加入清單；要加必須經下拉嘅「＋ 新增」主動㩒
    final shiftId = _selectedId;
    final assignment = widget.store.assignments[_key];
    if (shiftId == null) {
      // 無揀更：如果原本有排班，唔郁（避免誤清）；如果想清，用「取消排班」掣
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

  /// 跳去指定日期：先存而家，再載入（畀上一日／下一日／㩒日曆格用）
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

  Future<void> _pick(String shiftId) async {
    if (_saving) return;
    setState(() {
      _selectedId = shiftId;
      _saving = true;
    });
    try {
      await _persistCurrent();
      // 固定面板：存完唔閂，留喺度等用戶㩒下一日
      if (mounted) setState(() => _saving = false);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 時段 accent 色（ARGB int），畀原生全屏鬧鐘用
  static int _slotBg(ShiftDef def) =>
      const ShiftTokens().slotForTime(def.startTime).bg.toARGB32();
  static int _slotFg(ShiftDef def) =>
      const ShiftTokens().slotForTime(def.startTime).fg.toARGB32();

  Future<void> _unassign() async {
    if (_saving) return;
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

  /// 場所下拉補全：低調 dropdown，淨係打字＋有焦點先 show。
  /// 網格 5 個一排 chip，按字母排序（# 開頭放最後）；㩒 chip 即填入。
  Widget _venueAutocomplete(ShiftTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _noteCtrl,
          focusNode: _venueFocus,
          decoration: const InputDecoration(
            labelText: '場所（打字自動補全，新場所會自動記住）',
            border: OutlineInputBorder(),
            counterText: '',
          ),
          maxLength: 12,
          onChanged: (_) => _markDirty(),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _noteCtrl,
          builder: (_, value, _) {
            final raw = value.text.trim();
            final q = raw.toLowerCase();
            // 低調：無焦點／無打字 → 乜都唔 show
            if (!_venueFocus.hasFocus || q.isEmpty) {
              return const SizedBox.shrink();
            }
            final matches = _filterVenues(q);
            // 用戶主動新增：打緊嘅字唔喺清單度（唔分大細楷）
            final isNew = !widget.store.venues
                .any((v) => v.toLowerCase() == q);
            if (matches.isEmpty && !isNew) {
              return const SizedBox.shrink();
            }
            // 唯一完全匹配 → 唔使 show（isNew 必 false）
            if (matches.length == 1 &&
                matches.first.toLowerCase() == q &&
                !isNew) {
              return const SizedBox.shrink();
            }
            return Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: t.neutralBg,
                border: Border.all(color: t.neutralStroke),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              constraints: const BoxConstraints(maxHeight: 230),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (matches.isNotEmpty)
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 2.4,
                        ),
                        itemCount: matches.length,
                        itemBuilder: (_, i) {
                          final v = matches[i];
                          final isSelected = v.trim().toUpperCase() ==
                              _noteCtrl.text.trim().toUpperCase();
                          return InkWell(
                            onTap: () => _selectVenue(v),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? t.brand.withValues(alpha: 0.15)
                                    : t.neutralBg2,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? t.brand
                                      : t.neutralStroke,
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Text(
                                v,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected ? t.brand : t.neutralFg,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),
                    // 用戶主動㩒先加入清單（唔再自動存）
                    if (isNew)
                      Padding(
                        padding: EdgeInsets.only(
                            top: matches.isNotEmpty ? 8 : 0),
                        child: InkWell(
                          onTap: () async {
                            await widget.store.addVenue(raw);
                            _selectVenue(raw);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: t.neutralStroke,
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Text(
                              '＋ 新增「$raw」到場所清單',
                              style: TextStyle(
                                fontSize: 13,
                                color: t.neutralFg2,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// 過濾＋排序：唔分大細楷 substring；字母順序，# 開頭放最後
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

  void _selectVenue(String v) {
    _noteCtrl.text = v;
    _noteCtrl.selection =
        TextSelection.fromPosition(TextPosition(offset: v.length));
    _markDirty();
    _venueFocus.unfocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final assignment = widget.store.assignments[_key];
    final currentId = assignment?.shiftId;
    final defs = widget.store.sortedDefs();

    return Container(
      decoration: BoxDecoration(
        color: t.neutralBg,
        border: Border(top: BorderSide(color: t.neutralStroke)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -200) {
            if (!_saving) _goDay(1); // 左滑 -> 下一日
          } else if (v > 200) {
            if (!_saving) _goDay(-1); // 右滑 -> 上一日
          }
        },
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 下拉關閉指示條（PRD 第五條：向下滑可關閉面板）
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) > 200) {
                  widget.onClose();
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.neutralStroke,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            // 頂部：上一日／日期／下一日（「完成」已刪：㩒外面／下滑退出）
            Row(
              children: [
                TextButton(
                  onPressed: _saving ? null : () => _goDay(-1),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('＜ 上一日'),
                ),
                Expanded(
                  child: Text(_dateLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: t.fontSubtitle,
                          fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: _saving ? null : () => _goDay(1),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('下一日 ＞'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              currentId == null
                  ? '未排更，揀一更：'
                  : '而家排緊「${widget.store.defs[currentId]?.name}」，可轉更：',
              style: TextStyle(fontSize: t.fontBody, color: t.neutralFg2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // 班次橫排卡片：每張恒用日曆時段色；選中加深色邊框＋剔
            Row(
              children: [
                for (int i = 0; i < defs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _shiftCard(t, defs[i], defs[i].id == _selectedId),
                ],
              ],
            ),
            const SizedBox(height: 10),
            // 場所：下拉網格補全（唔分大細楷；新場所自動記入清單）
            _venueAutocomplete(t),
            const SizedBox(height: 10),
            // 備註行：同更次獨立，可無更都有
            TextField(
              controller: _remarkCtrl,
              decoration: const InputDecoration(
                labelText: '備註（選填，同更次獨立）',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              maxLength: 200,
              onChanged: (_) => _markDirty(),
            ),
            const SizedBox(height: 10),
            // 底部：轉更／排更＋取消排班，左右並排
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: (_saving || _selectedId == null)
                        ? null
                        : () => _pick(_selectedId!),
                    child: Text(currentId == null ? '排更' : '轉更'),
                  ),
                ),
                if (currentId != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : _unassign,
                      child: Text('取消排班',
                          style: TextStyle(color: t.danger)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

  /// 班次卡：恒用日曆時段底色；選中加深色邊框＋右上剔。
  Widget _shiftCard(ShiftTokens t, ShiftDef def, bool selected) {
    final slot = t.slotForTime(def.startTime);
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        color: slot.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: selected ? slot.fg : slot.border,
              width: selected ? 2.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _saving
              ? null
              : () => setState(() {
                    _selectedId = def.id;
                    _markDirty();
                  }),
          child: Stack(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      def.name,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: slot.fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${def.startTime}–${def.endTime}',
                      style: TextStyle(fontSize: 11, color: slot.fg),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  top: 4,
                  right: 4,
                  child:
                      Icon(Icons.check_circle, size: 18, color: slot.fg),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
