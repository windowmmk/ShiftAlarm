/// v3.5 海洋著色器預設集（12 個物理參數）
///
/// 數值原封抄自 `web/ocean_shader.js` 第 6-91 行的 `SHIFT_OCEAN_PRESETS`。
/// 呢組參數與「帶高」完全無關（shader 係解析度無關嘅），所以改 96px／56px 都唔需要動佢。
/// 96px 相關嘅幾何常數只屬於 `_OceanPainter` fallback（見 ocean_atmosphere.dart 的 `_Compact96`）。
library;

/// 一組海洋大氣物理參數（對應 frag 內 12 個非相機／非時間嘅 uniform）。
class OceanShaderPreset {
  /// 太陽仰角（度，可為負 = 夜晚）
  final double sunElev;

  /// 太陽方位角（度，0 = 正北，180 = 正南）
  final double sunAzimuth;

  /// 風速（m/s）
  final double windSpeed;

  /// 湧浪有效波高（m）
  final double swellHs;

  /// 浪尖銳利度
  final double choppiness;

  /// 海水濁度（影響深海色與次表面散射）
  final double turbidity;

  /// 白浪泡沫量
  final double foam;

  /// 大氣霧霾（Mie 散射強度）
  final double haze;

  /// 雲量
  final double clouds;

  /// 曝光
  final double exposure;

  /// 日月盤光暈（bloom）
  final double bloom;

  /// 夜間生物螢光（「藍眼淚」）強度
  final double nightGlow;

  const OceanShaderPreset({
    required this.sunElev,
    required this.sunAzimuth,
    required this.windSpeed,
    required this.swellHs,
    required this.choppiness,
    required this.turbidity,
    required this.foam,
    required this.haze,
    required this.clouds,
    required this.exposure,
    required this.bloom,
    required this.nightGlow,
  });

  /// 早班出發（05:00-10:59）：晨曦破曉、低角度暖陽、微湧
  static const OceanShaderPreset morning = OceanShaderPreset(
    sunElev: 10.5,
    sunAzimuth: 142.0,
    windSpeed: 7.5,
    swellHs: 1.0,
    choppiness: 0.95,
    turbidity: 0.72,
    foam: 0.65,
    haze: 0.45,
    clouds: 0.30,
    exposure: 1.15,
    bloom: 0.80,
    nightGlow: 0.0,
  );

  /// 午班出發（11:00-16:29）：豔陽碧海、高角度烈日、清透
  static const OceanShaderPreset midday = OceanShaderPreset(
    sunElev: 55.0,
    sunAzimuth: 178.0,
    windSpeed: 6.0,
    swellHs: 0.70,
    choppiness: 0.82,
    turbidity: 0.92,
    foam: 0.38,
    haze: 0.14,
    clouds: 0.16,
    exposure: 1.38,
    bloom: 0.95,
    nightGlow: 0.0,
  );

  /// 晚班出發（16:30-21:29）：金暉落日、貼海平線的紅日、大湧
  static const OceanShaderPreset sunset = OceanShaderPreset(
    sunElev: 3.5,
    sunAzimuth: 195.0,
    windSpeed: 11.5,
    swellHs: 1.7,
    choppiness: 1.35,
    turbidity: 0.50,
    foam: 1.15,
    haze: 0.60,
    clouds: 0.48,
    exposure: 1.08,
    bloom: 1.20,
    nightGlow: 0.0,
  );

  /// 夜班出發（21:30-04:59）：星夜深邃、月光、藍眼淚
  static const OceanShaderPreset night = OceanShaderPreset(
    sunElev: -16.0,
    sunAzimuth: 215.0,
    windSpeed: 8.5,
    swellHs: 1.7,
    choppiness: 1.10,
    turbidity: 0.16,
    foam: 1.40,
    haze: 0.18,
    clouds: 0.14,
    exposure: 0.82,
    bloom: 0.85,
    nightGlow: 1.0,
  );

  /// 晴朗午後（備用）
  static const OceanShaderPreset afternoon = OceanShaderPreset(
    sunElev: 48.0,
    sunAzimuth: 172.0,
    windSpeed: 5.6,
    swellHs: 0.65,
    choppiness: 0.78,
    turbidity: 0.95,
    foam: 0.35,
    haze: 0.14,
    clouds: 0.20,
    exposure: 1.30,
    bloom: 0.85,
    nightGlow: 0.0,
  );

  /// 颱風級大浪（備用）
  static const OceanShaderPreset storm = OceanShaderPreset(
    sunElev: 2.5,
    sunAzimuth: 202.0,
    windSpeed: 18.5,
    swellHs: 3.1,
    choppiness: 1.65,
    turbidity: 0.48,
    foam: 1.85,
    haze: 0.68,
    clouds: 0.78,
    exposure: 1.12,
    bloom: 0.80,
    nightGlow: 0.2,
  );

  /// 由 `OceanAtmoState.mood`（大氣狀態簡稱）取對應預設集。
  ///
  /// 對照表（與 `web/ocean_shader.js` 的時間分段一致）：
  /// - 晨曦破曉 → [morning]（M）
  /// - 碧海晴空 → [midday]（A）
  /// - 金暉落日 → [sunset]（S）
  /// - 星夜藍眼淚 → [night]（N）
  /// - 其他 → [midday]（A）
  static OceanShaderPreset forMood(String mood) {
    if (mood.contains('晨曦') || mood.contains('破曉')) return morning;
    if (mood.contains('金暉') || mood.contains('落日') || mood.contains('黃昏')) {
      return sunset;
    }
    if (mood.contains('星夜') || mood.contains('暗夜') || mood.contains('藍眼淚')) {
      return night;
    }
    if (mood.contains('碧海') || mood.contains('晴空') || mood.contains('豔陽')) {
      return midday;
    }
    return midday;
  }

  /// 逐參數線性插值（對應 JS renderLoop 內的 `oceanCurrent[k] += (target - current) * t`）。
  static OceanShaderPreset lerp(
    OceanShaderPreset a,
    OceanShaderPreset b,
    double t,
  ) {
    final k = t.clamp(0.0, 1.0);
    if (k <= 0.0) return a;
    if (k >= 1.0) return b;
    double mix(double x, double y) => x + (y - x) * k;
    return OceanShaderPreset(
      sunElev: mix(a.sunElev, b.sunElev),
      sunAzimuth: mix(a.sunAzimuth, b.sunAzimuth),
      windSpeed: mix(a.windSpeed, b.windSpeed),
      swellHs: mix(a.swellHs, b.swellHs),
      choppiness: mix(a.choppiness, b.choppiness),
      turbidity: mix(a.turbidity, b.turbidity),
      foam: mix(a.foam, b.foam),
      haze: mix(a.haze, b.haze),
      clouds: mix(a.clouds, b.clouds),
      exposure: mix(a.exposure, b.exposure),
      bloom: mix(a.bloom, b.bloom),
      nightGlow: mix(a.nightGlow, b.nightGlow),
    );
  }
}
