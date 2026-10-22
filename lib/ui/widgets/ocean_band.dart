import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'ocean_atmosphere.dart';
import 'ocean_presets.dart';
import 'ocean_shader_controller.dart';

/// 一幀要餵給 shader 的動態值（由 30fps Timer 更新，painter 喺 paint 時讀）。
///
/// 用可變物件 + `ValueNotifier` 做 repaint 訊號，係為咗避免每幀 `setState`
/// 重建 widget 樹（裝飾元件唔值得令整個日曆陪跑）。
class _BandFrame {
  /// 經過秒數（**單調遞增，不取模**）。
  ///
  /// 同時餵 `uTime`（波浪相位）與 `sin(elapsed * 1.3)`（相機上下浮沉）。
  /// ⚠️ 絕對唔可以對佢取模：frag 內 9 條波的 `w = sqrt(G * k)` 各不相同，
  /// 相位不可能同時回到原點，`% 8` 會令整片海每 8 秒瞬移一次（T04-AC6）。
  double elapsed = 0.0;

  /// 浪湧進行度 p ∈ [0,1]；**靜止時 -1.0**（shader 以 >= 0.0 判斷衝擊環是否啟用）
  double waveProgress = -1.0;

  /// 浪湧強度 `sin(pπ) * 1.35`；靜止時 0.0
  double surgeIntensity = 0.0;

  /// 浪湧鏡頭下沉量 `sin(pπ) * 0.75`；靜止時 0.0
  double camDip = 0.0;

  /// 當前（逐幀插值中）的預設集
  OceanShaderPreset preset = OceanShaderPreset.midday;
}

/// v3.5 海平線帶：96px 高、圓角 16px 的裝飾性海洋（真光影線步進）。
///
/// 主路徑：`shaders/ocean.frag`（Android 與 Web 共用同一份著色器）。
/// Fallback：`shaders/ocean.frag` 載入唔到時，自動退回 [OceanAtmosphereWidget] 的 2D 版，
/// 全程 try/catch，唔會 crash、唔會白屏（見 docs/v3.5/ARCH.md §7.9）。
///
/// 呢個 widget **不可點擊**（純裝飾），亦唔會搶走月曆的觸控。
class OceanBand extends StatefulWidget {
  /// `false` = 收合至 0 並淡出（面板打開時）。
  final bool visible;

  /// 帶高（由月曆 LayoutBuilder 實算，上限 [kOceanBandHeight]）。
  final double height;

  const OceanBand({
    super.key,
    required this.visible,
    required this.height,
  });

  @override
  State<OceanBand> createState() => OceanBandState();
}

/// `OceanBand` 的 State。對外只暴露 [triggerSurge]（導入排更時由月曆觸發）。
class OceanBandState extends State<OceanBand> {
  /// 30fps 幀節流（裝飾唔需要 60fps，慳一半電；波浪 8 秒一循環，30fps 肉眼無差）
  static const Duration _frameInterval = Duration(milliseconds: 33);

  /// shader 載入 watchdog：超過呢個時間仍未完成，就當 `timeout` 走 fallback。
  static const Duration _loadWatchdog = Duration(seconds: 5);

  final Stopwatch _clock = Stopwatch();
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);
  final _BandFrame _frame = _BandFrame();

  /// fallback 專用 key（把 [triggerSurge] 轉發給 2D 版）
  final GlobalKey<OceanAtmosphereWidgetState> _fallbackKey =
      GlobalKey<OceanAtmosphereWidgetState>();

  Timer? _frameTimer;
  Timer? _moodTimer;
  Timer? _watchdog;

  /// `[OCEAN] renderer=` 只准印一次（機器可讀，T06 驗收依賴它）
  bool _rendererReported = false;

  ui.FragmentShader? _shader;

  /// 當前大氣狀態（一律用真實當前時間，唔再跟選中班次）
  OceanAtmoState _atmo = OceanAtmoState.fromCurrentTime();

  /// 預設集插值目標（逐幀以 `min(1, dt * kOceanPresetLerp)` 收斂，同 JS renderLoop 一致）
  OceanShaderPreset _presetTarget = OceanShaderPreset.midday;

  int? _surgeStartMs;

  @override
  void initState() {
    super.initState();
    _clock.start();
    _atmo = OceanAtmoState.fromCurrentTime();
    _presetTarget = OceanShaderPreset.forMood(_atmo.mood);
    _frame.preset = _presetTarget;
    _loadShader();
    _moodTimer = Timer.periodic(
      const Duration(seconds: kOceanMoodPollSeconds),
      (_) => _pollMood(),
    );
  }

  /// 非阻塞載入 shader：載入完成前顯示 fallback，完成後自動切換（唔拖慢啟動）。
  ///
  /// 無論成功或失敗，都會印**恰好一次**機器可讀的 `[OCEAN] renderer=…`（見 ARCH §7.12）：
  /// - `[OCEAN] renderer=pending`（開頭即印，就算卡死都看得到）
  /// - `[OCEAN] renderer=shader`
  /// - `[OCEAN] renderer=fallback reason=asset-missing|unsupported|compile-error|timeout`
  Future<void> _loadShader() async {
    debugPrint('[OCEAN] renderer=pending');
    _watchdog = Timer(_loadWatchdog, () {
      _reportRenderer('fallback reason=$kOceanFailTimeout');
    });

    await OceanShaderController.load();
    if (!mounted) return;

    final shader = OceanShaderController.createShader();
    if (shader == null) {
      final reason =
          OceanShaderController.failReason ?? kOceanFailUnsupported;
      _reportRenderer('fallback reason=$reason');
      return;
    }
    _reportRenderer('shader');
    setState(() => _shader = shader);
    _startFrameTimer();
  }

  /// 是否應該燒 30fps：帶有實際高度、而且未被收合。
  ///
  /// v3.6.1：鍵盤彈起時 `bandHeight` 直接歸 0（天色欄完全壓縮），
  /// 呢個時候**一定要停錶**，唔可以「繼續 30fps 跑、只係畫個空框」——
  /// 用戶打字嗰陣冇理由為一條 0px 的帶燒 CPU／電。
  bool get _shouldAnimate => widget.visible && widget.height > 0.0;

  /// 起 30fps 幀節流（重複呼叫無害；shader 未就緒時唔會起）。
  void _startFrameTimer() {
    if (_frameTimer != null || _shader == null || !_shouldAnimate) return;
    _frameTimer = Timer.periodic(_frameInterval, (_) => _onFrame());
  }

  /// 停 30fps 幀節流並釋放 Timer。
  ///
  /// `_clock` 刻意**唔停**：`elapsed` 用單調遞增的真實時間，
  /// 復活時相位無縫接上，唔會跳格（見 `_BandFrame.elapsed` 的說明）。
  void _stopFrameTimer() {
    _frameTimer?.cancel();
    _frameTimer = null;
  }

  /// 按當前可見性同步 Timer 狀態（可見 → 起，不可見 → 停）。
  void _syncFrameTimer() {
    if (_shouldAnimate) {
      _startFrameTimer();
    } else {
      _stopFrameTimer();
    }
  }

  @override
  void didUpdateWidget(covariant OceanBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible ||
        oldWidget.height != widget.height) {
      _syncFrameTimer();
    }
  }

  /// 測試用：30fps Timer 而家有冇真係喺度跑（永久防線，見 ocean_band_idle_test）。
  @visibleForTesting
  bool get debugFrameTimerRunning => _frameTimer?.isActive ?? false;

  /// 印出唯一的 renderer 標記（重複呼叫只會生效一次）。
  void _reportRenderer(String value) {
    if (_rendererReported) return;
    _rendererReported = true;
    _watchdog?.cancel();
    _watchdog = null;
    debugPrint('[OCEAN] renderer=$value');
  }

  /// 每 33ms 更新一幀的動態值，然後叫 painter 重畫（唔 setState）。
  void _onFrame() {
    if (!mounted) return;
    final nowMs = _clock.elapsedMilliseconds;

    // 單調遞增，**絕對唔可以取模**（見 _BandFrame.elapsed 的說明）
    _frame.elapsed = OceanShaderController.waveTimeSeconds(nowMs);

    // ── 浪湧（2200ms，對齊 JS importFx.duration）──
    final surgeStart = _surgeStartMs;
    if (surgeStart != null) {
      final p = (nowMs - surgeStart) / kOceanSurgeDurationMs.toDouble();
      if (p >= 1.0) {
        _surgeStartMs = null;
        _frame.waveProgress = -1.0;
        _frame.surgeIntensity = 0.0;
        _frame.camDip = 0.0;
      } else {
        final pulse = math.sin(p * math.pi);
        _frame.waveProgress = p;
        _frame.surgeIntensity = pulse * 1.35;
        _frame.camDip = pulse * 0.75;
      }
    }

    // ── 預設集逐參數插值（同 web/ocean_shader.js renderLoop 一致）──
    final dt = _frameInterval.inMilliseconds / 1000.0;
    final lerpSpeed = math.min(1.0, dt * kOceanPresetLerp);
    _frame.preset = OceanShaderPreset.lerp(_frame.preset, _presetTarget, lerpSpeed);

    _tick.value = _tick.value + 1;
  }

  /// 每 60 秒檢查大氣 mood；只有真係變咗才 setState（避免無謂重建）。
  void _pollMood() {
    if (!mounted) return;
    final next = OceanAtmoState.fromCurrentTime();
    if (next.mood == _atmo.mood) return;
    setState(() {
      _atmo = next;
      _presetTarget = OceanShaderPreset.forMood(next.mood);
    });
  }

  /// 導入排更時的海面浪湧。對外 API 與 v3.4.5 完全一樣（月曆的呼叫點一字不改）。
  ///
  /// - shader 路徑：餵 `uImportWaveProgress` / `uSurgeIntensity` / `uCamPos.y`，
  ///   衝擊環由 frag 內的 `shockRing` 邏輯繪製（透視正確的 3D 波前）。
  /// - fallback 路徑：轉發給 [OceanAtmosphereWidgetState.triggerSurge]（相位加速，唔畫 ring）。
  void triggerSurge() {
    _surgeStartMs = _clock.elapsedMilliseconds;
    _fallbackKey.currentState?.triggerSurge();
  }

  @override
  void dispose() {
    _stopFrameTimer();
    _moodTimer?.cancel();
    _watchdog?.cancel();
    _clock.stop();
    _shader?.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double height =
        widget.visible ? widget.height.clamp(0.0, kOceanBandHeight) : 0.0;

    return IgnorePointer(
      child: AnimatedSize(
        duration: const Duration(milliseconds: kOceanCollapseMs),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: double.infinity,
          height: height,
          child: AnimatedOpacity(
            opacity: height > 0.0 ? 1.0 : 0.0,
            duration: const Duration(milliseconds: kOceanCollapseMs),
            curve: Curves.easeOutCubic,
            child: height > 0.0 ? _buildBand() : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _buildBand() {
    final shader = _shader;

    // ⚠️ 嵌套順序必須係 `Center → ConstrainedBox → Padding → 容器`，
    // 同日曆卡（`calendar_screen.dart` ② 區）**逐層相同**。
    //
    // 以前呢度係 `Padding → Center → ConstrainedBox`（先縮再夾），
    // 日曆嗰邊係 `Center → ConstrainedBox → Padding`（先夾再縮），
    // 兩條路線喺 W > 480 時一定分叉：
    //   天色帶 = min(W − 16, 480)   → W=900 得 480
    //   日曆卡 = min(W, 480) − 16   → W=900 得 464
    // 即係**每邊差 8px**，Web PWA 桌面闊屏必中（手機 ≤480 反而睇唔出）。
    // `test/band_card_alignment_test.dart` 會用真 widget 量兩條邊鎖住呢個對齊。
    //
    // ⚠️ 容器用 `Container` + `clipBehavior` 取代舊嘅 `ClipRRect → ColoredBox`，
    // 係為咗同時畫底色**同描邊**：成套感靠嘅就係「同一條邊」。
    // 底色唔再用 `kCalendarPageBg`（同頁面同色 → shader pending 時睇落係空白），
    // 改 `kOceanBandSurface`（深一檔霧藍灰）；shader 靜默失敗時露出来嘅
    // 係協調色而唔係一條刺眼黑條，呢點同以前一樣。
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kOceanBandMaxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: kOceanBandInset),
          // RepaintBoundary 放最外層：把 30fps 的 shader 重繪完全隔離出月曆的圖層，
          // 唔會令成個日曆陪跑（同 ARCH §7.9 嘅理由一致）。
          child: RepaintBoundary(
            child: Container(
              key: const Key('ocean-band-card'),
              decoration: BoxDecoration(
                color: kOceanBandSurface,
                borderRadius: BorderRadius.circular(kOceanBandRadius),
                border: Border.all(color: kCardStroke),
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox.expand(
                child: shader != null
                    ? CustomPaint(
                        painter: _OceanShaderPainter(
                          shader: shader,
                          frame: _frame,
                          repaint: _tick,
                        ),
                      )
                    : OceanAtmosphereWidget(
                        key: _fallbackKey,
                        compact96: true,
                        targetState: _atmo,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 把 `shaders/ocean.frag` 畫成一條帶。
///
/// 所有 shader 相關呼叫都包喺 try/catch 內：裝飾元件**唔可以**令日曆開唔到。
class _OceanShaderPainter extends CustomPainter {
  _OceanShaderPainter({
    required this.shader,
    required this.frame,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ui.FragmentShader shader;
  final _BandFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    try {
      OceanShaderController.bindUniforms(
        shader,
        size: size,
        elapsed: frame.elapsed,
        camDip: frame.camDip,
        waveProgress: frame.waveProgress,
        surgeIntensity: frame.surgeIntensity,
        preset: frame.preset,
      );
      canvas.drawRect(
        Offset.zero & size,
        Paint()..shader = shader,
      );
    } catch (error) {
      // 靜默失敗：留返底色，唔會出現黑帶，亦唔會拋出未捕捉異常。
      debugPrint('[OCEAN] shader paint 失敗：$error');
    }
  }

  @override
  bool shouldRepaint(covariant _OceanShaderPainter oldDelegate) {
    return oldDelegate.shader != shader || oldDelegate.frame != frame;
  }
}
