package com.shiftalarm.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 應用程式主入口 Activity，負責註冊 Flutter 鬧鐘 MethodChannel。
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AlarmChannelHandler.CHANNEL_NAME
        ).setMethodCallHandler(AlarmChannelHandler(this))
    }
}
