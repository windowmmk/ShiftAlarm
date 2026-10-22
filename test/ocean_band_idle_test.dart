import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftalarm/theme/app_theme.dart';
import 'package:shiftalarm/ui/widgets/ocean_band.dart';
import 'package:shiftalarm/ui/widgets/ocean_shader_controller.dart';

/// v3.6.1 永久防線：天色欄**收合到 0 之後唔可以再燒 30fps**。
///
/// 背景：鍵盤彈起時 `CalendarLayout` 會把 `bandHeight` 壓到 0（用戶要求
/// 「點開排班開始輸入文字後…把頂部的天色欄完全壓縮為0」）。
/// 如果 `OceanBand` 仍然每秒 30 次 `Timer.periodic` 去更新一個 0px 高的
/// shader 幀，用戶打字時就係白白燒 CPU／電 —— 呢個測試就係鎖住「真係停咗」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(GlobalKey<OceanBandState> key,
      {required bool visible, required double height}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: height,
            child: OceanBand(key: key, visible: visible, height: height),
          ),
        ),
      ),
    );
  }

  testWidgets('帶高 96 → 收合到 0：30fps Timer 由「跑」變「停」，再展開會復活', (tester) async {
    // shader 載入要真 async（fake async 下 await 唔會完成）
    await tester.runAsync(() async {
      await OceanShaderController.load();
    });
    final hasShader = OceanShaderController.isAvailable;
    if (!hasShader) {
      // 部分 CI 的 flutter_tester 冇 runtime effect 後端：著色器路徑跑唔到，
      // 但「收合要停」嘅斷言同 shader 可唔可用無關，照樣要驗。
      // ignore: avoid_print
      print('[M] ocean.idle shader 不可用（${OceanShaderController.loadError}），'
          '只驗「收合必停」');
    }

    final key = GlobalKey<OceanBandState>();

    // ① 可見態
    await tester.pumpWidget(host(key, visible: true, height: kOceanBandHeight));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    if (hasShader) {
      expect(key.currentState!.debugFrameTimerRunning, isTrue,
          reason: '帶有高度時應該跑 30fps（否則天色欄會凍結）');
    }

    // ② 收合到 0（= 鍵盤彈起）
    await tester.pumpWidget(host(key, visible: false, height: 0));
    await tester.pump();
    expect(key.currentState!.debugFrameTimerRunning, isFalse,
        reason: '高度 0 時仍然燒 30fps（用戶打字時唔應該燒電）');

    // ③ 再展開：要復活，唔可以一停就永停
    await tester.pumpWidget(host(key, visible: true, height: kOceanBandHeight));
    await tester.pump();
    if (hasShader) {
      expect(key.currentState!.debugFrameTimerRunning, isTrue,
          reason: '重新展開時 30fps 要復活');
    }

    // ④ visible=false 但 height 仍然係 96（被可見性收合）：一樣要停
    await tester.pumpWidget(host(key, visible: false, height: kOceanBandHeight));
    await tester.pump();
    expect(key.currentState!.debugFrameTimerRunning, isFalse,
        reason: 'visible=false 時一樣唔應該跑 30fps');
  });

  testWidgets('一開始就係 0 高：由頭到尾都唔會起 30fps Timer', (tester) async {
    await tester.runAsync(() async {
      await OceanShaderController.load();
    });

    final key = GlobalKey<OceanBandState>();
    await tester.pumpWidget(host(key, visible: false, height: 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(key.currentState!.debugFrameTimerRunning, isFalse,
        reason: '0 高的天色欄唔應該起 Timer');
  });
}
