/// 海洋大氣物理與視覺參數（四時天色預設與插值）。
class OceanAtmoState {
  /// 太陽仰角（-0.2 深夜 .. 0.06 黃昏 .. 0.14 晨曦 .. 0.75 正午）。
  final double sunElevation;

  /// 太陽方位（-1.0 西 .. 0.0 正南 .. 1.0 東）。
  final double sunAzimuth;

  /// 晝夜係數（0.0 白天 .. 1.0 黑夜）。
  final double nightFactor;

  /// 夜更「藍眼淚」生物螢光強度（0.0 .. 1.0）。
  final double nightGlow;

  /// 波浪振幅倍率。
  final double waveAmp;

  /// 波浪速度倍率。
  final double waveSpeed;

  /// 大氣狀態簡稱。
  final String mood;

  /// 詳細描述。
  final String desc;

  const OceanAtmoState({
    required this.sunElevation,
    required this.sunAzimuth,
    required this.nightFactor,
    required this.nightGlow,
    required this.waveAmp,
    required this.waveSpeed,
    required this.mood,
    required this.desc,
  });

  /// 晨更（05:00–10:59）：旭日東升、晨曦金光、粉金朝霞。
  static const OceanAtmoState morning = OceanAtmoState(
    sunElevation: 0.18,
    sunAzimuth: 0.70,
    nightFactor: 0.0,
    nightGlow: 0.0,
    waveAmp: 0.90,
    waveSpeed: 1.0,
    mood: '晨曦破曉',
    desc: '旭日東升 • 晨曦金光 • 朝霞翡翠浪湧',
  );

  /// 午班（11:00–16:29 或休假）：豔陽高照、碧海晴空、明朗清亮。
  static const OceanAtmoState midday = OceanAtmoState(
    sunElevation: 0.92,
    sunAzimuth: 0.05,
    nightFactor: 0.0,
    nightGlow: 0.0,
    waveAmp: 0.70,
    waveSpeed: 0.80,
    mood: '碧海晴空',
    desc: '豔陽高照 • 碧海晴空 • 耀眼碎鑽波光',
  );

  /// 中更／黃昏（16:30–21:29）：金暉落日、夕陽晚霞、熔金海面。
  static const OceanAtmoState sunset = OceanAtmoState(
    sunElevation: 0.05,
    sunAzimuth: -0.75,
    nightFactor: 0.0,
    nightGlow: 0.0,
    waveAmp: 1.30,
    waveSpeed: 1.20,
    mood: '金暉落日',
    desc: '夕陽餘暉 • 金暉落日 • 緋紅暮光熔金',
  );

  /// 夜更（21:30–04:59）：深邃暗夜、星月沉靜、璀璨藍眼淚。
  static const OceanAtmoState night = OceanAtmoState(
    sunElevation: -0.32,
    sunAzimuth: 0.35,
    nightFactor: 1.0,
    nightGlow: 1.0,
    waveAmp: 0.85,
    waveSpeed: 0.70,
    mood: '星夜藍眼淚',
    desc: '暗夜深邃 • 星月沉靜 • 璀璨藍眼淚螢光',
  );

  /// 根據班次時間取得海天大氣（僅依時間匹配，不做名稱模糊比對）。
  static OceanAtmoState fromShift(String? shiftName, String? startTime) =>
      fromStartTime(startTime);

  /// 根據班次開始時間（`"HH:mm"`）精確匹配大氣狀態。
  static OceanAtmoState fromStartTime(String? startTime) {
    if (startTime == null || startTime.isEmpty) {
      return midday;
    }
    final parts = startTime.split(':');
    final hour = int.tryParse(parts.firstOrNull ?? '') ?? 12;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return _forTotalMinutes(hour * 60 + minute);
  }

  /// 根據目前真實世界時間取得海天大氣狀態。
  static OceanAtmoState fromCurrentTime([DateTime? time]) {
    final now = time ?? DateTime.now();
    return _forTotalMinutes(now.hour * 60 + now.minute);
  }

  static OceanAtmoState _forTotalMinutes(int totalMinutes) {
    if (totalMinutes >= 300 && totalMinutes < 660) return morning;
    if (totalMinutes >= 660 && totalMinutes < 990) return midday;
    if (totalMinutes >= 990 && totalMinutes < 1290) return sunset;
    return night;
  }

  static OceanAtmoState lerp(OceanAtmoState a, OceanAtmoState b, double t) {
    return OceanAtmoState(
      sunElevation: a.sunElevation + (b.sunElevation - a.sunElevation) * t,
      sunAzimuth: a.sunAzimuth + (b.sunAzimuth - a.sunAzimuth) * t,
      nightFactor: a.nightFactor + (b.nightFactor - a.nightFactor) * t,
      nightGlow: a.nightGlow + (b.nightGlow - a.nightGlow) * t,
      waveAmp: a.waveAmp + (b.waveAmp - a.waveAmp) * t,
      waveSpeed: a.waveSpeed + (b.waveSpeed - a.waveSpeed) * t,
      mood: t < 0.5 ? a.mood : b.mood,
      desc: t < 0.5 ? a.desc : b.desc,
    );
  }
}
