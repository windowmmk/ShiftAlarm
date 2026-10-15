import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/alarm_service.dart';
import '../../domain/holidays.dart';
import '../../domain/shift_store.dart';
import '../../theme/app_theme.dart';
import 'shift_picker_panel.dart';

/// 月曆：點一日 → 底部彈出揀班次；再點可轉更／取消。
/// 上下滑動連續滾動（無縫週列表）；「今日」返今日所在週。
class CalendarScreen extends StatefulWidget {
final ShiftStore store;
final AlarmService alarms;

const CalendarScreen({super.key, required this.store, required this.alarms});

@override
State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  /// 全個月曆共用：自動計出所有格都裝得落嘅最大字級，全格統一。
  final AutoSizeGroup _cellTextGroup = AutoSizeGroup();
  /// 無縫連續週滾動：每項 = 一週（固定高度），星期日開始。
  /// 每個禮拜喺成個日曆只出現一次，無重複、無空白 gap。
  static const _kInitialWeek = 100000;
  static const double _kWeekHeight = 76.0;
  late final ScrollController _scrollController;

  /// 畫面中央當前月份（頂部標題＋格仔淡化依據）
  late int _activeYear;
  late int _activeMonth;
bool? _exactAlarmOk;
bool? _fullScreenOk;

/// 詳情板選中日期（預設今日）；㩒日曆格更新。
late DateTime _selectedDate;

/// 排班面板（固定 widget，唔係 bottom sheet）開關；
/// 開嗰陣取代詳情板，擺喺日曆下方，唔遮日曆格。
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
// 直接跳去今日所在週（ListView 頂部對齊該週）
_scrollController = ScrollController(
initialScrollOffset: _kInitialWeek * _kWeekHeight,
)..addListener(_onScroll);
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
  }

@override
void dispose() {
_scrollController.removeListener(_onScroll);
_scrollController.dispose();
_remarkCtrl.dispose();
_remarkFocus.dispose();
widget.store.removeListener(_onStoreChanged);
super.dispose();
}

/// store 有寫入（排更／轉更／改備注／改定義）即自動刷新，唔使重啟 App。
void _onStoreChanged() {
if (mounted) setState(() {});
}

/// 基準星期日：_kInitialWeek 對應今日所在週嘅星期日
DateTime _anchorSunday() {
  final now = DateTime.now();
  final d = DateTime(now.year, now.month, now.day);
  return d.subtract(Duration(days: d.weekday % 7));
}

/// weekIndex → 該週星期日
DateTime _sundayForWeek(int week) =>
    _anchorSunday().add(Duration(days: (week - _kInitialWeek) * 7));

/// 滾動監聽：用畫面中央日期決定 active 年月（只在變化時 setState）
void _onScroll() {
  if (!_scrollController.hasClients) return;
  final pos = _scrollController.position;
  final centerOffset = pos.pixels + pos.viewportDimension / 2;
  final daysFromAnchor = (centerOffset / _kWeekHeight * 7).floor();
  final centerDate = _anchorSunday().add(Duration(days: daysFromAnchor));
  if (centerDate.year != _activeYear || centerDate.month != _activeMonth) {
    setState(() {
      _activeYear = centerDate.year;
      _activeMonth = centerDate.month;
    });
  }
}

/// 呢個月有冇任何排班（空狀態提示用）
bool _isMonthEmpty(DateTime month) {
  final prefix =
      '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
  return !widget.store.assignments.keys.any((k) => k.startsWith(prefix));
}

void _goToToday() {
  final now = DateTime.now();
  // 「今日」＝睇今日：跳返今日所在週＋選中今日（出選中框）＋詳情板更新
  setState(() {
    _selectedDate = DateTime(now.year, now.month, now.day);
  });
  _scrollController.animateTo(
    _kInitialWeek * _kWeekHeight,
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeOut,
  );
}

/// 箭頭切月：滾去目標月份 1 號所在週嘅頂部
void _shiftMonth(int delta) {
  final target = DateTime(_activeYear, _activeMonth + delta, 1);
  final targetSunday =
      target.subtract(Duration(days: target.weekday % 7));
  final weekIndex =
      _kInitialWeek + (targetSunday.difference(_anchorSunday()).inDays ~/ 7);
  _scrollController.animateTo(
    weekIndex * _kWeekHeight,
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeOut,
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

/// 開排班面板（固定 widget，唔係 bottom sheet）：取代詳情板，
/// 擺喺日曆下方；閂咗詳情板還原。
void _openPanel() {
  // 轉日之前，如果便利貼編輯緊，先存咗佢
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
    final target = DateTime(year, month, 1);
    final targetSunday =
        target.subtract(Duration(days: target.weekday % 7));
    final weekIndex =
        _kInitialWeek + (targetSunday.difference(_anchorSunday()).inDays ~/ 7);
    setState(() {
      _activeYear = year;
      _activeMonth = month;
    });
    _scrollController.animateTo(
      weekIndex * _kWeekHeight,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
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
icon: const Icon(Icons.chevron_left)),
IconButton(
onPressed: () => _shiftMonth(1),
icon: const Icon(Icons.chevron_right)),
],
),
body: Column(
children: [
        if (isNativeAlarmSupported && _exactAlarmOk == false)
          MaterialBanner(
            backgroundColor: const Color(0xFFFFF9F5),
            content:
                const Text('未授權精確鬧鐘，鬧鐘可能唔準時。請去設定開啟。'),
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
                onPressed: () => widget.alarms.bridge
                    .openFullScreenIntentSettings(),
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
// 無縫連續週滾動：每項固定 76px 一週，無重複、無 gap
child: ListView.builder(
controller: _scrollController,
itemExtent: _kWeekHeight,
itemBuilder: (_, week) => _weekRow(t, week),
),
),
// 空狀態：呢個月一日都冇排，俾句有用提示（唔係乾空白）
if (_isMonthEmpty(DateTime(_activeYear, _activeMonth)))
Padding(
padding: const EdgeInsets.symmetric(vertical: 6),
child: Text(
'呢個月未排更，撳右上「排班」開始',
style: TextStyle(fontSize: 13, color: t.neutralFg2),
textAlign: TextAlign.center,
),
),
// 排班面板開嗰陣取代詳情板（固定喺日曆下方，唔遮日曆格）；
// 閂咗詳情板還原。支援下滑退出。
_schedPanelOpen
    ? GestureDetector(
        onVerticalDragEnd: (details) {
          // 向下滑（正 velocity）就閂面板
          if ((details.primaryVelocity ?? 0) > 300) {
            setState(() => _schedPanelOpen = false);
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ShiftPickerPanel(
            key: _panelKey,
            initialDate: _selectedDate,
            store: widget.store,
            alarms: widget.alarms,
            onClose: () => setState(() => _schedPanelOpen = false),
          ),
        ),
      )
    : _detailPanel(t),
],
),
);
}

/// 日曆下方詳情板：三欄橫排。
/// 左小欄：日期＋班次時間（如「10月15日」「00–06」；無更顯示「未排更」，
/// 鬧鐘數跟喺時間下面——一眼睇到呢日有冇排漏鬧鐘）。
/// 中大欄：備註便利貼（維持「㩒即打、收鍵盤／失焦自動保存」，無提示字；
/// 假期當天便利貼上方顯示假期名，純顯示，唔寫入用戶備註）。
/// 右欄：「改排班」按鈕（圖標＋文字），㩒即開排班面板。
Widget _detailPanel(ShiftTokens t) {
  final key = ShiftStore.ymd(_selectedDate);
  final assignment = widget.store.assignments[key];
  final def =
      assignment != null ? widget.store.defs[assignment.shiftId] : null;
  final remark = widget.store.remarks[key] ?? '';
  // 鬧鐘數：一眼睇到呢日有冇排漏鬧鐘
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
    // 三欄：左日期＋時間｜中備註便利貼｜右改排班；小屏唔溢出靠左中欄壓縮。
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
        // 中大欄：備註便利貼；假期當天上方多一行假期名（純顯示）
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
        // 右欄：改排班（圖標＋文字）
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

/// 備註便利貼：預設空白（無提示字），中性白底；㩒即變 TextField，
/// 失焦自動存。只要「㩒即打」嘅交互，唔轉色。
Widget _remarkStickyNote(ShiftTokens t, String key, String remark) {
  final stickyBg = t.neutralBg; // 中性白（詳情板係淺灰 #F5F5F5）
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
      // 等一幀，等 TextField build 好再攞焦點彈鍵盤
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

/// 便利貼失焦／完成 → 自動保存並返顯示態（用開編輯時嘅 key，唔怕中途轉日）
Future<void> _saveInlineRemark() async {
  if (!_editingRemark) return;
  final key = _editingRemarkKey;
  final text = _remarkCtrl.text;
  setState(() {
    _editingRemark = false;
    _editingRemarkKey = '';
  });
  // 失焦時先 unfocus，避免鍵盤殘留
  _remarkFocus.unfocus();
  await widget.store.setRemark(key, text);
}

Widget _legend(ShiftTokens t) {
final defs = widget.store.sortedDefs();
// 用 Wrap 唔用 Row：用戶自定義班次多嗰陣唔會 overflow
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
fontSize: t.fontCaption, color: t.neutralFg2)),
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

/// 一週 Row：7 個 DayCell（星期日開始），固定高度，無重複、無 gap。
/// 每個禮拜喺成個日曆只出現一次。
Widget _weekRow(ShiftTokens t, int week) {
  final sunday = _sundayForWeek(week);
  final today = DateTime.now();
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      children: [
        for (int i = 0; i < 7; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < 6 ? 1 : 0),
              child: _weekDayCell(t, sunday.add(Duration(days: i)), today),
            ),
          ),
      ],
    ),
  );
}

/// 週 Row 入面嘅一日：直接用 active 年月判斷淡化（唔再傳 isCurrentMonth）。
Widget _weekDayCell(ShiftTokens t, DateTime date, DateTime today) {
  final day = date.day;
  final key = ShiftStore.ymd(date);
  final assignment = widget.store.assignments[key];
  final def = assignment != null ? widget.store.defs[assignment.shiftId] : null;
  final note = assignment?.note ?? '';
  final isToday = date.year == today.year &&
      date.month == today.month &&
      date.day == today.day;
  return _dayCell(t, date, day, def, note, isToday);
}

/// 日曆格三行佈局（80px）：三行用 AutoSizeText＋全個月曆共用嘅
/// AutoSizeGroup，自動計出所有格都裝得落嘅最大字級（10–18px，0.5 遞進），
/// 全個月曆字級統一——唔再逐格 FittedBox 縮放。
/// 行1：日期 w400（澳門公眾假期嗰日變紅）；行2：班次縮寫 w700（唯一加粗）；行3：場所 w400。
/// **所有格一律 3 行結構**：無更嘅空格行2、行3 用空字串佔位，
/// 有更但無場所嘅格行3 用空字串佔位——保證成個月曆三行像素級對齊
/// （日期齊日期、班次齊班次、場所齊場所；空格嘅日期唔再亂郁）。
/// 成組垂直置中；格內橫向 padding 0，文字攞足成格闊。
/// 有排更成格填滿時段 bg 色；今日 2px 品牌藍框。
Widget _dayCell(ShiftTokens t, DateTime date, int day, ShiftDef? def,
    String note, bool isToday) {
  final slot = def != null ? t.slotForTime(def.startTime) : null;
  // Scheme A：用畫面中央 active 年月判斷，非 active 月成格淡化。
  // AnimatedOpacity 包住邊框＋底色＋文字，滑動跨月時有絲滑過渡。
  final isActiveMonth =
      date.year == _activeYear && date.month == _activeMonth;

  final baseFg = slot?.fg ?? t.neutralFg;
  final baseBg = slot?.bg ?? t.neutralBg;
  // 澳門公眾假期：日期數字變紅（班次縮寫／場所色不變；非 active 月唔標紅）
  final dateFg = (isActiveMonth && holidayName(date) != null)
      ? t.danger
      : baseFg;
  // 查看模式：選中嗰日出深色邊框；選中框優先過今日藍框（要睇得清）。
  final isSelected = date.year == _selectedDate.year &&
      date.month == _selectedDate.month &&
      date.day == _selectedDate.day;
  final borderColor = isSelected
      ? t.neutralFg
      : (isToday ? t.brand : (slot?.border ?? t.neutralStroke));
  // 非 active 月：成格 AnimatedOpacity 0.6（邊框＋底色＋文字一齊淡）
  Widget cell = Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: baseBg,
        border: Border.all(
            color: borderColor, width: (isSelected || isToday) ? 2 : 1),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AutoSizeText('$day',
              style: TextStyle(fontWeight: FontWeight.w400, color: dateFg),
              textAlign: TextAlign.center,
              maxLines: 1,
              minFontSize: 10,
              maxFontSize: 18,
              stepGranularity: 0.5,
              group: _cellTextGroup,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          // 行2：班次縮寫。無更嘅格用空字串佔位——空字串唔影響
          // AutoSizeGroup 字級計算，但佔一行高，保證成個月曆嘅
          // 日期全部喺同一高度（空格唔再亂郁）。
          AutoSizeText(def != null ? truncateAbbr(def.abbr) : '',
              style: TextStyle(fontWeight: FontWeight.w700, color: baseFg),
              textAlign: TextAlign.center,
              maxLines: 1,
              minFontSize: 10,
              maxFontSize: 18,
              stepGranularity: 0.5,
              group: _cellTextGroup,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          // 行3：場所。無更或無場所時用空字串佔位（見
          // test/empty_text_height_test.dart），保證所有格三行
          // 像素級對齊（日期齊日期、班次齊班次、場所齊場所）。
          AutoSizeText(
              (def != null && note.isNotEmpty) ? truncateAbbr(note) : '',
              style: TextStyle(fontWeight: FontWeight.w400, color: baseFg),
              textAlign: TextAlign.center,
              maxLines: 1,
              minFontSize: 10,
              maxFontSize: 18,
              stepGranularity: 0.5,
              group: _cellTextGroup,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  // 成格 AnimatedOpacity：滑動跨月時淡入淡出有 200ms 過渡
  cell = AnimatedOpacity(
    duration: const Duration(milliseconds: 200),
    opacity: isActiveMonth ? 1.0 : 0.6,
    child: cell,
  );
  return GestureDetector(
    onTap: () {
      HapticFeedback.selectionClick();
      // 查看模式：只更新選中日＋詳情板，唔開 sheet。
      // 排班面板開緊嗰陣，㩒格＝閂面板（唔再跳去嗰日）。
      // 轉日之前，如果便利貼編輯緊，先存咗佢。
      if (_editingRemark) {
        _saveInlineRemark();
      }
      if (_schedPanelOpen) {
        setState(() => _schedPanelOpen = false);
        return;
      }
      setState(() {
        _selectedDate = DateTime(date.year, date.month, date.day);
      });
    },
    child: cell,
  );
}
}
