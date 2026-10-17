import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Duo 3D 書頁翻頁方向
enum DuoFlipDirection {
  none,
  forward, // 向左掀開當前頁（0° -> -90°），透出底層下一月（0.965 -> 1.0）
  backward, // 上一月從外部左側（-90° -> 0°）翻入覆蓋
}

/// Duo 書頁翻頁控制器：提供與 PageController 一致的呼叫介面
class DuoPageController extends ChangeNotifier {
  int _page;
  int get page => _page;

  _DuoBookPageViewState? _state;

  DuoPageController({int initialPage = 0}) : _page = initialPage;

  bool get hasClients => _state != null;

  void _attach(_DuoBookPageViewState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  /// 平滑翻頁至指定頁碼（支援 Duo 3D 書頁立體旋轉與漸變透明透底）
  Future<void> animateToPage(
    int targetPage, {
    Duration duration = const Duration(milliseconds: 380),
    Curve curve = Curves.easeOutCubic,
  }) async {
    if (_state != null) {
      await _state!._animateToPage(targetPage, duration: duration, curve: curve);
    } else {
      _page = targetPage;
      notifyListeners();
    }
  }

  /// 立即跳至指定頁碼
  void jumpToPage(int targetPage) {
    if (_state != null) {
      _state!._jumpToPage(targetPage);
    } else {
      _page = targetPage;
      notifyListeners();
    }
  }
}

/// 靈感源自 jal-co/iphone-duo 的真 3D 書頁翻頁組件：
/// - 頂頁沿左界書脊（Alignment.centerLeft）進行 3D 景深旋轉（rotateY 0° -> -90°）。
/// - 掀開時頂頁應用線性漸變透明遮罩（ShaderMask），左側書脊保留紙面實感，右側自然消融進光裡。
/// - 底層下一頁預先平鋪在下方，具備視差微縮放（scale 0.965 -> 1.0）與陰影消散（0.35 -> 0.0）。
/// - 往前翻頁時上一頁從外部左側帶漸變透明翻入覆蓋。
/// - 靜止狀態下僅渲染單層網格，零額外 GPU 紋理或 Shader 負載，保證極致 60/120fps。
class DuoBookPageView extends StatefulWidget {
  final DuoPageController controller;
  final NullableIndexedWidgetBuilder itemBuilder;
  final ValueChanged<int>? onPageChanged;

  const DuoBookPageView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.onPageChanged,
  });

  @override
  State<DuoBookPageView> createState() => _DuoBookPageViewState();
}

class _DuoBookPageViewState extends State<DuoBookPageView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipAnimCtrl;

  DuoFlipDirection _direction = DuoFlipDirection.none;
  double _flipProgress = 0.0; // 0.0 ~ 1.0

  int _targetPage = 0;
  double _dragStartX = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
    _flipAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _flipAnimCtrl.addListener(() {
      setState(() {
        _flipProgress = _flipAnimCtrl.value;
      });
    });
  }

  @override
  void didUpdateWidget(covariant DuoBookPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._detach();
      widget.controller._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller._detach();
    _flipAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _animateToPage(
    int targetPage, {
    required Duration duration,
    required Curve curve,
  }) async {
    if (_isDragging || _flipAnimCtrl.isAnimating) return;
    final current = widget.controller.page;
    if (targetPage == current) return;

    final diff = targetPage - current;
    if (diff.abs() > 1) {
      // 跨度大於 1 個月時，直接跳轉，避免狂翻多頁造成眩目
      _jumpToPage(targetPage);
      return;
    }

    _targetPage = targetPage;
    _direction = diff > 0 ? DuoFlipDirection.forward : DuoFlipDirection.backward;
    _flipAnimCtrl.duration = duration;

    final animation = CurvedAnimation(parent: _flipAnimCtrl, curve: curve);
    animation.addListener(() {
      setState(() {
        _flipProgress = animation.value;
      });
    });

    await _flipAnimCtrl.forward(from: 0.0);

    widget.controller._page = targetPage;
    widget.controller.notifyListeners();
    widget.onPageChanged?.call(targetPage);

    setState(() {
      _direction = DuoFlipDirection.none;
      _flipProgress = 0.0;
    });
  }

  void _jumpToPage(int targetPage) {
    if (_flipAnimCtrl.isAnimating) _flipAnimCtrl.stop();
    widget.controller._page = targetPage;
    widget.controller.notifyListeners();
    widget.onPageChanged?.call(targetPage);
    setState(() {
      _direction = DuoFlipDirection.none;
      _flipProgress = 0.0;
    });
  }

  void _onDragStart(DragStartDetails details) {
    if (_flipAnimCtrl.isAnimating) return;
    _dragStartX = details.localPosition.dx;
    _isDragging = true;
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    if (!_isDragging || width <= 0) return;
    final deltaX = details.localPosition.dx - _dragStartX;

    if (deltaX < 0) {
      // 向左拖動：向前翻（下一月）
      final progress = (-deltaX / width).clamp(0.0, 1.0);
      setState(() {
        _direction = DuoFlipDirection.forward;
        _flipProgress = progress;
        _targetPage = widget.controller.page + 1;
      });
    } else if (deltaX > 0) {
      // 向右拖動：向後翻（上一月）
      final progress = (deltaX / width).clamp(0.0, 1.0);
      setState(() {
        _direction = DuoFlipDirection.backward;
        _flipProgress = progress;
        _targetPage = widget.controller.page - 1;
      });
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    _isDragging = false;

    final velocity = details.primaryVelocity ?? 0.0;
    final bool shouldFlip;

    if (_direction == DuoFlipDirection.forward) {
      shouldFlip = _flipProgress > 0.35 || velocity < -300;
    } else if (_direction == DuoFlipDirection.backward) {
      shouldFlip = _flipProgress > 0.35 || velocity > 300;
    } else {
      shouldFlip = false;
    }

    if (shouldFlip) {
      final remaining = (1.0 - _flipProgress).clamp(0.0, 1.0);
      _flipAnimCtrl.duration = Duration(
        milliseconds: (300 * remaining).clamp(100, 360).toInt(),
      );
      _flipAnimCtrl.forward(from: _flipProgress).then((_) {
        widget.controller._page = _targetPage;
        widget.controller.notifyListeners();
        widget.onPageChanged?.call(_targetPage);
        if (mounted) {
          setState(() {
            _direction = DuoFlipDirection.none;
            _flipProgress = 0.0;
          });
        }
      });
    } else {
      // 取消翻頁，回彈至原位
      final remaining = _flipProgress.clamp(0.0, 1.0);
      _flipAnimCtrl.duration = Duration(
        milliseconds: (240 * remaining).clamp(80, 240).toInt(),
      );
      _flipAnimCtrl.reverse(from: _flipProgress).then((_) {
        if (mounted) {
          setState(() {
            _direction = DuoFlipDirection.none;
            _flipProgress = 0.0;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final curPage = widget.controller.page;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        // 靜態狀態：僅渲染當前月網格，零 GPU 紋理與 Shader 負擔
        if (_direction == DuoFlipDirection.none || _flipProgress == 0.0) {
          final pageWidget = widget.itemBuilder(context, curPage);
          return GestureDetector(
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
            onHorizontalDragEnd: _onDragEnd,
            behavior: HitTestBehavior.translucent,
            child: pageWidget ?? const SizedBox.shrink(),
          );
        }

        final Widget bottomLayer;
        final Widget topLayer;

        if (_direction == DuoFlipDirection.forward) {
          // 向左掀開當前頁，透出下一月
          final underPage = curPage + 1;
          final underChild = widget.itemBuilder(context, underPage) ?? const SizedBox.shrink();
          final activeChild = widget.itemBuilder(context, curPage) ?? const SizedBox.shrink();

          bottomLayer = _buildUnderLayer(underChild, _flipProgress);
          topLayer = _buildFlipperLayer(activeChild, _flipProgress, isForward: true);
        } else {
          // 上一月從外部向右翻入覆蓋當前月
          final prevPage = curPage - 1;
          final prevChild = widget.itemBuilder(context, prevPage) ?? const SizedBox.shrink();
          final currentChild = widget.itemBuilder(context, curPage) ?? const SizedBox.shrink();

          // 底層是當前月（隨翻入被覆蓋）
          bottomLayer = _buildUnderLayer(currentChild, 1.0 - _flipProgress);
          // 頂層是上一月（從 1.0 旋轉入位至 0.0）
          topLayer = _buildFlipperLayer(prevChild, 1.0 - _flipProgress, isForward: false);
        }

        return GestureDetector(
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
          onHorizontalDragEnd: _onDragEnd,
          behavior: HitTestBehavior.translucent,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              bottomLayer,
              topLayer,
            ],
          ),
        );
      },
    );
  }

  /// 底層透出頁面：具備視差微縮放（0.965 -> 1.0）與陰影漸散
  Widget _buildUnderLayer(Widget child, double progress) {
    final scale = 0.965 + progress * 0.035;
    final opacity = (0.94 + 0.06 * progress).clamp(0.0, 1.0);
    final shadowAlpha = ((1.0 - progress) * 0.28).clamp(0.0, 0.28);

    return Transform.scale(
      scale: scale,
      alignment: Alignment.center,
      child: Opacity(
        opacity: opacity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            // 投影遮罩層
            if (shadowAlpha > 0.01)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.black.withValues(alpha: shadowAlpha),
                          Colors.black.withValues(alpha: shadowAlpha * 0.4),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.32, 0.75],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 頂層 3D 翻頁層：
  /// - 錨定左側書脊（Alignment.centerLeft）
  /// - 旋轉角度 0° -> -90°（math.pi / 2.05）
  /// - 線性漸變透明遮罩（ShaderMask）：左側書脊保持實質，右側消融進光裡
  /// - 書脊微折痕暗部（Spine Crease）與紙邊受光泛白（Paper Veil）
  Widget _buildFlipperLayer(Widget child, double progress, {required bool isForward}) {
    if (progress >= 0.999) {
      // 旋轉至 90° 邊緣視角時完全不可見
      return const SizedBox.shrink();
    }

    final angle = progress * (math.pi / 2.04);
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.00085) // 景深透視
      ..rotateY(-angle);

    final solidStop = (1.0 - progress * 0.68).clamp(0.0, 1.0);
    final edgeAlpha = (1.0 - progress * 1.55).clamp(0.0, 1.0);

    final maskedChild = ShaderMask(
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.black,
            Colors.black,
            Colors.black.withValues(alpha: edgeAlpha),
          ],
          stops: [0.0, solidStop, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          // 紙邊受光罩（泛白，消融感）
          if (progress > 0.05)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.22 * progress),
                        Colors.white.withValues(alpha: 0.52 * progress),
                      ],
                      stops: const [0.40, 0.76, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          // 書脊折痕暗部
          if (progress > 0.05)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 38,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.18 * progress),
                        Colors.black.withValues(alpha: 0.04 * progress),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return Transform(
      transform: matrix,
      alignment: Alignment.centerLeft,
      child: maskedChild,
    );
  }
}
