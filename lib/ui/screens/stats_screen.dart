// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../domain/shift_store.dart';
import '../../domain/stats.dart';
import '../../theme/app_theme.dart';

/// 統計頁：區間切換＋總覽卡片＋班次分佈（名稱＋時段）＋地點分佈。
class StatsScreen extends StatefulWidget {
  final ShiftStore store;

  const StatsScreen({super.key, required this.store});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  StatsRange _range = StatsRange.thisMonth;
  StatsResult? _cachedResult;
  StatsRange? _cachedRange;
  List<String>? _cachedSlotDisplayLabels;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) {
      setState(() {
        _cachedResult = null;
        _cachedSlotDisplayLabels = null;
      });
    }
  }

  (StatsResult, List<String>) _getOrCompute() {
    if (_cachedResult != null &&
        _cachedSlotDisplayLabels != null &&
        _cachedRange == _range) {
      return (_cachedResult!, _cachedSlotDisplayLabels!);
    }
    _cachedRange = _range;
    final computed = _compute();
    _cachedResult = computed.$1;
    _cachedSlotDisplayLabels = computed.$2;
    return computed;
  }

  /// 掃描區間排班紀錄，同時推導各時段對應的班次顯示標籤（如「早更 · 06–12」）。
  (StatsResult, List<String>) _compute() {
    final range = _range.range(DateTime.now());
    final records = <ShiftRecord>[];
    final usedNamesBySlot = List.generate(4, (_) => <String, int>{});

    var d = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    while (!d.isAfter(end)) {
      final ymd = ShiftStore.ymd(d);
      final a = widget.store.assignments[ymd];
      if (a != null) {
        final def = widget.store.defs[a.shiftId];
        if (def != null) {
          final slotIdx = slotIndexForTime(def.startTime).clamp(0, 3);
          usedNamesBySlot[slotIdx][def.name] =
              (usedNamesBySlot[slotIdx][def.name] ?? 0) + 1;
          records.add(ShiftRecord(
            ymd: ymd,
            shiftId: a.shiftId,
            venue: a.note,
            slotIndex: slotIdx,
            durationMinutes: shiftDurationMinutes(def.startTime, def.endTime),
          ));
        }
      }
      d = DateTime(d.year, d.month, d.day + 1);
    }

    // 若某時段區間內無排班紀錄，回退至班次定義的名稱（優先呈現主班次）
    final defNamesBySlot = List.generate(4, (_) => <String>[]);
    for (final def in widget.store.sortedDefs()) {
      final slotIdx = slotIndexForTime(def.startTime).clamp(0, 3);
      if (!defNamesBySlot[slotIdx].contains(def.name)) {
        defNamesBySlot[slotIdx].add(def.name);
      }
    }

    final displayLabels = List<String>.generate(4, (i) {
      final used = usedNamesBySlot[i].entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final names = used.isNotEmpty
          ? [for (final e in used.take(2)) e.key]
          : [for (final n in defNamesBySlot[i].take(2)) n];
      if (names.isEmpty) return slotLabels[i];
      return '${names.join('／')} · ${slotLabels[i]}';
    });

    return (computeStats(range, records), displayLabels);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (r, slotDisplayLabels) = _getOrCompute();
    return Scaffold(
      backgroundColor: kCalendarPageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('統計'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              _rangeChips(t),
              const SizedBox(height: 8),
              Text(
                _rangeCaption(r),
                style: TextStyle(fontSize: t.fontCaption, color: t.neutralFg2),
              ),
              const SizedBox(height: 10),
              _overview(t, r),
              const SizedBox(height: 14),
              _sectionTitle(t, '班次分佈'),
              const SizedBox(height: 6),
              _slotBars(t, r, slotDisplayLabels),
              const SizedBox(height: 14),
              _sectionTitle(t, '地點分佈'),
              const SizedBox(height: 6),
              _venueBars(t, r),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rangeChips(ShiftTokens t) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in StatsRange.values) ...[
            Builder(builder: (ctx) {
              final isSel = _range == r;
              return InkWell(
                onTap: () => setState(() {
                  _range = r;
                  _cachedResult = null;
                  _cachedSlotDisplayLabels = null;
                }),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSel ? t.brand : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSel ? t.brand : kCardStroke,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    r.label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                      color: isSel ? Colors.white : t.neutralFg,
                      height: 1.1,
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  String _rangeCaption(StatsResult r) {
    String fmt(DateTime d) => '${d.month}月${d.day}日';
    final s = r.range.start, e = r.range.end;
    final now = DateTime.now();
    final y = (s.year == now.year && e.year == now.year) ? '' : '${s.year}年';
    return '$y${fmt(s)} – ${fmt(e)} · 共${r.totalDays}天';
  }

  Widget _overview(ShiftTokens t, StatsResult r) {
    return Row(
      children: [
        _overviewCard(t, '返工', '${r.workDays}', '日'),
        const SizedBox(width: 8),
        _overviewCard(t, '總工時', r.durationLabel, ''),
        const SizedBox(width: 8),
        _overviewCard(t, '休息', '${r.restDays}', '日'),
      ],
    );
  }

  Widget _overviewCard(ShiftTokens t, String label, String value, String unit) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: kCardStroke),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: t.fontCaption, color: t.neutralFg2),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: RichText(
                  maxLines: 1,
                  softWrap: false,
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: t.fontTitle,
                      fontWeight: FontWeight.w700,
                      color: t.neutralFg,
                    ),
                    children: [
                      TextSpan(text: value),
                      if (unit.isNotEmpty)
                        TextSpan(
                          text: ' $unit',
                          style: TextStyle(
                            fontSize: t.fontCaption,
                            fontWeight: FontWeight.normal,
                            color: t.neutralFg2,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(ShiftTokens t, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: t.fontBody,
          fontWeight: FontWeight.w600,
          color: t.neutralFg,
        ),
      ),
    );
  }

  /// 四時段分佈卡：雙層精簡排版（上方「班次名稱 · 時段」與統計數值，下方全寬進度條），
  /// 兼顧可讀性與 320px × 2.0x 大字體零溢出防線。
  Widget _slotBars(
    ShiftTokens t,
    StatsResult r,
    List<String> slotDisplayLabels,
  ) {
    final bgs = [t.slot00Bg, t.slot06Bg, t.slot12Bg, t.slot18Bg];
    final fgs = [t.slot00Fg, t.slot06Fg, t.slot12Fg, t.slot18Fg];
    final borders = [
      t.slot00Border,
      t.slot06Border,
      t.slot12Border,
      t.slot18Border,
    ];
    final maxSlot =
        r.slotDays.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kCardStroke),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            for (var i = 0; i < 4; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        Text(
                          slotDisplayLabels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: t.fontBody,
                            fontWeight: FontWeight.w600,
                            color: fgs[i],
                          ),
                        ),
                        Text(
                          '${r.slotDays[i]}日 · ${r.slotPercent(i).toStringAsFixed(1)}%',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: t.fontCaption,
                            color: t.neutralFg2,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: t.neutralBg2,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor:
                            r.workDays == 0 ? 0 : r.slotDays[i] / maxSlot,
                        child: Container(
                          decoration: BoxDecoration(
                            color: bgs[i],
                            border: Border.all(color: borders[i]),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 地點分佈橫條：按次數降序排列。
  Widget _venueBars(ShiftTokens t, StatsResult r) {
    if (r.venueCounts.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: kCardStroke),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              '此區間暫無地點紀錄',
              style: TextStyle(fontSize: t.fontCaption, color: t.neutralFg2),
            ),
          ),
        ),
      );
    }
    final maxCount = r.venueCounts.first.value;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kCardStroke),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            for (var idx = 0; idx < r.venueCounts.length; idx++) ...[
              if (idx > 0) const SizedBox(height: 10),
              _venueBarRow(t, r.venueCounts[idx], maxCount),
            ],
          ],
        ),
      ),
    );
  }

  Widget _venueBarRow(
    ShiftTokens t,
    MapEntry<String, int> entry,
    int maxCount,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            entry.key,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: t.fontBody,
              fontWeight: FontWeight.w600,
              color: t.neutralFg,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 14,
            decoration: BoxDecoration(
              color: t.neutralBg2,
              borderRadius: BorderRadius.circular(6),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: maxCount == 0 ? 0 : entry.value / maxCount,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFD6E9F8),
                  border: Border.all(color: const Color(0xFFA9CCE8)),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Text(
            '${entry.value}次',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: t.fontCaption,
              color: t.neutralFg2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
