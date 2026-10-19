library;

/// 統一版本：只有一個版本，無版本開關。
///
/// - 不預設任何班次／場所：用戶首次打開是空的，自己導入或建立配置。
/// - 打卡鬧鐘（開工／收工打卡）是通用功能，不再按版本區分。
const bool kOpenSource = true;

/// 應用程式版本資訊（注意：每次發布新版本時在此與 pubspec.yaml 同步更新）
const String kAppVersion = '3.4.1';
const int kAppBuildNumber = 39;
const String kAppVersionDisplay = '版本 $kAppVersion (Build $kAppBuildNumber)';
