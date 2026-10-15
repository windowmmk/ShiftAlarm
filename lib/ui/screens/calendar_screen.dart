import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/alarm_service.dart';
import '../../domain/config_io.dart';
import '../../domain/holidays.dart';
import '../../domain/roster_io.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';
import 'shift_picker_panel.dart';

/// 支援桌面與網頁滑鼠拖曳、觸摸、觸控板左右換月的 ScrollBehavior
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

/// 月曆：固定顯示 6 週（42 格），按月一頁頁左右滑動切換，極致 60fps GPU 快取過渡。
/// 明確區分本月與上月／下月；點選日期底部顯示班次與備忘；點「排班」即時排更。
class CalendarScreen extends StatefulWidget {
  final ShiftStore store;
  final AlarmService alarms;

  const CalendarScreen({super.key, required this.store, required this.alarms});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
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

  late final PageController _pageController;
  late int _currentPage;

  /// 頂部標題當前月份（以當前顯示頁面為準）
  late int _activeYear;
  late int _activeMonth;

  bool? _exactAlarmOk;
  bool? _fullScreenOk;

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

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _activeYear = now.year;
    _activeMonth = now.month;
    _currentPage = _pageForYearMonth(now.year, now.month);
    _pageController = PageController(initialPage: _currentPage);

    _remarkCtrl = TextEditingController();
    _remarkFocus = FocusNode();
    _remarkFocus.addListener(() {
      // 收鍵盤／失焦 → 自動保存
      if (!_remarkFocus.hasFocus && _editingRemark) {
        _saveInlineRemark();
      }
    });

    widget.store.addListener(_onStoreChanged);
    if (isNativeAlarmSupported) {
      _checkAlarmPermission();
      _checkFullScreenIntent();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUrlHashImport();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _remarkCtrl.dispose();
    _remarkFocus.dispose();
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
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

  /// 呢個月有冇任何排班（空狀態提示用）
  bool _isMonthEmpty(DateTime month) {
    final prefix =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    return !widget.store.assignments.keys.any((k) => k.startsWith(prefix));
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
      final curPage = _pageController.page?.round() ?? _currentPage;
      if (curPage != targetPage) {
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
    }
  }

  /// 左右切月：平滑切換到上一月／下一月（左右翻頁）
  void _shiftMonth(int delta) {
    if (!_pageController.hasClients) return;
    final targetPage = _currentPage + delta;
    _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _checkAlarmPermission() async {
    try {
      final ok = await widget.alarms.bridge.canScheduleExactAlarms();
      if (mounted) setState(() => _exactAlarmOk = ok);
    } catch (_) {}
  }

  Future<void> _checkFullScreenIntent() async {
    try {
      final ok = await widget.alarms.bridge.canUseFullScreenIntent();
      if (mounted) setState(() => _fullScreenOk = ok);
    } catch (_) {}
  }

  /// 開排班面板：取代詳情板，擺喺日曆下方
  void _openPanel() {
    if (_editingRemark) {
      _saveInlineRemark();
    }
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
                ),
                Text('$selectedYear年',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  onPressed: () => setDialogState(() => selectedYear++),
                  icon: const Icon(Icons.chevron_right),
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
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isCurrent ? t.brand : t.neutralBg2,
                        borderRadius: BorderRadius.circular(8),
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
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('關閉'),
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
      final curPage = _pageController.page?.round() ?? _currentPage;
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
          TextButton(
            onPressed: _openPanel,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('排班'),
          ),
          TextButton(
            onPressed: _goToToday,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('今日'),
          ),
          IconButton(
            onPressed: () => _shiftMonth(-1),
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一月',
          ),
          IconButton(
            onPressed: () => _shiftMonth(1),
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一月',
          ),
        ],
      ),
      body: Column(
        children: [
          if (isNativeAlarmSupported && _exactAlarmOk == false)
            MaterialBanner(
              backgroundColor: const Color(0xFFFFF9F5),
              content: const Text('未授權精確鬧鐘，鬧鐘可能唔準時。請去設定開啟。'),
              actions: [
                TextButton(
                  onPressed: () =>
                      widget.alarms.bridge.requestExactAlarmPermission(),
                  child: const Text('去設定'),
                ),
                TextButton(
                  onPressed: () => setState(() => _exactAlarmOk = null),
                  child: const Text('稍後'),
                ),
              ],
            ),
          if (isNativeAlarmSupported && _fullScreenOk == false)
            MaterialBanner(
              backgroundColor: const Color(0xFFFFF9F5),
              content: const Text('未允許全屏鬧鐘，通知唔會強制彈出。'),
              actions: [
                TextButton(
                  onPressed: () =>
                      widget.alarms.bridge.openFullScreenIntentSettings(),
                  child: const Text('去開啟'),
                ),
                TextButton(
                  onPressed: () => setState(() => _fullScreenOk = null),
                  child: const Text('稍後'),
                ),
              ],
            ),
          _legend(t),
          _weekHeader(t),
          Expanded(
            child: ScrollConfiguration(
              behavior: const _CalendarScrollBehavior(),
              child: PageView.builder(
                scrollDirection: Axis.horizontal, // 左右翻月
                physics: const PageScrollPhysics(), // 確保按頁吸附與平滑過渡
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
          ),
          // 空狀態提示：當月未排更
          if (_isMonthEmpty(DateTime(_activeYear, _activeMonth)))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '呢個月未排更，撳右上「排班」開始',
                style: TextStyle(fontSize: 13, color: t.neutralFg2),
                textAlign: TextAlign.center,
              ),
            ),
          // 排班面板或詳情板
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

  /// 一個月固定 6 週（42 格）標準網格：保證每個月單元格高度完全對齊，翻月絕不抖動
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
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
              child: Row(
                children: [
                  for (int d = 0; d < 7; d++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: d < 6 ? 2 : 0),
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

  /// 日曆格：固定三行佈局（日期、班次縮寫、場所），明確區分當前月份與非當前月份
  /// 採用超高效的單趟 FittedBox 縮放，徹底消除 Web 瀏覽器上 TextPainter 二分測量的卡頓
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

    // 當月與非當月（上月／下月）的鮮明視覺區分
    final Color cellBg;
    final Color borderColor;
    final Color dateColor;
    final Color abbrColor;
    final Color noteColor;

    if (isCurrentMonth) {
      cellBg = baseBg;
      borderColor = isSelected
          ? t.neutralFg
          : (isToday ? t.brand : (slot?.border ?? t.neutralStroke));
      dateColor = (holiday != null) ? t.danger : baseFg;
      abbrColor = baseFg;
      noteColor = baseFg;
    } else {
      // 非當月淡化處理：淡灰背景、邊框與低對比文字，一眼看出屬於鄰月
      cellBg = def != null
          ? slot!.bg.withValues(alpha: 0.3)
          : t.neutralBg2.withValues(alpha: 0.45);
      borderColor = isSelected
          ? t.neutralFg.withValues(alpha: 0.6)
          : (isToday
              ? t.brand.withValues(alpha: 0.5)
              : t.neutralStroke.withValues(alpha: 0.35));
      dateColor = (holiday != null)
          ? t.danger.withValues(alpha: 0.38)
          : t.neutralFg2.withValues(alpha: 0.38);
      abbrColor = (slot?.fg ?? t.neutralFg2).withValues(alpha: 0.38);
      noteColor = (slot?.fg ?? t.neutralFg2).withValues(alpha: 0.32);
    }

    Widget cell = Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: cellBg,
        border: Border.all(
          color: borderColor,
          width: (isSelected || isToday) ? 2.0 : 1.0,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 第一行：日期（澳門公眾假期顯示紅色；非本月淡化）
          Expanded(
            flex: 12,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isCurrentMonth ? FontWeight.w600 : FontWeight.w400,
                    color: dateColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          // 第二行：班次縮寫（加粗；無班次固定高度佔位，保持整月嚴格對齊）
          Expanded(
            flex: 11,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  def != null ? truncateAbbr(def.abbr) : '',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: abbrColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          // 第三行：場所（固定高度佔位）
          Expanded(
            flex: 9,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  (def != null && note.isNotEmpty) ? truncateAbbr(note) : '',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w400,
                    color: noteColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
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

  /// 日曆下方詳情板：三欄橫排（日期時間、備註便利貼、改排班）
  Widget _detailPanel(ShiftTokens t) {
    final key = ShiftStore.ymd(_selectedDate);
    final assignment = widget.store.assignments[key];
    final def =
        assignment != null ? widget.store.defs[assignment.shiftId] : null;
    final remark = widget.store.remarks[key] ?? '';
    final alarmCount =
        def == null ? 0 : def.alarms.where((a) => a.enabled).length;
    final holiday = holidayName(_selectedDate);

    return Container(
      height: 84,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.neutralBg2,
        border: Border(top: BorderSide(color: t.neutralStroke)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左小欄：日期＋班次時間
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_selectedDate.month}月${_selectedDate.day}日',
                  style: TextStyle(fontSize: 12, color: t.neutralFg2)),
              const SizedBox(height: 2),
              Text(
                def == null
                    ? '未排更'
                    : '${def.startTime.substring(0, 2)}–${def.endTime.substring(0, 2)}',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: def == null ? t.neutralFg2 : t.neutralFg),
              ),
              if (isNativeAlarmSupported && def != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('$alarmCount個鬧鐘',
                      style: TextStyle(fontSize: 11, color: t.neutralFg2)),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // 中大欄：備註便利貼
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (holiday != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(holiday,
                        style: TextStyle(fontSize: 12, color: t.danger),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                _remarkStickyNote(t, key, remark),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 右欄：改排班按鈕
          TextButton.icon(
            onPressed: _openPanel,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.edit_calendar, size: 18),
            label: const Text('改排班'),
          ),
        ],
      ),
    );
  }

  /// 備註便利貼：點擊即打，失焦自動保存
  Widget _remarkStickyNote(ShiftTokens t, String key, String remark) {
    final stickyBg = t.neutralBg;
    if (_editingRemark) {
      return SizedBox(
        height: 52,
        child: TextField(
          controller: _remarkCtrl,
          focusNode: _remarkFocus,
          maxLines: 2,
          maxLength: ShiftStore.maxRemarkLength,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: stickyBg,
            border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            counterText: '',
            isDense: true,
          ),
          onEditingComplete: _saveInlineRemark,
        ),
      );
    }
    return GestureDetector(
      onTap: () {
        _remarkCtrl.text = widget.store.remarks[key] ?? '';
        _editingRemarkKey = key;
        setState(() => _editingRemark = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _remarkFocus.requestFocus();
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 52,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: stickyBg,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          remark.isEmpty ? '點此新增今日備註…' : remark,
          style: TextStyle(
            fontSize: 14,
            color: remark.isEmpty ? t.neutralFg2 : t.neutralFg,
            fontStyle: remark.isEmpty ? FontStyle.italic : FontStyle.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
  }

  Widget _legend(ShiftTokens t) {
    final defs = widget.store.sortedDefs();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        alignment: WrapAlignment.spaceEvenly,
        children: [
          for (final def in defs)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: t.slotForTime(def.startTime).bg,
                    border: Border.all(
                        color: t.slotForTime(def.startTime).border),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${def.startTime.substring(0, 2)}–${def.endTime.substring(0, 2)}',
                  style: TextStyle(
                      fontSize: t.fontCaption, color: t.neutralFg2),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _weekHeader(ShiftTokens t) {
    const names = ['日', '一', '二', '三', '四', '五', '六'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: names
            .map((n) => Expanded(
                  child: Center(
                    child: Text(n,
                        style: TextStyle(
                            fontSize: t.fontCaption,
                            color: const Color(0xFF2A9D8F),
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
          title: const Row(
            children: [
              Icon(Icons.link, color: Color(0xFF2E7D32)),
              SizedBox(width: 8),
              Text('網址配置導入'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('檢測到網址分享的班次與場所配置：'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F8E9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFA5D6A7)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• 班次數量：${p.shifts} 個 (${p.names.join('、')})',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('• 常用場所：${p.venues} 個',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (p.crcVerified) ...[
                      const SizedBox(height: 4),
                      const Text('• 報文校驗：CRC32 驗證通過 ✓',
                          style: TextStyle(
                              color: Color(0xFF2E7D32), fontSize: 12)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '注意：導入後將覆蓋現有班次與場所設定。是否立即導入？',
                style: TextStyle(fontSize: 12, color: Colors.red),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('確定導入'),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        await importConfigText(widget.store, code);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('配置已成功導入！')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('網址配置解析失敗: $e')),
        );
      }
    }
  }

  Future<void> _promptImportRosterFromUrl(String code) async {
    try {
      final decoded = decodeRosterText(code, widget.store.defs);
      if (decoded.importResult.valid.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(decoded.importResult.errors.isNotEmpty
                  ? decoded.importResult.errors.first
                  : '排班數據無效'),
            ),
          );
        }
        return;
      }

      final count = decoded.importResult.valid.length;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.link, color: Color(0xFF1565C0)),
              SizedBox(width: 8),
              Text('網址排班導入'),
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
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF90CAF9)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• 待導入排班天數：$count 天',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (decoded.crcVerified) ...[
                      const SizedBox(height: 4),
                      const Text('• 報文校驗：CRC32 驗證通過 ✓',
                          style: TextStyle(
                              color: Color(0xFF1565C0), fontSize: 12)),
                    ],
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
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('套用排班'),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('成功導入 $count 天排班！')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('網址排班解析失敗: $e')),
        );
      }
    }
  }
}
