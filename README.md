# ShiftAlarm 排班鬧鐘 ⏰

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Web%20(PWA)-3DDC84?logo=android&logoColor=white)](https://windowmmk.github.io/ShiftAlarm/)
[![Privacy](https://img.shields.io/badge/Privacy-100%25%20Offline-success)](https://github.com/windowmmk/ShiftAlarm)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Latest Release](https://img.shields.io/badge/Release-v3.3.1-orange)](https://github.com/windowmmk/ShiftAlarm/releases)

專為輪班與排班人士量身打造的**極致隱私、純離線、全功能**排班日曆與精確鬧鐘應用程式（Flutter / Android 原生整合 / Web PWA）。

🌐 **線上體驗 Web 版**：[https://windowmmk.github.io/ShiftAlarm/](https://windowmmk.github.io/ShiftAlarm/)

---

## 🔒 核心承諾：極致隱私與純離線架構

- **100% 離線運行**：本應用程式在 Android 作業系統層級**完全未申請 `INTERNET` 網路存取權限**，在物理層面徹底杜絕聯網可能。
- **無帳號、無雲端**：所有班次、排程與備註資料全數存放於本機儲存空間，永不離開您的裝置。
- **零追蹤、零廣告**：無 Firebase、無 Crashlytics、無任何第三方追蹤分析或廣告 SDK。
- **透明可審計**：全開源架構，代碼乾淨透明，隨時接受社群審查。

---

## ✨ 主要功能亮點

### 🚀 全新 SA2 / SR2 極簡二進制協議（Base58）
- **體積壓縮 90%+**：捨棄冗長 JSON 欄位名，採用工業級自定義二進制緊湊預編碼：
  - **配置口令 (`SA2:<Base58>`)**：班次定義＋地點清單壓縮至 **90 ~ 115 字元**（原需 2000+ 字元）。
  - **排班口令 (`SR2:<Base58>`)**：整月排班＋地點＋備註壓縮至 **150 ~ 230 字元**。
- **IEEE 802.3 CRC32 防偽校驗**：CRC32 校驗碼與 UNIX 時間戳直接內嵌於二進制前導區，防止傳輸截斷與惡意竄改。
- **雙模相容純 CSV 文字**：同時支援傳統 Excel / 記事本純文字匯入匯出（格式：`YYYY-MM-DD,班次代號,地點`）。
- **多維零負擔分享體驗**：
  - **剪貼簿即時探針**：打開彈窗自動辨識有效口令，免去手動貼上步驟。
  - **網址一鍵導入**：分享連結支援 `?c=SA2:...` 與 `?r=SR2:...`（微信友善無 `#`，杜絕話題標籤誤判；亦向下相容 `#c=` 與 `#r=`），點開即跳出預覽確認並 1 秒套用。
  - **二維碼（QR Code）面對面快傳**：支援在現場一鍵生成 QR Code，支援網址與純短碼切換，面對面掃碼秒級同步。

### 📅 固定 6 週流暢月曆
- **標準 42 格固定網格**：每月固定 6 行排版，消除了跨月切換時的高度撕裂與震顫。
- **Web 60fps 滿幀渲染**：引入 `RepaintBoundary` 重繪邊界隔離與文字佈局快取，滑動體驗行雲流水。
- **年月快速跳轉**：點擊頂部標題即可展開年月快速切換面板，一鍵跨年跨月跳轉。
- **手勢與震動反饋**：
  - 日曆格點選支援輕微觸覺震動（Haptic Feedback），提供扎實手感。
  - 底部排班面板支援左右水平滑動手勢，連續排班切換日期得心應手。
- **獨立每日便利貼**：每日常駐便簽功能，排班與備註互不干擾。
- **澳門公眾假期標註**：內建法定公眾假期表，假期日期醒目標記，排班休假一目了然。

### ⏰ 精準輪班鬧鐘系統（Android 原生）
- **多鬧鐘調度**：每個班次可配置多組鬧鐘（提前開工提醒、打卡通知等）。
- **全屏鬧鐘喚醒**：原生 Android `AlarmManager` 精確調度，支援鎖屏全屏彈窗喚醒與自訂鈴聲。
- **溫和通知模式**：支援「僅通知」輕量震動提示，滿足開工或收工打卡等多樣化需求。
- **開機自動重排**：裝置重開機後，原生 `BootReceiver` 自動自本地還原並重新排程所有未來鬧鐘，絕不漏響。
- **權限自檢儀表板**：內建精確鬧鐘、全屏通知、電池最佳化白名單自檢引導。

### 🎨 班次與地點管理
- **所見即所得預覽**：班次編輯器內建即時日曆格縮圖，即時計算全形／半形單位字寬，超長自動防截斷警示。
- **地點自動補全**：輸入地點時自動比對歷史記錄，高亮標籤一鍵選填。

### 📊 工時與出勤統計總覽
- **多維度區間統計**：支援「本月」、「最近 7 天」、「近 30 天」、「近 90 天」、「今年至今」及自訂區間。
- **視覺化分佈圖表**：班次比例長條圖、地點分佈次數排行、總出勤天數與累計工時即時精算。

---

## 📂 專案結構簡介

```text
ShiftAlarm/
├── android/               # Android 原生模組（AlarmReceiver, BootReceiver, 權限自檢）
├── lib/
│   ├── alarm/             # 原生鬧鐘與廣播 MethodChannel 橋接層
│   ├── domain/            # 領域模型（SA2/SR2 二進制編解碼、Base58、CSV、假期、統計）
│   ├── theme/             # 設計規範與色彩 Token
│   ├── ui/
│   │   ├── screens/       # 畫面（日曆、排班面板、班次管理、統計圖表、權限設定）
│   │   └── widgets/       # 共用元件（徽章、縮圖、二維碼彈窗）
│   ├── config.dart        # 平台相容性開關
│   └── main.dart          # App 啟動入口與全域錯誤防護
└── test/                  # 單元測試集（協議編解碼、校驗碼、CSV、統計算法）
```

---

## 🛠️ 開發與建置

### 環境需求
- **Flutter SDK**：3.13+ 以上
- **Android SDK**：API 34 ~ 36
- **JDK**：OpenJDK 17

### 快速開始

```bash
# 1. 取得專案源碼
git clone https://github.com/windowmmk/ShiftAlarm.git
cd ShiftAlarm

# 2. 安裝 Flutter 依賴
flutter pub get

# 3. 執行單元測試
flutter test

# 4. 打包 Android Release APK
flutter build apk --release --target-platform android-arm64

# 5. 打包 Web PWA 版本
flutter build web --release
```

---

## 📜 版本演進歷程

- **v3.3.1** *(當前版本)*：
  - 徹底剔除歷史過渡期代碼與冗餘測試，代碼減重 550+ 行。
  - 正式確立 `SA2:` 與 `SR2:` 最新極簡二進制 Base58 協議與純 CSV 雙模架構。
  - 修復網址 Hash 導入排班時的原生鬧鐘自動註冊機制。
- **v3.3.0**：
  - 引入 `SA2:` / `SR2:` 極簡協議，體積壓縮至 90~150 字元。
  - 實作網址 Hash 一鍵導入（`#c=` / `#r=`）與 QR Code 面對面掃碼分享。
- **v3.2.1**：
  - 實現比特幣同款 Base58 編解碼器，解決 Base64 符號雙擊選取問題。
  - Web 端引入 `RepaintBoundary` 與文字排版快取，幀率提升至穩定的 60fps。
- **v3.2.0**：
  - 重構月曆為標準固定 6 週（42 格）分頁網格，修復跨年溢出 Bug。
  - 升級 Gradle 8.14，打通 GitHub Actions 自動化 Web / Android CI 建置。
- **v3.1.0**：
  - 初始開源版本，具備 100% 離線排班與 Android 原生輪班鬧鐘。

---

## 📄 開源授權

本專案採用 [MIT License](LICENSE) 授權開放。
