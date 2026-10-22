/// 配置導入導出：班次定義＋場所清單。
/// 支援最新極簡 SA2 Base58 報文協議：
/// - 外部協議報文頭：SA2:<Base58>（CRC32 與時間戳內嵌二進制，長度僅 90-115 字元）
/// - 支援多層容錯（自動清除換行、空格）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'base58.dart';
import 'shift_store.dart';

/// 報文頭協議標識與快速檢查（用於剪貼簿自動比對與監聽）
class ConfigPacketHeader {
  static const String prefix = 'SA2:';

  /// 快速檢查文字是否符合配置報文頭（用於剪貼簿快速監聽與比對，零成本避免誤報）
  static bool matches(String text) {
    final clean = text.trim().replaceAll(RegExp(r'\s+'), '');
    return clean.startsWith('SA2:');
  }
}

/// 快速檢查文字是否為合法的配置報文（供剪貼簿即時偵測使用）
bool isConfigPacket(String text) => ConfigPacketHeader.matches(text);

/// 計算標準 IEEE 802.3 CRC32 校驗碼，用於報文完整性驗證
int computeCrc32(List<int> bytes) {
  int crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (int i = 0; i < 8; i++) {
      if ((crc & 1) != 0) {
        crc = (crc >>> 1) ^ 0xEDB88320;
      } else {
        crc >>>= 1;
      }
    }
  }
  return (~crc) & 0xFFFFFFFF;
}

/// 導出當前配置為可序列化的 Map（包含內部報文頭與數據體）
Map<String, dynamic> exportConfig(ShiftStore store) {
  final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return {
    'app': 'ShiftAlarm',
    'version': 1,
    'header': {
      'magic': 'SHIFTALARM_CONFIG',
      'version': 1,
      'timestamp': nowTs,
      'shiftCount': store.defs.length,
      'venueCount': store.venues.length,
    },
    'shifts': [
      for (final e in store.defs.entries)
        {'id': e.key, ...e.value.toJson()},
    ],
    'venues': List<String>.from(store.venues),
  };
}

/// 二進制緊湊預編碼（v3）：
/// 徹底捨棄 JSON 重複鍵名開銷，將時段、開關狀態、代號、場所等資料壓縮打包為二進制流，
/// 讓導出的 Base58 口令長度直接從 2000+ 字元腰斬至 120-180 字元！
///
/// v3 相對 v2 唯一嘅分別：每個班次尾段多寫一段 `defId`（原 store 嘅班次 id）。
/// 為什麼要帶原 id：v2 嘅 id 係解碼時即時推導（`'s' + code`），但
/// `replaceAllDefs` 會清空重建班次清單，推導出嚟嘅 id 同原 store 唔一樣時，
/// `assignments` 就會全部變成孤兒 → 導入之後所有日子顯示「未知班次」。
/// 帶住原 id，導入端就可以砌返「舊 id → 新 id」對照表，把排班一齊搬過去。
///
/// 長度取捨：若 `def.id` 同 v2 推導規則（`code` 非空 → `'s'+code`，否則
/// `'s'+索引`）算出嚟嘅值一樣，就寫 0 長度，解碼端照 v2 規則推導即可。
/// 呢個「同值寫 0 字節」嘅做法同本格式處理 `name`／`abbr` 完全一致
/// （見下面「若與 code 相同或為空，寫 0 字節」），所以係無損嘅，
/// 只係唔重複寫一段本來就推導得到嘅資料。
Uint8List encodeCompactConfig(ShiftStore store) {
  final bb = BytesBuilder();
  bb.addByte(3); // protocol version 3

  final defs = store.defs.values.toList();
  bb.addByte(defs.length.clamp(0, 255));

  for (var i = 0; i < defs.length; i++) {
    final def = defs[i];
    // 時間 00:00 -> h, m
    final sParts = def.startTime.split(':');
    final sh = int.tryParse(sParts.isNotEmpty ? sParts[0] : '') ?? 0;
    final sm = int.tryParse(sParts.length > 1 ? sParts[1] : '') ?? 0;
    final eParts = def.endTime.split(':');
    final eh = int.tryParse(eParts.isNotEmpty ? eParts[0] : '') ?? 0;
    final em = int.tryParse(eParts.length > 1 ? eParts[1] : '') ?? 0;

    bb.addByte(sh.clamp(0, 23));
    bb.addByte(sm.clamp(0, 59));
    bb.addByte(eh.clamp(0, 23));
    bb.addByte(em.clamp(0, 59));

    // 打卡鬧鐘狀態
    final clockIn =
        def.alarms.where((a) => a.id == ShiftAlarm.clockInId).firstOrNull;
    final clockOut =
        def.alarms.where((a) => a.id == ShiftAlarm.clockOutId).firstOrNull;
    int clockFlags = 0;
    if (clockIn?.enabled ?? false) clockFlags |= (1 << 0);
    if (clockOut?.enabled ?? false) clockFlags |= (1 << 1);
    bb.addByte(clockFlags);

    // 自定義鬧鐘（扣除系統固定打卡鬧鐘）
    final customAlarms = def.alarms
        .where((a) =>
            a.id != ShiftAlarm.clockInId && a.id != ShiftAlarm.clockOutId)
        .toList();
    bb.addByte(customAlarms.length.clamp(0, 255));

    for (final ca in customAlarms) {
      final bd = ByteData(2)..setInt16(0, ca.offsetMinutes, Endian.big);
      bb.add(bd.buffer.asUint8List());

      final isDefaultLabel =
          ca.label == '開工鬧鐘' || ca.label == 'Alarm' || ca.label.isEmpty;
      int aFlags = 0;
      if (ca.enabled) aFlags |= (1 << 0);
      if (ca.notificationOnly) aFlags |= (1 << 1);
      if (!isDefaultLabel) aFlags |= (1 << 2);
      bb.addByte(aFlags);

      if (!isDefaultLabel) {
        final labelBytes = utf8.encode(ca.label);
        bb.addByte(labelBytes.length.clamp(0, 255));
        bb.add(labelBytes);
      }
    }

    // 代號 code
    final codeBytes = utf8.encode(def.code);
    bb.addByte(codeBytes.length.clamp(0, 255));
    bb.add(codeBytes);

    // 名稱 name（若與 code 相同或為空，寫 0 字節）
    if (def.name == def.code || def.name.isEmpty) {
      bb.addByte(0);
    } else {
      final nameBytes = utf8.encode(def.name);
      bb.addByte(nameBytes.length.clamp(0, 255));
      bb.add(nameBytes);
    }

    // 縮寫 abbr（若與 name 或 code 相同，寫 0 字節）
    if (def.abbr == def.name || def.abbr == def.code || def.abbr.isEmpty) {
      bb.addByte(0);
    } else {
      final abbrBytes = utf8.encode(def.abbr);
      bb.addByte(abbrBytes.length.clamp(0, 255));
      bb.add(abbrBytes);
    }

    // v3：原班次 id（defId）。同 v2 推導規則一致時寫 0 字節，唔重複佔長度。
    final derivedId = def.code.isNotEmpty ? 's${def.code}' : 's$i';
    if (def.id.isEmpty || def.id == derivedId) {
      bb.addByte(0);
    } else {
      final idBytes = utf8.encode(def.id);
      bb.addByte(idBytes.length.clamp(0, 255));
      bb.add(idBytes);
    }
  }

  // 場所清單
  final venues = store.venues;
  bb.addByte(venues.length.clamp(0, 255));
  for (final v in venues) {
    final vBytes = utf8.encode(v);
    bb.addByte(vBytes.length.clamp(0, 255));
    bb.add(vBytes);
  }

  return bb.toBytes();
}

/// 二進制緊湊預編碼解碼（同時支援 v2 與 v3）。
///
/// v2 冇 `defId`（id 只能由 code 推導），v3 每個班次尾段多一段 `defId`。
/// 兩個版本都要讀得，因為用戶手機裡面／截圖裡面仍然有舊 v2 口令碼，
/// 一升版就讀唔到＝把「換機復原」呢個唯一嘅救援通道封死。
Map<String, dynamic> decodeCompactConfig(Uint8List bytes) {
  var offset = 0;
  if (bytes.isEmpty) throw const ConfigImportException('數據為空');
  final version = bytes[offset++];
  if (version != 2 && version != 3) {
    throw ConfigImportException('不支援的緊湊協議版本: $version');
  }

  final shiftCount = bytes[offset++];
  final shifts = <Map<String, dynamic>>[];

  for (int i = 0; i < shiftCount; i++) {
    final sh = bytes[offset++];
    final sm = bytes[offset++];
    final eh = bytes[offset++];
    final em = bytes[offset++];
    final startTime =
        '${sh.toString().padLeft(2, '0')}:${sm.toString().padLeft(2, '0')}';
    final endTime =
        '${eh.toString().padLeft(2, '0')}:${em.toString().padLeft(2, '0')}';

    final clockFlags = bytes[offset++];
    final clockInEnabled = (clockFlags & (1 << 0)) != 0;
    final clockOutEnabled = (clockFlags & (1 << 1)) != 0;

    final customAlarmCount = bytes[offset++];
    final alarms = <Map<String, dynamic>>[];

    for (int a = 0; a < customAlarmCount; a++) {
      final bd = ByteData.sublistView(bytes, offset, offset + 2);
      final offsetMins = bd.getInt16(0, Endian.big);
      offset += 2;

      final aFlags = bytes[offset++];
      final aEnabled = (aFlags & (1 << 0)) != 0;
      final aNotifOnly = (aFlags & (1 << 1)) != 0;
      final hasCustomLabel = (aFlags & (1 << 2)) != 0;

      String label = '開工鬧鐘';
      if (hasCustomLabel) {
        final lLen = bytes[offset++];
        label = utf8.decode(bytes.sublist(offset, offset + lLen));
        offset += lLen;
      }

      alarms.add({
        'id': 'a${a + 1}',
        'label': label,
        'offsetMinutes': offsetMins,
        'notificationOnly': aNotifOnly,
        'enabled': aEnabled,
      });
    }

    // 保證存在系統打卡鬧鐘
    alarms.add({
      'id': ShiftAlarm.clockInId,
      'label': '開工打卡',
      'offsetMinutes': 0,
      'notificationOnly': true,
      'enabled': clockInEnabled,
    });
    alarms.add({
      'id': ShiftAlarm.clockOutId,
      'label': '收工打卡',
      'offsetMinutes': ShiftDef.durationMinutes(startTime, endTime),
      'notificationOnly': true,
      'enabled': clockOutEnabled,
    });

    final codeLen = bytes[offset++];
    final code = utf8.decode(bytes.sublist(offset, offset + codeLen));
    offset += codeLen;

    final nameLen = bytes[offset++];
    final String name;
    if (nameLen > 0) {
      name = utf8.decode(bytes.sublist(offset, offset + nameLen));
      offset += nameLen;
    } else {
      name = code.isNotEmpty ? code : '班次${i + 1}';
    }

    final abbrLen = bytes[offset++];
    final String abbr;
    if (abbrLen > 0) {
      abbr = utf8.decode(bytes.sublist(offset, offset + abbrLen));
      offset += abbrLen;
    } else {
      abbr = truncateAbbr(name);
    }

    // v3：原班次 id（defId）。0 長度＝同 v2 推導規則一致，唔使重複寫。
    String? defId;
    if (version >= 3) {
      final idLen = bytes[offset++];
      if (idLen > 0) {
        defId = utf8.decode(bytes.sublist(offset, offset + idLen));
        offset += idLen;
      }
    }

    final id = (defId != null && defId.isNotEmpty)
        ? defId
        : (code.isNotEmpty ? 's$code' : 's$i');
    shifts.add({
      'id': id,
      // 舊版（v2）冇原 id，呢個 key 留空，等 importConfig 用 code／name 反推
      'defId': defId,
      'name': name,
      'abbr': abbr,
      'code': code,
      'startTime': startTime,
      'endTime': endTime,
      'alarms': alarms,
    });
  }

  final venueCount = bytes[offset++];
  final venues = <String>[];
  for (int j = 0; j < venueCount; j++) {
    final vLen = bytes[offset++];
    final venue = utf8.decode(bytes.sublist(offset, offset + vLen));
    offset += vLen;
    venues.add(venue);
  }

  return {
    'app': 'ShiftAlarm',
    'version': version,
    'header': {
      'magic': 'SHIFTALARM_CONFIG',
      'version': version,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'shiftCount': shifts.length,
      'venueCount': venues.length,
    },
    'shifts': shifts,
    'venues': venues,
  };
}

/// 導出為帶有極簡協議報文頭（SA2:<Base58>）的極速 Base58 緊湊預編碼口令碼：
/// 報文頭內化打包：CRC32（4 字節）與時間戳（4 字節）直接嵌入二進制數據體中，
/// 外部前綴僅 4 字元（SA2:），長度直接壓至 90~115 字元以內！
String exportConfigCode(ShiftStore store) {
  final dataBytes = encodeCompactConfig(store);
  final crc = computeCrc32(dataBytes);
  final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  final bb = BytesBuilder();
  final crcBd = ByteData(4)..setUint32(0, crc, Endian.big);
  bb.add(crcBd.buffer.asUint8List());

  final tsBd = ByteData(4)..setUint32(0, nowTs, Endian.big);
  bb.add(tsBd.buffer.asUint8List());

  bb.add(dataBytes);

  final packetBytes = bb.toBytes();
  final b58 = base58Encode(packetBytes);
  return 'SA2:$b58';
}

/// 導出為 JSON 字符串（pretty print，方便人讀）。
String exportConfigJson(ShiftStore store) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(exportConfig(store));
}

/// 報文解析結果
class DecodedConfigPayload {
  final Map<String, dynamic> data;
  final String? crcHex;
  final int? byteLen;
  final DateTime? exportTime;
  final bool crcVerified;

  const DecodedConfigPayload({
    required this.data,
    this.crcHex,
    this.byteLen,
    this.exportTime,
    this.crcVerified = false,
  });
}

/// 解碼配置字串：僅支援最新極簡 SA2 協議（Base58 緊湊二進制預編碼）
DecodedConfigPayload decodeConfigText(String text) {
  final rawTrimmed = text.trim();
  if (rawTrimmed.isEmpty) {
    throw const ConfigImportException('內容係空嘅');
  }

  // 1. 去除所有內部空白與換行符號（針對通訊軟體或備忘錄折行貼上的容錯）
  final cleanText = rawTrimmed.replaceAll(RegExp(r'\s+'), '');

  // 2. 嚴格支援極簡 SA2 協議：SA2:<Base58>
  if (!cleanText.startsWith('SA2:')) {
    throw const ConfigImportException('口令無效（請使用 SA2: 極簡配置口令）');
  }

  final payload = cleanText.substring(4);
  List<int>? bytes;
  try {
    bytes = base58Decode(payload);
  } catch (_) {}

  if (bytes == null || bytes.length < 10) {
    throw const ConfigImportException('極簡報文數據損壞或長度不足');
  }

  final u8 = Uint8List.fromList(bytes);
  final expectedCrc =
      ByteData.sublistView(u8, 0, 4).getUint32(0, Endian.big);
  final tsSec =
      ByteData.sublistView(u8, 4, 8).getUint32(0, Endian.big);
  final exportTime = DateTime.fromMillisecondsSinceEpoch(tsSec * 1000);
  final dataBytes = Uint8List.sublistView(u8, 8);

  final actualCrc = computeCrc32(dataBytes);
  if (actualCrc != expectedCrc) {
    throw const ConfigImportException('報文校驗碼不符（內容不完整或被截斷），請重新複製完整口令');
  }

  try {
    final decoded = decodeCompactConfig(dataBytes);
    _validateConfigStructure(decoded);
    return DecodedConfigPayload(
      data: decoded,
      crcHex: expectedCrc.toRadixString(16).padLeft(8, '0'),
      byteLen: bytes.length,
      exportTime: exportTime,
      crcVerified: true,
    );
  } catch (e) {
    if (e is ConfigImportException) rethrow;
    throw const ConfigImportException('極簡報文數據內容損壞，無法解析');
  }
}

/// 內部報文頭與數據結構合法性驗證
void _validateConfigStructure(Map<String, dynamic> json) {
  if (json['app'] != 'ShiftAlarm') {
    throw const ConfigImportException('報文頭標記錯誤：非 ShiftAlarm 配置檔');
  }
  final shiftsRaw = json['shifts'];
  final venuesRaw = json['venues'];
  if (shiftsRaw is! List) {
    throw const ConfigImportException('配置檔缺少 shifts 班次資料');
  }
  if (venuesRaw is! List) {
    throw const ConfigImportException('配置檔缺少 venues 場所資料');
  }
  if (shiftsRaw.isEmpty) {
    throw const ConfigImportException('配置檔冇包含任何班次');
  }

  // 若含有內部報文頭，校驗班次數量冗餘
  final header = json['header'];
  if (header is Map) {
    final expectedShifts = header['shiftCount'] as int?;
    if (expectedShifts != null && shiftsRaw.length != expectedShifts) {
      throw ConfigImportException(
          '內部報文頭校驗失敗：班次數量不符（記錄為 $expectedShifts，實收 ${shiftsRaw.length}）');
    }
  }
}

/// 從 Map 導入配置：清空現有班次／場所，寫入導入的。
///
/// 關鍵：換走班次定義之前，一定要先砌好「舊 id → 新 id」對照表，把
/// `assignments` 內所有 `shiftId` 一齊搬過去。否則導入之後全部日子會變成
/// 孤兒 → 日曆顯示「未知班次」，而用戶見到嘅係「導入完排班全冇了」。
///
/// 對照表嘅來源分兩種（必須保持向後兼容，舊 SA2 口令碼照樣要導入得）：
/// - v3 報文自帶 `defId`（原 store 嘅 id）→ 直接對照。
/// - v2 報文冇 `defId`，其 id 係解碼時即時由 `code` 推導出嚟
///   （`'s' + code`），同原 store 完全無關 → 只能靠 `code` 反推，
///   `code` 對唔上就退而用 `name` 對照。
/// 仍然對唔上就當「無法對應」，原值保留唔刪 —— 寧可顯示未知班次，
/// 都唔可以刪用戶資料。
Future<void> importConfig(ShiftStore store, Map<String, dynamic> json) async {
  _validateConfigStructure(json);
  final shiftsRaw = json['shifts'] as List;
  final venuesRaw = json['venues'] as List;

  // 導入前嘅班次定義：v2 要靠佢嘅 code／name 反推原 id
  final oldDefs = Map<String, ShiftDef>.from(store.defs);

  // 解析班次
  final defs = <String, ShiftDef>{};
  // 舊 id → 新 id
  final idMap = <String, String>{};
  // 冇 defId 嘅班次（v2），等解析完再用 code／name 反推
  final pending = <({String newId, String code, String name})>[];

  for (final e in shiftsRaw) {
    if (e is! Map) continue;
    final m = Map<String, Object?>.from(e);
    final id = m['id']?.toString();
    if (id == null || id.isEmpty) continue;
    final ShiftDef def;
    try {
      def = ShiftDef.fromJson(id, m);
      def.normalizeClockAlarms();
    } catch (_) {
      continue; // 逐個班次獨立容錯，壞一個唔可以拖死整份配置
    }
    defs[id] = def;

    final defId = m['defId']?.toString();
    if (defId != null && defId.isNotEmpty) {
      idMap[defId] = id;
    } else {
      pending.add((newId: id, code: def.code, name: def.name));
    }
  }
  if (defs.isEmpty) {
    throw const ConfigImportException('配置檔冇有效班次');
  }

  // v2 兼容：靠 code 反推，再靠 name 兜底
  for (final p in pending) {
    final oldId = _findOldIdByCode(oldDefs, p.code) ??
        _findOldIdByName(oldDefs, p.name);
    if (oldId != null) idMap[oldId] = p.newId;
  }

  // 解析場所
  final venues = <String>[];
  for (final v in venuesRaw) {
    if (v is String && v.trim().isNotEmpty && !venues.contains(v.trim())) {
      venues.add(v.trim());
    }
  }

  // 次序好重要：先重寫 assignments 嘅 shiftId，再換 defs。
  // 反過來就會有一瞬間「assignments 指向舊 id、defs 只有新 id」嘅孤兒狀態。
  await store.remapAssignmentShiftIds(idMap);
  await store.replaceAllDefs(defs);
  await store.replaceAllVenues(venues);
}

/// 用代號反推舊班次 id（v2 口令碼兼容用）。空白代號唔可以用嚟對照，
/// 否則所有冇填代號嘅班次都會互相誤配。
String? _findOldIdByCode(Map<String, ShiftDef> oldDefs, String code) {
  final c = code.trim();
  if (c.isEmpty) return null;
  final ids = oldDefs.keys.toList()..sort();
  for (final id in ids) {
    if (oldDefs[id]!.code.trim() == c) return id;
  }
  return null;
}

/// 用名稱反推舊班次 id（v2 口令碼兼容嘅最後一道對照）。
String? _findOldIdByName(Map<String, ShiftDef> oldDefs, String name) {
  final n = name.trim();
  if (n.isEmpty) return null;
  final ids = oldDefs.keys.toList()..sort();
  for (final id in ids) {
    if (oldDefs[id]!.name.trim() == n) return id;
  }
  return null;
}

/// 從任意文字（帶報文頭與 CRC32 校驗碼的 Base64 口令碼或 JSON 字符串）導入。
Future<void> importConfigText(ShiftStore store, String text) async {
  final payload = decodeConfigText(text);
  await importConfig(store, payload.data);
}

/// 兼容舊呼叫
Future<void> importConfigJson(ShiftStore store, String text) =>
    importConfigText(store, text);

/// 預覽結果結構
typedef ConfigPreview = ({
  int shifts,
  int venues,
  List<String> names,
  DateTime? exportTime,
  String? crcHex,
  bool crcVerified,
});

/// 預覽：從報文口令碼或 JSON 解析出班次／場所數量、名稱、生成時間與報文頭校驗狀態
ConfigPreview previewConfig(String text) {
  final payload = decodeConfigText(text);
  final shiftsRaw = payload.data['shifts'] as List;
  final venuesRaw = payload.data['venues'] as List;
  final names = <String>[];
  for (final e in shiftsRaw) {
    if (e is Map) {
      final name = e['name'] as String?;
      if (name != null) names.add(name);
    }
  }
  final venueCount = venuesRaw.whereType<String>().length;
  return (
    shifts: shiftsRaw.length,
    venues: venueCount,
    names: names,
    exportTime: payload.exportTime,
    crcHex: payload.crcHex,
    crcVerified: payload.crcVerified,
  );
}

class ConfigImportException implements Exception {
  final String message;
  const ConfigImportException(this.message);
  @override
  String toString() => message;
}
