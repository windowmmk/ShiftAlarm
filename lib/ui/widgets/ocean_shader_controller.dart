import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../theme/app_theme.dart';
import 'ocean_presets.dart';

/// `shaders/ocean.frag` 的 uniform 佈局（**線性 float 索引**）。
///
/// `FragmentShader.setFloat(index, value)` 嘅 index 係「按 uniform 宣告順序累加嘅 float 格位」：
/// `float` 佔 1 格、`vec2` 佔 2 格、`vec3` 佔 3 格。
/// 索引錯咗**唔會報錯**，只會靜默畫錯（例如把太陽方位餵落曝光值）。
///
/// ⚠️ 呢個表必須與 `shaders/ocean.frag` 的 uniform 宣告順序**逐格一致**，
///    而且 frag 內每個 uniform 都必須真係被引用（否則 impellerc 會剔除，索引整體前移）。
///    回歸測試見 `test/ocean_uniform_layout_test.dart`。
class _U {
  static const int res = 0; // vec2  → 0,1
  static const int time = 2; // float
  static const int camPos = 3; // vec3  → 3,4,5
  static const int camFwd = 6; // vec3  → 6,7,8
  static const int camRight = 9; // vec3  → 9,10,11
  static const int camUp = 12; // vec3  → 12,13,14
  static const int windSpeed = 15;
  static const int swellHs = 16;
  static const int choppiness = 17;
  static const int turbidity = 18;
  static const int foam = 19;
  static const int sunDir = 20; // vec3  → 20,21,22
  static const int haze = 23;
  static const int clouds = 24;
  static const int exposure = 25;
  static const int bloom = 26;
  static const int nightGlow = 27;
  static const int waveProgress = 28;
  static const int surge = 29;
}

/// shader 不可用的機器可讀原因（ARCH §7.12；`[OCEAN] renderer=fallback reason=…` 只准用呢四個值）。
///
/// T06 要刪 `ocean_bridge*.dart`，而刪除的前提係 Web console 出現 `renderer=shader`。
/// 若只有自由文字 `loadError`，事後無法判斷 Web 到底係邊一種失敗，所以一定要分類。
const String kOceanFailAssetMissing = 'asset-missing';
const String kOceanFailUnsupported = 'unsupported';
const String kOceanFailCompileError = 'compile-error';
const String kOceanFailTimeout = 'timeout';

/// 海洋著色器控制器：全域單例載入 `FragmentProgram`、建立 `FragmentShader`、餵 uniform。
///
/// 設計約束（見 docs/v3.5/ARCH.md §3.5.6 / §4.4 / §7.9）：
/// 1. `FragmentProgram.fromAsset` **全域只做一次**並快取（static），
///    絕對唔可以在 `build()` / `paint()` 內呼叫 —— 否則每幀都會重新編譯，直接掉幀。
/// 2. `load()` **永不 rethrow**：載入失敗只記錄 [loadError] 並令 [isAvailable] 保持 false，
///    由 `OceanBand` 自動退回 2D `_OceanPainter`，唔可以白屏、唔可以 crash。
/// 3. `FragmentProgram` 跟 App 生命週期共用，唔釋放；`FragmentShader` 由呼叫方 dispose。
class OceanShaderController {
  OceanShaderController._();

  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  /// 失敗原因原文（供 log 與當機紀錄查看）
  static String? loadError;

  /// 失敗原因分類（[kOceanFailAssetMissing] / [kOceanFailUnsupported] /
  /// [kOceanFailCompileError] / [kOceanFailTimeout]），成功時為 null。
  ///
  /// 只有 `loadError` 係自由文字，唔可以靠它做機器判斷，所以另外存一份分類。
  static String? failReason;

  /// Dart 側 uniform 佔用的 float 格總數（= `_U` 最大索引 + 1）。
  static const int uniformFloatCount = _U.surge + 1;

  /// Dart 側 uniform 的最大 float 索引。
  static const int uniformMaxIndex = _U.surge;

  /// shader 是否已經成功載入並可用。
  static bool get isAvailable => _program != null;

  /// 是否正在載入中（首幀會走 fallback，載入完自動切換）。
  static bool get isLoading => _loading != null && _program == null;

  /// 載入 shader 資產。可重複呼叫：第一次真正載入，之後立即返回同一個 Future。
  static Future<void> load() {
    if (_program != null) return Future<void>.value();
    final existing = _loading;
    if (existing != null) return existing;
    final future = _load();
    _loading = future;
    return future;
  }

  static Future<void> _load() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(kOceanShaderAsset);
      _program = program;
      loadError = null;
      failReason = null;
    } catch (error) {
      // 舊機 GPU 限制／後端不支援／資產缺失／編譯失敗：全部走 fallback，永不 rethrow。
      _program = null;
      loadError = error.toString();
      failReason = classifyLoadError(error);
      debugPrint('[OCEAN] FragmentProgram.fromAsset 失敗，改用 2D fallback：$error');
    }
  }

  /// 把 `fromAsset` 的異常分類成四個機器可讀原因之一（ARCH §7.12）。
  static String classifyLoadError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('not found') ||
        text.contains('unable to load asset') ||
        text.contains('no such file') ||
        text.contains('asset')) {
      return kOceanFailAssetMissing;
    }
    if (text.contains('compile') ||
        text.contains('impeller') ||
        text.contains('skia') ||
        text.contains('shader')) {
      return kOceanFailCompileError;
    }
    return kOceanFailUnsupported;
  }

  /// 建立一個 `FragmentShader`（每個 `OceanBand` 自己持有一個，由呼叫方 dispose）。
  ///
  /// 未就緒時回傳 `null`，呼叫方據此走 fallback。
  static ui.FragmentShader? createShader() {
    final program = _program;
    if (program == null) return null;
    try {
      return program.fragmentShader();
    } catch (error) {
      loadError = error.toString();
      failReason = classifyLoadError(error);
      debugPrint('[OCEAN] fragmentShader() 失敗，改用 2D fallback：$error');
      return null;
    }
  }

  /// 波浪時間（秒）：**必須單調遞增，不可取模**。
  ///
  /// frag 內 9 條波的角頻率 `w = sqrt(G * k)` 各不相同（k 由 0.14 起每級 ×1.52），
  /// 相位不可能同時回到原點，所以 `% 8` 會在每個 8 秒邊界令整片海瞬移一次（T04-AC6）。
  /// 呢個函式就係「8 秒跳變」的回歸鎖：只寫在註解裡，下次還是會有人加回 `% 8000`。
  static double waveTimeSeconds(int elapsedMs) => elapsedMs / 1000.0;

  /// 由帶的實際 size 算出 pitch，令海平線（`rd.y == 0`）落在帶高的 [kOceanHorizonRatio]。
  ///
  /// 推導：`ndc.y' = 1 - 2 * fragY/h`（向上為正），`rd.y ≈ sinP + ndc.y' * vertHalfTan * cosP`。
  /// 令 `rd.y = 0` → `ndc.y' = -pitch / vertHalfTan`；而海平線在 45% 時 `ndc.y' = 1 - 2*0.45 = 0.1`。
  /// 所以 `pitch = -(1 - 2 * ratio) * vertHalfTan`（464×96 時 = -0.0213）。
  ///
  /// **因為 aspect 隨帶寬高變化，pitch 必須每次繪製用實際 size 算出，唔可以硬編 -0.021。**
  static double pitchForSize(ui.Size size) {
    final aspect = size.width / math.max(size.height, 1.0);
    final vertHalfTan = kOceanHorizHalfTan / aspect;
    return -(1.0 - 2.0 * kOceanHorizonRatio) * vertHalfTan;
  }

  /// 把 30 個 float 一次過餵入 shader（見 [_U] 佈局表）。
  ///
  /// - [elapsed]：真實經過秒數（**單調遞增，不取模**）。同時餵 `uTime`（波浪相位、
  ///   雲層漂移、衝擊環紋理）與相機上下浮沉的 `sin(elapsed * 1.3)`。
  /// - [camDip]：浪湧時的鏡頭下沉量（`sin(pπ) * 0.75`）
  /// - [waveProgress]：浪湧進行度 p ∈ [0,1]；**靜止時必須傳 -1.0**
  /// - [surgeIntensity]：`sin(pπ) * 1.35`；靜止時 0.0
  static void bindUniforms(
    ui.FragmentShader shader, {
    required ui.Size size,
    required double elapsed,
    required double camDip,
    required double waveProgress,
    required double surgeIntensity,
    required OceanShaderPreset preset,
  }) {
    final width = math.max(size.width, 1.0);
    final height = math.max(size.height, 1.0);

    // ── 太陽方向（移植 JS 443-447：度 → 弧度 → 單位向量）──
    final elevRad = preset.sunElev * math.pi / 180.0;
    final azimRad = preset.sunAzimuth * math.pi / 180.0;
    final sunX = math.sin(azimRad) * math.cos(elevRad);
    final sunY = math.sin(elevRad);
    final sunZ = math.cos(azimRad) * math.cos(elevRad);

    // ── 相機（移植 JS 449-452）──
    final camY = math.max(1.2, 2.5 - camDip + math.sin(elapsed * 1.3) * 0.18);
    final pitch = pitchForSize(ui.Size(width, height));
    final cosP = math.cos(pitch);
    final sinP = math.sin(pitch);

    shader.setFloat(_U.res, width);
    shader.setFloat(_U.res + 1, height);

    shader.setFloat(_U.time, elapsed);

    shader.setFloat(_U.camPos, 0.0);
    shader.setFloat(_U.camPos + 1, camY);
    shader.setFloat(_U.camPos + 2, 0.0);

    shader.setFloat(_U.camFwd, 0.0);
    shader.setFloat(_U.camFwd + 1, sinP);
    shader.setFloat(_U.camFwd + 2, -cosP);

    shader.setFloat(_U.camRight, -1.0);
    shader.setFloat(_U.camRight + 1, 0.0);
    shader.setFloat(_U.camRight + 2, 0.0);

    shader.setFloat(_U.camUp, 0.0);
    shader.setFloat(_U.camUp + 1, cosP);
    shader.setFloat(_U.camUp + 2, sinP);

    shader.setFloat(_U.windSpeed, preset.windSpeed);
    shader.setFloat(_U.swellHs, preset.swellHs);
    shader.setFloat(_U.choppiness, preset.choppiness);
    shader.setFloat(_U.turbidity, preset.turbidity);
    shader.setFloat(_U.foam, preset.foam);

    shader.setFloat(_U.sunDir, sunX);
    shader.setFloat(_U.sunDir + 1, sunY);
    shader.setFloat(_U.sunDir + 2, sunZ);

    shader.setFloat(_U.haze, preset.haze);
    shader.setFloat(_U.clouds, preset.clouds);
    shader.setFloat(_U.exposure, preset.exposure);
    shader.setFloat(_U.bloom, preset.bloom);
    shader.setFloat(_U.nightGlow, preset.nightGlow);

    shader.setFloat(_U.waveProgress, waveProgress);
    shader.setFloat(_U.surge, surgeIntensity);
  }
}
