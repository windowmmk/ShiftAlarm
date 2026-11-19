import 'dart:ui' show PointerDeviceKind;

import 'package:auto_size_text/auto_size_text.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../domain/alarm_service.dart';
import '../../domain/calendar_layout.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';
import '../dialogs/unified_import_dialog.dart';
import '../widgets/ocean_band.dart';
import '../widgets/top_notification.dart';
import 'calendar/calendar_detail_card.dart';
import 'calendar/calendar_month_grid.dart';
import 'calendar/calendar_month_picker.dart';
import 'calendar/url_import_handler.dart';
import 'shift_picker_panel.dart';

/// 支援桌面滑鼠拖曳、觸控、觸控板左右翻月的 ScrollBehavior。
class _CalendarScrollBehavior extends MaterialScrollBehavior {
  const _CalendarScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// 月曆主畫面：三區固定版面（頂部天色帶／中間 42 格月曆卡／底部排班詳情與原地編輯）。
class CalendarScreen extends StatefulWidget {
  final ShiftStore store;
  final AlarmService alarms;

  const CalendarScreen({super.key, required this.store, required this.alarms});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with TickerProviderStateMixin {
  static const int _kBaseYear = 2026;
  static const int _kBaseMonth = 1;
  static const int _kInitialPage = 1200;

  int _pageForYearMonth(int year, int month) =>
      _kInitialPage + (year - _kBaseYear) * 12 + (month - _kBaseMonth);

  DateTime _monthForPage(int page) =>
      DateTime(_kBaseYear, _kBaseMonth + (page - _kInitialPage), 1);

  late final PageController _pageController;
  late int _currentPage;
  late int _activeYear;
  late int _activeMonth;
  late DateTime _selectedDate;

  bool _pickerMode = false;
  bool _urlImportHandled = false;
  final GlobalKey<ShiftPickerPanelState> _panelKey =
      GlobalKey<ShiftPickerPanelState>();
  final GlobalKey<OceanBandState> _oceanKey = GlobalKey<OceanBandState>();

  bool _editingRemark = false;
  String _editingRemarkKey = '';
  late final TextEditingController _remarkCtrl;
  late final FocusNode _remarkFocus;

  late final AnimationController _cardFloatAnimCtrl;
  late final AnimationController _todayPulseCtrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _activeYear = now.year;
    _activeMonth = now.month;
    _currentPage = _pageForYearMonth(now.year, now.month);
    _pageController = PageController(initialPage: _currentPage);

    _cardFloatAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
      value: 1.0,
    )..addListener(() {
        if (mounted) setState(() {});
      });

    // 今日呼吸圈不綁 setState，僅由 CalendarDayCell 局部 AnimatedBuilder 消費。
    _todayPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _remarkCtrl = TextEditingController();
    _remarkFocus = FocusNode();
    _remarkFocus.addListener(() {
      if (!_remarkFocus.hasFocus && _editingRemark) {
        _saveInlineRemark();
      }
    });

    widget.store.addListener(_onStoreChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUrlImport();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _cardFloatAnimCtrl.dispose();
    _todayPulseCtrl.dispose();
    _remarkCtrl.dispose();
    _remarkFocus.dispose();
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _playSequentialImportAnimation(List<String> dates) async {
    final Set<int> pageIndices = {};
    for (final d in dates) {
      final parts = d.split('-');
      if (parts.length >= 2) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (y != null && m != null) {
          pageIndices.add(_pageForYearMonth(y, m));
        }
      }
    }
    final sortedPages = pageIndices.toList()..sort();
    if (sortedPages.isEmpty) {
      if (mounted) setState(() {});
      _oceanKey.currentState?.triggerSurge();
      _cardFloatAnimCtrl.forward(from: 0.0);
      return;
    }

    for (int i = 0; i < sortedPages.length; i++) {
      final targetPage = sortedPages[i];
      if (_pageController.hasClients) {
        final curPage = _pageController.page?.round() ?? _currentPage;
        if (curPage != targetPage) {
          await _pageController.animateToPage(
            targetPage,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
          );
        }
      }
      if (mounted) {
        setState(() {
          _currentPage = targetPage;
          final m = _monthForPage(targetPage);
          _activeYear = m.year;
          _activeMonth = m.month;
        });
      }

      _oceanKey.currentState?.triggerSurge();
      await _cardFloatAnimCtrl.forward(from: 0.0);

      if (i < sortedPages.length - 1) {
        await Future.delayed(const Duration(milliseconds: 220));
      }
    }
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
    _animateOrJumpToPage(targetPage);
  }

  void _shiftMonth(int delta) {
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      _currentPage + delta,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _jumpToYearMonth(int year, int month) {
    final targetPage = _pageForYearMonth(year, month);
    _animateOrJumpToPage(targetPage);
    setState(() {
      _currentPage = targetPage;
      _activeYear = year;
      _activeMonth = month;
    });
  }

  void _animateOrJumpToPage(int targetPage) {
    if (!_pageController.hasClients) return;
    final curPage = _pageController.page?.round() ?? _currentPage;
    if (curPage == targetPage) return;
    if ((targetPage - curPage).abs() <= 3) {
      _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pageController.jumpToPage(targetPage);
    }
  }

  void _openPicker() {
    if (_editingRemark) _saveInlineRemark();
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _pickerMode = true);
  }

  void _closePicker() {
    setState(() => _pickerMode = false);
  }

  Future<void> _showMonthPicker() async {
    final picked = await showYearMonthPickerDialog(
      context,
      activeYear: _activeYear,
      activeMonth: _activeMonth,
    );
    if (picked != null && mounted) {
      _jumpToYearMonth(picked.$1, picked.$2);
    }
  }

  void _onSelectDate(DateTime date, bool isCurrentMonth) {
    if (_editingRemark) _saveInlineRemark();
    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
    });
    if (_pickerMode) {
      _panelKey.currentState?.goToDate(date);
    }
    if (!isCurrentMonth) {
      _jumpToYearMonth(date.year, date.month);
    }
  }

  void _startInlineRemarkEdit() {
    final key = ShiftStore.ymd(_selectedDate);
    _remarkCtrl.text = widget.store.remarks[key] ?? '';
    setState(() {
      _editingRemark = true;
      _editingRemarkKey = key;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _remarkFocus.requestFocus();
    });
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
      showTopNotification(context, '備註已儲存');
    }
  }

  void _checkUrlImport() {
    if (_urlImportHandled) return;
    final codes = extractUrlImportCodes(Uri.base);
    if (codes.configCode == null && codes.rosterCode == null) return;
    _urlImportHandled = true;

    if (codes.configCode != null && mounted) {
      promptUrlConfigImport(
        context: context,
        store: widget.store,
        code: codes.configCode!,
      );
    } else if (codes.rosterCode != null && mounted) {
      promptUrlRosterImport(
        context: context,
        store: widget.store,
        alarms: widget.alarms,
        code: codes.rosterCode!,
        onImported: _playSequentialImportAnimation,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCalendarPageBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 8,
        title: InkWell(
          onTap: _showMonthPicker,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: AutoSizeText(
                    '$_activeYear年$_activeMonth月',
                    maxLines: 1,
                    minFontSize: 11,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => showUnifiedImportDialog(
              context: context,
              store: widget.store,
              alarms: widget.alarms,
              onImportDone: (List<String> dates) {
                _playSequentialImportAnimation(dates);
              },
            ),
            icon: const Icon(Icons.file_download_outlined, size: 20),
            tooltip: '導入排班 / 配置',
          ),
          OutlinedButton(
            onPressed: _goToToday,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 36),
            ),
            child: const Text(
              '今日',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
            ),
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final mq = MediaQuery.of(context);
          final keyboardOpen =
              View.of(context).viewInsets.bottom > 0 || mq.viewInsets.bottom > 0;
          final layout = CalendarLayout.compute(
            constraints.maxHeight,
            bottomInset: mq.padding.bottom,
            keyboardOpen: keyboardOpen,
          );

          return Column(
            children: [
              // ① 頂部天色帶（高度由外層 SizedBox 鎖定，避免鍵盤切換瞬間溢出）
              SizedBox(
                height: layout.bandHeight,
                child: OceanBand(
                  key: _oceanKey,
                  visible: layout.bandHeight >= 48.0,
                  height: layout.bandHeight,
                ),
              ),
              // ② 中間日曆卡（與天色帶共用容器寬度、內縮、圓角與描邊）
              SizedBox(
                key: const Key('calendar-zone'),
                height: layout.gridHeight,
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: kOceanBandMaxWidth),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kOceanBandInset,
                        vertical: kOceanBandGap,
                      ),
                      child: Container(
                        key: const Key('calendar-grid-card'),
                        decoration: BoxDecoration(
                          color: kOceanBandSurface,
                          borderRadius: BorderRadius.circular(kOceanBandRadius),
                          border: Border.all(color: kCardStroke),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ClipRect(
                          child: ScrollConfiguration(
                            behavior: const _CalendarScrollBehavior(),
                            child: PageView.builder(
                              scrollDirection: Axis.horizontal,
                              physics: const PageScrollPhysics(),
                              controller: _pageController,
                              onPageChanged: _onPageChanged,
                              itemBuilder: (_, page) {
                                final m = _monthForPage(page);
                                return RepaintBoundary(
                                  key: ValueKey('month_${m.year}_${m.month}'),
                                  child: CalendarMonthGrid(
                                    store: widget.store,
                                    year: m.year,
                                    month: m.month,
                                    cellHeight: layout.cellHeight,
                                    selectedDate: _selectedDate,
                                    cardFloatAnimCtrl: _cardFloatAnimCtrl,
                                    todayPulseCtrl: _todayPulseCtrl,
                                    onSelectDate: _onSelectDate,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // ③ 底部排班詳情／排班編輯（同一格高度原地切換）
              SizedBox(
                height: layout.detailHeight,
                child: ClipRect(
                  child: _pickerMode
                      ? ShiftPickerPanel(
                          key: _panelKey,
                          initialDate: _selectedDate,
                          store: widget.store,
                          alarms: widget.alarms,
                          onClose: _closePicker,
                        )
                      : CalendarDetailCard(
                          store: widget.store,
                          selectedDate: _selectedDate,
                          editingRemark: _editingRemark,
                          remarkCtrl: _remarkCtrl,
                          remarkFocus: _remarkFocus,
                          onOpenPicker: _openPicker,
                          onStartRemarkEdit: _startInlineRemarkEdit,
                          onSaveRemark: _saveInlineRemark,
                        ),
                ),
              ),
              // ④ 預留底部導航欄高度
              SizedBox(height: layout.navHeight),
            ],
          );
        },
      ),
    );
  }
}
