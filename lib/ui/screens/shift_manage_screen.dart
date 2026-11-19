// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../domain/alarm_service.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';
import 'shift_edit_screen.dart';

export 'shift_edit_screen.dart' show ShiftEditScreen;

/// 班次與地點管理頁：管理班次定義（名稱／縮寫／時段／鬧鐘）與常用地點清單。
class ShiftManageScreen extends StatefulWidget {
  final ShiftStore store;
  final AlarmService alarms;

  const ShiftManageScreen({
    super.key,
    required this.store,
    required this.alarms,
  });

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
          const SnackBar(content: Text('已儲存，相關日期鬧鐘已重新排程')),
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
          enabled: true,
        ),
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
      backgroundColor: kCalendarPageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
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
    if (defs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule_outlined, size: 40, color: t.neutralFg2),
              const SizedBox(height: 10),
              Text(
                '尚未建立班次，點擊右上角「+」新增',
                style: TextStyle(fontSize: t.fontBody, color: t.neutralFg2),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          itemCount: defs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final def = defs[i];
            final slot = t.slotForTime(def.startTime);
            final enabledCount = def.alarms.where((a) => a.enabled).length;
            return Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: slot.border),
              ),
              color: slot.bg,
              child: ListTile(
                title: Text(
                  def.displayTitle,
                  style: TextStyle(fontWeight: FontWeight.w700, color: slot.fg),
                ),
                subtitle: Text(
                  isNativeAlarmSupported
                      ? '${def.startTime}–${def.endTime} · $enabledCount 個鬧鐘'
                      : '${def.startTime}–${def.endTime}',
                  style: TextStyle(color: slot.fg.withValues(alpha: 0.88)),
                ),
                trailing: Icon(Icons.chevron_right, color: slot.fg),
                onTap: () => _openEdit(def),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _venueList(ShiftTokens t) {
    final venues = widget.store.venues;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          children: [
            Text(
              '排班時輸入會自動補全；新輸入的地點將自動加入此清單。',
              style: TextStyle(fontSize: 12, color: t.neutralFg2),
            ),
            const SizedBox(height: 12),
            for (final v in venues)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: kCardStroke),
                ),
                child: ListTile(
                  title: Text(
                    v,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
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
        ),
      ),
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
            child: const Text('取消'),
          ),
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
        title: Text('重新命名「$oldV」'),
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
            child: const Text('取消'),
          ),
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
        content: const Text('刪除後輸入將不再自動補全此地點（已排班的日子不受影響）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
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
