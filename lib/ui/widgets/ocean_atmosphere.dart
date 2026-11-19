import 'dart:math' as math;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'ocean_atmo_state.dart';
import 'ocean_fallback_painter.dart';

export 'ocean_atmo_state.dart' show OceanAtmoState;

/// 海天連動動態背景 Widget（2D CustomPainter 渲染）。
///
/// 當 `shaders/ocean.frag` 不可用（舊機 GPU 限制／後端不支援／資產缺失）時，
/// 由 `OceanBand` 自動降級使用此組件，確保不白屏、不當機。
class OceanAtmosphereWidget extends StatefulWidget {
  final OceanAtmoState targetState;
  final Widget? child;

  /// `true` = 96px 海平線帶模式（僅影響 2D 降級繪製）。
  final bool compact96;

  const OceanAtmosphereWidget({
    super.key,
    required this.targetState,
    this.child,
    this.compact96 = false,
  });

  @override
  State<OceanAtmosphereWidget> createState() => OceanAtmosphereWidgetState();
}

class OceanAtmosphereWidgetState extends State<OceanAtmosphereWidget>
    with TickerProviderStateMixin {
  late final AnimationController _waveCycleCtrl;
  late final AnimationController _transitionCtrl;
  late final AnimationController _surgeCtrl;

  late OceanAtmoState _prevState;
  late OceanAtmoState _currentState;

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

  /// 觸發導入排班時的海面波浪激盪效果。
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
        final surgeMultiplier = math.sin(surgeProgress * math.pi) * 1.6;

        return CustomPaint(
          painter: OceanFallbackPainter(
            time: _waveCycleCtrl.value * 2 * math.pi,
            atmo: state,
            surgeMultiplier: surgeMultiplier,
            surgeProgress: surgeProgress,
            compact96: widget.compact96,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
