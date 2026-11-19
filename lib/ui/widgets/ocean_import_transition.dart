import 'dart:math' as math;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';

/// 導入排班時的 42 格（6 週）浮力波浪進場動畫模式。
enum OceanImportMode {
  /// 破浪光潮・浮力落位（由下往上隨波浪相位浮起）。
  tidalWave,

  /// 星群漩渦・結晶入位（由中心向外螺旋震波鎖定）。
  vortexSnap,

  /// 天際折疊・晝夜快轉（由海平線 3D 展開）。
  horizonFlip,
}

class OceanStaggeredCellTransition extends StatelessWidget {
  final int index;
  final Animation<double> controller;
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

    final int row = index ~/ 7;
    final int col = index % 7;

    final double delayFraction = switch (mode) {
      OceanImportMode.tidalWave => ((5 - row) * 0.075) + (col * 0.022),
      OceanImportMode.vortexSnap =>
        (math.sqrt(math.pow(col - 3.0, 2) + math.pow(row - 2.5, 2)) / 4.0) *
            0.52,
      OceanImportMode.horizonFlip => (row * 0.08) + ((col - 3).abs() * 0.025),
    };

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
        final double crestFlash = math.sin((t.clamp(0.0, 1.0)) * math.pi);

        final Matrix4 transform = Matrix4.identity()..setEntry(3, 2, 0.0012);

        if (mode == OceanImportMode.tidalWave) {
          final double translateY = 36.0 * inv - 8.0 * math.sin(t * math.pi);
          final double rotateX = (0.78 * inv) - 0.16 * math.sin(t * math.pi);
          final double scale = 0.80 + 0.20 * t;
          transform
            ..translateByDouble(0.0, translateY, 0.0, 1.0)
            ..rotateX(rotateX)
            ..scaleByDouble(scale, scale, 1.0, 1.0);
        } else if (mode == OceanImportMode.vortexSnap) {
          final double dx = (col - 3.0) * 38.0 * inv;
          final double dy = (row - 2.5) * 38.0 * inv;
          final double rotZ = (col - 3.0 + row - 2.5) * 0.25 * inv;
          final double scale = 0.35 + 0.65 * t;
          transform
            ..translateByDouble(dx, dy, 0.0, 1.0)
            ..rotateZ(rotZ)
            ..scaleByDouble(scale, scale, 1.0, 1.0);
        } else {
          final double translateY = -55.0 * inv;
          final double rotateX = -1.25 * inv;
          transform
            ..translateByDouble(0.0, translateY, 0.0, 1.0)
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
