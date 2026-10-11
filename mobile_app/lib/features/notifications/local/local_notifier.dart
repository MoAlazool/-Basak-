import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../data/notifications_repository.dart';
import '../push/notification_platform.dart';

/// The notifications the phone shows by itself, with no push server: the vote
/// reminders, the two subscription dates, and inbox notifications the app
/// learnt about while it was running. They share one plugin, so each kind
/// keeps to its own numbers and never cancels another's.
class LocalNotifier {
  LocalNotifier._();

  static final plugin = FlutterLocalNotificationsPlugin();

  /// Vote reminders: [voteFirst] up to, not including, [voteFirst] + [voteMax].
  /// iOS keeps 64 pending notifications in all; the rest is left for the others.
  static const voteFirst = 0;
  static const voteMax = 56;

  static const subscriptionExpiring = 100;
  static const subscriptionExpired = 101;

  /// Inbox notifications are numbered from here, by their id.
  static const _inboxFirst = 1000;
  static const _inboxSpan = 1 << 30;

  /// A notification of this app was tapped (see [payloadOf]).
  static void Function(Map<String, String> data)? onTap;

  static tz.Location? _cairo;
  static Future<bool>? _starting;
  static bool _askedPermission = false;

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Company times are Cairo times, wherever the phone is set.
  static tz.Location get cairo => _cairo!;

  /// Starts the plugin, once. False where there are no notifications at all.
  static Future<bool> ready() async {
    if (!supported) return false;
    return _starting ??= _start();
  }

  static Future<bool> _start() async {
    try {
      tz_data.initializeTimeZones();
      _cairo = tz.getLocation('Africa/Cairo');
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_basak'),
          // Asked when there is a first reminder to plan, not at launch.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) => _tapped(response.payload),
      );
      return true;
    } catch (error) {
      debugPrint('Local notifications: $error');
      _starting = null;
      return false;
    }
  }

  /// The notification whose tap started the app, when that is how it started.
  static Future<void> handleLaunch() async {
    if (!await ready()) return;
    try {
      final launch = await plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) _tapped(launch!.notificationResponse?.payload);
    } catch (error) {
      debugPrint('Local notifications: launch: $error');
    }
  }

  static void _tapped(String? payload) {
    final data = dataOf(payload);
    if (data.isNotEmpty) onTap?.call(data);
  }

  /// What a tap carries: ids and the route only, as a push does.
  static String payloadOf(Map<String, String> data) => jsonEncode(data);

  @visibleForTesting
  static Map<String, String> dataOf(String? payload) {
    if (payload == null || payload.isEmpty) return const {};
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String) entry.key as String: entry.value as String,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Whether the system lets the app show notifications. With [ask], Android
  /// 13+ and iOS show their prompt once; a refusal is respected.
  static Future<bool> permitted({bool ask = false}) async {
    if (!await ready()) return false;
    try {
      final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        if (await android.areNotificationsEnabled() == true) return true;
        if (!ask || _askedPermission) return false;
        _askedPermission = true;
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        // Shows the system prompt the first time only.
        if (ask) return await ios.requestPermissions(alert: true, sound: true) ?? false;
        return (await ios.checkPermissions())?.isEnabled ?? false;
      }
    } catch (error) {
      debugPrint('Local notifications: permission: $error');
    }
    return false;
  }

  /// Cancels the planned notifications numbered [first] up to, not including,
  /// [first] + [count], and no others.
  static Future<void> cancelRange(int first, int count) async {
    if (!await ready()) return;
    for (final request in await plugin.pendingNotificationRequests()) {
      if (inRange(request.id, first, count)) await plugin.cancel(id: request.id);
    }
  }

  @visibleForTesting
  static bool inRange(int id, int first, int count) => id >= first && id < first + count;

  /// Everything of the account that is leaving this phone: what is planned
  /// and what is still in the tray.
  static Future<void> clear() async {
    if (await ready()) await plugin.cancelAll();
  }

  /// The number an inbox notification is shown under: the same one each time,
  /// so showing it twice replaces it instead of adding a second.
  @visibleForTesting
  static int inboxId(String notificationId) {
    var hash = 0;
    for (final unit in notificationId.codeUnits) {
      hash = (hash * 31 + unit) % _inboxSpan;
    }
    return _inboxFirst + hash;
  }

  static NotificationDetails detailsFor(NotificationCategory category, {bool urgent = false}) {
    final channel = NotificationPlatform.channels.firstWhere(
      (c) => c.id == NotificationPlatform.channelId(category),
      orElse: () => NotificationPlatform.channels.last,
    );
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: channel.importance,
        priority: urgent ? Priority.high : Priority.defaultPriority,
        icon: 'ic_stat_basak',
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  /// Shows an inbox notification in the system tray now. Never asks for
  /// permission and never throws. False when it could not be shown.
  static Future<bool> showInbox(AppNotification notification) async {
    try {
      if (!await permitted()) return false;
      await plugin.show(
        id: inboxId(notification.id),
        title: notification.title.isNotEmpty ? notification.title : notification.body,
        body: notification.title.isNotEmpty ? notification.body : null,
        notificationDetails: detailsFor(notification.category, urgent: notification.highPriority),
        payload: payloadOf(tapData(notification)),
      );
      return true;
    } catch (error) {
      debugPrint('Local notifications: show: $error');
      return false;
    }
  }

  /// Takes [notificationIds] out of the system tray, where this phone put them.
  static Future<void> dismissInbox(Iterable<String> notificationIds) async {
    try {
      if (!await ready()) return;
      for (final id in notificationIds) {
        await plugin.cancel(id: inboxId(id));
      }
    } catch (error) {
      debugPrint('Local notifications: dismiss: $error');
    }
  }

  /// The same fields a push of [notification] carries in its data.
  static Map<String, String> tapData(AppNotification notification) => {
        ...notification.data,
        'notification_id': notification.id,
        'type': notification.type,
        'category': notification.category.name,
      };
}
