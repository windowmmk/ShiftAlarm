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

  /// 響鬧預告提前量（分鐘）。固定 60，不做可配置。
  /// ⚠️ 必須與 Kotlin `PreAlertScheduler.LEAD_MINUTES` 保持一致。
  ///
  /// 放喺 domain 唔放 config.dart：config 係「App 身分」（版本／開源旗標），
  /// 鬧鐘業務常數屬於 domain。
  ///
  /// Dart 側**不用**這個常數做判斷（`leadAt <= now` 只在 Kotlin 判斷一處），
  /// 它只用於文件、測試與未來若要做 Dart 端預檢。
  static const int preAlertLeadMinutes = 60;

  /// 預告 id 命名空間偏移。全鬧鐘／只通知用 id，預告用 id + 900000。
  /// ⚠️ 必須與 Kotlin `PreAlertScheduler.PRE_ALERT_ID_OFFSET` 保持一致。
  static const int preAlertIdOffset = 900000;

  /// 預告 id（**僅供測試**斷言三組 id 互斥）。
  /// 實際轉換由 Kotlin `PreAlertScheduler.preAlertId()` 做，權威轉換點在原生側。
  static int preAlertIdFor(String ymd, int index) =>
      alarmIdFor(ymd, index) + preAlertIdOffset;

  /// 預告標題：「1 小時後：早更 開工打卡」
  static String preAlertTitle(String shiftName, String label) =>
      '1 小時後：$shiftName $label';

  /// 預告內文：「仲有 1 小時響 · 開工時間到了，記得打卡！ (06:00)」
  ///
  /// 必須**串接** [formatAlarmBody] 的輸出，不准另寫一份文案邏輯；
  /// 內文只可以出現一次「1 小時」。
  static String preAlertBody(String alarmBody) => '仲有 1 小時響 · $alarmBody';

  /// 組一條預告排程（唯一組裝點，[onAssigned] 與 [syncOnLaunch] 共用）。
  /// `triggerAt` 係鬧鐘**觸發**時刻，不是預告時刻；−60 分鐘由原生側做。
  static PreAlertSchedule preAlertFor({
    required String ymd,
    required ShiftDef def,
    required ShiftAlarm alarm,
    required int alarmId,
    required DateTime triggerAt,
    required String alarmBody,
    String note = '',
  }) {
    return PreAlertSchedule(
      alarmId: alarmId,
      triggerAtMillis: triggerAt.millisecondsSinceEpoch,
      title: preAlertTitle(def.name, alarm.label),
      body: preAlertBody(alarmBody),
      date: ymd,
      shiftName: def.name,
      startTime: def.startTime,
      note: note,
    );
  }

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

  /// 推送及全屏鬧鐘文案格式化（去除「延後360分鐘」等技術位移用語，轉為人性化自然文案）
  static String formatAlarmBody({
    required String startTime,
    required String endTime,
    required ShiftAlarm alarm,
    String note = '',
  }) {
    final (triggerHhmm, _) = alarmClockParts(startTime, alarm.offsetMinutes);
    final venuePart = note.trim().isNotEmpty ? ' · 地點：${note.trim()}' : '';
    final label = alarm.label;
    final isClockOut = alarm.id == ShiftAlarm.clockOutId ||
        label.contains('收工') ||
        label.contains('下班');
    final isClockIn = alarm.id == ShiftAlarm.clockInId ||
        label.contains('開工打卡') ||
        label.contains('上班打卡');

    if (isClockOut) {
      return '收工時間到了，記得打卡！ ($triggerHhmm)$venuePart';
    }
    if (isClockIn) {
      return '開工時間到了，記得打卡！ ($startTime)$venuePart';
    }
    final shiftRange = endTime.isNotEmpty ? '$startTime–$endTime' : startTime;
    return '班次時間：$shiftRange$venuePart';
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

  /// 取消該日所有鬧鐘：舊制 id＋新制 10 個 index（全鬧鐘＋只通知＋響鬧預告）。
  ///
  /// 呢度係**唯一**取消入口：轉更／刪更／重新指派全部經呢度。
  /// 漏咗預告就等於留低幽靈通知喺通知欄，所以三條通道都要逐個 index 清。
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
      try {
        await bridge.cancelPreAlert(id);
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
      final body = formatAlarmBody(
        startTime: def.startTime,
        endTime: def.endTime,
        alarm: alarm,
        note: note,
      );
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
      // 響鬧預告：全屏／只通知兩條通道都要排（使用者原話「每次鬧鐘響之前 1 小時」）。
      // 獨立 try/catch：預告排唔到（例如原生側舊版未實作呢個 channel method）
      // 絕對唔可以令真鬧鐘排程失敗。
      try {
        await bridge.schedulePreAlert(preAlertFor(
          ymd: ymd,
          def: def,
          alarm: alarm,
          alarmId: id,
          triggerAt: t,
          alarmBody: body,
          note: note,
        ));
      } catch (_) {}
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
    final preAlerts = <PreAlertSchedule>[];
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
        final body = formatAlarmBody(
          startTime: def.startTime,
          endTime: def.endTime,
          alarm: alarm,
          note: note,
        );
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
        // 響鬧預告：兩條通道都排（同 onAssigned 一致）
        preAlerts.add(preAlertFor(
          ymd: e.key,
          def: def,
          alarm: alarm,
          alarmId: id,
          triggerAt: t,
          alarmBody: body,
          note: note,
        ));
      }
    }
    if (full.isNotEmpty || gentle.isNotEmpty || preAlerts.isNotEmpty) {
      await bridge.rescheduleAll(full, gentle, preAlerts);
    }
  }
}
