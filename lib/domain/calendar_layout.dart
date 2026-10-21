import 'dart:math' as math;

/// 日曆頁三區固定佈局算式（純函數、零 Flutter 依賴，可直接單元測試）。
///
/// 版面由上到下固定三區，位置同高度都唔會再彈出彈入（v3.6 起取代舊版
/// 「㩒日期先由底部彈出詳情板」的做法）：
///
/// ```
/// ┌──────────────┐
/// │ 頂部海洋線    │ bandHeight
/// ├──────────────┤
/// │ 中間日曆      │ gridHeight（6 行 × cellHeight + gridOverhead）
/// ├──────────────┤
/// │ 底部排班詳情  │ detailHeight（原地切換成排班編輯，都係呢一格）
/// ├──────────────┤
/// │ 底部導航欄留白 │ navHeight
/// └──────────────┘
/// ```
///
/// 空間唔夠時的讓位順序（用戶揀「優先保日曆格大」）：
///   1. 海洋帶 [oceanMax] → [oceanMin]
///   2. 底部區 [detailMax] → [detailMin]
///   3. 日曆格 [cellMax] → 縮細（最後先讓）
///
/// 大屏剩餘空間全部俾日曆，格高生長到 [cellGrowMax] 為止，再多就由
/// `_monthGrid` 的 `Center` 上下平均分掉，唔會拉歪格形。
class CalendarLayout {
  /// 底部導航欄遮住的高度。
  /// `HomeScreen` 用 `extendBody: true`，body 會一直伸到導航欄底下，所以要自己留白。
  static const double navReserved = 72.0;

  /// 海洋帶理想高度（必須等於 `kOceanBandHeight`，由測試鎖住）／讓位後下限。
  /// 低過 56 就連海平線同太陽都砌唔埋，寧願留返呢個下限。
  static const double oceanMax = 96.0;
  static const double oceanMin = 56.0;

  /// 底部區理想高度／讓位後下限。
  ///
  /// [detailMin] 由實測反推出來：詳情卡內容（日期行 + 班次行 + 備註行）實測 103px，
  /// 加 `margin 4+6` 與 `padding 8+10` 共 28.4px → 最少要 132。
  /// 再預留備註進入編輯態（TextField 36 取代 30，+6）與三鍵導航機 `SafeArea`
  /// 墊高嘅餘量，定喺 142。
  /// 排班編輯係原地切換入呢一格，裁切咗會睇唔到完成掣，所以呢個下限唔可以再壓。
  ///
  /// 實測依據：`test/calendar_screen_layout_test.dart` 會用真 widget 泵出嚟驗，
  /// 一旦唔夠位會直接報 RenderFlex overflow。
  static const double detailMax = 158.0;
  static const double detailMin = 142.0;

  /// 月曆網格除咗 6 行格之外的固定開銷：Padding 8 + 星期列 24 + SizedBox 4。
  /// 6 × 75 + 36 = 486，即係舊版寫死嘅 `kGridMinHeight`。
  static const double gridOverhead = 36.0;

  /// 日曆格理想高度（= 舊版寫死嘅 75）／大屏生長上限。
  static const double cellMax = 75.0;
  static const double cellGrowMax = 92.0;

  /// 頂部海洋線實算高度
  final double bandHeight;

  /// 中間日曆區實算高度（含 [gridOverhead]）
  final double gridHeight;

  /// 每一格日曆格的實算高度
  final double cellHeight;

  /// 底部排班詳情區實算高度
  final double detailHeight;

  /// 實留嘅導航欄高度（body 細過 [navReserved] 時會跟住縮，避免反過來溢出）
  final double navHeight;

  const CalendarLayout._({
    required this.bandHeight,
    required this.gridHeight,
    required this.cellHeight,
    required this.detailHeight,
    required this.navHeight,
  });

  /// 按 Scaffold body 嘅可用高度（`LayoutBuilder` 的 `constraints.maxHeight`）切三區。
  factory CalendarLayout.compute(double bodyHeight) {
    final double nav =
        math.min(navReserved, math.max(0.0, bodyHeight));
    final double avail = math.max(0.0, bodyHeight - nav);

    double band = oceanMax;
    double detail = detailMax;

    // 日曆先按理想格高攞足，唔夠位就依次削海洋帶、底部區（日曆最後先讓）。
    double deficit = (band + detail + gridOverhead + 6 * cellMax) - avail;
    if (deficit > 0) {
      final double cut = math.min(deficit, band - oceanMin);
      band -= cut;
      deficit -= cut;
    }
    if (deficit > 0) {
      final double cut = math.min(deficit, detail - detailMin);
      detail -= cut;
      deficit -= cut;
    }

    // 日曆食晒剩餘：有剩就生長（上限 cellGrowMax），唔夠就縮。
    // 呢度唔設格高下限 —— 設下限會令內容高過 [gridHeight] 而 RenderFlex 溢出，
    // 寧願喺極細視窗（鍵盤彈起）縮到睇唔清，都唔好彈黃黑間條。
    double grid = math.max(0.0, avail - band - detail);
    if (grid <= 0) {
      // 極端情況：連海洋帶 + 底部區都放唔落，兩者按剩餘空間等比讓步。
      final double sum = band + detail;
      final double k = sum > 0 ? avail / sum : 0.0;
      band *= k;
      detail *= k;
      grid = 0.0;
    }

    final double raw = grid <= gridOverhead ? 0.0 : (grid - gridOverhead) / 6;
    final double cell = raw.clamp(0.0, cellGrowMax);

    return CalendarLayout._(
      bandHeight: band,
      gridHeight: grid,
      cellHeight: cell,
      detailHeight: detail,
      navHeight: nav,
    );
  }

  /// 三區加導航留白嘅實佔高度。
  /// 永遠等於傳入嘅 `bodyHeight`（body ≥ 0 時）—— 即係永遠唔會溢出，由測試鎖住。
  double get totalHeight => bandHeight + gridHeight + detailHeight + navHeight;
}
