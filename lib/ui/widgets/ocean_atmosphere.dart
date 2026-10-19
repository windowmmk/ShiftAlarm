import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 海洋大氣參數
class OceanAtmoState {
  final double sunElevation; // -0.2 (深夜) .. 0.1 (日出/日落) .. 0.9 (正午)
  final double sunAzimuth; // -1.0 (西) .. 0.0 (正南) .. 1.0 (東)
  final double nightFactor; // 0.0 (白天) .. 1.0 (黑夜)
  final double waveAmp; // 波浪振幅倍率
  final double waveSpeed; // 波浪速度倍率
  final String mood; // 大氣狀態簡稱
  final String desc; // 詳細描述

  const OceanAtmoState({
    required this.sunElevation,
    required this.sunAzimuth,
    required this.nightFactor,
    required this.waveAmp,
    required this.waveSpeed,
    required this.mood,
    required this.desc,
  });

  /// 晨更（05:00–10:59）：旭日東升、金輝破曉
  static const OceanAtmoState morning = OceanAtmoState(
    sunElevation: 0.12,
    sunAzimuth: 0.85,
    nightFactor: 0.0,
    waveAmp: 0.9,
    waveSpeed: 1.0,
    mood: '晨曦',
    desc: '太陽仰角 8° • 旭日東升',
  );

  /// 正午／休假（11:00–14:59 或休假）：碧海晴空、豔陽高照
  static const OceanAtmoState midday = OceanAtmoState(
    sunElevation: 0.88,
    sunAzimuth: 0.10,
    nightFactor: 0.0,
    waveAmp: 0.7,
    waveSpeed: 0.85,
    mood: '碧海',
    desc: '太陽仰角 55° • 碧海晴空',
  );

  /// 中更／黃昏（15:00–20:59）：金暉落日、暖橘晚霞
  static const OceanAtmoState sunset = OceanAtmoState(
    sunElevation: 0.08,
    sunAzimuth: -0.65,
    nightFactor: 0.0,
    waveAmp: 1.2,
    waveSpeed: 1.15,
    mood: '黃昏',
    desc: '太陽仰角 5° • 金暉落日',
  );

  /// 夜更（21:00–04:59）：星夜月色、深邃靜海
  static const OceanAtmoState night = OceanAtmoState(
    sunElevation: -0.16,
    sunAzimuth: 0.40,
    nightFactor: 1.0,
    waveAmp: 0.6,
    waveSpeed: 0.7,
    mood: '星夜',
    desc: '暮光仰角 -9° • 月色靜海',
  );

  /// 根據班次開始時間（"HH:mm"）判斷對應大氣
  static OceanAtmoState fromStartTime(String? startTime) {
    if (startTime == null || startTime.isEmpty) {
      return midday;
    }
    final hour = int.tryParse(startTime.split(':').firstOrNull ?? '') ?? 12;
    if (hour >= 5 && hour < 11) {
      return morning;
    } else if (hour >= 11 && hour < 15) {
      return midday;
    } else if (hour >= 15 && hour < 21) {
      return sunset;
    } else {
      return night;
    }
  }

  static OceanAtmoState lerp(OceanAtmoState a, OceanAtmoState b, double t) {
    return OceanAtmoState(
      sunElevation: a.sunElevation + (b.sunElevation - a.sunElevation) * t,
      sunAzimuth: a.sunAzimuth + (b.sunAzimuth - a.sunAzimuth) * t,
      nightFactor: a.nightFactor + (b.nightFactor - a.nightFactor) * t,
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

  /// 大氣狀態過渡控制器（平滑插值 700ms）
  late final AnimationController _transitionCtrl;
  late OceanAtmoState _prevState;
  late OceanAtmoState _currentState;

  /// 導入排更時的巨浪增強控制器（1800ms）
  late final AnimationController _surgeCtrl;

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
      duration: const Duration(milliseconds: 700),
    );

    _surgeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
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
    return AnimatedBuilder(
      animation: Listenable.merge([_waveCycleCtrl, _transitionCtrl, _surgeCtrl]),
      builder: (context, child) {
        final state = _currentInterpolatedState;
        final surgeProgress = _surgeCtrl.value;
        // 激盪脈衝倍率：拋物線曲線 0 -> 1 -> 0
        final surgeMultiplier = math.sin(surgeProgress * math.pi) * 1.4;

        return CustomPaint(
          painter: _OceanPainter(
            time: _waveCycleCtrl.value * 2 * math.pi,
            atmo: state,
            surgeMultiplier: surgeMultiplier,
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

  _OceanPainter({
    required this.time,
    required this.atmo,
    required this.surgeMultiplier,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // 海平線位置（約螢幕 42% 高度處）
    final horizonY = h * 0.42;

    _paintSky(canvas, Size(w, horizonY));
    _paintSunOrMoon(canvas, Size(w, horizonY));
    _paintWater(canvas, Size(w, h), horizonY);
    _paintLightModeOverlay(canvas, Size(w, h));
  }

  /// 繪製天空漸變（根據太陽仰角與晝夜模式）
  void _paintSky(Canvas canvas, Size skySize) {
    final w = skySize.width;
    final h = skySize.height;

    final night = atmo.nightFactor.clamp(0.0, 1.0);
    final elev = atmo.sunElevation;

    final Color topColor;
    final Color bottomColor;

    if (night > 0.5) {
      // 深邃星夜天空
      topColor = const Color(0xFF0D172A);
      bottomColor = const Color(0xFF1E293B);
    } else if (elev < 0.20) {
      // 晨曦／黃昏橘紅漸變
      final isMorning = atmo.sunAzimuth > 0;
      if (isMorning) {
        topColor = Color.lerp(
          const Color(0xFF60A5FA),
          const Color(0xFFFDE68A),
          0.35,
        )!;
        bottomColor = const Color(0xFFFDBA74);
      } else {
        topColor = const Color(0xFF818CF8);
        bottomColor = const Color(0xFFFB7185);
      }
    } else {
      // 碧海晴空日間天藍色
      topColor = const Color(0xFF93C5FD);
      bottomColor = const Color(0xFFE0F2FE);
    }

    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [topColor, bottomColor],
      ).createShader(Rect.fromLTWH(0, 0, w, h + 10));

    canvas.drawRect(Rect.fromLTWH(0, 0, w, h + 10), skyPaint);
  }

  /// 繪製太陽或月亮與光暈
  void _paintSunOrMoon(Canvas canvas, Size skySize) {
    final w = skySize.width;
    final h = skySize.height;
    final night = atmo.nightFactor;
    final elev = atmo.sunElevation;

    // 太陽仰角對應螢幕 Y：elev 越高，位置越偏上
    final sunScreenY = h - (elev + 0.15) * (h * 0.70);
    final sunScreenX = w * (0.5 + atmo.sunAzimuth * 0.35);

    if (night < 0.5) {
      // 太陽與光暈
      final sunRadius = (16.0 + (1.0 - elev.clamp(0.0, 1.0)) * 6.0);
      final glowRadius = sunRadius * 4.2;

      final isSunsetOrSunrise = elev < 0.20;
      final Color glowColor = isSunsetOrSunrise
          ? const Color(0xFFF97316).withValues(alpha: 0.35)
          : const Color(0xFFFDE047).withValues(alpha: 0.28);
      final Color sunColor = isSunsetOrSunrise
          ? const Color(0xFFEA580C)
          : const Color(0xFFFEF08A);

      // 外光暈
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
      // 月亮與靜夜星光
      const moonX = 0.72;
      final moonCenter = Offset(w * moonX, h * 0.28);
      const moonRadius = 14.0;

      // 月暈
      final moonGlowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFE0E7FF).withValues(alpha: 0.25),
            const Color(0xFFE0E7FF).withValues(alpha: 0.0),
          ],
        ).createShader(
            Rect.fromCircle(center: moonCenter, radius: moonRadius * 3.5));
      canvas.drawCircle(moonCenter, moonRadius * 3.5, moonGlowPaint);

      // 彎月本體
      final moonPaint = Paint()..color = const Color(0xFFEEF2FF);
      canvas.drawCircle(moonCenter, moonRadius, moonPaint);

      // 靜夜繁星
      final starPaint = Paint()..color = Colors.white;
      for (int i = 0; i < 28; i++) {
        final sx = ((i * 79 + 23) % w.toInt()).toDouble();
        final sy = ((i * 53 + 17) % (h * 0.85).toInt()).toDouble();
        final twinkle =
            0.35 + 0.65 * math.sin(time * 2.0 + i * 1.3).abs();
        starPaint.color = Colors.white.withValues(alpha: 0.75 * twinkle);
        canvas.drawCircle(Offset(sx, sy), (i % 3 == 0 ? 1.2 : 0.8), starPaint);
      }
    }
  }

  /// 繪製多層次動態海浪
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
      waterTopColor = const Color(0xFF1E293B);
      waterBottomColor = const Color(0xFF0F172A);
    } else if (elev < 0.20) {
      waterTopColor = const Color(0xFF0284C7);
      waterBottomColor = const Color(0xFF0369A1);
    } else {
      waterTopColor = const Color(0xFF38BDF8);
      waterBottomColor = const Color(0xFF0284C7);
    }

    final waterBgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [waterTopColor, waterBottomColor],
      ).createShader(Rect.fromLTWH(0, horizonY, w, waterH));

    canvas.drawRect(Rect.fromLTWH(0, horizonY, w, waterH), waterBgPaint);

    // 4 層波浪（近大遠小、波速疊加、含激盪脈衝）
    final baseAmp = (atmo.waveAmp + surgeMultiplier) * 8.0;

    final waves = [
      _WaveSpec(freq: 0.012, amp: baseAmp * 1.0, speed: 1.0, yRatio: 0.0, alpha: 0.35),
      _WaveSpec(freq: 0.018, amp: baseAmp * 0.8, speed: 1.4, yRatio: 0.18, alpha: 0.28),
      _WaveSpec(freq: 0.026, amp: baseAmp * 0.55, speed: 1.9, yRatio: 0.38, alpha: 0.22),
      _WaveSpec(freq: 0.038, amp: baseAmp * 0.35, speed: 2.5, yRatio: 0.62, alpha: 0.18),
    ];

    for (final wave in waves) {
      final wavePath = Path();
      final baseY = horizonY + waterH * wave.yRatio;
      wavePath.moveTo(0, baseY);

      for (double x = 0; x <= w; x += 4.0) {
        final waveVal = math.sin(x * wave.freq + time * wave.speed) * wave.amp +
            math.sin(x * wave.freq * 1.8 + time * wave.speed * 0.6 + 1.2) *
                (wave.amp * 0.45);
        wavePath.lineTo(x, baseY + waveVal);
      }

      wavePath.lineTo(w, h);
      wavePath.lineTo(0, h);
      wavePath.close();

      final waveColor = night > 0.5
          ? const Color(0xFF38BDF8).withValues(alpha: wave.alpha * 0.65)
          : Colors.white.withValues(alpha: wave.alpha);

      final wavePaint = Paint()..color = waveColor;
      canvas.drawPath(wavePath, wavePaint);
    }
  }

  /// 繪製微柔和透光層，在確保文字高對比度的同時讓海面、波浪與太陽清晰通透
  void _paintLightModeOverlay(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final overlayPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.04),
          Colors.white.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0.16),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), overlayPaint);
  }

  @override
  bool shouldRepaint(covariant _OceanPainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.atmo != atmo ||
        oldDelegate.surgeMultiplier != surgeMultiplier;
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
