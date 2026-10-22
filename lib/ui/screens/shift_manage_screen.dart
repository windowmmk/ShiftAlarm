import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/alarm_service.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';

/// 班次管理頁：列出所有班次，㩒入去改名／縮寫／開工收工時間／鬧鐘列表；
/// 支援新增／刪除班次。改完會將用緊呢更嘅日子全部重排鬧鐘。
class ShiftManageScreen extends StatefulWidget {
  final ShiftStore store;
  final AlarmService alarms;

  const ShiftManageScreen(
      {super.key, required this.store, required this.alarms});

  @override
  State<ShiftManageScreen> createState() => _ShiftManageScreenState();
}

class _ShiftManageScreenState extends State<ShiftManageScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    widget.store.addListener(_refresh);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    widget.store.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  static (int, int) _accentFor(ShiftDef def) {
    final slot = const ShiftTokens().slotForTime(def.startTime);
    return (slot.bg.toARGB32(), slot.fg.toARGB32());
  }

  /// 將用緊呢個班次嘅日子全部重排鬧鐘
  Future<void> _rescheduleFor(String shiftId) async {
    final def = widget.store.defs[shiftId];
    if (def == null) return;
    final accent = _accentFor(def);
    for (final e in widget.store.assignments.entries) {
      if (e.value.shiftId == shiftId) {
        try {
          await widget.alarms.onAssigned(
            e.key,
            def,
            accentBg: accent.$1,
            accentFg: accent.$2,
            note: e.value.note,
          );
        } catch (_) {}
      }
    }
  }

  Future<void> _openEdit(ShiftDef? def) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ShiftEditScreen(
          store: widget.store,
          alarms: widget.alarms,
          def: def,
        ),
      ),
    );
    if (changed == true && def != null) {
      await _rescheduleFor(def.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已儲存，相關日子鬧鐘已重排')),
        );
      }
    }
  }

  Future<void> _addShift() async {
    final id = 'c${DateTime.now().millisecondsSinceEpoch}';
    final def = ShiftDef(
      id: id,
      name: '新班次',
      startTime: '09:00',
      endTime: '18:00',
      alarms: [
        ShiftAlarm(
            id: 'a1',
            label: '開工鬧鐘',
            offsetMinutes: -30,
            notificationOnly: false,
            enabled: true),
        // 自訂班次一樣有固定打卡（addDef 會再 normalize 保底）
        ShiftAlarm.clockIn(),
        ShiftAlarm.clockOutFor('09:00', '18:00'),
      ],
    );
    await widget.store.addDef(def);
    if (mounted) await _openEdit(widget.store.defs[id]);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: const Text('班次管理'),
        actions: [
          IconButton(
            onPressed: _addShift,
            icon: const Icon(Icons.add),
            tooltip: '新增班次',
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '班次'),
            Tab(text: '地點'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _shiftList(t),
          _venueList(t),
        ],
      ),
    );
  }

  Widget _shiftList(ShiftTokens t) {
    final defs = widget.store.sortedDefs();
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: defs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final def = defs[i];
        final slot = t.slotForTime(def.startTime);
        final enabledCount =
            def.alarms.where((a) => a.enabled).length;
        return Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: slot.border),
          ),
          color: slot.bg,
          child: ListTile(
            title: Text('${def.name}（${def.abbr}）',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: slot.fg)),
            subtitle: Text(
              isNativeAlarmSupported
                  ? '${def.startTime}–${def.endTime} · $enabledCount 個鬧鐘'
                  : '${def.startTime}–${def.endTime}',
              style: TextStyle(color: slot.fg),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openEdit(def),
          ),
        );
      },
    );
  }

  /// 地點清單 Tab：列出／新增／改名／刪除
  Widget _venueList(ShiftTokens t) {
    final venues = widget.store.venues;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('排班時打字會自動補全；打咗新地點會自動加入呢度。',
            style: TextStyle(fontSize: 12, color: t.neutralFg2)),
        const SizedBox(height: 12),
        for (final v in venues)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(v,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: '改名',
                    onPressed: () => _renameVenue(v),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '刪除',
                    onPressed: () => _deleteVenue(v),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _addVenue,
          icon: const Icon(Icons.add),
          label: const Text('新增地點'),
        ),
      ],
    );
  }

  Future<void> _addVenue() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增地點'),
        content: TextField(
          controller: ctrl,
          inputFormatters: const [AbbrUnitLengthFormatter(4)],
          maxLength: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '如 總部、A1（最多 4 單位）',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('新增'),
          ),
        ],
      ),
    );
    final v = ctrl.text.trim();
    ctrl.dispose();
    if (ok == true && v.isNotEmpty && mounted) {
      await widget.store.addVenue(v);
    }
  }

  Future<void> _renameVenue(String oldV) async {
    final ctrl = TextEditingController(text: oldV);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('改名「$oldV」'),
        content: TextField(
          controller: ctrl,
          inputFormatters: const [AbbrUnitLengthFormatter(4)],
          maxLength: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '最多 4 單位',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    final v = ctrl.text.trim();
    ctrl.dispose();
    if (ok == true && v.isNotEmpty && v != oldV && mounted) {
      await widget.store.renameVenue(oldV, v);
    }
  }

  Future<void> _deleteVenue(String v) async {
    final t = context.tokens;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('刪除「$v」？'),
        content: const Text('之後打字唔會再補全呢個地點（已排嘅日子唔受影響）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: t.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await widget.store.removeVenue(v);
    }
  }
}

/// 班次編輯頁：名／縮寫／開工收工時間／鬧鐘列表；可刪除班次。
class ShiftEditScreen extends StatefulWidget {
  final ShiftStore store;
  final AlarmService alarms;
  final ShiftDef? def; // null＝新增（唔用，新增經 manage 頁先建）

  const ShiftEditScreen(
      {super.key, required this.store, required this.alarms, this.def});

  @override
  State<ShiftEditScreen> createState() => _ShiftEditScreenState();
}

class _ShiftEditScreenState extends State<ShiftEditScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _abbrCtrl;
  late final TextEditingController _codeCtrl;
  late String _startTime;
  late String _endTime;
  late List<ShiftAlarm> _alarms;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.def!;
    _nameCtrl = TextEditingController(text: d.name);
    _abbrCtrl = TextEditingController(text: d.abbr);
    _codeCtrl = TextEditingController(text: d.code);
    _startTime = d.startTime;
    _endTime = d.endTime;
    _alarms = d.alarms.map((a) => a.copy()).toList();
    _nameCtrl.addListener(_onFieldChanged);
    _abbrCtrl.addListener(_onFieldChanged);
    _codeCtrl.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onFieldChanged);
    _abbrCtrl.removeListener(_onFieldChanged);
    _codeCtrl.removeListener(_onFieldChanged);
    _nameCtrl.dispose();
    _abbrCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final init = _parseHm(isStart ? _startTime : _endTime);
    final picked = await showTimePicker(
      context: context,
      initialTime: init,
      helpText: isStart ? '開工時間' : '收工時間',
    );
    if (picked != null) {
      final s =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (isStart) {
          _startTime = s;
        } else {
          _endTime = s;
        }
        // 收工打卡跟住班次時長即時重算，預覽同儲存一致
        final dur = ShiftDef.durationMinutes(_startTime, _endTime);
        for (final a in _alarms) {
          if (a.id == ShiftAlarm.clockOutId) a.offsetMinutes = dur;
        }
      });
    }
  }

  static TimeOfDay _parseHm(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(
        hour: int.tryParse(p.isNotEmpty ? p[0] : '') ?? 0,
        minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  String _alarmDesc(ShiftAlarm a) {
    final when = AlarmService.offsetText(a.offsetMinutes);
    final clock = AlarmService.alarmClockText(_startTime, a.offsetMinutes);
    final type = a.notificationOnly ? '只通知' : '全鬧鐘';
    final off = a.enabled ? '' : '（已關）';
    return '$when → 實際 $clock · $type$off';
  }

  /// 固定打卡鬧鐘（只可以開／關）／可編輯鬧鐘分開列
  List<ShiftAlarm> get _fixedAlarms =>
      _alarms.where((a) => a.isClockAlarm).toList();
  List<ShiftAlarm> get _editableAlarms =>
      _alarms.where((a) => !a.isClockAlarm).toList();

  /// 固定打卡副標題：實際打卡時刻＋只通知（唔可以改時間／名）
  String _clockDesc(ShiftAlarm a) {
    final clock = AlarmService.alarmClockText(_startTime, a.offsetMinutes);
    final off = a.enabled ? '' : '（已關）';
    return '實際 $clock · 只通知$off';
  }

  /// 新增／編輯單個鬧鐘，回傳編輯後嘅 ShiftAlarm（null＝取消）
  Future<ShiftAlarm?> _editAlarmDialog(ShiftAlarm? src) async {
    final labelCtrl = TextEditingController(text: src?.label ?? '');
    final minCtrl = TextEditingController(
        text: src == null ? '30' : src.offsetMinutes.abs().toString());
    bool isBefore = src == null ? true : src.offsetMinutes <= 0;
    bool notificationOnly = src?.notificationOnly ?? false;
    bool enabled = src?.enabled ?? true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(src == null ? '新增鬧鐘' : '編輯鬧鐘'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: '名稱（如：開工鬧鐘／收工打卡）',
                    border: OutlineInputBorder(),
                  ),
                  maxLength: 12,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('提前')),
                        ButtonSegment(value: false, label: Text('延後')),
                      ],
                      selected: {isBefore},
                      onSelectionChanged: (s) =>
                          setD(() => isBefore = s.first),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: minCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setD(() {}),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                          labelText: '分鐘',
                          border: OutlineInputBorder(),
                          suffixText: '分鐘',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('相對開工時間（延後可用嚟做收工提示）',
                    style: TextStyle(
                        fontSize: 12, color: context.tokens.neutralFg2)),
                const SizedBox(height: 8),
                Builder(builder: (_) {
                  final mins = int.tryParse(minCtrl.text) ?? 0;
                  final off = isBefore ? -mins : mins;
                  final clock = AlarmService.alarmClockText(
                      _startTime, off);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.tokens.neutralBg2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '實際響鐘：$clock\n（開工 $_startTime ${isBefore ? '提前' : '延後'} $mins 分鐘）',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('全鬧鐘')),
                    ButtonSegment(value: true, label: Text('只通知')),
                  ],
                  selected: {notificationOnly},
                  onSelectionChanged: (s) =>
                      setD(() => notificationOnly = s.first),
                ),
                const SizedBox(height: 4),
                Text('「只通知」淨發通知，唔響鬧鐘聲、唔彈全屏',
                    style: TextStyle(
                        fontSize: 12, color: context.tokens.neutralFg2)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('啟用'),
                  value: enabled,
                  onChanged: (v) => setD(() => enabled = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('確定'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return null;
    final label = labelCtrl.text.trim();
    if (label.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('名稱唔可以空')));
      }
      return null;
    }
    final mins = int.tryParse(minCtrl.text.trim()) ?? -1;
    if (mins < 0 || mins > 24 * 60) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('分鐘請輸入 0–1440')));
      }
      return null;
    }
    return ShiftAlarm(
      id: src?.id ?? 'a${DateTime.now().millisecondsSinceEpoch}',
      label: label,
      offsetMinutes: isBefore ? -mins : mins,
      notificationOnly: notificationOnly,
      enabled: enabled,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('班次名唔可以空')));
      return;
    }
    final abbr = _abbrCtrl.text.trim();
    if (abbr.isEmpty || abbrUnits(abbr) > 4) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('縮寫唔可以空，亦唔可以超過 4 單位')));
      return;
    }
    final code = _codeCtrl.text.trim();
    // 代號：可空；唔空就要 ≤4 英數字
    if (code.isNotEmpty && !RegExp(r'^[A-Za-z0-9]{1,4}$').hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('代號只可以係 1-4 個英文字母或數字')));
      return;
    }
    if (_alarms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('至少要有一個鬧鐘')));
      return;
    }
    // 時間範圍：開工＝收工（零時長）唔畀存；收工早過開工視為跨日班（如 18-00），允許。
    if (_startTime == _endTime) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('開工同收工時間唔可以一樣')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.store.updateDef(
        widget.def!.id,
        name: name,
        abbr: abbr,
        code: code,
        startTime: _startTime,
        endTime: _endTime,
        alarms: _alarms,
      );
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final def = widget.def!;
    final usedBy = widget.store.assignments.entries
        .where((e) => e.value.shiftId == def.id)
        .map((e) => e.key)
        .toList();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('刪除「${def.name}」？'),
        content: Text(usedBy.isEmpty
            ? '確定刪除呢個班次？'
            : '有 ${usedBy.length} 日排緊呢更，刪除會一併取消嗰啲日子嘅排班同鬧鐘。確定？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFCF222E),
              foregroundColor: Colors.white,
            ),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _saving = true);
    try {
      for (final ymd in usedBy) {
        try {
          await widget.alarms.onUnassigned(ymd);
        } catch (_) {}
      }
      await widget.store.unassignBatch(usedBy);
      await widget.store.removeDef(def.id);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 1:1 月曆格即時預覽（所見即所得，及時檢視縮寫是否超限）
  Widget _buildLiveCellPreview(ShiftTokens t) {
    final slot = t.slotForTime(_startTime);
    final rawText = _abbrCtrl.text.trim().isNotEmpty
        ? _abbrCtrl.text.trim()
        : (_nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : '縮寫');
    final abbrDisplay = truncateAbbr(rawText);
    final units = abbrUnits(rawText);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.neutralBg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.neutralStroke),
      ),
      child: Row(
        children: [
          // 1:1 日曆格預覽
          _EditPreviewCell(
            key: const Key('shift-edit-preview-cell'),
            slot: slot,
            abbr: abbrDisplay,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: slot.bg,
                        border: Border.all(color: slot.border),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 標題要可以縮：320px @2.0x 時呢一行實測橫向溢出 19.8px
                    Flexible(
                      child: Text(
                        '月曆格即時預覽',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: t.fontBody,
                          fontWeight: FontWeight.w600,
                          color: t.neutralFg,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '時段：$_startTime ～ $_endTime',
                  style: TextStyle(fontSize: 12, color: t.neutralFg2),
                ),
                const SizedBox(height: 2),
                Text(
                  '縮寫佔用：$units / 4 單位${units > 4 ? '（超長已自動截斷）' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: units > 4 ? t.danger : t.neutralFg2,
                    fontWeight: units > 4 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: Text('編輯${widget.def!.name}'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _delete,
            child: Text('刪除', style: TextStyle(color: t.danger)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildLiveCellPreview(t),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
                labelText: '班次名', border: OutlineInputBorder()),
            maxLength: 12,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _abbrCtrl,
            decoration: const InputDecoration(
                labelText: '縮寫（≤4 單位）', border: OutlineInputBorder()),
            maxLength: 8,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeCtrl,
            decoration: const InputDecoration(
                labelText: '代號（≤4 英數字，CSV 導入用，可空）',
                border: OutlineInputBorder()),
            maxLength: 4,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(true),
                  child: Text('開工 $_startTime'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(false),
                  child: Text('收工 $_endTime'),
                ),
              ),
            ],
          ),
          if (isNativeAlarmSupported) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Text('鬧鐘（${_alarms.length}）',
                    style: TextStyle(
                        fontSize: t.fontSubtitle, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: (_saving || _alarms.length >= 10)
                      ? null
                      : () async {
                          final a = await _editAlarmDialog(null);
                          if (a != null) {
                            setState(() => _alarms.add(a));
                          }
                        },
                  icon: const Icon(Icons.add),
                  label: Text(_alarms.length >= 10 ? '已滿（10）' : '新增'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 固定打卡：只可以開／關，冇編輯／刪除入口
            if (_fixedAlarms.isNotEmpty) ...[
              Text('打卡提醒（固定，只可以開／關）',
                  style: TextStyle(fontSize: 13, color: t.neutralFg2)),
              const SizedBox(height: 4),
              for (final a in _fixedAlarms)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(a.label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(_clockDesc(a)),
                    trailing: Switch(
                      value: a.enabled,
                      onChanged: (v) =>
                          setState(() => a.enabled = v),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
            for (final a in _editableAlarms)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(a.label,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_alarmDesc(a)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: a.enabled,
                        onChanged: (v) =>
                            setState(() => a.enabled = v),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _editableAlarms.length <= 1
                            ? null
                            : () =>
                                setState(() => _alarms.remove(a)),
                        tooltip: '刪除鬧鐘',
                      ),
                    ],
                  ),
                  onTap: () async {
                    final na =
                        await _editAlarmDialog(a);
                    if (na != null) {
                      setState(() {
                        final i = _alarms.indexOf(a);
                        if (i >= 0) _alarms[i] = na;
                      });
                    }
                  },
                ),
              ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
            ),
            child: Text(_saving ? '儲存緊…' : '儲存'),
          ),
        ],
      ),
    );
  }
}

/// 班次編輯頁的 **1:1 日曆格預覽格**（54×76，同 `CalendarScreen` 的真實日曆格一樣大）。
///
/// 呢個格存在的唯一意義係「所見即所得」：用戶喺編輯頁睇到嘅比例，就係排完班之後
/// 日曆上的比例。真實日曆格本身**唔會**跟系統文字縮放變大（`CalendarScreen` 用
/// `AutoSizeText` 自己收放字級），所以預覽格都必須把文字縮放鎖死 1.0 ——
/// 唔係嘅話兩邊比例就對唔上，預覽即刻講大話。
///
/// 實測（viewport 寬 × 系統字體縮放）：
///   - 320×640 @2.0x：格內三行字（日期／縮寫／地點）需要 158px，但只有 65px
///     → 直向溢出 **93px**；
///   - 360×800 @2.0x：直向溢出 13px。
///
/// ⚠️ 唔可以改用 `FittedBox(BoxFit.scaleDown)` 硬縮：呢度個盒得 54×76，
/// `scaleDown` 會把字縮到**剩返肉眼幾乎睇唔到**嘅比例，反而睇唔出縮寫長短。
/// 鎖 `TextScaler.noScaling` 之後，三檔字體縮放下渲染完全一致。
///
/// ⚠️ 唔好再把「格內字級永遠等於真實日曆格」當理由——**呢句係錯嘅，已實測**：
/// 真實日曆格三行各係 `Expanded` + `FittedBox(BoxFit.scaleDown)`，字級會跟系統
/// 縮放放大到行高上限（`Text('15')` 自然尺寸 1.0x=17.0px、2.0x=34.0px，實際
/// 繪製被壓到行高）。所以兩邊**機制唔同**，只係都唔會溢出：真實格靠縮到行高，
/// 預覽格靠鎖死字級。
class _EditPreviewCell extends StatelessWidget {
  /// 該班次時段對應的四色 token（底／字／邊）
  final SlotColors slot;

  /// 已按 4 單位截斷的縮寫（截斷規則同真實日曆格一致）
  final String abbr;

  const _EditPreviewCell({super.key, required this.slot, required this.abbr});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 76,
      decoration: BoxDecoration(
        color: slot.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: slot.border, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      // 預覽格係固定 54×76 的「標準樣本」，格內字級必須鎖死喺設計值。
      //
      // 已實測（360px，1.0x vs 2.0x）：真實日曆格三行各係
      // `Expanded` + `FittedBox(BoxFit.scaleDown)`，字級跟系統縮放但**永遠唔會
      // 溢出**——撐唔落就縮到行高上限。所以縮寫喺真實格入面並冇「爆格」風險，
      // 預覽嘅作用只係畀用戶睇「呢個縮寫喺格入面係咩樣」。
      //
      // 鎖死字級嘅理由：呢度係**固定細盒**，跟系統字體放大只會撐爆自己
      // （320px @1.3x 起實測直向溢出 93px），而又縮唔出真實格嘅內容。
      // 鎖死之後 1.0x / 1.3x / 2.0x 三檔渲染完全一致，用戶先有一個穩定參照。
      child: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.noScaling),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '15',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: slot.fg,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              abbr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: slot.fg,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '地點',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: slot.fg,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
