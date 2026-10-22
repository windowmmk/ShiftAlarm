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
///   2. 底部區 [detailMax] → [detailMin]（v3.6.1 起兩者相等，呢一級變 no-op）
///   3. 日曆格 [cellMax] → 縮細（最後先讓）
///
/// 大屏剩餘空間全部俾日曆，格高生長到 [cellGrowMax] 為止，再多就由
/// `_monthGrid` 的 `Center` 上下平均分掉，唔會拉歪格形。
class CalendarLayout {
  /// 底部導航欄留白的**預設值**（僅在呼叫方冇提供真實 inset 時使用）。
  ///
  /// ⚠️ v3.6.1 起呢個常數唔再係「真值」：`HomeScreen` 用 `extendBody: true`，
  /// Scaffold 會把**真實導航欄高度**注入 body 的 `MediaQuery.padding.bottom`
  /// （實測手勢導航 88.8px、三鍵導航 112.8px，鍵盤彈起時變 0），
  /// 所以 `CalendarScreen` 每次都會顯式傳 `bottomInset`。
  ///
  /// 舊版寫死 72 係錯的：手勢機卡片底被導航欄蓋 10px、三鍵機蓋 40px。
  /// 保留 72 只係為咗「冇 MediaQuery 的純算式呼叫」（單元測試、日後預覽）
  /// 仍然有個合理數值，唔會突然變 0 而令三區全部塌落底部。
  static const double navReserved = 72.0;

  /// 海洋帶理想高度（必須等於 `kOceanBandHeight`，由測試鎖住）／讓位後下限。
  /// 低過 56 就連海平線同太陽都砌唔埋，寧願留返呢個下限。
  ///
  /// ⚠️ [oceanMin] 只在**非鍵盤態**有意義：鍵盤彈起時 [bandHeight] 直接歸 0
  /// （用戶明確要求「輸入文字時把頂部的天色欄完全壓縮為 0」），
  /// 呢個時候 0 < [oceanMin] 係刻意嘅，唔算違反下限。
  static const double oceanMax = 96.0;
  static const double oceanMin = 56.0;

  /// 底部區理想高度 = 讓位後下限（v3.6.1 起兩者相等）。
  ///
  /// 定喺 140 係實測反推出來的「剛剛好裝得落、冇餘量」：
  /// - 詳情卡內容自然高 **103**（日期行 21 + 6 + 班次行 40 + 6 + 備註行 30）；
  /// - 備註進入編輯態時 TextField 36 取代 30 → 內容變 **109**；
  /// - 卡片固定開銷 = margin 4+6 + padding 8+10 + border 1.2×2 = **30.4**。
  ///
  /// 所以：103 + 30.4 = 133.4（普通態）／109 + 30.4 = 139.4（編輯態）→
  /// **140 就係「啱啱好」**：普通態內層餘 6.6px、編輯態餘 0.6px。
  ///
  /// 舊版 158/142 會令大屏白白多 18px 空白（用戶原話：「第三欄的高度，
  /// 現在尚有余量在底下空白位置，應該用盡」），所以兩者一齊收窄到 140。
  ///
  /// 排班編輯係原地切換入呢一格，裁切咗會睇唔到完成掣，所以呢個值唔可以再壓。
  /// 實測依據：`test/calendar_layout_measure_test.dart` 會用真 widget 泵出嚟驗。
  static const double detailMax = 140.0;
  static const double detailMin = 140.0;

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

  /// 實留嘅導航欄高度（body 細過 `bottomInset` 時會跟住縮，避免反過來溢出）
  final double navHeight;

  const CalendarLayout._({
    required this.bandHeight,
    required this.gridHeight,
    required this.cellHeight,
    required this.detailHeight,
    required this.navHeight,
  });

  /// 按 Scaffold body 嘅可用高度（`LayoutBuilder` 的 `constraints.maxHeight`）切三區。
  ///
  /// [bottomInset] 係**真實**底部安全區高度（`MediaQuery.padding.bottom`）。
  /// `extendBody: true` 之下 Scaffold 會把導航欄高度注入 body 的
  /// `padding.bottom`，所以直接讀佢就係「導航欄真正遮住幾多」；
  /// 鍵盤彈起時 Scaffold 會將佢歸零 → [navHeight] 自動變 0，唔會再空出 72。
  ///
  /// [keyboardOpen] 為 `true` 時海洋帶直接壓到 0，讓出嚟的高度全部俾日曆
  /// （用戶原話：「點開排班開始輸入文字後…請可把頂部的天色欄完全壓縮為0」）。
  factory CalendarLayout.compute(
    double bodyHeight, {
    double bottomInset = navReserved,
    bool keyboardOpen = false,
  }) {
    final double safeBody = math.max(0.0, bodyHeight);
    // 導航留白唔可以大過 body 本身，否則反過來溢出
    final double nav = math.min(math.max(0.0, bottomInset), safeBody);
    final double avail = math.max(0.0, safeBody - nav);

    double band = keyboardOpen ? 0.0 : oceanMax;
    double detail = detailMax;

    // 日曆先按理想格高攞足，唔夠位就依次削海洋帶、底部區（日曆最後先讓）。
    double deficit = (band + detail + gridOverhead + 6 * cellMax) - avail;
    // ① 海洋帶：只有「高過下限」先有得讓。
    //    鍵盤態 band = 0（低過 oceanMin）→ 呢級直接跳過，唔會反彈返 56。
    final double bandRoom = band - oceanMin;
    if (deficit > 0 && bandRoom > 0) {
      final double cut = math.min(deficit, bandRoom);
      band -= cut;
      deficit -= cut;
    }
    // ② 底部區：v3.6.1 起 detailMax == detailMin == 140，所以 `detailRoom` 恆為 0、
    //    呢一級恆為 no-op。**刻意保留**：日後有人把 [detailMax] 調大（例如加多一行），
    //    讓位鏈要能夠自動生效，唔使人再改一次呢段邏輯。
    final double detailRoom = detail - detailMin;
    if (deficit > 0 && detailRoom > 0) {
      final double cut = math.min(deficit, detailRoom);
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
