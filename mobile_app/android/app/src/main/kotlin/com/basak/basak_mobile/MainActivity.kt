package com.basak.basak_mobile

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

// A FragmentActivity: the fingerprint / face prompt (local_auth) needs one.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Signing in with a fingerprint or face (lib/.../biometric_device.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "basak/biometrics")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hardware" -> result.success(biometricHardware())
                    "enrollmentMark" -> result.success(enrollmentMark(call.argument<Boolean>("renew") == true))
                    else -> result.notImplemented()
                }
            }
        // Notification settings screen of this app (lib/.../notification_platform.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "basak/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openSettings" -> result.success(openNotificationSettings())
                    // This app's own page in Settings, where its permissions are (the camera).
                    "openAppSettings" -> result.success(openAppSettings())
                    // Android shows no number on the icon; its dot follows the tray.
                    "setBadge" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
    }

    private fun openAppSettings(): Boolean = try {
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (e: Exception) {
        false
    }

    /** Which biometric sensors the phone has: the app names its sign-in after them. */
    private fun biometricHardware(): Map<String, Boolean> = mapOf(
        "fingerprint" to packageManager.hasSystemFeature("android.hardware.fingerprint"),
        "face" to packageManager.hasSystemFeature("android.hardware.biometrics.face"),
        "iris" to packageManager.hasSystemFeature("android.hardware.biometrics.iris"),
    )

    /**
     * Tells whether a fingerprint or face was enrolled since the sign-in was
     * switched on. A keystore key made then ([renew]) is invalidated by the
     * system on a new enrolment; the key is never used to encrypt anything.
     * "valid", "invalidated", "missing" (the phone removed it, or it was never
     * made), or null when the phone cannot say (no strong biometric enrolled).
     */
    private fun enrollmentMark(renew: Boolean): String? {
        val alias = "basak_biometric_enrollment"
        return try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            if (renew) {
                if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias)
                val spec = KeyGenParameterSpec.Builder(
                    alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_CBC)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_PKCS7)
                    .setUserAuthenticationRequired(true)
                    .setInvalidatedByBiometricEnrollment(true)
                    .build()
                KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
                    init(spec)
                    generateKey()
                }
            }
            val key = keyStore.getKey(alias, null) as? SecretKey ?: return "missing"
            try {
                Cipher.getInstance("AES/CBC/PKCS7Padding").init(Cipher.ENCRYPT_MODE, key)
                "valid"
            } catch (e: KeyPermanentlyInvalidatedException) {
                "invalidated"
            }
        } catch (e: Exception) {
            null
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
