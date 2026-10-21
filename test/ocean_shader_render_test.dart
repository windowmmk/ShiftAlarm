import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftalarm/ui/widgets/ocean_presets.dart';
import 'package:shiftalarm/ui/widgets/ocean_shader_controller.dart';

/// v3.5 海洋著色器的「真係畫得出」煙霧測試。
///
/// 呢個測試守 §7.9 的 **C 類失敗**（shader 編譯成功、執行成功，但畫面全黑／上下倒轉／
/// uniform 索引串位）—— 呢類失敗冇任何異常可以捕捉，只有離屏讀回像素才驗得到。
///
/// 用 464×96（實際帶的尺寸）離屏渲染一次，然後：
///   ① 唔可以係洋紅底（代表 shader 完全冇輸出）或全黑；
///   ② 海平線（亮度突變列）必須落在帶高的 45% 附近 —— 同時驗證「y 軸反轉」有冇做；
///   ③ 夜更的青藍色（藍眼淚）像素必須集中在下半（水面）；
///   ④ 夜更整體必須明顯比正午暗（驗 uniform 索引冇串位）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const int w = 464;
  const int h = 96;

  /// 離屏渲染一次，回傳 RGBA 像素。
  Future<List<int>> render(OceanShaderPreset preset) async {
    final shader = OceanShaderController.createShader();
    expect(shader, isNotNull,
        reason: 'shader 未就緒：${OceanShaderController.loadError}');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // 先鋪洋紅底：若 shader 完全冇輸出，讀回就會係洋紅
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 464, 96),
      Paint()..color = const Color(0xFFFF00FF),
    );
    OceanShaderController.bindUniforms(
      shader!,
      size: const Size(464, 96),
      elapsed: 1.0,
      camDip: 0.0,
      waveProgress: -1.0,
      surgeIntensity: 0.0,
      preset: preset,
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 464, 96),
      Paint()..shader = shader,
    );
    final image = await recorder.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    shader.dispose();
    image.dispose();
    return data!.buffer.asUint8List().toList();
  }

  int pixelAt(List<int> rgba, int x, int y) {
    final i = (y * w + x) * 4;
    return (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
  }

  double rowLuma(List<int> rgba, int y) {
    var sum = 0.0;
    for (int x = 0; x < w; x += 2) {
      final p = pixelAt(rgba, x, y);
      sum += ((p >> 16) & 0xFF) + ((p >> 8) & 0xFF) + (p & 0xFF);
    }
    return sum / (w / 2);
  }

  test('shader 畫得出、方向正確、uniform 索引冇串位', () async {
    await OceanShaderController.load();
    if (!OceanShaderController.isAvailable) {
      // 呢個環境冇 runtime effect 後端（部分 CI 的 flutter_tester 會係咁）：
      // 唔算回歸，跳過即可；真機／Web 的畫質驗證另外做。
      markTestSkipped(
        '此環境不支援 runtime effect：${OceanShaderController.loadError}',
      );
      return;
    }

    final midday = await render(OceanShaderPreset.midday);

    // ① 唔可以係洋紅底，亦唔可以全黑
    final top = pixelAt(midday, w ~/ 2, 2);
    final bottom = pixelAt(midday, w ~/ 2, h - 3);
    expect(top, isNot(0xFF00FF), reason: '頂部仍係洋紅底 → shader 冇輸出');
    expect(bottom, isNot(0xFF00FF), reason: '底部仍係洋紅底 → shader 冇輸出');
    expect(top | bottom, isNot(0), reason: '整條帶全黑 → 靜默畫錯（C 類失敗）');

    // ② 海平線（相鄰兩行最大亮度突變）必須落在 45% 附近 = row 43
    var bestJump = -1.0;
    var horizonRow = -1;
    for (int y = 1; y < h; y++) {
      final jump = (rowLuma(midday, y) - rowLuma(midday, y - 1)).abs();
      if (jump > bestJump) {
        bestJump = jump;
        horizonRow = y;
      }
    }
    expect(
      horizonRow,
      inInclusiveRange(40, 48),
      reason: '海平線應在 45%（row≈43）；若喺 row≈53 就代表 y 軸冇反轉（畫面上下倒轉）',
    );

    // ③ 夜更的藍眼淚必須集中在水面（下半）
    final night = await render(OceanShaderPreset.night);
    int cyanPixels(int y0, int y1) {
      var count = 0;
      for (int y = y0; y < y1; y++) {
        for (int x = 0; x < w; x++) {
          final p = pixelAt(night, x, y);
          final r = (p >> 16) & 0xFF;
          final b = p & 0xFF;
          if (b > 80 && b > r + 30) count++;
        }
      }
      return count;
    }

    final cyanTop = cyanPixels(0, 38);
    final cyanBottom = cyanPixels(58, h);
    expect(
      cyanBottom,
      greaterThan(cyanTop * 5),
      reason: '青藍色（藍眼淚／月光倒影）應集中在水面（下半），'
          'top=$cyanTop bottom=$cyanBottom',
    );

    // ④ 夜更應該明顯比正午暗（若 uniform 索引串位，兩者會接近）
    var middaySkyLuma = 0.0;
    var nightSkyLuma = 0.0;
    for (int y = 2; y < 36; y++) {
      middaySkyLuma += rowLuma(midday, y);
      nightSkyLuma += rowLuma(night, y);
    }
    expect(
      nightSkyLuma,
      lessThan(middaySkyLuma * 0.6),
      reason: '夜更天空明顯比正午暗（midday=$middaySkyLuma night=$nightSkyLuma）',
    );
  });
}
