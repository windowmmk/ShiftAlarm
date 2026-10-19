// ShiftAlarm x Web-Ocean: 42-Cell (6-Week) Staggered Buoyant Wave Import Transition
// Drop-in Flutter Widget from official specification

import 'dart:math' as math;
import 'package:flutter/material.dart';

enum OceanImportMode {
  tidalWave, // 🌊 破浪光潮・浮力落位 (由下往上隨波浪相位浮起)
  vortexSnap, // 🌀 星群漩渦・結晶入位 (由中心向外螺旋震波鎖定)
  horizonFlip, // 🌅 天際折疊・晝夜快轉 (由海平線 3D 跑道展開)
}

class OceanStaggeredCellTransition extends StatelessWidget {
  final int index; // 0..41 (Fixed 6 weeks x 7 days)
  final Animation<double> controller; // 0.0 -> 1.0 (duration ~1800ms)
  final OceanImportMode mode;
  final Widget child;

  const OceanStaggeredCellTransition({
    super.key,
    required this.index,
    required this.controller,
    this.mode = OceanImportMode.tidalWave,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.isAnimating) {
      return child;
    }

    final int row = index ~/ 7; // 0..5
    final int col = index % 7; // 0..6

    // Calculate normalized wave propagation delay [0.0 .. 0.55]
    double delayFraction;
    switch (mode) {
      case OceanImportMode.tidalWave:
        // Sweeps from bottom row (5) to top row (0) with diagonal swell
        delayFraction = ((5 - row) * 0.075) + (col * 0.022);
        break;
      case OceanImportMode.vortexSnap:
        final double dx = col - 3.0;
        final double dy = row - 2.5;
        final double dist = math.sqrt(dx * dx + dy * dy);
        delayFraction = (dist / 4.0) * 0.52;
        break;
      case OceanImportMode.horizonFlip:
        delayFraction = (row * 0.08) + ((col - 3).abs() * 0.025);
        break;
    }

    final double start = delayFraction.clamp(0.0, 0.65);
    final double end = (start + 0.35).clamp(0.0, 1.0);

    final Animation<double> cellAnim = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: Curves.easeOutBack),
    );

    return AnimatedBuilder(
      animation: cellAnim,
      builder: (context, _) {
        final double t = cellAnim.value;
        final double inv = 1.0 - t;

        // Wave crest specular border flash at peak of surge
        final double crestFlash = math.sin((t.clamp(0.0, 1.0)) * math.pi);

        final Matrix4 transform = Matrix4.identity()
          ..setEntry(3, 2, 0.0012); // 3D perspective

        if (mode == OceanImportMode.tidalWave) {
          // Buoyant wave surge: rises from depth with 3D pitch tilt
          final double translateY = 36.0 * inv - 8.0 * math.sin(t * math.pi);
          final double rotateX = (0.78 * inv) - 0.16 * math.sin(t * math.pi);
          final double scale = 0.80 + 0.20 * t;
          transform
            ..translate(0.0, translateY, 0.0)
            ..rotateX(rotateX)
            ..scale(scale, scale);
        } else if (mode == OceanImportMode.vortexSnap) {
          final double dx = (col - 3.0) * 38.0 * inv;
          final double dy = (row - 2.5) * 38.0 * inv;
          final double rotZ = (col - 3.0 + row - 2.5) * 0.25 * inv;
          final double scale = 0.35 + 0.65 * t;
          transform
            ..translate(dx, dy, 0.0)
            ..rotateZ(rotZ)
            ..scale(scale, scale);
        } else {
          final double translateY = -55.0 * inv;
          final double rotateX = -1.25 * inv;
          transform
            ..translate(0.0, translateY, 0.0)
            ..rotateX(rotateX);
        }

        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: transform,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: crestFlash > 0.05
                    ? Border.all(
                        color: Color.lerp(
                          const Color(0x0038BDF8),
                          const Color(0xCC7DD3FC),
                          crestFlash,
                        )!,
                        width: 1.5,
                      )
                    : null,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
