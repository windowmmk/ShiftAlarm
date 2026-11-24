# 更新日誌 (Changelog)

本專案遵循語意化版本規範，發版時由 GitHub Actions 自動擷取對應版本章節作為 GitHub Release 說明。

## v3.7.1

### 功能與體驗升級
- **排班新增「假期類」（支援自訂名稱）**：排班操作列加入「假期」按鈕，內建年假／病假／補假／事假／婚假／產假快選並支援自由輸入自訂假期名稱；月曆格與詳情卡以柔霧鼠尾草綠標示「全日休假（不計工時）」。
- **假期全鏈路隔離與防呆**：自動撤銷當日鬧鐘與響前預告、不計入返工日數／工時與地點分佈、Android 原生開機重建（`BootRescheduler`）自動跳過防鬼響，且完整支援 SR2 口令與 CSV 導入導出。
- **夜間海景視覺升級（柔亮月夜、不黑不陰森）**：GLSL 主著色器與 2D 降級繪製器同步新增滿月月暈、微閃星光、柔和月夜靛藍海岸天色與水波碎銀月影倒映，並將藍眼淚調整為輕柔青藍光暈。

## v3.7.0

### 架構與程式碼重構
- **Flutter 模組化拆分**：將原本超過 800～1,600 行的核心單檔拆解為職責單一的子模組：
  - 日曆頁拆分為 `calendar_day_cell.dart`、`calendar_month_grid.dart`、`calendar_detail_card.dart`、`calendar_month_picker.dart`、`url_import_handler.dart` 與精簡版 `calendar_screen.dart`
  - 領域模型由 `shift_store.dart` 獨立抽離至 `shift_models.dart`（向下相容匯出）
  - 班次管理與編輯拆分為 `shift_manage_screen.dart`、`shift_edit_screen.dart` 與 `alarm_edit_dialog.dart`
  - 設定頁對話框抽離為 `share_export_dialogs.dart` 與 `about_dialog.dart`
  - 2D 海洋降級渲染拆分為 `ocean_atmo_state.dart`、`ocean_fallback_painter.dart` 與 `ocean_atmosphere.dart`
- **Android 原生 Kotlin 模組化**：
  - 拆出 `AlarmChannelHandler.kt`、`PermissionHelper.kt`、`BootRescheduler.kt`、`PreAlertDismissStore.kt` 與 `AlarmUiStyles.kt`
  - 修正淺色時段底色在全屏鬧鐘頁上的文字對比度（柔底深字徽章＋高對比主按鈕）
- **靜態分析清零**：修復所有棄用 API（`Matrix4.translateByDouble`/`scaleByDouble`）、未用變數／函式、非同步 `BuildContext` 警告與文件註解告警，`flutter analyze` 達成 **0 issues**。

### 介面細節與文案打磨
- **純繁體用語統一**：全面將「設置」統一為「設定」，清理混雜口語，維持一致專業感。
- **班次管理頁去重**：當班次名稱與縮寫相同時直接顯示「早更」，不再重複括號顯示為「早更（早更）」。
- **統計頁資訊升級**：「班次分佈」改以雙層高可讀卡片呈現，同步顯示班次名稱與時段（如「早更 · 06–12」），並通過 320px × 2.0x 大字體零溢出驗證。
- **設定頁與詳情卡層次精修**：延續淺色極簡風格，將設定頁改為圓角分組卡片，統一全頁底色、描邊與寬屏居中對齊。

### 安全、測試與 CI/CD
- **簽名金鑰移入 GitHub Secrets**：取消 `shiftalarm-release.jks` 的 Git 追蹤並移除工作流中的明文密碼，保留原簽名金鑰確保舊機可直接覆蓋升級。
- **測試集分層整理**：將原本平鋪的 28 個測試檔整理至 `test/domain/`、`test/alarm/`、`test/ocean/` 與 `test/ui/`，並新增 UI 打磨與響應式回歸測試。
- **自動化管線強化**：新增 `ci.yml`（靜態檢查＋單元／元件測試＋Web／Android 建置驗證），升級 Android 建置鏈至 AGP 9.3.1 / Gradle 9.5.0 / Kotlin 2.4.20（對齊 Flutter 3.50），並改寫 `build-apk.yml` 自動讀取 `CHANGELOG.md` 作為發版日誌。

## v3.6.3

- **天色帶與月曆卡一體化**：修正闊屏（> 480px）每邊錯開 8px 的容器嵌套順序問題，共用底色、描邊、圓角與內縮。
- **格線對比度提升**：日曆卡改用霧藍灰底色，空白格對比度由 15/255 提升至 23/255。
- 新增 `band_card_alignment_test.dart` 鎖定 320／360／412／900px 對齊與對比度防線。

## v3.6.2

- 修復六個介面於窄屏＋系統大字體下的版面溢出問題。
- 啟動重排移至首幀後非同步執行，消除冷啟動白屏。
- 強化 `ShiftStore` 損壞 JSON 隔離備份與 Android 三通道幽靈鬧鐘對帳。

## v3.6.1

- 響前 1 小時預告改為狀態欄倒計時且僅限真鬧鐘（純通知打卡不發預告）。
- 輸入文字鍵盤彈起時頂部天色帶完全壓縮為 0，並精準讀取真實底部系統導航高度。

## v3.6.0

- 重構為三區固定版面（頂部天色帶／中間月曆／底部排班詳情），取消彈出／彈入動畫。
