import 'package:flutter/material.dart';

import '../../domain/shift_store.dart';
import '../../domain/stats.dart';
import '../../theme/app_theme.dart';

/// 統計頁：區間切換＋總覽＋班次分佈＋場所分佈。
/// 只讀 ShiftStore；唔掂鬧鐘。
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
      });
    }
  }

  StatsResult _getOrCompute() {
    if (_cachedResult != null && _cachedRange == _range) {
      return _cachedResult!;
    }
    _cachedRange = _range;
    return _cachedResult = _compute();
  }

  /// 區間內逐日掃 assignments 組裝紀錄（defs 唔存在就跳過，防爛數據）。
  StatsResult _compute() {
    final range = _range.range(DateTime.now());
    final records = <ShiftRecord>[];
    var d = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    while (!d.isAfter(end)) {
      final ymd = ShiftStore.ymd(d);
      final a = widget.store.assignments[ymd];
      if (a != null) {
        final def = widget.store.defs[a.shiftId];
        if (def != null) {
          records.add(ShiftRecord(
            ymd: ymd,
            shiftId: a.shiftId,
            venue: a.note,
            slotIndex: slotIndexForTime(def.startTime),
          ));
        }
      }
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return computeStats(range, records);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = _getOrCompute();
    return Scaffold(
      appBar: AppBar(title: const Text('統計')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _rangeChips(t),
          const SizedBox(height: 8),
          Text(_rangeCaption(r),
              style: TextStyle(fontSize: t.fontCaption, color: t.neutralFg2)),
          const SizedBox(height: 8),
          _overview(t, r),
          const SizedBox(height: 12),
          _sectionTitle(t, '班次分佈'),
          const SizedBox(height: 4),
          _slotBars(t, r),
          const SizedBox(height: 12),
          _sectionTitle(t, '場所分佈'),
          const SizedBox(height: 4),
          _venueBars(t, r),
          const SizedBox(height: 16),
        ],
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
                }),
                borderRadius: BorderRadius.circular(6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSel ? t.brand : t.neutralBg2,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSel ? t.brand : t.neutralStroke,
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
    final y =
        (s.year == now.year && e.year == now.year) ? '' : '${s.year}年';
    return '$y${fmt(s)} – ${fmt(e)} · 共${r.totalDays}天';
  }

  Widget _overview(ShiftTokens t, StatsResult r) {
    return Row(
      children: [
        _overviewCard(t, '返工', '${r.workDays}', '日'),
        const SizedBox(width: 8),
        _overviewCard(t, '總工時', '${r.workHours}', '小時'),
        const SizedBox(width: 8),
        _overviewCard(t, '休息', '${r.restDays}', '日'),
      ],
    );
  }

  Widget _overviewCard(ShiftTokens t, String label, String value, String unit) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Text(label,
                  style:
                      TextStyle(fontSize: t.fontCaption, color: t.neutralFg2)),
              const SizedBox(height: 4),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                      fontSize: t.fontTitle,
                      fontWeight: FontWeight.w700,
                      color: t.neutralFg),
                  children: [
                    TextSpan(text: value),
                    TextSpan(
                      text: ' $unit',
                      style: TextStyle(
                          fontSize: t.fontCaption,
                          fontWeight: FontWeight.normal,
                          color: t.neutralFg2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(ShiftTokens t, String title) {
    return Text(title,
        style: TextStyle(
            fontSize: t.fontBody,
            fontWeight: FontWeight.w600,
            color: t.neutralFg));
  }

  /// 四時段橫條：用 theme 四色，長度按四段中最高日數佔比。
  Widget _slotBars(ShiftTokens t, StatsResult r) {
    final bgs = [t.slot00Bg, t.slot06Bg, t.slot12Bg, t.slot18Bg];
    final fgs = [t.slot00Fg, t.slot06Fg, t.slot12Fg, t.slot18Fg];
    final borders = [
      t.slot00Border,
      t.slot06Border,
      t.slot12Border,
      t.slot18Border
    ];
    final maxSlot =
        r.slotDays.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(slotLabels[i],
                          style: TextStyle(
                              fontSize: t.fontBody,
                              fontWeight: FontWeight.w600,
                              color: fgs[i])),
                    ),
                    Expanded(
                      child: Container(
                        height: 18,
                        decoration: BoxDecoration(
                          color: t.neutralBg2,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor:
                              r.workDays == 0 ? 0 : r.slotDays[i] / maxSlot,
                          child: Container(
                            decoration: BoxDecoration(
                              color: bgs[i],
                              border: Border.all(color: borders[i]),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 92,
                      child: Text(
                        '${r.slotDays[i]}日 · ${r.slotPercent(i).toStringAsFixed(1)}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: t.fontCaption, color: t.neutralFg2),
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

  /// 場所橫條：按次數降序，長度按最高次數佔比。
  Widget _venueBars(ShiftTokens t, StatsResult r) {
    if (r.venueCounts.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text('呢段時間未有場所紀錄',
                style:
                    TextStyle(fontSize: t.fontCaption, color: t.neutralFg2)),
          ),
        ),
      );
    }
    final maxCount = r.venueCounts.first.value;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (final e in r.venueCounts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(e.key,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: t.fontBody,
                              fontWeight: FontWeight.w600,
                              color: t.neutralFg)),
                    ),
                    Expanded(
                      child: Container(
                        height: 18,
                        decoration: BoxDecoration(
                          color: t.neutralBg2,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor:
                              maxCount == 0 ? 0 : e.value / maxCount,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFD6E9F8),
                              border:
                                  Border.all(color: const Color(0xFFA9CCE8)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 52,
                      child: Text('${e.value}次',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: t.fontCaption,
                              color: t.neutralFg2)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
