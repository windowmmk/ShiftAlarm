import 'dart:math' as math;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'ocean_atmo_state.dart';

/// 海洋大氣 2D CustomPainter（當 FragmentShader 不可用時的降級渲染器）。
class OceanFallbackPainter extends CustomPainter {
  final double time;
  final OceanAtmoState atmo;
  final double surgeMultiplier;
  final double surgeProgress;

  /// `true` = 96px 海平線帶模式（採用 [_Compact96] 幾何常數）。
  final bool compact96;

  const OceanFallbackPainter({
    required this.time,
    required this.atmo,
    required this.surgeMultiplier,
    required this.surgeProgress,
    this.compact96 = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    if (compact96) {
      _paintCompact(canvas, size);
      return;
    }

    final horizonY = h * 0.40 + math.sin(time * 0.8) * 3.0;
    _paintSky(canvas, Size(w, horizonY));
    _paintSunOrMoon(canvas, Size(w, horizonY));
    _paintWater(canvas, Size(w, h), horizonY);
    _paintLightModeOverlay(canvas, Size(w, h));
  }

  void _paintSky(Canvas canvas, Size skySize) {
    final w = skySize.width;
    final h = skySize.height;
    final night = atmo.nightFactor.clamp(0.0, 1.0);
    final elev = atmo.sunElevation;

    final Color zenithCol;
    final Color horizonCol;
    if (night > 0.5) {
      zenithCol = const Color(0xFF243452);
      horizonCol = const Color(0xFF425B80);
    } else if (elev < 0.20) {
      if (atmo.sunAzimuth > 0) {
        zenithCol = const Color(0xFF2563EB);
        horizonCol = const Color(0xFFFDBA74);
      } else {
        zenithCol = const Color(0xFF4C1D95);
        horizonCol = const Color(0xFFFB923C);
      }
    } else {
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

  void _paintSunOrMoon(Canvas canvas, Size skySize) {
    final w = skySize.width;
    final h = skySize.height;
    final night = atmo.nightFactor;
    final elev = atmo.sunElevation;
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

      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [glowColor, glowColor.withValues(alpha: 0.0)],
        ).createShader(
          Rect.fromCircle(
            center: Offset(sunScreenX, sunScreenY),
            radius: glowRadius,
          ),
        );
      canvas.drawCircle(Offset(sunScreenX, sunScreenY), glowRadius, glowPaint);
      canvas.drawCircle(
        Offset(sunScreenX, sunScreenY),
        sunRadius,
        Paint()..color = sunColor,
      );
      return;
    }

    final moonCenter = Offset(w * 0.72, h * 0.26);
    const moonRadius = 14.0;
    final moonGlowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFE0E7FF).withValues(alpha: 0.30),
          const Color(0xFFE0E7FF).withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(center: moonCenter, radius: moonRadius * 3.8),
      );
    canvas.drawCircle(moonCenter, moonRadius * 3.8, moonGlowPaint);
    canvas.drawCircle(
      moonCenter,
      moonRadius,
      Paint()..color = const Color(0xFFEEF2FF),
    );

    final starPaint = Paint()..color = Colors.white;
    final starW = math.max(1, w.toInt());
    final starH = math.max(1, (h * 0.88).toInt());
    for (int i = 0; i < 32; i++) {
      final sx = ((i * 79 + 23) % starW).toDouble();
      final sy = ((i * 53 + 17) % starH).toDouble();
      final twinkle = 0.35 + 0.65 * math.sin(time * 2.2 + i * 1.3).abs();
      starPaint.color = Colors.white.withValues(alpha: 0.80 * twinkle);
      canvas.drawCircle(Offset(sx, sy), i % 4 == 0 ? 1.4 : 0.85, starPaint);
    }
  }

  (Color, Color) _waterGradientColors() {
    if (atmo.nightFactor > 0.5) {
      return (const Color(0xFF1E4468), const Color(0xFF15304D));
    }
    if (atmo.sunElevation < 0.20) {
      return (const Color(0xFF0284C7), const Color(0xFF082F49));
    }
    return (const Color(0xFF0284C7), const Color(0xFF0C4A6E));
  }

  void _paintWater(Canvas canvas, Size fullSize, double horizonY) {
    final w = fullSize.width;
    final h = fullSize.height;
    final waterH = h - horizonY;
    if (waterH <= 0) return;

    final night = atmo.nightFactor;
    final (waterTopColor, waterBottomColor) = _waterGradientColors();

    canvas.drawRect(
      Rect.fromLTWH(0, horizonY, w, waterH),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [waterTopColor, waterBottomColor],
        ).createShader(Rect.fromLTWH(0, horizonY, w, waterH)),
    );

    final sunScreenX =
        night < 0.5 ? w * (0.5 + atmo.sunAzimuth * 0.35) : w * 0.72;
    _paintGlitterPath(
      canvas,
      w: w,
      h: h,
      horizonY: horizonY,
      waterH: waterH,
      centerX: sunScreenX,
      stepY: 4.5,
      offsetY: 2.0,
      strokeWidth: 2.0,
    );

    final baseAmp = (atmo.waveAmp + surgeMultiplier) * 9.0;
    final waves = [
      _WaveSpec(
          freq: 0.012, amp: baseAmp * 1.0, speed: 1.0, yRatio: 0.02, alpha: 0.32),
      _WaveSpec(
          freq: 0.018, amp: baseAmp * 0.82, speed: 1.35, yRatio: 0.18, alpha: 0.26),
      _WaveSpec(
          freq: 0.025, amp: baseAmp * 0.60, speed: 1.8, yRatio: 0.38, alpha: 0.22),
      _WaveSpec(
          freq: 0.036, amp: baseAmp * 0.38, speed: 2.4, yRatio: 0.65, alpha: 0.18),
    ];

    for (final wave in waves) {
      _paintWaveLayer(
        canvas,
        w: w,
        h: h,
        baseY: horizonY + waterH * wave.yRatio,
        freq: wave.freq,
        amp: wave.amp,
        speed: wave.speed,
        alpha: wave.alpha,
        stepX: 3.5,
        foamStroke: (night > 0.5 && atmo.nightGlow > 0.1) ? 2.6 : 1.8,
      );
    }

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

      final ringPath = Path()..moveTo(0, ringY);
      for (double x = 0; x <= w; x += 6.0) {
        ringPath.lineTo(x, ringY + math.sin(x * 0.04 + time * 6.0) * 4.0);
      }
      canvas.drawPath(ringPath, ringPaint);
    }
  }

  void _paintGlitterPath(
    Canvas canvas, {
    required double w,
    required double h,
    required double horizonY,
    required double waterH,
    required double centerX,
    required double stepY,
    required double offsetY,
    required double strokeWidth,
  }) {
    final night = atmo.nightFactor;
    final elev = atmo.sunElevation;
    final Color glitterColor = night > 0.5
        ? const Color(0xFFE0E7FF)
        : (elev < 0.20 ? const Color(0xFFFDE047) : Colors.white);
    final topGlitterW = w * 0.08;
    final btmGlitterW = w * 0.36;

    for (double y = horizonY + offsetY; y < h; y += stepY) {
      final prog = (y - horizonY) / waterH;
      final curW = topGlitterW + (btmGlitterW - topGlitterW) * prog;
      final shimmer = math.sin(y * 0.24 - time * 3.8) * 0.5 + 0.5;
      if (shimmer > 0.22) {
        final lineAlpha =
            ((0.12 + 0.45 * shimmer) * (1.0 - prog * 0.35)).clamp(0.0, 1.0);
        canvas.drawLine(
          Offset(centerX - curW * 0.5 * shimmer, y),
          Offset(centerX + curW * 0.5 * shimmer, y),
          Paint()
            ..color = glitterColor.withValues(alpha: lineAlpha)
            ..strokeWidth = strokeWidth,
        );
      }
    }
  }

  void _paintWaveLayer(
    Canvas canvas, {
    required double w,
    required double h,
    required double baseY,
    required double freq,
    required double amp,
    required double speed,
    required double alpha,
    required double stepX,
    required double foamStroke,
  }) {
    final night = atmo.nightFactor;
    final elev = atmo.sunElevation;
    final wavePath = Path()..moveTo(0, baseY);
    final foamPath = Path();
    bool foamStarted = false;

    for (double x = 0; x <= w; x += stepX) {
      final ph = x * freq + time * speed;
      final waveVal =
          math.sin(ph) * amp + math.sin(ph * 2.0 + 1.2) * (amp * 0.30);
      final curY = baseY + waveVal;
      wavePath.lineTo(x, curY);

      if (waveVal < -amp * 0.35) {
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

    wavePath
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final waveColor = night > 0.5
        ? const Color(0xFF2B5B84).withValues(alpha: alpha * 0.70)
        : (elev < 0.20
            ? const Color(0xFF0369A1).withValues(alpha: alpha)
            : const Color(0xFF38BDF8).withValues(alpha: alpha));
    canvas.drawPath(wavePath, Paint()..color = waveColor);

    final bool bioluminescent = night > 0.5 && atmo.nightGlow > 0.1;
    final Color foamColor =
        (bioluminescent ? const Color(0xFF38BDF8) : Colors.white)
            .withValues(alpha: bioluminescent ? 0.62 : 0.45);
    canvas.drawPath(
      foamPath,
      Paint()
        ..color = foamColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = foamStroke
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintLightModeOverlay(
    Canvas canvas,
    Size size, {
    double alphaScale = 1.0,
  }) {
    final overlayPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.06 * alphaScale),
          Colors.white.withValues(alpha: 0.10 * alphaScale),
          Colors.white.withValues(alpha: 0.18 * alphaScale),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), overlayPaint);
  }

  void _paintCompact(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizonY = h * _Compact96.horizonRatio;

    _paintSky(canvas, Size(w, horizonY));
    _paintCompactSunOrMoon(canvas, w, horizonY);
    _paintCompactWater(canvas, w, h, horizonY);
    _paintLightModeOverlay(
      canvas,
      Size(w, h),
      alphaScale: _Compact96.overlayAlpha,
    );
  }

  void _paintCompactSunOrMoon(Canvas canvas, double w, double horizonY) {
    final night = atmo.nightFactor;
    final elev = atmo.sunElevation;
    final cx = w * (0.5 + atmo.sunAzimuth * 0.30);
    final cy = horizonY * (night > 0.5 ? 0.42 : 0.58);
    const radius = _Compact96.sunRadius;
    const glowRadius = radius * _Compact96.glowScale;

    if (night < 0.5) {
      final isSunsetOrSunrise = elev < 0.20;
      final Color glowColor = (isSunsetOrSunrise
              ? const Color(0xFFF97316)
              : const Color(0xFFFDE047))
          .withValues(alpha: 0.42);
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [glowColor, glowColor.withValues(alpha: 0.0)],
        ).createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: glowRadius),
        );
      canvas.drawCircle(Offset(cx, cy), glowRadius, glowPaint);
      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()
          ..color = isSunsetOrSunrise
              ? const Color(0xFFEA580C)
              : const Color(0xFFFEF08A),
      );
      return;
    }

    final moonGlowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFEF3C7).withValues(alpha: 0.36),
          const Color(0xFFFEF3C7).withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(center: Offset(cx, cy), radius: glowRadius),
      );
    canvas.drawCircle(Offset(cx, cy), glowRadius, moonGlowPaint);
    canvas.drawCircle(
      Offset(cx, cy),
      radius * 0.80,
      Paint()..color = const Color(0xFFFFFBEB),
    );

    final starW = math.max(1, w.toInt());
    final starH = math.max(1, (horizonY * 0.90).toInt());
    final starPaint = Paint();
    for (int i = 0; i < _Compact96.starCount; i++) {
      final sx = ((i * 79 + 23) % starW).toDouble();
      final sy = ((i * 53 + 17) % starH).toDouble();
      final twinkle = 0.35 + 0.65 * math.sin(time * 2.2 + i * 1.3).abs();
      starPaint.color = Colors.white.withValues(alpha: 0.80 * twinkle);
      canvas.drawCircle(
        Offset(sx, sy),
        i % 4 == 0 ? _Compact96.starRadiusBig : _Compact96.starRadiusSmall,
        starPaint,
      );
    }
  }

  void _paintCompactWater(
    Canvas canvas,
    double w,
    double h,
    double horizonY,
  ) {
    final waterH = h - horizonY;
    if (waterH <= 0) return;

    final (waterTopColor, waterBottomColor) = _waterGradientColors();
    canvas.drawRect(
      Rect.fromLTWH(0, horizonY, w, waterH),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [waterTopColor, waterBottomColor],
        ).createShader(Rect.fromLTWH(0, horizonY, w, waterH)),
    );

    final cx = w * (0.5 + atmo.sunAzimuth * 0.30);
    _paintGlitterPath(
      canvas,
      w: w,
      h: h,
      horizonY: horizonY,
      waterH: waterH,
      centerX: cx,
      stepY: 3.0,
      offsetY: 1.5,
      strokeWidth: 1.4,
    );

    final baseAmp = (atmo.waveAmp + surgeMultiplier) * _Compact96.ampScale;
    for (int layer = 0; layer < _Compact96.waveLayers; layer++) {
      _paintWaveLayer(
        canvas,
        w: w,
        h: h,
        baseY: horizonY + waterH * _Compact96.waveBaseYRatios[layer],
        freq: 0.012 + layer * 0.009,
        amp: math.min(baseAmp * (1.0 - layer * 0.22), _Compact96.maxAmp),
        speed: 1.0 + layer * 0.45,
        alpha: 0.32 - layer * 0.05,
        stepX: 3.0,
        foamStroke: _Compact96.foamStroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant OceanFallbackPainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.atmo != atmo ||
        oldDelegate.surgeMultiplier != surgeMultiplier ||
        oldDelegate.surgeProgress != surgeProgress ||
        oldDelegate.compact96 != compact96;
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

/// 96px 海平線帶 2D 降級模式的幾何常數。
class _Compact96 {
  _Compact96._();

  static const double horizonRatio = 0.45;
  static const int waveLayers = 3;
  static const double maxAmp = 5.5;
  static const double ampScale = 3.8;
  static const double sunRadius = 11.0;
  static const int starCount = 20;
  static const double starRadiusSmall = 0.8;
  static const double starRadiusBig = 1.6;
  static const double glowScale = 3.0;
  static const double foamStroke = 1.8;
  static const double overlayAlpha = 0.6;
  static const List<double> waveBaseYRatios = <double>[0.0, 0.30, 0.60];
}
