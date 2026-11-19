// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../domain/alarm_service.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';
import '../dialogs/alarm_edit_dialog.dart';

/// 班次編輯頁：名稱／縮寫／代號／開工收工時間／鬧鐘列表與 1:1 日曆格預覽。
class ShiftEditScreen extends StatefulWidget {
  final ShiftStore store;
  final AlarmService alarms;
  final ShiftDef? def;

  const ShiftEditScreen({
    super.key,
    required this.store,
    required this.alarms,
    this.def,
  });

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
    if (picked == null) return;
    final s =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (isStart) {
        _startTime = s;
      } else {
        _endTime = s;
      }
      final dur = ShiftDef.durationMinutes(_startTime, _endTime);
      for (final a in _alarms) {
        if (a.id == ShiftAlarm.clockOutId) a.offsetMinutes = dur;
      }
    });
  }

  static TimeOfDay _parseHm(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(
      hour: int.tryParse(p.isNotEmpty ? p[0] : '') ?? 0,
      minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0,
    );
  }

  String _alarmDesc(ShiftAlarm a) {
    final when = AlarmService.offsetText(a.offsetMinutes);
    final clock = AlarmService.alarmClockText(_startTime, a.offsetMinutes);
    final type = a.notificationOnly ? '只通知' : '全鬧鐘';
    final off = a.enabled ? '' : '（已關閉）';
    return '$when → 實際 $clock · $type$off';
  }

  List<ShiftAlarm> get _fixedAlarms =>
      _alarms.where((a) => a.isClockAlarm).toList();
  List<ShiftAlarm> get _editableAlarms =>
      _alarms.where((a) => !a.isClockAlarm).toList();

  String _clockDesc(ShiftAlarm a) {
    final clock = AlarmService.alarmClockText(_startTime, a.offsetMinutes);
    final off = a.enabled ? '' : '（已關閉）';
    return '實際 $clock · 只通知$off';
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('班次名稱不可為空')),
      );
      return;
    }
    final abbr = _abbrCtrl.text.trim();
    if (abbr.isEmpty || abbrUnits(abbr) > 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('縮寫不可為空，且不可超過 4 單位')),
      );
      return;
    }
    final code = _codeCtrl.text.trim();
    if (code.isNotEmpty && !RegExp(r'^[A-Za-z0-9]{1,4}$').hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('代號僅限 1–4 個英文字母或數字')),
      );
      return;
    }
    if (_alarms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需要設定一個鬧鐘')),
      );
      return;
    }
    if (_startTime == _endTime) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('開工與收工時間不可相同')),
      );
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
        content: Text(
          usedBy.isEmpty
              ? '確定刪除此班次？'
              : '目前有 ${usedBy.length} 天排定此班次，刪除將一併取消這些日期的排班與鬧鐘。確定刪除？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
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
              labelText: '班次名稱',
              border: OutlineInputBorder(),
            ),
            maxLength: 12,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _abbrCtrl,
            decoration: const InputDecoration(
              labelText: '縮寫（≤4 單位）',
              border: OutlineInputBorder(),
            ),
            maxLength: 8,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeCtrl,
            decoration: const InputDecoration(
              labelText: '代號（≤4 英數字，CSV 導入用，可留空）',
              border: OutlineInputBorder(),
            ),
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
                Text(
                  '鬧鐘（${_alarms.length}）',
                  style: TextStyle(
                    fontSize: t.fontSubtitle,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: (_saving || _alarms.length >= 10)
                      ? null
                      : () async {
                          final a = await showAlarmEditDialog(
                            context,
                            startTime: _startTime,
                          );
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
            if (_fixedAlarms.isNotEmpty) ...[
              Text(
                '打卡提醒（固定，僅可開／關）',
                style: TextStyle(fontSize: 13, color: t.neutralFg2),
              ),
              const SizedBox(height: 4),
              for (final a in _fixedAlarms)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      a.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(_clockDesc(a)),
                    trailing: Switch(
                      value: a.enabled,
                      onChanged: (v) => setState(() => a.enabled = v),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
            for (final a in _editableAlarms)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                    a.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(_alarmDesc(a)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: a.enabled,
                        onChanged: (v) => setState(() => a.enabled = v),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _editableAlarms.length <= 1
                            ? null
                            : () => setState(() => _alarms.remove(a)),
                        tooltip: '刪除鬧鐘',
                      ),
                    ],
                  ),
                  onTap: () async {
                    final na = await showAlarmEditDialog(
                      context,
                      startTime: _startTime,
                      src: a,
                    );
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
            child: Text(_saving ? '儲存中…' : '儲存'),
          ),
        ],
      ),
    );
  }
}

/// 班次編輯頁的 1:1 日曆格預覽（54×76，鎖定 [TextScaler.noScaling] 確保穩定參照）。
class _EditPreviewCell extends StatelessWidget {
  final SlotColors slot;
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
