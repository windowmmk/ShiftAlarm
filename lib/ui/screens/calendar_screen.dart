import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/alarm_service.dart';
import '../../domain/calendar_layout.dart';
import '../../domain/config_io.dart';
import '../../domain/holidays.dart';
import '../../domain/roster_io.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';
import '../dialogs/unified_import_dialog.dart';
import '../widgets/ocean_band.dart';
import '../widgets/ocean_import_transition.dart';
import '../widgets/top_notification.dart';
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
/// 支援排班卡片從無到有飄入、公眾假期紅線與 120ms 堅實微觸感。
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

  late final PageController _pageController;
  late int _currentPage;

  /// 頂部標題當前月份（以當前顯示頁面為準）
  late int _activeYear;
  late int _activeMonth;

  /// 詳情板選中日期（預設今日）；㩒日曆格更新
  late DateTime _selectedDate;

  /// 底部區模式：`false` = 排班詳情，`true` = 排班編輯。
  /// 兩者共用底部區同一格高度，原地切換，無彈出／彈入動畫。
  bool _pickerMode = false;
  final GlobalKey<ShiftPickerPanelState> _panelKey =
      GlobalKey<ShiftPickerPanelState>();

  /// 海平線帶 Key（導入排更時觸發浪湧，shader 與 2D fallback 共用同一個入口）
  final GlobalKey<OceanBandState> _oceanKey = GlobalKey<OceanBandState>();

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
    _pageController = PageController(initialPage: _currentPage);

    _cardFloatAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
      value: 1.0,
    )..addListener(() {
        if (mounted) setState(() {});
      });

    _sweepAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..addListener(() {
        if (mounted) setState(() {});
      });

    // 今日呼吸圈：**唔加 addListener(setState)**。
    // 佢係 repeat(reverse: true)，若喺呢度 setState 就會令整個 CalendarScreen 每幀重建；
    // 改由 _dayCell 內一個局部 AnimatedBuilder 消費呢個 controller（只重畫今日格的外陰影）。
    _todayPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

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

  /// store 有寫入即自動刷新
  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  /// 批量導入跨月動效：依序自第一個月推進波浪落位，完成後自動滑動翻至下個月，直至所有月份排更完成
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

      // 觸發海面浪湧與該月 42 格專屬色彩波浪推進
      _oceanKey.currentState?.triggerSurge();
      await _cardFloatAnimCtrl.forward(from: 0.0);

      // 若有後續月份，稍作停留讓用戶清晰感知完成狀態後換頁
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

  /// 左右切月：平滑切換到上一月／下一月（左右平滑滑動）
  void _shiftMonth(int delta) {
    if (!_pageController.hasClients) return;
    final targetPage = _currentPage + delta;
    _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// 底部區切換去排班編輯：原地換內容，高度唔變、無彈出動畫。
  void _openPicker() {
    if (_editingRemark) {
      _saveInlineRemark();
    }
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _pickerMode = true);
  }

  /// 排班編輯完成／返回：底部區換返排班詳情，同樣原地切換。
  void _closePicker() {
    setState(() => _pickerMode = false);
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
                // ⚠️ 呢個 Text 一定要包 `Flexible` + 省略號，唔可以任由佢撐開。
                // AppBar 的 middle slot 只會分到「總寬 − leading − actions − spacing」
                // 的剩餘寬度（實測 320/360/390/412 分別只剩 55.8 / 95.8 / 125.8 / 147.8），
                // 而標題（4 位數字＋年＋2 位數字＋月＋下拉箭頭）本身要 164px，
                // 所以舊版**每一個寬度都爆邊**（320 爆 108、360 爆 68、390 爆 38、412 爆 16）。
                // 包了 Flexible 之後，剩餘寬度有幾多就用幾多，永遠唔會再爆。
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
          // 導入由「圖示＋文字」的 tonal 按鈕改成純圖示：舊版呢個按鈕實佔 72.2px，
          // 連同後面三個控制合共 220.2px，係標題被擠爆的主因。
          // 圖示版只佔 48px（保住 48dp 最小觸控目標），文字提示改用 tooltip。
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
      // 三區固定：① 頂部海洋線 ② 中間日曆 ③ 底部排班詳情。
      // 高度全部由 CalendarLayout 一次算定，切換排班編輯只係原地換內容，無彈出彈入。
      body: LayoutBuilder(
        builder: (context, constraints) {
          // v3.6.1：底部留白改用**真實**導航欄高度，唔再靠寫死嘅 72。
          // `HomeScreen` 用 `extendBody: true`，Scaffold 會把導航欄高度注入 body 的
          // `padding.bottom`（實測手勢導航 88.8 / 三鍵導航 112.8）；鍵盤彈起時
          // Scaffold 已將佢歸零，所以 navHeight 自動變 0，唔會再空出 72px 死白。
          final mq = MediaQuery.of(context);
          // ⚠️ 鍵盤唔可以讀 `mq.viewInsets.bottom`：Scaffold（`resizeToAvoidBottomInset`
          // 預設 true）在 body 之前已經把底部 viewInsets 食掉，body 內永遠讀到 0
          // （實測：view 有 300，body 內 viewInsets.bottom = 0）。所以讀未經消費的
          // `View.of(context).viewInsets`（實體像素，只用作 > 0 判斷，dpr 無影響）。
          final keyboardOpen =
              View.of(context).viewInsets.bottom > 0 || mq.viewInsets.bottom > 0;
          final layout = CalendarLayout.compute(
            constraints.maxHeight,
            bottomInset: mq.padding.bottom,
            // 輸入文字（鍵盤彈起）時天色欄完全壓縮為 0，讓位俾日曆同底部區
            keyboardOpen: keyboardOpen,
          );

          return Column(
            children: [
              // ① 頂部海洋線
              //
              // ⚠️ 外面一定要用 `SizedBox` 夾死高度：`OceanBand` 內部有 260ms 的
              // 高度過渡。若佢直接做 Column 的 child，鍵盤彈起收合嗰 260ms 內
              // 佢仍然報舊高度 96，而日曆區已經按 band=0 長大 → Column 短暫超高
              // 96px，會閃一下黃黑間條。夾死之後「讓位」係即時的，動畫只係內部視覺。
              SizedBox(
                height: layout.bandHeight,
                child: OceanBand(
                  key: _oceanKey,
                  visible: layout.bandHeight >= 48.0,
                  height: layout.bandHeight,
                ),
              ),
              // ② 中間日曆：高度寫死，格高由佈局算式實算（理想 75，唔夠位先縮）
              SizedBox(
                height: layout.gridHeight,
                child: ClipRect(
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
                          child: _monthGrid(
                            t,
                            m.year,
                            m.month,
                            cellHeight: layout.cellHeight,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              // ③ 底部排班詳情／排班編輯：同一格高度，原地切換
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
                      : _detailPanel(t),
                ),
              ),
              // ④ 預留底部半透明導航欄高度（HomeScreen 用 extendBody，body 伸到欄底）
              SizedBox(height: layout.navHeight),
            ],
          );
        },
      ),
    );
  }

  /// 一個月固定 6 週（42 格）標準網格：四周留白，破浪光潮推進時整個月曆容器如甲板般 3D 俯仰
  ///
  /// **高度分配係自適應的**：頂部星期表頭用自然高度（會隨系統字體縮放變高），
  /// 剩餘高度由 6 個星期列以 `Expanded` 平均吸收。
  ///
  /// v3.6.2 之前呢度係「表頭自然高度 + 6 × `SizedBox(height: cellHeight)`」，
  /// 而 `CalendarLayout` 只預留 36px 給表頭與間距（實算：`gridHeight` − 8（上下 padding）
  /// − 4（間距）= 24px 才是表頭可用高度）。1.0 倍字體時表頭 21px 剛好夠，
  /// 但 1.15 倍就 24px 頂死、1.3 倍 26px 爆 2px、2.0 倍 38px 爆 14px ——
  /// 即係**任何開了「大字體」無障礙設定的用戶，日曆都會出黃黑間條**。
  /// 改用 `Expanded` 之後，表頭想幾高就幾高，格仔自動縮一點去讓位，
  /// 結構上唔可能再溢出（`Expanded` 只會平分，唔會超出）。
  ///
  /// [cellHeight] 只作**理想上限**參考：`CalendarLayout` 用它算出 `gridHeight`，
  /// 所以正常字體時每列分到的高度就係 `cellHeight` 本身。
  Widget _monthGrid(
    ShiftTokens t,
    int year,
    int month, {
    required double cellHeight,
  }) {
    // 只作 debug 期守門：正常路徑由 CalendarLayout 保證為正數
    assert(cellHeight > 0, '格高必須為正數（由 CalendarLayout 實算）');
    final firstDay = DateTime(year, month, 1);
    final firstWeekday = firstDay.weekday % 7; // 星期日為 0
    final firstSunday = DateTime(year, month, 1 - firstWeekday);
    const weekCount = 6; // 永遠固定 6 行（42 格），消除跨月高度撕裂與抖動
    final today = DateTime.now();

    final grid = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4), // 四周邊距留白，透出靈動海面
          child: Column(
            // ⚠️ 一定要 `max`：下面 6 列用 `Expanded` 平分剩餘高度，
            // 而 `Expanded` 要求 Column 有明確的高度上限（由外層 SizedBox 提供）。
            mainAxisSize: MainAxisSize.max,
            children: [
              _weekHeader(t),
              const SizedBox(height: 4),
              for (int w = 0; w < weekCount; w++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(
                      children: [
                        for (int d = 0; d < 7; d++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(right: d < 6 ? 3.0 : 0),
                              child: OceanStaggeredCellTransition(
                                index: w * 7 + d,
                                controller: _cardFloatAnimCtrl,
                                mode: OceanImportMode.tidalWave,
                                child: _dayCell(
                                  t,
                                  DateTime(firstSunday.year, firstSunday.month,
                                      firstSunday.day + w * 7 + d),
                                  today,
                                  year,
                                  month,
                                  row: w,
                                  col: d,
                                ),
                              ),
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

    if (!_cardFloatAnimCtrl.isAnimating) return grid;

    // 破浪光潮推進時，整個月曆容器 3D 俯仰傾斜（深度參考 shiftalarm_web_ocean）
    final tiltT = math.sin(_cardFloatAnimCtrl.value * math.pi);
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateX(0.08 * tiltT)
        ..translate(0.0, 6.0 * tiltT)
        ..scale(1.0 - 0.015 * tiltT),
      child: grid,
    );
  }

  /// 日曆格：清晰對比、主次分明、字重自然平衡
  Widget _dayCell(
    ShiftTokens t,
    DateTime date,
    DateTime today,
    int activeYear,
    int activeMonth, {
    required int row,
    required int col,
  }) {
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

    // 當月與非當月（上月／下月）的色彩處理：輕度半透明保護高對比度可讀性
    final Color cellBg;
    final Color borderColor;
    final Color dateColor;
    final Color abbrColor;
    final Color noteColor;

    if (isCurrentMonth) {
      // 輕度半透明：排更格 0.88 飽和色，空白格 0.84 珍珠白，文字深邃清晰
      cellBg = def != null
          ? slot!.bg.withValues(alpha: 0.88)
          : Colors.white.withValues(alpha: 0.84);
      borderColor = isSelected
          ? t.brand
          : (isToday
              ? t.brand.withValues(alpha: 0.85)
              : (slot?.border ?? t.neutralStroke).withValues(alpha: 0.65));
      dateColor = (holiday != null) ? t.danger : baseFg;
      abbrColor = baseFg;
      noteColor = baseFg;
    } else {
      // 鄰月淡化處理
      cellBg = def != null
          ? slot!.bg.withValues(alpha: 0.40)
          : Colors.white.withValues(alpha: 0.35);
      borderColor = (slot?.border ?? t.neutralStroke).withValues(alpha: 0.30);
      dateColor = (holiday != null)
          ? t.danger.withValues(alpha: 0.52)
          : t.neutralFg.withValues(alpha: 0.42);
      abbrColor = (slot?.fg ?? t.neutralFg).withValues(alpha: 0.55);
      noteColor = (slot?.fg ?? t.neutralFg2).withValues(alpha: 0.48);
    }

    // 今日 (Today) 柔和微呼吸圈：改由下面一個**局部** AnimatedBuilder 繪製外陰影，
    // 唔再喺呢度計（若喺呢度讀 _todayPulseCtrl.value，就等於整個 CalendarScreen 每幀重建）。

    // 導入排更波浪式推進計算（自底排斜向上如海浪翻湧浮入）
    final bool isWaveSurging =
        _cardFloatAnimCtrl.isAnimating && isCurrentMonth && def != null;
    double waveT = 1.0;
    double sheenT = 0.0;
    if (isWaveSurging) {
      final waveStart = (((5 - row) * 0.09 + col * 0.032)).clamp(0.0, 0.65);
      final waveEnd = (waveStart + 0.35).clamp(0.0, 1.0);
      final animVal = _cardFloatAnimCtrl.value;
      if (animVal < waveStart) {
        waveT = 0.0;
        sheenT = 0.0;
      } else if (animVal >= waveEnd) {
        waveT = 1.0;
        sheenT = 0.0;
      } else {
        final localT = (animVal - waveStart) / (waveEnd - waveStart);
        waveT = localT.clamp(0.0, 1.0);
        sheenT = localT.clamp(0.0, 1.0);
      }
    }

    // 依更次時段取得專屬流光與浪花光暈主色（早更金紅/正午天藍/中更粉紫/夜更螢光深海）
    Color shiftFxPrimary = t.brand;
    Color shiftFxAccent = const Color(0xFFFDE047);
    if (def != null) {
      final hour =
          int.tryParse(def.startTime.split(':').firstOrNull ?? '') ?? 12;
      if (hour >= 5 && hour < 11) {
        // 早更：晨曦旭日金色與暖紅朝霞
        shiftFxPrimary = const Color(0xFFEA580C);
        shiftFxAccent = const Color(0xFFFBBF24);
      } else if (hour >= 11 && hour < 15) {
        // 正午／日更：碧海天藍與日光浪尖
        shiftFxPrimary = const Color(0xFF0284C7);
        shiftFxAccent = const Color(0xFF38BDF8);
      } else if (hour >= 15 && hour < 21) {
        // 中更／黃昏：暮光玫紅與落日晚霞粉紫
        shiftFxPrimary = const Color(0xFFE11D48);
        shiftFxAccent = const Color(0xFFF472B6);
      } else {
        // 夜更：深海星夜與藍眼淚螢光青藍
        shiftFxPrimary = const Color(0xFF6366F1);
        shiftFxAccent = const Color(0xFF00F0FF);
      }
    }

    // 浪花掠過時的更次專屬色彩微光暈
    BoxShadow? surgeGlowShadow;
    if (isWaveSurging && sheenT > 0.03 && sheenT < 0.97) {
      final pulse = (1.0 - (sheenT - 0.5).abs() * 2.0).clamp(0.0, 1.0);
      surgeGlowShadow = BoxShadow(
        color: shiftFxPrimary.withValues(alpha: 0.55 * pulse),
        blurRadius: 16.0 * pulse,
        spreadRadius: 1.5 * pulse,
        offset: Offset(0, 6.0 * pulse),
      );
    }

    Widget wrapWaveContent(Widget child) => child;

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
                borderRadius: BorderRadius.circular(9),
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
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          if (surgeGlowShadow != null) surgeGlowShadow,
        ],
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
                // 第二行：班次縮寫（清晰適中 17.0px w600，支援波浪式浮入）
                Expanded(
                  child: Center(
                    child: def != null
                        ? wrapWaveContent(
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
                // 第三行：地點（常規字重 17.0px normal，支援波浪式浮入）
                Expanded(
                  child: Center(
                    child: (def != null && note.isNotEmpty)
                        ? wrapWaveContent(
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
          // 導入排更波浪流光掠過（依更次不同色彩展現專屬流光）
          if (isWaveSurging && sheenT > 0.01 && sheenT < 0.99)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Transform.translate(
                    offset: Offset((sheenT * 2.4 - 1.2) * 55.0, 0),
                    child: Transform.rotate(
                      angle: 0.22,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              shiftFxPrimary.withValues(alpha: 0.40),
                              shiftFxAccent.withValues(alpha: 0.60),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.40, 0.60, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // 月終純視覺時間流光（掠過 1~31 日）
          if (sweepOverlay != null) sweepOverlay,
        ],
      ),
    );

    // 今日呼吸圈：只包住今日那一格的**外陰影**，唔碰尺寸／顏色／文字。
    // 咁樣 60fps 的 repeat 動畫只會重畫呢一個小 DecoratedBox，唔會令整個月曆陪跑。
    if (isToday && isCurrentMonth) {
      final Widget baseCell = cell;
      cell = AnimatedBuilder(
        animation: _todayPulseCtrl,
        child: baseCell,
        builder: (context, child) {
          final pulseVal = _todayPulseCtrl.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: t.brand.withValues(alpha: 0.12 + 0.26 * pulseVal),
                  blurRadius: 4.0 + 3.0 * pulseVal,
                  spreadRadius: 0.5 + 1.2 * pulseVal,
                ),
              ],
            ),
            child: child,
          );
        },
      );
    }

    return _HapticCell(
      onTap: () {
        if (_editingRemark) {
          _saveInlineRemark();
        }
        setState(() {
          _selectedDate = DateTime(date.year, date.month, date.day);
        });
        // 底部區處於排班編輯時，直接將編輯器跳去呢一日（原地換內容，無動畫）
        if (_pickerMode) {
          _panelKey.currentState?.goToDate(date);
        }
        if (!isCurrentMonth) {
          _jumpToYearMonth(date.year, date.month);
        }
      },
      child: cell,
    );
  }

  /// 底部區（固定第三區）：所選日期嘅排班詳情。
  /// 常駐顯示、高度由 [CalendarLayout] 定死，無彈出、無下划隱去。
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
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      // 永久防線：底部區高度固定，若用戶開咗大字級、或者日後加多一行令內容變高，
      // 呢度會變成可捲動，而唔會 RenderFlex 溢出彈黃黑間條。
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 第一行：日期、星期、節日標籤
            Row(
              children: [
                Text(
                  '${_selectedDate.month}月${_selectedDate.day}日',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.neutralFg,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '星期$weekdayName',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                    color: t.neutralFg2,
                  ),
                ),
                if (holiday != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: t.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      holiday,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: t.danger,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            // 第二行：班次詳情、時間、地點標註 與 緊湊排班按鈕
            Row(
              children: [
                Expanded(
                  child: def != null
                      ? Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: slot?.bg ?? t.neutralBg,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: slot?.border ?? t.neutralStroke,
                                ),
                              ),
                              child: Text(
                                def.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: slot?.fg ?? t.neutralFg,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${def.startTime}–${def.endTime}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.normal,
                                color: t.neutralFg,
                              ),
                            ),
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
                        )
                      : Text(
                          '未排班',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.normal,
                            color: t.neutralFg2,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _openPicker,
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    minimumSize: const Size(0, 36),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.edit_calendar, size: 15),
                  label: const Text(
                    '排班',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 第三行：備註條（點擊直接新增／編輯，緊湊高雅，無冗餘空間）
            _editingRemark
                ? SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _remarkCtrl,
                      focusNode: _remarkFocus,
                      maxLines: 1,
                      maxLength: ShiftStore.maxRemarkLength,
                      style: const TextStyle(fontSize: 12.5),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.90),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: t.brand, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        counterText: '',
                        isDense: true,
                        hintText: '新增備註…',
                        prefixIcon: Icon(Icons.notes_rounded,
                            size: 15, color: t.neutralFg2),
                        suffixIcon: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.check, size: 16),
                          onPressed: _saveInlineRemark,
                        ),
                      ),
                      onEditingComplete: _saveInlineRemark,
                    ),
                  )
                : InkWell(
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
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.60),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: t.neutralStroke.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.notes_rounded,
                              size: 14, color: t.neutralFg2),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              remark.isEmpty ? '點擊新增備註…' : remark,
                              style: TextStyle(
                                fontSize: 12,
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
          ],
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
        children: [
          for (int d = 0; d < 7; d++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: d < 6 ? 3.0 : 0),
                child: Center(
                  child: Text(
                    names[d],
                    style: TextStyle(
                      fontSize: t.fontCaption,
                      color: t.neutralFg2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
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
          _playSequentialImportAnimation(
              [for (final r in decoded.importResult.valid) r.date]);
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
