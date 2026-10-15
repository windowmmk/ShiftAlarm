# ShiftAlarm 排班鬧鐘 ⏰

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white)](https://www.android.com)
[![Privacy](https://img.shields.io/badge/Privacy-100%25%20Offline-success)](https://github.com/windowmmk/ShiftAlarm)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

專為輪班與排班人士量身打造的**極致隱私、純離線、全功能**排班日曆與精確鬧鐘應用程式（Flutter / Android 原生整合）。

---

## 🔒 核心承諾：極致隱私與純離線架構

- **100% 離線運行**：本應用程式在 OS 作業系統層級**完全未申請 `INTERNET` 網路存取權限**，物理層面杜絕聯網可能。
- **無帳號、無雲端**：所有班次、排程與備註資料全數安全加密存放於手機本地儲存空間，永不離開您的裝置。
- **零追蹤、零分析**：無 Firebase、無 Crashlytics、無任何第三方追蹤分析或廣告 SDK。
- **透明可審計**：全開源架構，代碼乾淨透明，隨時接受社群審查。

---

## ✨ 主要功能亮點

### 📅 無縫月曆排班與流暢交互
- **無縫週滾動日曆**：採用連續週列表結構，上下滑動順暢自如，無月與月之間的撕裂感或空白間隔。
- **快速年月選擇器**：點擊頂部標題即可展開年月快速切換面板，一鍵跨年跨月跳轉。
- **手勢與震動反饋**：
  - 日曆格點選支援輕微觸覺震動（Haptic Feedback），提供扎實手感。
  - 底部排班面板支援左右水平滑動手勢，連續排班切換日期得心應手。
- **獨立每日便利貼**：每日常駐便簽功能，排班與備註互不干擾；未記錄時提供直覺的提示引導。
- **澳門公眾假期標註**：內建法定公眾假期表，假期日期醒目標記，排班休假一目了然。

### ⏰ 精準輪班鬧鐘系統
- **多鬧鐘支援**：每個班次可配置多組鬧鐘（提前開工提醒、打卡通知等）。
- **全屏鬧鐘喚醒**：原生 Android `AlarmManager` 精確調度，支援鎖屏全屏彈窗喚醒與自訂鈴聲。
- **溫和通知模式**：支援「僅通知」輕量震動提示，滿足開工或收工打卡等多樣化需求。
- **開機自動重排**：裝置重開機後，原生 `BootReceiver` 自動自本地還原並重新排程所有未來鬧鐘，絕不漏響。

### 🎨 靈活的班次與場所管理
- **所見即所得（1:1 即時預覽）**：班次編輯器內建即時日曆格縮圖，輸入時即時計算單位字寬，超長自動防截斷警示。
- **自動補全與快選**：輸入場所時自動比對歷史記錄，高亮標籤一鍵選填。
- **CSV 離線批量匯入**：透過剪貼簿即可快速貼上並匯入大量排班資料，支援錯誤格式自動檢查。
- **配置匯入與匯出**：完整支援班次定義與場所清單的 JSON 備份與還原，更換手機無縫銜接。

### 📊 工時與出勤統計總覽
- **多維度區間統計**：支援「本月」、「最近 7 天」、「近 30 天」、「近 90 天」、「今年至今」及自訂區間。
- **視覺化分佈圖表**：班次比例長條圖、場所分佈次數排行、總出勤天數與累計工時即時精算。

---

## 🛠️ 開發與建置環境

### 環境需求
- **Flutter SDK**：3.x 以上
- **Android SDK**：API 34 ~ 36
- **JDK**：OpenJDK 17

### 快速開始

1. **取得專案源碼**：
   ```bash
   git clone https://github.com/windowmmk/ShiftAlarm.git
   cd ShiftAlarm
   ```

2. **安裝 Flutter 依賴**：
   ```bash
   flutter pub get
   ```

3. **靜態分析與單元測試**：
   ```bash
   dart analyze
   flutter test
   ```

4. **打包 Release APK**：
   ```bash
   flutter build apk --release --target-platform android-arm64
   ```
   產生的 APK 位於：`build/app/outputs/flutter-apk/app-release.apk`。

---

## 📂 專案結構簡介

```text
ShiftAlarm/
├── android/               # Android 原生專案（AlarmReceiver, BootReceiver, 權限管理）
├── lib/
│   ├── alarm/             # 原生鬧鐘與廣播 MethodChannel 橋接層
│   ├── domain/            # 領域模型（班次邏輯、離線儲存、CSV 解析、假期表、統計算法）
│   ├── theme/             # 設計規範與色彩 Token
│   ├── ui/
│   │   ├── screens/       # 畫面（日曆、排班面板、班次管理、統計圖表、權限設定）
│   │   └── widgets/       # 共用元件
│   └── main.dart          # App 啟動入口
└── test/                  # 單元測試與回歸測試集
```

---

## 📄 開源授權

本專案採用 [MIT License](LICENSE) 授權開放。
