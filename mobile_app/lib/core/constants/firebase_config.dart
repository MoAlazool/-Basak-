import 'package:flutter/foundation.dart';

/// The Firebase client identifiers push notifications need, passed at build
/// time with `--dart-define` (the same way as [SupabaseConfig]). They identify
/// the app to Firebase and are not secrets; the keys that may *send* a push
/// (service account, APNs key) live on the server only.
///
/// Without them the app has no push: nothing is asked of the user and the
/// in-app Notification Center keeps working on its own.
class FirebaseConfig {
  static const String projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const String androidApiKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
  static const String iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const String iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');

  /// Optional: only when the Firebase iOS app is registered under another
  /// bundle id than the one this build runs with.
  static const String iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');

  /// This build's push configuration, or null when it has none.
  static PushConfig? get current => PushConfig.resolve(
        platform: kIsWeb ? null : defaultTargetPlatform,
        projectId: projectId,
        messagingSenderId: messagingSenderId,
        androidAppId: androidAppId,
        androidApiKey: androidApiKey,
        iosAppId: iosAppId,
        iosApiKey: iosApiKey,
        iosBundleId: iosBundleId,
      );
}

/// What Firebase is initialised with on this phone.
class PushConfig {
  /// 'android' | 'ios', as the server stores it with the device.
  final String platform;
  final String projectId;
  final String messagingSenderId;
  final String appId;
  final String apiKey;
  final String? iosBundleId;

  const PushConfig({
    required this.platform,
    required this.projectId,
    required this.messagingSenderId,
    required this.appId,
    required this.apiKey,
    this.iosBundleId,
  });

  /// Null unless every value this [platform] needs is present (and the
  /// platform is a phone): a half-configured build has no push at all.
  static PushConfig? resolve({
    required TargetPlatform? platform,
    required String projectId,
    required String messagingSenderId,
    required String androidAppId,
    required String androidApiKey,
    required String iosAppId,
    required String iosApiKey,
    String iosBundleId = '',
  }) {
    final (name, appId, apiKey) = switch (platform) {
      TargetPlatform.android => ('android', androidAppId, androidApiKey),
      TargetPlatform.iOS => ('ios', iosAppId, iosApiKey),
      _ => ('', '', ''),
    };
    final values = [name, projectId, messagingSenderId, appId, apiKey];
    if (values.any((value) => value.trim().isEmpty)) return null;
    return PushConfig(
      platform: name,
      projectId: projectId.trim(),
      messagingSenderId: messagingSenderId.trim(),
      appId: appId.trim(),
      apiKey: apiKey.trim(),
      iosBundleId: name == 'ios' && iosBundleId.trim().isNotEmpty ? iosBundleId.trim() : null,
    );
  }
}
