import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/alarm_service.dart';
import '../../domain/config_io.dart';
import '../../domain/roster_io.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';

/// 智慧通用導入彈窗：支援 SR2 排班口令、SA2 配置口令、分享網址（?r= / ?c=）與純 CSV 文字的一鍵辨識與校驗
Future<void> showUnifiedImportDialog({
  required BuildContext context,
  required ShiftStore store,
  required AlarmService alarms,
  VoidCallback? onImportDone,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _UnifiedImportDialog(
      store: store,
      alarms: alarms,
      onImportDone: onImportDone,
    ),
  );
}

class _UnifiedImportDialog extends StatefulWidget {
  final ShiftStore store;
  final AlarmService alarms;
  final VoidCallback? onImportDone;

  const _UnifiedImportDialog({
    required this.store,
    required this.alarms,
    this.onImportDone,
  });

  @override
  State<_UnifiedImportDialog> createState() => _UnifiedImportDialogState();
}

class _UnifiedImportDialogState extends State<_UnifiedImportDialog> {
  final TextEditingController _ctrl = TextEditingController();

  DecodedRosterResult? _rosterResult;
  ConfigPreview? _configPreview;
  String? _parseError;
  bool _importing = false;
  bool _clipboardAutoDetected = false;
  String _detectedType = '';

  @override
  void initState() {
    super.initState();
    _checkClipboardOnOpen();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 從網址或原始文字中提取口令或排班內容
  String _extractCodeOrText(String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null) {
        final q = uri.queryParameters;
        if (q.containsKey('r') && q['r']!.isNotEmpty) {
          return q['r']!;
        }
        if (q.containsKey('c') && q['c']!.isNotEmpty) {
          return q['c']!;
        }
        final f = uri.fragment;
        if (f.startsWith('r=')) return Uri.decodeComponent(f.substring(2));
        if (f.startsWith('c=')) return Uri.decodeComponent(f.substring(2));
        if (isRosterPacket(f) || isConfigPacket(f)) return Uri.decodeComponent(f);
      }
    }
    return trimmed;
  }

  Future<void> _checkClipboardOnOpen() async {
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = clip?.text?.trim() ?? '';
      if (raw.isNotEmpty) {
        final code = _extractCodeOrText(raw);
        if (isRosterPacket(code) || isConfigPacket(code) || code.contains(',')) {
          _ctrl.text = raw;
          _parseText(raw, fromClipboard: true);
        }
      }
    } catch (_) {}
  }

  void _parseText(String raw, {bool fromClipboard = false}) {
    final clean = _extractCodeOrText(raw);
    _rosterResult = null;
    _configPreview = null;
    _parseError = null;
    _detectedType = '';

    if (clean.isEmpty) {
      setState(() {
        _clipboardAutoDetected = false;
      });
      return;
    }

    // 1. 優先檢查是否為配置報文（SA2:）
    if (isConfigPacket(clean)) {
      try {
        final preview = previewConfig(clean);
        setState(() {
          _configPreview = preview;
          _detectedType = '配置口令 (SA2)';
          if (fromClipboard) _clipboardAutoDetected = true;
        });
        return;
      } on ConfigImportException catch (e) {
        setState(() {
          _parseError = e.message;
        });
        return;
      } catch (e) {
        setState(() {
          _parseError = '配置口令解析失敗：$e';
        });
        return;
      }
    }

    // 2. 檢查排班報文（SR2:）或 CSV 排班文字
    try {
      final decoded = decodeRosterText(clean, widget.store.defs);
      if (decoded.importResult.valid.isNotEmpty) {
        setState(() {
          _rosterResult = decoded;
          _detectedType = decoded.isPacket ? '排班口令 (SR2)' : 'CSV 純文字排班';
          if (fromClipboard) _clipboardAutoDetected = true;
        });
        return;
      } else if (decoded.importResult.errors.isNotEmpty) {
        setState(() {
          _parseError = decoded.importResult.errors.first;
        });
        return;
      }
    } catch (e) {
      setState(() {
        _parseError = '排班數據格式異常：$e';
      });
      return;
    }

    setState(() {
      _parseError = '未辨識為有效排班或配置口令，請檢查內容';
    });
  }

  static int _accentBg(ShiftDef def) =>
      const ShiftTokens().slotForTime(def.startTime).bg.toARGB32();
  static int _accentFg(ShiftDef def) =>
      const ShiftTokens().slotForTime(def.startTime).fg.toARGB32();

  Future<void> _executeImport() async {
    if (_importing) return;
    setState(() => _importing = true);

    final clean = _extractCodeOrText(_ctrl.text);

    // A. 導入配置
    if (_configPreview != null) {
      try {
        await importConfigText(widget.store, clean);
        if (mounted) {
          Navigator.pop(context);
          widget.onImportDone?.call();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '配置導入成功：${_configPreview!.shifts} 個班次、'
                '${_configPreview!.venues} 個場所',
              ),
              backgroundColor: const Color(0xFF2E7D32),
            ),
          );
        }
      } catch (e) {
        setState(() {
          _importing = false;
          _parseError = '配置導入失敗：$e';
        });
      }
      return;
    }

    // B. 導入排班
    if (_rosterResult != null) {
      try {
        final rows = _rosterResult!.importResult.valid;
        await widget.store.assignBatch([
          for (final r in rows)
            (
              ymd: r.date,
              shiftId: r.shiftId,
              note: r.venue,
              remark: r.remark,
            )
        ]);

        var alarmSuccessCount = 0;
        for (final r in rows) {
          final def = widget.store.defs[r.shiftId];
          if (def == null) continue;
          try {
            await widget.alarms.onAssigned(
              r.date,
              def,
              accentBg: _accentBg(def),
              accentFg: _accentFg(def),
              note: r.venue,
            );
            alarmSuccessCount++;
          } catch (_) {}
        }

        if (mounted) {
          Navigator.pop(context);
          widget.onImportDone?.call();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('排班導入成功：共 ${rows.length} 日排班（$alarmSuccessCount 個鬧鐘已同步）'),
              backgroundColor: const Color(0xFF2E7D32),
            ),
          );
        }
      } catch (e) {
        setState(() {
          _importing = false;
          _parseError = '排班寫入失敗：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canConfirm = (_rosterResult != null &&
            _rosterResult!.importResult.valid.isNotEmpty) ||
        _configPreview != null;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.file_download_outlined, color: Color(0xFF0078D4)),
          SizedBox(width: 8),
          Text('導入排班 / 配置', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_clipboardAutoDetected)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFA5D6A7)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.content_paste_go,
                          size: 16, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '已自動辨識剪貼簿：$_detectedType',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                '支援貼上 SR2: 排班口令、SA2: 配置口令、分享網址（?r= / ?c=）或純 CSV 文字。',
                style: TextStyle(fontSize: 12, color: t.neutralFg2),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '粘貼口令碼或排班內容：',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        final clip =
                            await Clipboard.getData(Clipboard.kTextPlain);
                        final text = clip?.text?.trim() ?? '';
                        if (text.isNotEmpty) {
                          _ctrl.text = text;
                          _parseText(text);
                        }
                      } catch (_) {}
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.paste, size: 14),
                    label: const Text('貼上剪貼簿', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _ctrl,
                maxLines: 5,
                minLines: 3,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: '貼上 SR2:... / SA2:... / 網址或每行「YYYY-MM-DD,代號,場所」…',
                  hintStyle: const TextStyle(fontSize: 12),
                  suffixIcon: _ctrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _ctrl.clear();
                            _parseText('');
                          },
                        )
                      : null,
                ),
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                onChanged: (text) => _parseText(text),
              ),
              if (_parseError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _parseError!,
                  style: TextStyle(fontSize: 12, color: t.danger),
                ),
              ],
              if (_rosterResult != null) ...[
                const SizedBox(height: 10),
                _buildRosterPreview(_rosterResult!, t),
              ],
              if (_configPreview != null) ...[
                const SizedBox(height: 10),
                _buildConfigPreview(_configPreview!, t),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: (canConfirm && !_importing) ? _executeImport : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0078D4),
            foregroundColor: Colors.white,
          ),
          icon: _importing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check, size: 16),
          label: Text(_importing ? '導入中…' : '確認導入'),
        ),
      ],
    );
  }

  Widget _buildRosterPreview(DecodedRosterResult res, ShiftTokens t) {
    final r = res.importResult;
    final overwrite = r.valid
        .where((row) => widget.store.assignments.containsKey(row.date))
        .length;
    final dates = r.valid.map((e) => e.date).toList()..sort();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.neutralBg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.neutralStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('有效 ${r.valid.length} 日排班',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const Spacer(),
              if (res.crcVerified)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified, size: 12, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 3),
                      Text('CRC32 通過 (${res.crcHex})',
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2E7D32))),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (dates.isNotEmpty)
            Text(
              '日期範圍：${dates.first} 至 ${dates.last}',
              style: TextStyle(fontSize: 12, color: t.neutralFg2),
            ),
          if (overwrite > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '提示：其中 $overwrite 日已有排班，確認導入將覆蓋。',
                style: const TextStyle(fontSize: 11, color: Color(0xFFE65100)),
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final row in r.valid.take(8))
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.neutralBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: t.neutralStroke),
                  ),
                  child: Text(
                    '${row.date.substring(5)}: ${row.shiftId}${row.venue.isNotEmpty ? ' (${row.venue})' : ''}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              if (r.valid.length > 8)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text('+ 還有 ${r.valid.length - 8} 日…',
                      style: TextStyle(fontSize: 11, color: t.neutralFg2)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfigPreview(ConfigPreview p, ShiftTokens t) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.neutralBg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.neutralStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${p.shifts} 個班次、${p.venues} 個場所',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const Spacer(),
              if (p.crcVerified)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified, size: 12, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 3),
                      Text('CRC32 通過 (${p.crcHex})',
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2E7D32))),
                    ],
                  ),
                ),
            ],
          ),
          if (p.names.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '班次：${p.names.join('、')}',
              style: TextStyle(fontSize: 12, color: t.neutralFg2),
            ),
          ],
          const SizedBox(height: 4),
          const Text(
            '⚠️ 注意：導入新配置將更新現有班次與場所清單。',
            style: TextStyle(fontSize: 11, color: Color(0xFFE65100)),
          ),
        ],
      ),
    );
  }
}
