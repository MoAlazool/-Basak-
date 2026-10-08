import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/notifications_repository.dart';

/// The few things notifications need from the phone itself.
class NotificationPlatform {
  NotificationPlatform._();

  /// Implemented in MainActivity.kt and AppDelegate.swift.
  static const _channel = MethodChannel('basak/notifications');

  /// The Android channel a push of [category] is shown on. The server sends
  /// the same id (`basak_<category>`) with every push.
  static String channelId(NotificationCategory category) => 'basak_${category.name}';

  /// The channels as the user sees them in the system settings.
  static const channels = [
    AndroidNotificationChannel(
      'basak_subscription',
      'الاشتراك والدفع',
      description: 'مراجعة الإيصال، تفعيل الاشتراك وقرب انتهائه',
      importance: Importance.defaultImportance,
    ),
    AndroidNotificationChannel(
      'basak_transport',
      'حركة الباص',
      description: 'تأخير الباص، تحركه، وصوله أو إلغاء الرحلة',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      'basak_announcement',
      'إعلانات الشركة والمشرف',
      description: 'رسائل إدارة الشركة ومشرف الباص',
      importance: Importance.defaultImportance,
    ),
  ];

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Creates the push channels (Android 8+). Creating one that exists changes
  /// nothing, so this runs on every start; the vote-reminder channel is not touched.
  static Future<void> createChannels() async {
    if (!_android) return;
    try {
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      for (final channel in channels) {
        await android?.createNotificationChannel(channel);
      }
    } catch (error) {
      debugPrint('Push: channels not created: $error');
    }
  }

  /// Opens this app's notification page in the system settings.
  static Future<bool> openSystemSettings() async {
    if (!_android && !_ios) return false;
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Shows [count] on the app icon (iOS). Android has no number to set: its
  /// launcher dot follows the notifications still in the tray.
  static Future<void> setBadge(int count) async {
    if (!_ios) return;
    try {
      await _channel.invokeMethod<void>('setBadge', count);
    } catch (_) {}
  }
}
