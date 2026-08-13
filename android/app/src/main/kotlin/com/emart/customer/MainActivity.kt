package com.emart.customer

import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    // Settings.Secure.ANDROID_ID, not device_info_plus's AndroidDeviceInfo.id
    // (that field is Build.ID, the OS firmware build tag - identical across
    // every device on the same firmware build, not a per-device identifier).
    // ANDROID_ID is scoped per app-signing-key + user + physical device, so
    // it stays stable across app data clears/reinstalls (same signing key)
    // but genuinely differs between two different physical devices - which
    // is what DeviceSessionService's one-device-session gate needs.
    private val androidIdChannel = "com.quickdash.customer/android_id"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, androidIdChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "getAndroidId") {
                    result.success(Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID))
                } else {
                    result.notImplemented()
                }
            }
    }
}
