/// 班次時間純函數：'HH:mm' 解析與時長計算。
///
/// 全專案**只此一份** —— 打卡鬧鐘的 `dk_out` offset（`shift_store.dart`）與
/// 統計頁的總工時（`stats.dart`）都必須經此。否則兩邊會各自漂移，
/// `stats.dart` 舊版硬編碼「每更 6 小時」就是這樣長出來的：
/// 同一個概念在兩個地方各有一份實作，改了一邊另一邊照樣錯，而且不會有測試紅。
library;

/// 'HH:mm' → 當日分鐘數（0–1439）。
///
/// 容許無補零寫法：`'9'` → 540（09:00），`'09:0'` → 540。
/// 這是刻意保留的寬容度 —— 本函數同時是打卡鬧鐘 offset 的來源，
/// 把一個語意明確的輸入打成 0，會令收工鐘在開工時刻響，比算錯更嚴重。
///
/// 以下一律回 `null`（呼叫方按 `0` 處理）：
/// - 時分越界：`'24:00'`、`'09:60'`、`'-1:00'`
/// - 無法解析：`'abc'`、`''`、`':30'`、`'09:xx'`
///
/// 舊版 `ShiftDef.durationMinutes` 的內部 `mins()` 用 `?? 0` 吞掉解析失敗，
/// 所以 `'abc'` 會被當成 00:00、`'24:00'` 會算出 1440（＝跨日 0 分鐘）。
/// 那些是「鬼數字」：看起來像真的算過，實際上是憑空捏造。此處收緊成 `null`。
///
/// 多於兩段（`'09:00:00'`）沿用舊版行為：只取前兩段，忽略其餘。
int? hmToMinutes(String raw) {
  final parts = raw.trim().split(':');
  final h = int.tryParse(parts[0].trim());
  if (h == null) return null;
  final m = parts.length > 1 ? int.tryParse(parts[1].trim()) : 0;
  if (m == null) return null;
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

/// 班次時長（分鐘）。
///
/// - 收工早過開工視為跨日：`18:00–00:00` → 360、`22:00–06:00` → 480
/// - `start == end` → 0（UI 層唔畀存，屬無效設定；刻意不放大成 24 小時）
/// - 任一時間無法解析 → 0
///
/// 回傳值恆為 0–1439，不會是負數（Dart 的 `%` 對負數仍回非負）。
int shiftDurationMinutes(String startTime, String endTime) {
  final a = hmToMinutes(startTime);
  final b = hmToMinutes(endTime);
  if (a == null || b == null) return 0;
  return (b - a) % 1440;
}
