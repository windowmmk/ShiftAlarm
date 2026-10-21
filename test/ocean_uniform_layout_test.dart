import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftalarm/ui/widgets/ocean_shader_controller.dart';

/// v3.5 海洋著色器的 uniform 佈局回歸測試（**唔需要載入 shader**，純常數／文字斷言）。
///
/// 呢個測試守住 ARCH §3.5.2 個陷阱：
/// `impellerc` 會剔除「宣告但未被引用」嘅 uniform，令後面所有 float 索引整體前移 ——
/// 畫面會變得莫名奇妙但**唔會拋任何異常**。所以：
///   ① Dart 側 `_U` 的最大索引 + 1 必須恆等 30；
///   ② frag 內 19 個 uniform 必須逐個被引用；
///   ③ frag 宣告型別累加出來的 float 格數必須同 Dart 側一致。
void main() {
  /// frag 內 uniform 的宣告順序（必須與 `_U` 逐格一致）
  const List<String> expectedUniforms = <String>[
    'uResolution', // vec2 → 0,1
    'uTime', // 2
    'uCamPos', // vec3 → 3,4,5
    'uCamFwd', // vec3 → 6,7,8
    'uCamRight', // vec3 → 9,10,11
    'uCamUp', // vec3 → 12,13,14
    'uWindSpeed', // 15
    'uSwellHs', // 16
    'uChoppiness', // 17
    'uTurbidity', // 18
    'uFoam', // 19
    'uSunDir', // vec3 → 20,21,22
    'uHaze', // 23
    'uClouds', // 24
    'uExposure', // 25
    'uBloom', // 26
    'uNightGlow', // 27
    'uImportWaveProgress', // 28
    'uSurgeIntensity', // 29
  ];

  /// 讀 frag 並**先剝掉註解**再斷言。
  ///
  /// 唔剝註解就等於自證：有人宣告 `uniform float uFoo;` 而只在註解提過一次，
  /// 測試照樣綠，但 impellerc 照樣會剔除佢（索引前移、畫面錯亂但唔拋異常）。
  String readFrag() =>
      File('shaders/ocean.frag').readAsStringSync().replaceAll(
            RegExp(r'//[^\n]*'),
            '',
          );

  group('ocean.frag uniform 佈局', () {
    test('Dart 側 _U 的最大索引 + 1 == 30', () {
      expect(OceanShaderController.uniformMaxIndex, 29);
      expect(OceanShaderController.uniformFloatCount, 30);
      expect(OceanShaderController.uniformMaxIndex + 1, 30);
    });

    test('波浪時間必須單調遞增，不可取模（防 8 秒跳變 T04-AC6）', () {
      // 8 秒邊界兩側必須仍然遞增（若有人加回 % 8000，呢兩行會反轉）
      expect(
        OceanShaderController.waveTimeSeconds(7999),
        lessThan(OceanShaderController.waveTimeSeconds(8000)),
        reason: 'uTime 在 8 秒邊界被取模 → 整片海會瞬移回原點',
      );
      expect(
        OceanShaderController.waveTimeSeconds(15999),
        lessThan(OceanShaderController.waveTimeSeconds(16000)),
        reason: 'uTime 在 16 秒邊界被取模',
      );
      // 而且必須係真正的秒數（1ms = 0.001s）
      expect(
        OceanShaderController.waveTimeSeconds(8001) -
            OceanShaderController.waveTimeSeconds(8000),
        closeTo(0.001, 1e-9),
      );
      expect(OceanShaderController.waveTimeSeconds(0), 0.0);
    });

    test('frag 的 19 個 uniform 宣告順序與 Dart 側一致', () {
      final source = readFrag();
      final declared = RegExp(r'uniform\s+\w+\s+(\w+)\s*;')
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toList();

      expect(declared.length, 19, reason: 'uniform 數量凍結在 19 個（ARCH §3.5.6 條件 ③）');
      expect(declared, expectedUniforms);
    });

    test('由 frag 宣告型別累加的 float 格數 == Dart 側 30 格', () {
      final source = readFrag();
      final matches =
          RegExp(r'uniform\s+(vec2|vec3|float)\s+(\w+)\s*;').allMatches(source);

      int slots = 0;
      for (final match in matches) {
        final type = match.group(1)!;
        slots += switch (type) {
          'vec2' => 2,
          'vec3' => 3,
          _ => 1,
        };
      }

      expect(slots, 30);
      expect(slots, OceanShaderController.uniformFloatCount);
    });

    test('每個 uniform 都有被 body 引用（否則 impellerc 會剔除並令索引前移）', () {
      final source = readFrag();
      for (final name in expectedUniforms) {
        final occurrences = RegExp('\\b$name\\b').allMatches(source).length;
        expect(
          occurrences,
          greaterThanOrEqualTo(2),
          reason: '$name 只宣告但未被引用 —— impellerc 會剔除佢，令後面索引整體前移',
        );
      }
    });

    test('失敗原因只會落在 §7.12 允許的四個值（T06 驗收依賴）', () {
      const allowed = <String>{
        kOceanFailAssetMissing,
        kOceanFailUnsupported,
        kOceanFailCompileError,
        kOceanFailTimeout,
      };
      expect(allowed, hasLength(4));

      expect(
        OceanShaderController.classifyLoadError(
          Exception("Asset 'shaders/ocean.frag' not found"),
        ),
        kOceanFailAssetMissing,
      );
      expect(
        OceanShaderController.classifyLoadError(
          Exception('Failed to compile shader'),
        ),
        kOceanFailCompileError,
      );
      expect(
        OceanShaderController.classifyLoadError(StateError('backend gone')),
        kOceanFailUnsupported,
      );
      for (final reason in <String>[
        OceanShaderController.classifyLoadError(Exception('x')),
        OceanShaderController.classifyLoadError(StateError('y')),
      ]) {
        expect(allowed, contains(reason));
      }
    });
  });
}
