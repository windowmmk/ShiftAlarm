import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftalarm/domain/base58.dart';
import 'package:shiftalarm/domain/config_io.dart' show computeCrc32;
import 'package:shiftalarm/domain/roster_io.dart';
import 'package:shiftalarm/domain/shift_store.dart';

/// 排班分享協議（SR2）邊界測試——永久防線。
///
/// 每一條測試都對應一個**真實現過嘅缺陷**，而且刻意寫成「舊版一定會紅」：
/// - P1-4：備註長度欄位只寫 1 字節，但實際寫入全部 bytes → 整份分享碼報廢。
/// - P1-8：班次 code 為空時多個班次撞成同一個 key → 導入時班次對錯。
/// - P1-5：報文內含唔存在嘅日期（如 2026-02-30）要跳過該筆，唔可以令
///   整份碼導入失敗，亦唔可以讓 DateTime 自動進位把該筆算成另一日。

/// 建立測試用 store（預設用內建樣本班次）
Future<ShiftStore> _store({Map<String, ShiftDef>? defs}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = ShiftStore(prefs);
  await store.load();
  await store.replaceAllDefs(defs ?? ShiftStore.samplePresetDefs());
  return store;
}

/// 一個班次（時間不同、code 皆為空）——P1-8 用
ShiftDef _def(String id, String name, String start, String end) => ShiftDef(
      id: id,
      name: name,
      code: '', // 故意留空：UI 允許用戶唔填代號
      startTime: start,
      endTime: end,
      alarms: [
        ShiftAlarm(id: 'a1', label: '開工鬧鐘', offsetMinutes: -30),
      ],
    );

/// 手砌一個 v2 報文（含 CRC32 與時間戳），用於測試「解碼端」的防禦。
/// 正常 exportRosterCode 唔可能產生非法日期，所以呢類案例一定要手砌 bytes。
String _buildPacket(
  List<({int y, int m, int d, String code, String venue, String remark})> rows,
) {
  final bb = BytesBuilder();
  bb.addByte(2); // protocol version 2
  bb.addByte((rows.length >> 8) & 0xFF);
  bb.addByte(rows.length & 0xFF);
  for (final r in rows) {
    bb.addByte((r.y >> 8) & 0xFF);
    bb.addByte(r.y & 0xFF);
    bb.addByte(r.m);
    bb.addByte(r.d);
    final cb = utf8.encode(r.code);
    bb.addByte(cb.length);
    bb.add(cb);
    final vb = utf8.encode(r.venue);
    bb.addByte(vb.length);
    bb.add(vb);
    final rb = utf8.encode(r.remark);
    bb.addByte(rb.length);
    bb.add(rb);
  }
  final data = bb.toBytes();

  final crc = computeCrc32(data);
  final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final out = BytesBuilder();
  out.add([(crc >> 24) & 0xFF, (crc >> 16) & 0xFF, (crc >> 8) & 0xFF, crc & 0xFF]);
  out.add([(ts >> 24) & 0xFF, (ts >> 16) & 0xFF, (ts >> 8) & 0xFF, ts & 0xFF]);
  out.add(data);
  return 'SR2:${base58Encode(out.toBytes())}';
}

void main() {
  group('P1-4 備註超長（1 字節長度欄位）', () {
    test('200 個中文字（600 字節）→ 分享碼仍然導入得，其餘日子完全正確', () async {
      final store = await _store();
      await store.assignBatch([
        (ymd: '2026-10-01', shiftId: 's00', note: 'A1', remark: ''),
        (ymd: '2026-10-02', shiftId: 's06', note: 'B1', remark: ''),
        (ymd: '2026-10-03', shiftId: 's12', note: 'C1', remark: ''),
      ]);
      // UI 上限 200 字：200 個中文 = 600 字節，遠超 255
      final longRemark = '備' * 200;
      await store.setRemark('2026-10-02', longRemark);
      expect(store.remarks['2026-10-02']!.length, 200,
          reason: '前提：store 真係存到 200 字（UI 允許）');

      final code = exportRosterCode(store);
      final decoded = decodeRosterText(code, store.defs);

      // 舊版：長度寫 255 但實際寫 600 字節 → 解碼錯位 → CRC32 不符
      expect(decoded.isPacket, isTrue);
      expect(decoded.crcVerified, isTrue, reason: '舊版這裡會 CRC 對唔上');
      expect(decoded.importResult.errors, isEmpty);
      expect(decoded.importResult.valid.length, 3);

      final byDate = {
        for (final r in decoded.importResult.valid) r.date: r,
      };
      // 其餘日子必須「完全正確」——截斷唔可以污染到其他記錄
      expect(byDate['2026-10-01']!.shiftId, 's00');
      expect(byDate['2026-10-01']!.venue, 'A1');
      expect(byDate['2026-10-01']!.remark, '');
      expect(byDate['2026-10-03']!.shiftId, 's12');
      expect(byDate['2026-10-03']!.venue, 'C1');
      expect(byDate['2026-10-03']!.remark, '');

      final remark = byDate['2026-10-02']!.remark;
      expect(utf8.encode(remark).length, lessThanOrEqualTo(255));
      // 255 ÷ 3 = 85，剛好整數邊界，所以截到 85 個中文字
      expect(remark.length, 85);
      expect(remark, '備' * 85);
      expect(longRemark.startsWith(remark), isTrue,
          reason: '截斷結果必須係原字串前綴，唔可以有亂碼');

      // 再實際導入一次，確認備註真係落得返 store。
      // 注意：assignBatch 有「已包含就唔覆蓋」嘅合併邏輯，所以要先把舊備註
      // 清走，否則 200 字嘅舊備註會因為 contains(85 字前綴) 而原封不動。
      await store.setRemark('2026-10-02', '');
      await store.assignBatch([
        for (final r in decoded.importResult.valid)
          (ymd: r.date, shiftId: r.shiftId, note: r.venue, remark: r.remark)
      ]);
      expect(store.assignments.length, 3);
      expect(store.remarks['2026-10-02'], '備' * 85);
    });

    test('100 個 emoji（4 字節）→ 截斷點唔會落喺半個 emoji 中間', () async {
      final store = await _store();
      await store.assignBatch([
        (ymd: '2026-10-01', shiftId: 's00', note: 'A1', remark: ''),
      ]);
      const emoji = '🎉'; // U+1F389，UTF-8 佔 4 字節
      await store.setRemark('2026-10-01', emoji * 100);
      expect(store.remarks['2026-10-01']!.length, 200,
          reason: '100 個 emoji = 200 個 UTF-16 code unit，仍然在 UI 上限內');

      final decoded = decodeRosterText(exportRosterCode(store), store.defs);

      expect(decoded.crcVerified, isTrue, reason: '舊版這裡會 CRC 對唔上');
      expect(decoded.importResult.errors, isEmpty);
      final remark = decoded.importResult.valid.single.remark;

      // 關鍵：解碼端 utf8.decode 唔可以拋異常（截斷必須落在合法邊界）
      expect(() => utf8.decode(utf8.encode(remark)), returnsNormally);
      expect(remark.contains('\uFFFD'), isFalse,
          reason: '出現替換字元即代表切斷了半個 emoji');
      // 4 × 63 = 252 ≤ 255；第 64 個會超，所以應得 63 個
      expect(remark.runes.length, 63);
      expect(remark, emoji * 63);
    });

    test('短備註（未超 255 字節）完全唔變', () async {
      final store = await _store();
      await store.assignBatch([
        (ymd: '2026-10-01', shiftId: 's00', note: 'A1', remark: ''),
      ]);
      await store.setRemark('2026-10-01', '換班：同阿明調更');
      final decoded = decodeRosterText(exportRosterCode(store), store.defs);
      expect(decoded.importResult.valid.single.remark, '換班：同阿明調更');
    });
  });

  group('P1-8 班次 code 為空', () {
    test('兩個班次 code 都係空、時間唔同 → 導入後仍然對得上正確班次', () async {
      final defs = <String, ShiftDef>{
        'sa': _def('sa', '早更', '06:00', '14:00'),
        'sb': _def('sb', '夜更', '14:00', '22:00'),
      };
      final store = await _store(defs: defs);
      expect(store.defs['sa']!.code, isEmpty);
      expect(store.defs['sb']!.code, isEmpty);

      await store.assignBatch([
        (ymd: '2026-10-01', shiftId: 'sa', note: 'A1', remark: ''),
        (ymd: '2026-10-02', shiftId: 'sb', note: 'B1', remark: ''),
        (ymd: '2026-10-03', shiftId: 'sa', note: 'A1', remark: ''),
      ]);

      final decoded = decodeRosterText(exportRosterCode(store), store.defs);
      // 舊版：兩個班次都寫空 code → 導入端 codeMap 冇 key → 全部報
      // 「代號「」找不到對應的班次」，一日都導入唔到。
      expect(decoded.crcVerified, isTrue);
      expect(decoded.importResult.errors, isEmpty);
      expect(decoded.importResult.valid.length, 3);

      final byDate = {
        for (final r in decoded.importResult.valid) r.date: r,
      };
      expect(byDate['2026-10-01']!.shiftId, 'sa');
      expect(byDate['2026-10-02']!.shiftId, 'sb');
      expect(byDate['2026-10-03']!.shiftId, 'sa');
      expect(byDate['2026-10-02']!.venue, 'B1');
    });

    test('有 code 的班次仍然優先按 code 比對（行為不變）', () async {
      final store = await _store();
      await store.assignBatch([
        (ymd: '2026-10-01', shiftId: 's00', note: 'A1', remark: ''),
        (ymd: '2026-10-02', shiftId: 's18', note: 'A2', remark: ''),
      ]);
      final decoded = decodeRosterText(exportRosterCode(store), store.defs);
      final byDate = {
        for (final r in decoded.importResult.valid) r.date: r,
      };
      expect(byDate['2026-10-01']!.shiftId, 's00');
      expect(byDate['2026-10-02']!.shiftId, 's18');
    });
  });

  group('P1-5 解碼端日期防禦', () {
    test('報文含 2026-02-30 → 跳過該筆並報錯，其餘日子照入（offset 唔會錯位）', () async {
      final store = await _store();
      final packet = _buildPacket([
        (y: 2026, m: 2, d: 30, code: '00', venue: 'A1', remark: ''),
        (y: 2026, m: 10, d: 5, code: '06', venue: 'B1', remark: ''),
      ]);

      final decoded = decodeRosterText(packet, store.defs);
      expect(decoded.isPacket, isTrue);
      expect(decoded.crcVerified, isTrue);
      // 舊版：照收 2026-02-30，之後統計會把它算成 3 月 2 日
      expect(decoded.importResult.valid.length, 1);
      expect(decoded.importResult.valid.single.date, '2026-10-05');
      expect(decoded.importResult.valid.single.shiftId, 's06');
      expect(decoded.importResult.valid.single.venue, 'B1');
      expect(decoded.importResult.errors.length, 1);
      expect(decoded.importResult.errors.single, contains('日期唔存在'));
    });

    test('報文含 2026-13-01（月份越界）→ 跳過，唔會變成 2027-01-01', () async {
      final store = await _store();
      final packet = _buildPacket([
        (y: 2026, m: 13, d: 1, code: '00', venue: 'A1', remark: ''),
      ]);
      final decoded = decodeRosterText(packet, store.defs);
      expect(decoded.importResult.valid, isEmpty);
      expect(decoded.importResult.errors.single, contains('日期唔存在'));
    });

    test('全部日期合法時，長備註＋場所一齊 round-trip 冇誤差', () async {
      final store = await _store();
      final packet = _buildPacket([
        (y: 2026, m: 10, d: 5, code: '00', venue: 'A1', remark: '準時開工'),
        (y: 2026, m: 10, d: 6, code: '06', venue: 'B1', remark: ''),
      ]);
      final decoded = decodeRosterText(packet, store.defs);
      expect(decoded.importResult.errors, isEmpty);
      expect(decoded.importResult.valid.length, 2);
      expect(decoded.importResult.valid[0].remark, '準時開工');
      expect(decoded.importResult.valid[0].venue, 'A1');
      expect(decoded.importResult.valid[1].date, '2026-10-06');
    });
  });
}
