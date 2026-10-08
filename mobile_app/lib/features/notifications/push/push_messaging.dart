import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/firebase_config.dart';
import '../notification_router.dart';

/// Whether the system lets this app show notifications.
enum PushPermission {
  granted,

  /// Never asked: the system prompt can still be shown.
  notAsked,

  /// Refused, but the system may show its prompt again (Android).
  denied,

  /// Refused for good: only the system settings can switch it on.
  blocked,
}

/// A push as the app sees it: the visible text and the ids it carries.
class PushMessage {
  final String title;
  final String body;
  final Map<String, dynamic> data;

  const PushMessage({this.title = '', this.body = '', this.data = const {}});

  NotificationIntent get intent => NotificationIntent.fromPush(data);
  String? get notificationId => intent.notificationId;
}

/// The push service, as much of it as the app uses. Firebase in the real app;
/// a fake in tests; [DisabledPushMessaging] when the build has no push.
abstract interface class PushMessaging {
  /// False when this build has no push configuration: nothing below is called.
  bool get available;

  /// 'android' | 'ios'.
  String get platform;

  /// Connects to the push service. False when it could not be started.
  Future<bool> initialize();

  Future<PushPermission> permission();

  /// Shows the system prompt (when the system still allows one).
  Future<PushPermission> requestPermission();

  /// This phone's push token; null when there is none (yet).
  Future<String?> token();

  /// Makes the current token stop working; the next [token] is a new one.
  Future<void> deleteToken();

  Stream<String> get onTokenRefresh;

  /// Arrived while the app is open (the system shows nothing by itself).
  Stream<PushMessage> get onForegroundMessage;

  /// A system notification was tapped with the app in the background.
  Stream<PushMessage> get onMessageOpened;

  /// The notification whose tap started the app, if that is how it started.
  Future<PushMessage?> initialMessage();
}

/// This build has no push (no Firebase identifiers were passed to it).
class DisabledPushMessaging implements PushMessaging {
  const DisabledPushMessaging();

  @override
  bool get available => false;
  @override
  String get platform => '';
  @override
  Future<bool> initialize() async => false;
  @override
  Future<PushPermission> permission() async => PushPermission.blocked;
  @override
  Future<PushPermission> requestPermission() async => PushPermission.blocked;
  @override
  Future<String?> token() async => null;
  @override
  Future<void> deleteToken() async {}
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Stream<PushMessage> get onForegroundMessage => const Stream.empty();
  @override
  Stream<PushMessage> get onMessageOpened => const Stream.empty();
  @override
  Future<PushMessage?> initialMessage() async => null;
}

/// Runs in its own isolate when a push arrives with the app in the background
/// or closed. The system already shows the notification and the inbox is read
/// from the server when the app opens, so there is nothing to do here.
@pragma('vm:entry-point')
Future<void> basakPushBackgroundHandler(RemoteMessage message) async {}

/// Firebase Cloud Messaging (and, through it, APNs on iOS), initialised from
/// the build's [PushConfig] instead of google-services.json / GoogleService-Info.plist.
class FirebasePushMessaging implements PushMessaging {
  final PushConfig config;

  FirebasePushMessaging(this.config);

  Future<bool>? _ready;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  bool get available => true;

  @override
  String get platform => config.platform;

  @override
  Future<bool> initialize() => _ready ??= _initialize();

  Future<bool> _initialize() async {
    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: config.apiKey,
          appId: config.appId,
          messagingSenderId: config.messagingSenderId,
          projectId: config.projectId,
          iosBundleId: config.iosBundleId,
        ),
      );
      FirebaseMessaging.onBackgroundMessage(basakPushBackgroundHandler);
      // While the app is open it shows its own banner; iOS must not add a
      // second, system one on top. The badge still follows the server.
      await _messaging.setForegroundNotificationPresentationOptions(
          alert: false, badge: true, sound: false);
      return true;
    } catch (error) {
      debugPrint('Push: Firebase could not be started: $error');
      return false;
    }
  }

  @override
  Future<PushPermission> permission() async {
    if (!await initialize()) return PushPermission.blocked;
    return _permission((await _messaging.getNotificationSettings()).authorizationStatus);
  }

  @override
  Future<PushPermission> requestPermission() async {
    if (!await initialize()) return PushPermission.blocked;
    final settings = await _messaging.requestPermission(alert: true, badge: true, sound: true);
    return _permission(settings.authorizationStatus);
  }

  PushPermission _permission(AuthorizationStatus status) => switch (status) {
        AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushPermission.granted,
        AuthorizationStatus.notDetermined => PushPermission.notAsked,
        // iOS asks once only; Android 13+ may show its prompt a second time.
        AuthorizationStatus.denied =>
          config.platform == 'ios' ? PushPermission.blocked : PushPermission.denied,
        _ => PushPermission.blocked,
      };

  @override
  Future<String?> token() async {
    if (!await initialize()) return null;
    try {
      // iOS hands out an FCM token only once APNs has given its own (never on
      // a simulator, or without the Push Notifications capability).
      if (config.platform == 'ios' && await _messaging.getAPNSToken() == null) return null;
      return await _messaging.getToken();
    } catch (error) {
      debugPrint('Push: no token: $error');
      return null;
    }
  }

  @override
  Future<void> deleteToken() async {
    if (await initialize()) await _messaging.deleteToken();
  }

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<PushMessage> get onForegroundMessage => FirebaseMessaging.onMessage.map(_message);

  @override
  Stream<PushMessage> get onMessageOpened => FirebaseMessaging.onMessageOpenedApp.map(_message);

  @override
  Future<PushMessage?> initialMessage() async {
    if (!await initialize()) return null;
    final message = await _messaging.getInitialMessage();
    return message == null ? null : _message(message);
  }

  static PushMessage _message(RemoteMessage message) => PushMessage(
        title: message.notification?.title ?? '',
        body: message.notification?.body ?? '',
        data: message.data,
      );
}
