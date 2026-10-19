import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ocean_bridge.dart';

/// 海洋大氣物理與視覺參數（深度參考 shiftalarm_web_ocean 規格）
class OceanAtmoState {
  final double sunElevation; // 太陽仰角 (-0.2 深夜 .. 0.06 黃昏 .. 0.14 晨曦 .. 0.75 正午)
  final double sunAzimuth; // 太陽方位 (-1.0 西 .. 0.0 正南 .. 1.0 東)
  final double nightFactor; // 0.0 (白天) .. 1.0 (黑夜)
  final double nightGlow; // 0.0 (無) .. 1.0 (夜更「藍眼淚」生物螢光)
  final double waveAmp; // 波浪振幅倍率
  final double waveSpeed; // 波浪速度倍率
  final String mood; // 大氣狀態簡稱
  final String desc; // 詳細描述

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

  /// 晨更（05:00–10:59）：旭日東升、晨曦金光、粉金朝霞
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

  /// 午班（11:00–16:59 或休假）：豔陽高照、碧海晴空、明朗清亮（天特別亮！）
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

  /// 中更／黃昏（17:00–19:59）：金暉落日、夕陽晚霞、熔金海面
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

  /// 夜更（20:00–04:59）：深邃暗夜、星月沉靜、璀璨藍眼淚（天特別暗！）
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

  /// 根據班次時間（或真實世界時間）取得海天大氣：
  /// 完全依「時間」匹配，不使用名稱文字模糊比對（避免「凌晨更」、「夜更(18:00)」、「中更(12:00)」等文字衝突誤判）：
  /// - 05:00 ~ 10:59（早班出發 05:00~07:00）：天剛矇矇亮、晨曦露臉 -> 晨曦破曉 (M)
  /// - 11:00 ~ 16:29（午班出發 11:00~14:30）：正午頂頭烈日、晴空萬里 -> 豔陽碧海 (A)
  /// - 16:30 ~ 21:29（晚班出發 16:30~18:30）：夕陽西下、金暉落日暮光 -> 金暉落日 (S)
  /// - 21:30 ~ 04:59（夜班出發 21:30~23:30）：萬籟俱寂、暗夜星空深邃 -> 星夜深邃 (N)
  static OceanAtmoState fromShift(String? shiftName, String? startTime) {
    return fromStartTime(startTime);
  }

  /// 根據班次開始時間（"HH:mm"）精確匹配大氣：
  static OceanAtmoState fromStartTime(String? startTime) {
    if (startTime == null || startTime.isEmpty) {
      return midday;
    }
    final parts = startTime.split(':');
    final hour = int.tryParse(parts.firstOrNull ?? '') ?? 12;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    final totalMinutes = hour * 60 + minute;

    if (totalMinutes >= 300 && totalMinutes < 660) {
      return morning; // 05:00 - 10:59 早更/早班 (例如 06:00)：晨曦破曉
    } else if (totalMinutes >= 660 && totalMinutes < 990) {
      return midday; // 11:00 - 16:29 午更/中更 (例如 12:00)：豔陽碧海
    } else if (totalMinutes >= 990 && totalMinutes < 1290) {
      return sunset; // 16:30 - 21:29 晚更/夜更 (例如 18:00)：金暉落日
    } else {
      return night; // 21:30 - 04:59 凌晨更/夜班 (例如 00:00)：星夜深邃
    }
  }

  /// 根據當前真實世界時間（自然時辰出發體感）取得海天大氣：
  /// - 05:00–10:59（早班出發 05:00~07:00）：天剛矇矇亮、晨曦露臉
  /// - 11:00–16:29（午班出發 11:00~14:30）：正午頂頭烈日、晴空萬里
  /// - 16:30–21:29（晚班出發 16:30~18:30）：夕陽西下、金暉落日暮光
  /// - 21:30–04:59（夜班出發 21:30~23:30）：萬籟俱寂、暗夜星空與藍眼淚
  static OceanAtmoState fromCurrentTime([DateTime? time]) {
    final now = time ?? DateTime.now();
    final totalMinutes = now.hour * 60 + now.minute;
    if (totalMinutes >= 300 && totalMinutes < 660) {
      return morning; // 05:00 - 10:59: 晨曦破曉
    } else if (totalMinutes >= 660 && totalMinutes < 990) {
      return midday; // 11:00 - 16:29: 豔陽碧海
    } else if (totalMinutes >= 990 && totalMinutes < 1290) {
      return sunset; // 16:30 - 21:29: 金暉落日
    } else {
      return night; // 21:30 - 04:59: 星夜深邃
    }
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

/// 海天連動動態背景 Widget（CustomPainter 渲染）
class OceanAtmosphereWidget extends StatefulWidget {
  final OceanAtmoState targetState;
  final Widget? child;

  const OceanAtmosphereWidget({
    super.key,
    required this.targetState,
    this.child,
  });

  @override
  State<OceanAtmosphereWidget> createState() => OceanAtmosphereWidgetState();
}

class OceanAtmosphereWidgetState extends State<OceanAtmosphereWidget>
    with TickerProviderStateMixin {
  /// 持續波浪流動控制器（循環 8000ms）
  late final AnimationController _waveCycleCtrl;

  /// 大氣狀態過渡控制器（平滑插值 750ms）
  late final AnimationController _transitionCtrl;
  late OceanAtmoState _prevState;
  late OceanAtmoState _currentState;

  /// 導入排更時的巨浪增強控制器（2000ms）
  late final AnimationController _surgeCtrl;

  void _syncWebAtmosphere(OceanAtmoState state) {
    if (!kIsWeb) return;
    if (state.mood.contains('晨曦')) {
      code = 'M';
    } else if (state.mood.contains('碧海') || state.mood.contains('晴空') || state.mood.contains('豔陽')) {
      code = 'A'; // 午班：豔陽高照，天足夠亮！
    } else if (state.mood.contains('金暉') || state.mood.contains('落日') || state.mood.contains('黃昏')) {
      code = 'S'; // 黃昏落日
    } else if (state.mood.contains('星夜') || state.mood.contains('暗夜')) {
      code = 'N'; // 夜班：深邃暗夜，天足夠暗！
    }
    jsSetOceanAtmosphere(
      code,
      state.sunElevation * 60.0,
      state.sunAzimuth * 180.0,
      state.nightGlow,
    );
  }

  @override
  void initState() {
    super.initState();
    _prevState = widget.targetState;
    _currentState = widget.targetState;

    _waveCycleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();

    _transitionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );

    _surgeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _syncWebAtmosphere(widget.targetState);
  }

  @override
  void didUpdateWidget(covariant OceanAtmosphereWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetState.mood != widget.targetState.mood ||
        (oldWidget.targetState.sunElevation - widget.targetState.sunElevation)
                .abs() >
            0.01) {
      _prevState = _currentInterpolatedState;
      _currentState = widget.targetState;
      _transitionCtrl.forward(from: 0.0);
      _syncWebAtmosphere(widget.targetState);
    }
  }

  OceanAtmoState get _currentInterpolatedState {
    if (!_transitionCtrl.isAnimating && _transitionCtrl.isCompleted) {
      return _currentState;
    }
    final t = Curves.easeInOutCubic.transform(_transitionCtrl.value);
    return OceanAtmoState.lerp(_prevState, _currentState, t);
  }

  /// 觸發導入排更時的海面波浪激盪效果
  void triggerSurge() {
    _surgeCtrl.forward(from: 0.0);
    if (kIsWeb) {
      jsTriggerOceanSurge();
    }
  }

  @override
  void dispose() {
    _waveCycleCtrl.dispose();
    _transitionCtrl.dispose();
    _surgeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // 在 Web 瀏覽器端：底層由原版 WebGL 著色器硬體滿幀渲染真 3D 物理海洋！
      return SizedBox.expand(
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_waveCycleCtrl, _transitionCtrl, _surgeCtrl]),
      builder: (context, child) {
        final state = _currentInterpolatedState;
        final surgeProgress = _surgeCtrl.value;
        // 激盪脈衝倍率：拋物線 0 -> 1 -> 0
        final surgeMultiplier = math.sin(surgeProgress * math.pi) * 1.6;

        return CustomPaint(
          painter: _OceanPainter(
            time: _waveCycleCtrl.value * 2 * math.pi,
            atmo: state,
            surgeMultiplier: surgeMultiplier,
            surgeProgress: surgeProgress,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _OceanPainter extends CustomPainter {
  final double time;
  final OceanAtmoState atmo;
  final double surgeMultiplier;
  final double surgeProgress;

  _OceanPainter({
    required this.time,
    required this.atmo,
    required this.surgeMultiplier,
    required this.surgeProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // 海平線位置（隨海浪微幅呼吸）
    final horizonY = h * 0.40 + math.sin(time * 0.8) * 3.0;

    _paintSky(canvas, Size(w, horizonY));
    _paintSunOrMoon(canvas, Size(w, horizonY));
    _paintWater(canvas, Size(w, h), horizonY);
    _paintLightModeOverlay(canvas, Size(w, h));
  }

  /// 繪製天空漸變與大氣光暈
  void _paintSky(Canvas canvas, Size skySize) {
    final w = skySize.width;
    final h = skySize.height;

    final night = atmo.nightFactor.clamp(0.0, 1.0);
    final elev = atmo.sunElevation;

    final Color zenithCol;
    final Color horizonCol;

    if (night > 0.5) {
      // 深邃星夜天空（夜更：天特別暗）
      zenithCol = const Color(0xFF020409);
      horizonCol = const Color(0xFF080F1E);
    } else if (elev < 0.20) {
      // 晨曦／金暉落日橘紅與霞光
      final isMorning = atmo.sunAzimuth > 0;
      if (isMorning) {
        zenithCol = const Color(0xFF2563EB);
        horizonCol = const Color(0xFFFDBA74);
      } else {
        zenithCol = const Color(0xFF4C1D95);
        horizonCol = const Color(0xFFFB923C);
      }
    } else {
      // 碧海晴空天藍（午更：天特別亮）
      zenithCol = const Color(0xFF0284C7);
      horizonCol = const Color(0xFFBAE6FD);
    }

    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [zenithCol, horizonCol],
      ).createShader(Rect.fromLTWH(0, 0, w, h + 8));

    canvas.drawRect(Rect.fromLTWH(0, 0, w, h + 8), skyPaint);
  }

  /// 繪製太陽或月亮、光暈與星光
  void _paintSunOrMoon(Canvas canvas, Size skySize) {
    final w = skySize.width;
    final h = skySize.height;
    final night = atmo.nightFactor;
    final elev = atmo.sunElevation;

    // 太陽仰角對應螢幕 Y
    final sunScreenY = h - (elev + 0.12) * (h * 0.70);
    final sunScreenX = w * (0.5 + atmo.sunAzimuth * 0.35);

    if (night < 0.5) {
      final sunRadius = 18.0 + (1.0 - elev.clamp(0.0, 1.0)) * 6.0;
      final glowRadius = sunRadius * 4.6;

      final isSunsetOrSunrise = elev < 0.20;
      final Color glowColor = isSunsetOrSunrise
          ? const Color(0xFFF97316).withValues(alpha: 0.42)
          : const Color(0xFFFDE047).withValues(alpha: 0.32);
      final Color sunColor = isSunsetOrSunrise
          ? const Color(0xFFEA580C)
          : const Color(0xFFFEF08A);

      // 外光暈（Mie 散射大氣輝光）
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [glowColor, glowColor.withValues(alpha: 0.0)],
        ).createShader(
            Rect.fromCircle(center: Offset(sunScreenX, sunScreenY), radius: glowRadius));
      canvas.drawCircle(Offset(sunScreenX, sunScreenY), glowRadius, glowPaint);

      // 太陽本體
      final sunPaint = Paint()..color = sunColor;
      canvas.drawCircle(Offset(sunScreenX, sunScreenY), sunRadius, sunPaint);
    } else {
      // 月亮與靜夜繁星
      final moonCenter = Offset(w * 0.72, h * 0.26);
      const moonRadius = 14.0;

      // 月暈
      final moonGlowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFE0E7FF).withValues(alpha: 0.30),
            const Color(0xFFE0E7FF).withValues(alpha: 0.0),
          ],
        ).createShader(
            Rect.fromCircle(center: moonCenter, radius: moonRadius * 3.8));
      canvas.drawCircle(moonCenter, moonRadius * 3.8, moonGlowPaint);

      // 彎月本體
      final moonPaint = Paint()..color = const Color(0xFFEEF2FF);
      canvas.drawCircle(moonCenter, moonRadius, moonPaint);

      // 靜夜繁星（隨波光閃爍）
      final starPaint = Paint()..color = Colors.white;
      for (int i = 0; i < 32; i++) {
        final sx = ((i * 79 + 23) % w.toInt()).toDouble();
        final sy = ((i * 53 + 17) % (h * 0.88).toInt()).toDouble();
        final twinkle = 0.35 + 0.65 * math.sin(time * 2.2 + i * 1.3).abs();
        starPaint.color = Colors.white.withValues(alpha: 0.80 * twinkle);
        canvas.drawCircle(Offset(sx, sy), (i % 4 == 0 ? 1.4 : 0.85), starPaint);
      }
    }
  }

  /// 繪製海面、太陽光柱粼粼倒影、白浪泡沫與星夜藍眼淚
  void _paintWater(Canvas canvas, Size fullSize, double horizonY) {
    final w = fullSize.width;
    final h = fullSize.height;
    final waterH = h - horizonY;
    final night = atmo.nightFactor;
    final elev = atmo.sunElevation;

    // 海水基底漸變
    final Color waterTopColor;
    final Color waterBottomColor;

    if (night > 0.5) {
      waterTopColor = const Color(0xFF040914);
      waterBottomColor = const Color(0xFF010308);
    } else if (elev < 0.20) {
      waterTopColor = const Color(0xFF0284C7);
      waterBottomColor = const Color(0xFF082F49);
    } else {
      waterTopColor = const Color(0xFF0284C7);
      waterBottomColor = const Color(0xFF0C4A6E);
    }

    final waterBgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [waterTopColor, waterBottomColor],
      ).createShader(Rect.fromLTWH(0, horizonY, w, waterH));

    canvas.drawRect(Rect.fromLTWH(0, horizonY, w, waterH), waterBgPaint);

    // ── 1. 太陽／月亮海面長條粼粼光柱倒影（Specular Glitter Path）──
    final sunScreenX = night < 0.5
        ? w * (0.5 + atmo.sunAzimuth * 0.35)
        : w * 0.72;
    final Color glitterColor = night > 0.5
        ? const Color(0xFFE0E7FF)
        : (elev < 0.20 ? const Color(0xFFFDE047) : const Color(0xFFFFFFFF));

    final topGlitterW = w * 0.08;
    final btmGlitterW = w * 0.36;

    for (double y = horizonY + 2; y < h; y += 4.5) {
      final prog = (y - horizonY) / waterH;
      final curW = topGlitterW + (btmGlitterW - topGlitterW) * prog;
      final shimmer = math.sin(y * 0.24 - time * 3.8) * 0.5 + 0.5;
      if (shimmer > 0.22) {
        final lineAlpha = ((0.12 + 0.45 * shimmer) * (1.0 - prog * 0.35))
            .clamp(0.0, 1.0);
        final linePaint = Paint()
          ..color = glitterColor.withValues(alpha: lineAlpha)
          ..strokeWidth = 2.0;
        canvas.drawLine(
          Offset(sunScreenX - curW * 0.5 * shimmer, y),
          Offset(sunScreenX + curW * 0.5 * shimmer, y),
          linePaint,
        );
      }
    }

    // ── 2. 多層次 Gerstner 幾何波浪與白浪泡沫／藍眼淚 ──
    final baseAmp = (atmo.waveAmp + surgeMultiplier) * 9.0;

    final waves = [
      _WaveSpec(freq: 0.012, amp: baseAmp * 1.0, speed: 1.0, yRatio: 0.02, alpha: 0.32),
      _WaveSpec(freq: 0.018, amp: baseAmp * 0.82, speed: 1.35, yRatio: 0.18, alpha: 0.26),
      _WaveSpec(freq: 0.025, amp: baseAmp * 0.60, speed: 1.8, yRatio: 0.38, alpha: 0.22),
      _WaveSpec(freq: 0.036, amp: baseAmp * 0.38, speed: 2.4, yRatio: 0.65, alpha: 0.18),
    ];

    for (final wave in waves) {
      final wavePath = Path();
      final foamPath = Path();
      final baseY = horizonY + waterH * wave.yRatio;
      wavePath.moveTo(0, baseY);

      bool foamStarted = false;

      for (double x = 0; x <= w; x += 3.5) {
        // Gerstner 尖峰修正（Crest Sharpening）
        final ph = x * wave.freq + time * wave.speed;
        final waveVal = math.sin(ph) * wave.amp +
            math.sin(ph * 2.0 + 1.2) * (wave.amp * 0.30);
        final curY = baseY + waveVal;
        wavePath.lineTo(x, curY);

        // 波峰處繪製白浪泡沫或夜更藍眼淚螢光
        if (waveVal < -wave.amp * 0.35) {
          if (!foamStarted) {
            foamPath.moveTo(x, curY);
            foamStarted = true;
          } else {
            foamPath.lineTo(x, curY);
          }
        } else {
          foamStarted = false;
        }
      }

      wavePath.lineTo(w, h);
      wavePath.lineTo(0, h);
      wavePath.close();

      // 波浪本體著色
      final waveColor = night > 0.5
          ? const Color(0xFF1E3A8A).withValues(alpha: wave.alpha * 0.75)
          : (elev < 0.20
              ? const Color(0xFF0369A1).withValues(alpha: wave.alpha)
              : const Color(0xFF38BDF8).withValues(alpha: wave.alpha));

      final wavePaint = Paint()..color = waveColor;
      canvas.drawPath(wavePath, wavePaint);

      // 浪尖白浪泡沫或「星夜藍眼淚」螢光
      final Color foamColor = (night > 0.5 && atmo.nightGlow > 0.1)
          ? const Color(0xFF00F0FF).withValues(alpha: 0.75) // 藍眼淚璀璨青藍
          : Colors.white.withValues(alpha: 0.45);

      final foamPaint = Paint()
        ..color = foamColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = (night > 0.5 && atmo.nightGlow > 0.1) ? 2.6 : 1.8
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(foamPath, foamPaint);
    }

    // ── 3. 導入排更時擴散的衝擊波光浪（Shockwave Ring Crest）──
    if (surgeProgress > 0.01 && surgeProgress < 0.99) {
      final ringY = horizonY + waterH * (1.0 - surgeProgress);
      final ringPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            const Color(0xFF38BDF8).withValues(alpha: 0.75 * surgeMultiplier),
            const Color(0xFFFDE047).withValues(alpha: 0.90 * surgeMultiplier),
            Colors.transparent,
          ],
          stops: const [0.0, 0.40, 0.60, 1.0],
        ).createShader(Rect.fromLTWH(0, ringY - 8, w, 16))
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke;

      final ringPath = Path();
      ringPath.moveTo(0, ringY);
      for (double x = 0; x <= w; x += 6.0) {
        final dy = math.sin(x * 0.04 + time * 6.0) * 4.0;
        ringPath.lineTo(x, ringY + dy);
      }
      canvas.drawPath(ringPath, ringPaint);
    }
  }

  /// 繪製微柔和透光層（確保文字高對比度的同時讓海面、波浪與太陽清晰通透）
  void _paintLightModeOverlay(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final overlayPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.06),
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.18),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), overlayPaint);
  }

  @override
  bool shouldRepaint(covariant _OceanPainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.atmo != atmo ||
        oldDelegate.surgeMultiplier != surgeMultiplier ||
        oldDelegate.surgeProgress != surgeProgress;
  }
}

class _WaveSpec {
  final double freq;
  final double amp;
  final double speed;
  final double yRatio;
  final double alpha;

  const _WaveSpec({
    required this.freq,
    required this.amp,
    required this.speed,
    required this.yRatio,
    required this.alpha,
  });
}
