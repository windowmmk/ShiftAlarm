import '../alarm/alarm_bridge.dart';
import 'shift_store.dart';

/// 鬧鐘領域服務。
/// 規則：指派更次嗰刻，為該班次每個 enabled 鬧鐘排程；
/// 轉更／刪更／改班次嗰刻取消舊鬧鐘再重排。
///
/// 鬧鐘 id 方案：
/// - baseId ＝ YYYYMMDD 整數（如 20261015）
/// - 新制：baseId * 10 + index（index＝該班次 alarms 列表下標，0–9）
/// - 舊制（遷移前）：baseId 本身。onAssigned／onUnassigned 會一併取消舊制 id，
///   避免升級後有幽靈鬧鐘。
/// - 全鬧鐘同只通知用同一個數字 id，但原生側 PendingIntent 指向唔同 Receiver，
///   唔會撞。
class AlarmService {
  final AlarmBridge bridge;

  AlarmService(this.bridge);

  /// YYYY-MM-DD → 20261015（解析失敗回 0，唔拋）
  static int alarmBaseId(String ymd) {
    try {
      return int.parse(ymd.replaceAll('-', ''));
    } catch (_) {
      return 0;
    }
  }

  /// 新制鬧鐘 id
  static int alarmIdFor(String ymd, int index) => alarmBaseId(ymd) * 10 + index;

  /// 開工一刻（本地時區）
  static DateTime? shiftStart(String ymd, String hhmm) {
    try {
      final d = ymd.split('-').map(int.parse).toList();
      final t = hhmm.split(':').map(int.parse).toList();
      return DateTime(d[0], d[1], d[2], t[0], t[1]);
    } catch (_) {
      return null;
    }
  }

  /// 某個鬧鐘實際觸發時間＝開工＋offsetMinutes；已過則回 null（唔排）
  static DateTime? triggerAtFor(String ymd, ShiftDef def, ShiftAlarm alarm) {
    final start = shiftStart(ymd, def.startTime);
    if (start == null) return null;
    final t = start.add(Duration(minutes: alarm.offsetMinutes));
    return t.isAfter(DateTime.now()) ? t : null;
  }

  static String offsetText(int offsetMinutes) {
    if (offsetMinutes < 0) return '提前${-offsetMinutes}分鐘';
    if (offsetMinutes > 0) return '延後$offsetMinutes分鐘';
    return '準時';
  }

  /// 鬧鐘實際觸發時刻（**顯示用**，唔影響排程）：
  /// trigger = 開工分鐘數 + offsetMinutes，normalize 到 0–1439。
  /// 回傳 (HH:mm, dayOffset)：dayOffset −1=前一日、0=當日、+1=後一日。
  /// 例：("00:00", −60) → ("23:00", −1)；("18:00", 360) → ("00:00", 1)。
  /// 注意 Dart `~/` 係向零截斷，負數要用 (total − norm) ~/ 1440 先啱。
  static (String, int) alarmClockParts(String startHhmm, int offsetMinutes) {
    final p = startHhmm.split(':');
    final startMin = (int.tryParse(p.isNotEmpty ? p[0] : '') ?? 0) * 60 +
        (p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0);
    final total = startMin + offsetMinutes;
    final norm = total % 1440; // Dart % 恆正 → 0–1439
    final dayOffset = (total - norm) ~/ 1440;
    final hh = (norm ~/ 60).toString().padLeft(2, '0');
    final mm = (norm % 60).toString().padLeft(2, '0');
    return ('$hh:$mm', dayOffset);
  }

  /// 日偏移標籤：0=當日（唔標）、−1=前一日、+1=後一日。
  static String alarmDayLabel(int dayOffset) {
    if (dayOffset == 0) return '';
    if (dayOffset == -1) return '（前一日）';
    if (dayOffset == 1) return '（後一日）';
    if (dayOffset < -1) return '（前${-dayOffset}日）';
    return '（$dayOffset日後）';
  }

  /// 一行過：「23:00（前一日）」
  static String alarmClockText(String startHhmm, int offsetMinutes) {
    final (hhmm, d) = alarmClockParts(startHhmm, offsetMinutes);
    return '$hhmm${alarmDayLabel(d)}';
  }

  /// 取消該日所有鬧鐘：舊制 id＋新制 10 個 index（全鬧鐘＋只通知）。
  Future<void> _cancelAllFor(String ymd) async {
    final base = alarmBaseId(ymd);
    try {
      await bridge.cancel(base); // 舊制幽靈
    } catch (_) {}
    for (var i = 0; i < ShiftAlarm.maxAlarmsPerShift; i++) {
      final id = base * 10 + i;
      try {
        await bridge.cancel(id);
      } catch (_) {}
      try {
        await bridge.cancelGentle(id);
      } catch (_) {}
    }
  }

  /// 指派／轉更：先取消舊鬧鐘，再按班次 alarms 逐個排。
  /// accentBg/accentFg：時段 accent 色（ARGB），UI 層由 ShiftTokens 計出嚟傳入。
  Future<void> onAssigned(
    String ymd,
    ShiftDef def, {
    int accentBg = 0xFF0078D4,
    int accentFg = 0xFFFFFFFF,
    String note = '',
  }) async {
    await _cancelAllFor(ymd);
    final base = alarmBaseId(ymd);
    for (var i = 0; i < def.alarms.length && i < ShiftAlarm.maxAlarmsPerShift; i++) {
      final alarm = def.alarms[i];
      if (!alarm.enabled) continue;
      final t = triggerAtFor(ymd, def, alarm);
      if (t == null) continue; // 已過，唔排
      final id = base * 10 + i;
      final title = '${def.name} ${alarm.label}';
      final body =
          '$ymd ${def.startTime}開工（${offsetText(alarm.offsetMinutes)}）${note.isNotEmpty ? ' · $note' : ''}';
      if (alarm.notificationOnly) {
        await bridge.scheduleGentle(
          id: id,
          triggerAtMillis: t.millisecondsSinceEpoch,
          title: title,
          body: body,
        );
      } else {
        await bridge.schedule(
          id: id,
          triggerAtMillis: t.millisecondsSinceEpoch,
          title: title,
          body: body,
          accentBg: accentBg,
          accentFg: accentFg,
          shiftName: def.name,
          startTime: def.startTime,
          date: ymd,
          note: note,
        );
      }
    }
  }

  /// 刪更：取消該日所有鬧鐘，唔留幽靈。
  Future<void> onUnassigned(String ymd) => _cancelAllFor(ymd);

  /// App 啟動保險：將所有未來鬧鐘一次過交原生側重排（同 id 覆蓋）。
  /// accentFor：由 (ShiftDef) 計出 (accentBg, accentFg) 嘅函數，UI 層傳入。
  Future<void> syncOnLaunch(
    ShiftStore store, {
    (int, int) Function(ShiftDef)? accentFor,
  }) async {
    final full = <AlarmSchedule>[];
    final gentle = <GentleAlarmSchedule>[];
    for (final e in store.assignments.entries) {
      final def = store.defs[e.value.shiftId];
      if (def == null) continue;
      final base = alarmBaseId(e.key);
      // 順手清舊制幽靈
      try {
        await bridge.cancel(base);
      } catch (_) {}
      final accent = accentFor?.call(def);
      final note = e.value.note;
      for (var i = 0; i < def.alarms.length && i < ShiftAlarm.maxAlarmsPerShift; i++) {
        final alarm = def.alarms[i];
        if (!alarm.enabled) continue;
        final t = triggerAtFor(e.key, def, alarm);
        if (t == null) continue;
        final id = base * 10 + i;
        final title = '${def.name} ${alarm.label}';
        final body =
            '${e.key} ${def.startTime}開工（${offsetText(alarm.offsetMinutes)}）${note.isNotEmpty ? ' · $note' : ''}';
        if (alarm.notificationOnly) {
          gentle.add(GentleAlarmSchedule(
            id: id,
            triggerAtMillis: t.millisecondsSinceEpoch,
            title: title,
            body: body,
          ));
        } else {
          full.add(AlarmSchedule(
            id: id,
            triggerAtMillis: t.millisecondsSinceEpoch,
            title: title,
            body: body,
            accentBg: accent?.$1 ?? 0xFF0078D4,
            accentFg: accent?.$2 ?? 0xFFFFFFFF,
            shiftName: def.name,
            startTime: def.startTime,
            date: e.key,
            note: note,
          ));
        }
      }
    }
    if (full.isNotEmpty || gentle.isNotEmpty) {
      await bridge.rescheduleAll(full, gentle);
    }
  }
}
