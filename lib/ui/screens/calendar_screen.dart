import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/alarm_service.dart';
import '../../domain/config_io.dart';
import '../../domain/holidays.dart';
import '../../domain/roster_io.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';
import '../dialogs/unified_import_dialog.dart';
import '../widgets/duo_book_page_view.dart';
import '../widgets/top_notification.dart';
import 'shift_picker_panel.dart';

/// 120ms 堅實微觸感（微縮放 1.0 -> 0.965 -> 1.0）日曆格包裝組件
class _HapticCell extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _HapticCell({
    super.key,
    required this.child,
    required this.onTap,
  });

  @override
  State<_HapticCell> createState() => _HapticCellState();
}

class _HapticCellState extends State<_HapticCell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.965)
            .chain(CurveTween(curve: Curves.easeInQuad)),
        weight: 38,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.965, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 62,
      ),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap() {
    _ctrl.forward(from: 0.0);
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}

/// 月曆：固定顯示 6 週（42 格），按月一頁頁左右滑動切換，極致 60fps GPU 快取過渡。
/// 支援 Duo 式 3D 左界書頁翻頁、排班卡片從無到有飄入、跨月純視覺流光過渡與 120ms 堅實微觸感。
class CalendarScreen extends StatefulWidget {
  final ShiftStore store;
  final AlarmService alarms;

  const CalendarScreen({super.key, required this.store, required this.alarms});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with TickerProviderStateMixin {
  /// 基準年月與頁碼映射：支援前後 100 年，徹底杜絕偏移算錯導致的 3943 年 Bug
  static const int _kBaseYear = 2026;
  static const int _kBaseMonth = 1;
  static const int _kInitialPage = 1200;

  int _pageForYearMonth(int year, int month) =>
      _kInitialPage + (year - _kBaseYear) * 12 + (month - _kBaseMonth);

  DateTime _monthForPage(int page) {
    final delta = page - _kInitialPage;
    return DateTime(_kBaseYear, _kBaseMonth + delta, 1);
  }

  late final DuoPageController _pageController;
  late int _currentPage;

  /// 頂部標題當前月份（以當前顯示頁面為準）
  late int _activeYear;
  late int _activeMonth;

  /// 詳情板選中日期（預設今日）；㩒日曆格更新
  late DateTime _selectedDate;

  /// 排班面板開關（固定 widget，擺喺日曆下方，唔遮日曆格）
  bool _schedPanelOpen = false;
  final GlobalKey<ShiftPickerPanelState> _panelKey =
      GlobalKey<ShiftPickerPanelState>();

  /// 備註便利貼 inline 編輯狀態
  bool _editingRemark = false;
  String _editingRemarkKey = '';
  late final TextEditingController _remarkCtrl;
  late final FocusNode _remarkFocus;

  /// 排班卡片從無到有飄入動畫控制器（時長 1100ms）
  late final AnimationController _cardFloatAnimCtrl;

  /// 跨月純視覺流光掃過動畫控制器（時長 650ms）
  late final AnimationController _sweepAnimCtrl;

  /// 今日 (Today) 柔和呼吸圈動畫控制器（循環 2000ms）
  late final AnimationController _todayPulseCtrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _activeYear = now.year;
    _activeMonth = now.month;
    _currentPage = _pageForYearMonth(now.year, now.month);
    _pageController = DuoPageController(initialPage: _currentPage);

    _cardFloatAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..addListener(() {
        if (mounted) setState(() {});
      });

    _sweepAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..addListener(() {
        if (mounted) setState(() {});
      });

    _todayPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _todayPulseCtrl.addListener(() {
      if (mounted) setState(() {});
    });

    _remarkCtrl = TextEditingController();
    _remarkFocus = FocusNode();
    _remarkFocus.addListener(() {
      // 收鍵盤／失焦 → 自動保存
      if (!_remarkFocus.hasFocus && _editingRemark) {
        _saveInlineRemark();
      }
    });

    widget.store.addListener(_onStoreChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUrlHashImport();
      _checkMonthTransitionOnStartup();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _cardFloatAnimCtrl.dispose();
    _sweepAnimCtrl.dispose();
    _todayPulseCtrl.dispose();
    _remarkCtrl.dispose();
    _remarkFocus.dispose();
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  /// 檢查是否每逢新月第一次進入：觸發純視覺流光掃過上月並自然 3D 翻書過渡到本月
  void _checkMonthTransitionOnStartup() {
    final now = DateTime.now();
    final currentKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final lastSeen = widget.store.prefs.getString('last_seen_active_month');
    if (lastSeen == null) {
      widget.store.prefs.setString('last_seen_active_month', currentKey);
      return;
    }
    if (lastSeen != currentKey) {
      final parts = lastSeen.split('-');
      if (parts.length == 2) {
        final lastYear = int.tryParse(parts[0]);
        final lastMonth = int.tryParse(parts[1]);
        if (lastYear != null && lastMonth != null) {
          final prevDate = DateTime(lastYear, lastMonth, 1);
          final targetPage = _pageForYearMonth(now.year, now.month);
          final prevPage = _pageForYearMonth(prevDate.year, prevDate.month);
          if (targetPage - prevPage == 1) {
            // 剛好隔 1 個月：先停留在上一月，流光掃過上月月末，然後自然 3D 翻書進本月
            _pageController.jumpToPage(prevPage);
            setState(() {
              _currentPage = prevPage;
              _activeYear = prevDate.year;
              _activeMonth = prevDate.month;
            });
            Future.delayed(const Duration(milliseconds: 350), () {
              if (!mounted) return;
              _sweepAnimCtrl.forward(from: 0.0).then((_) {
                if (!mounted) return;
                _shiftMonth(1);
                widget.store.prefs.setString('last_seen_active_month', currentKey);
              });
            });
            return;
          }
        }
      }
      widget.store.prefs.setString('last_seen_active_month', currentKey);
    }
  }

  /// store 有寫入即自動刷新
  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _onPageChanged(int page) {
    final m = _monthForPage(page);
    setState(() {
      _currentPage = page;
      _activeYear = m.year;
      _activeMonth = m.month;
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    final targetPage = _pageForYearMonth(now.year, now.month);
    setState(() {
      _selectedDate = DateTime(now.year, now.month, now.day);
      _activeYear = now.year;
      _activeMonth = now.month;
      _currentPage = targetPage;
    });
    if (_pageController.hasClients) {
      final curPage = _pageController.page;
      if (curPage != targetPage) {
        if ((targetPage - curPage).abs() <= 1) {
          _pageController.animateToPage(
            targetPage,
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
          );
        } else {
          _pageController.jumpToPage(targetPage);
        }
      }
    }
  }

  /// 左右切月：平滑切換到上一月／下一月（Duo 3D 書頁立體翻頁）
  void _shiftMonth(int delta) {
    if (!_pageController.hasClients) return;
    final targetPage = _currentPage + delta;
    _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  /// 開排班面板：取代詳情板，擺喺日曆下方
  void _openPanel() {
    if (_editingRemark) {
      _saveInlineRemark();
    }
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _schedPanelOpen = true);
  }

  /// 彈出年月選擇器（快速跳轉指定月份）
  void _showMonthPicker() {
    int selectedYear = _activeYear;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final t = context.tokens;
          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => setDialogState(() => selectedYear--),
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '上一年',
                ),
                Text('$selectedYear年',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: t.neutralFg)),
                IconButton(
                  onPressed: () => setDialogState(() => selectedYear++),
                  icon: const Icon(Icons.chevron_right),
                  tooltip: '下一年',
                ),
              ],
            ),
            content: SizedBox(
              width: 280,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.8,
                ),
                itemCount: 12,
                itemBuilder: (_, i) {
                  final month = i + 1;
                  final isCurrent =
                      selectedYear == _activeYear && month == _activeMonth;
                  return InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _jumpToYearMonth(selectedYear, month);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isCurrent ? t.brand : t.neutralBg2,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isCurrent ? t.brand : t.neutralStroke,
                        ),
                      ),
                      child: Text(
                        '$month月',
                        style: TextStyle(
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isCurrent ? Colors.white : t.neutralFg,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('關閉',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _jumpToYearMonth(int year, int month) {
    final targetPage = _pageForYearMonth(year, month);
    if (_pageController.hasClients) {
      final curPage = _pageController.page;
      if ((targetPage - curPage).abs() <= 1) {
        _pageController.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
      } else {
        _pageController.jumpToPage(targetPage);
      }
    }
    setState(() {
      _currentPage = targetPage;
      _activeYear = year;
      _activeMonth = month;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _showMonthPicker,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$_activeYear年$_activeMonth月'),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton.tonalIcon(
            onPressed: () => showUnifiedImportDialog(
              context: context,
              store: widget.store,
              alarms: widget.alarms,
              onImportDone: () {
                setState(() {});
                _cardFloatAnimCtrl.forward(from: 0.0);
              },
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 36),
            ),
            icon: const Icon(Icons.file_download_outlined, size: 17),
            label: const Text('導入',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 4),
          OutlinedButton(
            onPressed: _goToToday,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 36),
            ),
            child: const Text('今日',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
          ),
          IconButton(
            onPressed: () => _shiftMonth(-1),
            icon: const Icon(Icons.chevron_left, size: 24),
            tooltip: '上一月',
          ),
          IconButton(
            onPressed: () => _shiftMonth(1),
            icon: const Icon(Icons.chevron_right, size: 24),
            tooltip: '下一月',
          ),
        ],
      ),
      body: Column(
        children: [
          _weekHeader(t),
          Expanded(
            child: DuoBookPageView(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemBuilder: (_, page) {
                final m = _monthForPage(page);
                // RepaintBoundary 將每個月緩存為獨立 GPU 紋理圖層，滑動時零 CPU 重繪，達到原生級 60fps
                return RepaintBoundary(
                  key: ValueKey('month_${m.year}_${m.month}'),
                  child: _monthGrid(t, m.year, m.month),
                );
              },
            ),
          ),
          // 排班面板或精簡詳情板
          _schedPanelOpen
              ? ShiftPickerPanel(
                  key: _panelKey,
                  initialDate: _selectedDate,
                  store: widget.store,
                  alarms: widget.alarms,
                  onClose: () => setState(() => _schedPanelOpen = false),
                )
              : _detailPanel(t),
        ],
      ),
    );
  }

  /// 一個月固定 6 週（42 格）標準網格：緊湊排版，消除上下左右與行距多餘留白
  Widget _monthGrid(ShiftTokens t, int year, int month) {
    final firstDay = DateTime(year, month, 1);
    final firstWeekday = firstDay.weekday % 7; // 星期日為 0
    final firstSunday = DateTime(year, month, 1 - firstWeekday);
    const weekCount = 6; // 永遠固定 6 行（42 格），消除跨月高度撕裂與抖動
    final today = DateTime.now();

    return Column(
      children: [
        for (int w = 0; w < weekCount; w++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0.5),
              child: Row(
                children: [
                  for (int d = 0; d < 7; d++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: d < 6 ? 1.5 : 0),
                        child: _dayCell(
                          t,
                          DateTime(firstSunday.year, firstSunday.month,
                              firstSunday.day + w * 7 + d),
                          today,
                          year,
                          month,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 日曆格：清晰對比、主次分明、字重自然平衡
  Widget _dayCell(
    ShiftTokens t,
    DateTime date,
    DateTime today,
    int activeYear,
    int activeMonth,
  ) {
    final day = date.day;
    final key = ShiftStore.ymd(date);
    final assignment = widget.store.assignments[key];
    final def = assignment != null ? widget.store.defs[assignment.shiftId] : null;
    final note = assignment?.note ?? '';
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final isSelected = date.year == _selectedDate.year &&
        date.month == _selectedDate.month &&
        date.day == _selectedDate.day;
    final isCurrentMonth =
        date.year == activeYear && date.month == activeMonth;
    final holiday = holidayName(date);

    final slot = def != null ? t.slotForTime(def.startTime) : null;
    final baseFg = slot?.fg ?? t.neutralFg;
    final baseBg = slot?.bg ?? t.neutralBg;

    // 當月與非當月（上月／下月）的色彩處理：減弱濾鏡效果，保持色彩清晰可辨
    final Color cellBg;
    final Color borderColor;
    final Color dateColor;
    final Color abbrColor;
    final Color noteColor;

    if (isCurrentMonth) {
      cellBg = baseBg;
      borderColor = isSelected
          ? t.brand
          : (isToday ? t.brand.withValues(alpha: 0.65) : (slot?.border ?? t.neutralStroke));
      dateColor = (holiday != null) ? t.danger : baseFg;
      abbrColor = baseFg;
      noteColor = baseFg;
    } else {
      // 鄰月淡化處理：再微調淺約 15%，保持柔和層次區分
      cellBg = def != null
          ? slot!.bg.withValues(alpha: 0.48)
          : t.neutralBg2.withValues(alpha: 0.45);
      borderColor = isSelected
          ? t.brand
          : (isToday
              ? t.brand.withValues(alpha: 0.55)
              : (slot?.border ?? t.neutralStroke).withValues(alpha: 0.38));
      dateColor = (holiday != null)
          ? t.danger.withValues(alpha: 0.52)
          : t.neutralFg.withValues(alpha: 0.42);
      abbrColor = (slot?.fg ?? t.neutralFg).withValues(alpha: 0.55);
      noteColor = (slot?.fg ?? t.neutralFg2).withValues(alpha: 0.48);
    }

    // 今日 (Today) 柔和微呼吸圈
    BoxShadow? todayPulseShadow;
    if (isToday && isCurrentMonth) {
      final pulseVal = _todayPulseCtrl.value;
      todayPulseShadow = BoxShadow(
        color: t.brand.withValues(alpha: 0.12 + 0.26 * pulseVal),
        blurRadius: 4.0 + 3.0 * pulseVal,
        spreadRadius: 0.5 + 1.2 * pulseVal,
      );
    }

    // 排班卡片從無到有飄入計算（Staggered Float In）
    final bool isCardFloating =
        _cardFloatAnimCtrl.isAnimating && isCurrentMonth && def != null;
    double cardT = 1.0;
    if (isCardFloating) {
      final dayRatio = ((day - 1) * 0.022).clamp(0.0, 0.70);
      final endRatio = (dayRatio + 0.30).clamp(0.0, 1.0);
      final animVal = _cardFloatAnimCtrl.value;
      if (animVal < dayRatio) {
        cardT = 0.0;
      } else if (animVal >= endRatio) {
        cardT = 1.0;
      } else {
        final localT = (animVal - dayRatio) / (endRatio - dayRatio);
        cardT = Curves.easeOutBack.transform(localT);
      }
    }

    Widget wrapFloatingCard(Widget child) {
      if (!isCardFloating) return child;
      if (cardT <= 0.001) return const SizedBox.shrink();
      final clampedT = cardT.clamp(0.0, 1.0);
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..translate(0.0, -24.0 * (1.0 - clampedT))
          ..rotateX(0.18 * (1.0 - clampedT))
          ..scale(0.92 + 0.08 * clampedT),
        child: Opacity(
          opacity: clampedT,
          child: child,
        ),
      );
    }

    // 月終純視覺時間流光（sweepAnimCtrl 播放時依序掠過 1~31 日）
    Widget? sweepOverlay;
    if (_sweepAnimCtrl.isAnimating && isCurrentMonth) {
      final dayProg = (day - 1) / 30.0;
      final sweepVal = _sweepAnimCtrl.value;
      final dist = (sweepVal - dayProg).abs();
      if (dist < 0.14) {
        final intensity = (1.0 - dist / 0.14).clamp(0.0, 1.0);
        sweepOverlay = Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: t.brand.withValues(alpha: 0.22 * intensity),
                border: Border.all(
                  color: t.brand.withValues(alpha: 0.55 * intensity),
                  width: 1.5,
                ),
              ),
            ),
          ),
        );
      }
    }

    Widget cell = Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: cellBg,
        border: Border.all(
          color: borderColor,
          width: (isSelected || isToday) ? 1.5 : 1.0,
        ),
        borderRadius: BorderRadius.circular(4),
        boxShadow: todayPulseShadow != null ? [todayPulseShadow] : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 第一行：日期（自然平衡 17.0px w500，避免 Android 系統過粗）
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 17.0,
                          fontWeight: FontWeight.w500,
                          color: dateColor,
                          height: 1.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                // 第二行：班次縮寫（清晰適中 17.0px w600，支援從無到有飄入）
                Expanded(
                  child: Center(
                    child: def != null
                        ? wrapFloatingCard(
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                truncateAbbr(def.abbr),
                                style: TextStyle(
                                  fontSize: 17.0,
                                  fontWeight: FontWeight.w600,
                                  color: abbrColor,
                                  height: 1.0,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                // 第三行：地點（常規字重 17.0px normal，支援從無到有飄入）
                Expanded(
                  child: Center(
                    child: (def != null && note.isNotEmpty)
                        ? wrapFloatingCard(
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                truncateAbbr(note),
                                style: TextStyle(
                                  fontSize: 17.0,
                                  fontWeight: FontWeight.normal,
                                  color: noteColor,
                                  height: 1.0,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
          // 公眾假期頂部紅色微粗線指示條（緊貼框邊，頂部圓角契合外框）
          if (holiday != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 2.8,
              child: Container(
                decoration: BoxDecoration(
                  color: isCurrentMonth
                      ? t.danger
                      : t.danger.withValues(alpha: 0.50),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3.0),
                  ),
                ),
              ),
            ),
          // 月終純視覺時間流光（掠過 1~31 日）
          if (sweepOverlay != null) sweepOverlay,
        ],
      ),
    );

    return _HapticCell(
      onTap: () {
        if (_editingRemark) {
          _saveInlineRemark();
        }
        if (_schedPanelOpen) {
          _panelKey.currentState?.goToDate(date);
          setState(() {
            _selectedDate = DateTime(date.year, date.month, date.day);
          });
          if (!isCurrentMonth) {
            _jumpToYearMonth(date.year, date.month);
          }
          return;
        }
        setState(() {
          _selectedDate = DateTime(date.year, date.month, date.day);
        });
        if (!isCurrentMonth) {
          _jumpToYearMonth(date.year, date.month);
        }
      },
      child: cell,
    );
  }

  /// 日曆下方詳情面板：
  /// - 上方：備註便簽欄
  /// - 下方：日期、班次、地點詳情條（兩行高，自然字重重構排版，主次分明）
  Widget _detailPanel(ShiftTokens t) {
    final key = ShiftStore.ymd(_selectedDate);
    final assignment = widget.store.assignments[key];
    final def =
        assignment != null ? widget.store.defs[assignment.shiftId] : null;
    final note = assignment?.note ?? '';
    final remark = widget.store.remarks[key] ?? '';
    final holiday = holidayName(_selectedDate);
    const weekdays = ['日', '一', '二', '三', '四', '五', '六'];
    final weekdayName = weekdays[_selectedDate.weekday % 7];
    final slot = def != null ? t.slotForTime(def.startTime) : null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.neutralBg,
        border: Border(top: BorderSide(color: t.neutralStroke)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 126,
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8, left: 12, right: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 第一行（上方）：備註便簽欄（嚴格固定高度 38px）
                SizedBox(
                  height: 38,
                  child: _editingRemark
                      ? TextField(
                          controller: _remarkCtrl,
                          focusNode: _remarkFocus,
                          maxLines: 1,
                          maxLength: ShiftStore.maxRemarkLength,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: t.neutralBg2,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: t.brand, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            counterText: '',
                            isDense: true,
                            hintText: '新增備註…',
                            prefixIcon: Icon(Icons.notes_rounded,
                                size: 16, color: t.neutralFg2),
                            suffixIcon: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.check, size: 18),
                              onPressed: _saveInlineRemark,
                            ),
                          ),
                          onEditingComplete: _saveInlineRemark,
                        )
                      : GestureDetector(
                          onTap: () {
                            _remarkCtrl.text = widget.store.remarks[key] ?? '';
                            setState(() {
                              _editingRemark = true;
                              _editingRemarkKey = key;
                            });
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _remarkFocus.requestFocus();
                            });
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            height: 38,
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: t.neutralBg2,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: t.neutralStroke),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.notes_rounded,
                                    size: 16, color: t.neutralFg2),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    remark.isEmpty ? '新增備註…' : remark,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: remark.isEmpty
                                          ? t.neutralFg2
                                          : t.neutralFg,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                // 第二行（下方）：日期排班地點（嚴格固定高度 64px，排版居中穩定）
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: t.neutralBg2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: t.neutralStroke),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // 上行：日期與星期（固定 22px）
                            SizedBox(
                              height: 22,
                              child: Row(
                                children: [
                                  Text(
                                    '${_selectedDate.month}月${_selectedDate.day}日',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w500,
                                      color: t.neutralFg,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '星期$weekdayName',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.normal,
                                      color: t.neutralFg2,
                                    ),
                                  ),
                                  if (holiday != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: t.danger.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        holiday,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: t.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 3),
                            // 下行：班次時間 與 地點（固定 23px）
                            SizedBox(
                              height: 23,
                              child: Row(
                                children: [
                                  if (def != null) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: slot?.bg ?? t.neutralBg,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: slot?.border ?? t.neutralStroke,
                                        ),
                                      ),
                                      child: Text(
                                        def.name,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: slot?.fg ?? t.neutralFg,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${def.startTime}–${def.endTime}',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.normal,
                                        color: t.neutralFg,
                                      ),
                                    ),
                                  ] else ...[
                                    Text(
                                      '未排班',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.normal,
                                        color: t.neutralFg2,
                                      ),
                                    ),
                                  ],
                                  if (note.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Icon(Icons.location_on, size: 14, color: t.brand),
                                    const SizedBox(width: 2),
                                    Flexible(
                                      child: Text(
                                        note,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.normal,
                                          color: t.brand,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // 右側：排班按鈕（自適應兩行高度）
                      FilledButton.icon(
                        onPressed: _openPanel,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          minimumSize: const Size(0, 42),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.edit_calendar, size: 16),
                        label: const Text(
                          '排班',
                          style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveInlineRemark() async {
    if (!_editingRemark) return;
    final key = _editingRemarkKey;
    final text = _remarkCtrl.text;
    setState(() {
      _editingRemark = false;
      _editingRemarkKey = '';
    });
    _remarkFocus.unfocus();
    await widget.store.setRemark(key, text);
    if (mounted) {
      showTopNotification(context, '備註已保存');
    }
  }

  Widget _weekHeader(ShiftTokens t) {
    const names = ['日', '一', '二', '三', '四', '五', '六'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: names
            .map((n) => Expanded(
                  child: Center(
                    child: Text(n,
                        style: TextStyle(
                            fontSize: t.fontCaption,
                            color: t.neutralFg2,
                            fontWeight: FontWeight.w600)),
                  ),
                ))
            .toList(),
      ),
    );
  }

  bool _urlHashHandled = false;

  /// 自動檢查網址參數與 Hash（優先 ?c=SA2:... / ?r=SR2:... 避免微信標籤誤判；相容 #c= / #r=）
  void _checkUrlHashImport() {
    if (_urlHashHandled) return;

    String? configCode;
    String? rosterCode;

    // 1. 優先檢查 Query 參數（?c=... 或 ?r=...），在微信中完全無 # 符號，徹底杜絕被誤認為話題標籤
    final q = Uri.base.queryParameters;
    if (q.containsKey('c') && q['c']!.isNotEmpty) {
      configCode = q['c'];
    } else if (q.containsKey('r') && q['r']!.isNotEmpty) {
      rosterCode = q['r'];
    }

    // 2. 次選檢查 Hash 錨點（#c=... 或 #r=...）相容直接輸入或錨點連結
    if (configCode == null && rosterCode == null) {
      final fragment = Uri.base.fragment;
      if (fragment.isNotEmpty) {
        if (fragment.startsWith('c=')) {
          configCode = Uri.decodeComponent(fragment.substring(2));
        } else if (fragment.startsWith('r=')) {
          rosterCode = Uri.decodeComponent(fragment.substring(2));
        } else if (isConfigPacket(fragment)) {
          configCode = Uri.decodeComponent(fragment);
        } else if (isRosterPacket(fragment)) {
          rosterCode = Uri.decodeComponent(fragment);
        }
      }
    }

    if (configCode == null && rosterCode == null) return;
    _urlHashHandled = true;

    if (configCode != null && mounted) {
      _promptImportConfigFromUrl(configCode);
    } else if (rosterCode != null && mounted) {
      _promptImportRosterFromUrl(rosterCode);
    }
  }

  Future<void> _promptImportConfigFromUrl(String code) async {
    try {
      final p = previewConfig(code);
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.link, color: context.tokens.brand),
              const SizedBox(width: 8),
              const Text('網址配置導入'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('檢測到網址分享的班次與地點配置：'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.tokens.neutralBg2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.tokens.neutralStroke),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• 班次數量：${p.shifts} 個 (${p.names.join('、')})',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('• 常用地點：${p.venues} 個',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '注意：導入後將覆蓋現有班次與地點設定。是否立即導入？',
                style: TextStyle(fontSize: 12, color: Colors.red),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('取消', style: TextStyle(fontSize: 14)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('確定導入',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        await importConfigText(widget.store, code);
        if (mounted) {
          showTopNotification(context, '配置已成功導入！');
        }
      }
    } catch (e) {
      if (mounted) {
        showTopNotification(context, '網址配置解析失敗: $e',
            icon: Icons.error_outline, iconColor: const Color(0xFFF87171));
      }
    }
  }

  Future<void> _promptImportRosterFromUrl(String code) async {
    try {
      final decoded = decodeRosterText(code, widget.store.defs);
      if (decoded.importResult.valid.isEmpty) {
        if (mounted) {
          showTopNotification(
            context,
            decoded.importResult.errors.isNotEmpty
                ? decoded.importResult.errors.first
                : '排班數據無效',
            icon: Icons.error_outline,
            iconColor: const Color(0xFFF87171),
          );
        }
        return;
      }

      final count = decoded.importResult.valid.length;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.link, color: context.tokens.brand),
              const SizedBox(width: 8),
              const Text('網址排班導入'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('檢測到網址分享的排班表（共 $count 天排班）：'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.tokens.neutralBg2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.tokens.neutralStroke),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• 待導入排班天數：$count 天',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('是否將此排班表套用至日曆？', style: TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('取消', style: TextStyle(fontSize: 14)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('套用排班',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        await widget.store.assignBatch([
          for (final r in decoded.importResult.valid)
            (ymd: r.date, shiftId: r.shiftId, note: r.venue, remark: r.remark)
        ]);
        if (isNativeAlarmSupported) {
          for (final r in decoded.importResult.valid) {
            final def = widget.store.defs[r.shiftId];
            if (def == null) continue;
            try {
              await widget.alarms.onAssigned(
                r.date,
                def,
                note: r.venue,
              );
            } catch (_) {}
          }
        }
        if (mounted) {
          showTopNotification(context, '成功導入 $count 天排班！');
        }
      }
    } catch (e) {
      if (mounted) {
        showTopNotification(context, '網址排班解析失敗: $e',
            icon: Icons.error_outline, iconColor: const Color(0xFFF87171));
      }
    }
  }
}
