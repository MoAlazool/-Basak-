package com.basak.basak_mobile

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Notification settings screen of this app (lib/.../notification_platform.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "basak/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openSettings" -> result.success(openNotificationSettings())
                    // Android shows no number on the icon; its dot follows the tray.
                    "setBadge" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
    }

    private fun openNotificationSettings(): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        }
        return try {
            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: Exception) {
            false
        }
    }
}
