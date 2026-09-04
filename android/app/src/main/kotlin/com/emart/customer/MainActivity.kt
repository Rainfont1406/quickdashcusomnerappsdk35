package com.emart.customer

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterFragmentActivity() {
    // Settings.Secure.ANDROID_ID, not device_info_plus's AndroidDeviceInfo.id
    // (that field is Build.ID, the OS firmware build tag - identical across
    // every device on the same firmware build, not a per-device identifier).
    // ANDROID_ID is scoped per app-signing-key + user + physical device, so
    // it stays stable across app data clears/reinstalls (same signing key)
    // but genuinely differs between two different physical devices - which
    // is what DeviceSessionService's one-device-session gate needs.
    private val androidIdChannel = "com.quickdash.customer/android_id"

    // Real installed-UPI-app detection (2026-08-31) - PaymentScreen's
    // "RECOMMENDED" / "PAY BY ANY UPI APP" tiles show whichever apps are
    // actually installed on THIS device (own name/icon, like Zomato/Swiggy),
    // instead of a fixed guess list. Relies on the <queries><intent> upi
    // scheme declaration already in AndroidManifest.xml for Android 11+
    // package visibility - without it, queryIntentActivities below silently
    // returns an empty list (not an error), so UpiAppsService's Dart side
    // falls back to the generic "Other UPI Apps" tile in that case.
    private val upiAppsChannel = "com.quickdash.customer/upi_apps"

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, upiAppsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledUpiApps" -> result.success(getInstalledUpiApps())
                    "launchUpiApp" -> {
                        val uri = call.argument<String>("uri")
                        val packageName = call.argument<String>("packageName")
                        if (uri == null || packageName == null) {
                            result.error("invalid_args", "uri and packageName are required", null)
                        } else {
                            result.success(launchUpiApp(uri, packageName))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Every installed app that resolves a upi://pay ACTION_VIEW intent,
    // deduped by package (an app can register more than one matching
    // activity). Each entry: packageName, appName (the app's own launcher
    // label, not a name we maintain), icon (PNG bytes of the app's own
    // launcher icon, or omitted if the drawable can't be rendered - Dart
    // falls back to a generic icon in that case).
    private fun getInstalledUpiApps(): List<Map<String, Any>> {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("upi://pay"))
        val resolveInfos = packageManager.queryIntentActivities(intent, 0)
        val seenPackages = HashSet<String>()
        val apps = ArrayList<Map<String, Any>>()
        for (info in resolveInfos) {
            val packageName = info.activityInfo?.packageName ?: continue
            if (!seenPackages.add(packageName)) continue
            val appName = try {
                info.loadLabel(packageManager).toString()
            } catch (e: Exception) {
                packageName
            }
            val app = HashMap<String, Any>()
            app["packageName"] = packageName
            app["appName"] = appName
            try {
                app["icon"] = drawableToPngBytes(info.loadIcon(packageManager))
            } catch (e: Exception) {
                // No icon - Dart side falls back to a generic UPI glyph.
            }
            apps.add(app)
        }
        return apps
    }

    private fun drawableToPngBytes(drawable: Drawable): ByteArray {
        // Read the BitmapDrawable's bitmap into a local val first rather than
        // smart-casting through drawable.bitmap inline - it's a Java getter,
        // not a stable Kotlin field, so the compiler won't smart-cast it
        // across the null-check and the read.
        val existingBitmap: Bitmap? = (drawable as? BitmapDrawable)?.bitmap
        val bitmap: Bitmap = existingBitmap ?: run {
            val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 96
            val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 96
            val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            bmp
        }
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }

    // Opens the given upi://pay link in ONE specific app (via Intent.setPackage),
    // instead of url_launcher's plain ACTION_VIEW which - when more than one UPI
    // app is installed - lets Android show its own chooser regardless of which
    // app tile the customer actually tapped. Returns false (not an exception) if
    // that package can no longer handle the intent (uninstalled since the list
    // was fetched, etc.) so the Dart side can fall back to the generic launcher.
    private fun launchUpiApp(uri: String, packageName: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
            intent.setPackage(packageName)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
