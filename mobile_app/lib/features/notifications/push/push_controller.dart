import 'dart:async';

import 'package:flutter/foundation.dart';

import '../notification_router.dart';
import 'push_messaging.dart';

/// The server side of a push device (register_push_device / unregister_push_device).
abstract interface class PushDeviceApi {
  Future<void> register({
    required String installationId,
    required String platform,
    required String token,
    required String locale,
    required String appVersion,
  });

  Future<void> unregister(String installationId);
}

/// Keeps this phone's push token attached to whoever is signed in, and to
/// nobody else, and passes pushes on to the app: taps to the router, messages
/// that arrive while the app is open to the banner.
class PushController {
  final PushMessaging messaging;
  final PushDeviceApi devices;
  final NotificationRouter router;
  final Future<String> Function() installationId;
  final Future<String> Function() appVersion;
  final String? Function() currentUserId;

  /// A push arrived while the app is open.
  final void Function(PushMessage message) onForeground;
  final String locale;

  PushController({
    required this.messaging,
    required this.devices,
    required this.router,
    required this.installationId,
    required this.appVersion,
    required this.currentUserId,
    required this.onForeground,
    this.locale = 'ar',
  });

  static const _serverTimeout = Duration(seconds: 10);
  static const _detachTimeout = Duration(seconds: 3);

  Future<bool>? _started;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// What the server was last told: this token belongs to this account.
  ({String userId, String token})? _attached;

  /// [detach] already ran for the session that is ending (an ordinary sign-out).
  bool _detached = false;
  Future<void> _queue = Future.value();

  bool get available => messaging.available;

  /// Connects to the push service and starts listening. Safe to call again.
  /// Never asks for permission: that only happens when the user agrees to.
  Future<bool> start() => _started ??= _start();

  Future<bool> _start() async {
    if (!messaging.available || !await messaging.initialize()) return false;
    _subscriptions
      ..add(messaging.onTokenRefresh.listen((_) => sync()))
      ..add(messaging.onForegroundMessage.listen((message) {
        if (currentUserId() != null) onForeground(message);
      }))
      ..add(messaging.onMessageOpened.listen(_tapped));
    try {
      final initial = await messaging.initialMessage();
      if (initial != null) _tapped(initial);
    } catch (error) {
      debugPrint('Push: initial message: $error');
    }
    return true;
  }

  void _tapped(PushMessage message) => router.open(message.intent, NotificationTapSource.push);

  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }

  Future<PushPermission> permission() async =>
      await start() ? await messaging.permission() : PushPermission.blocked;

  /// Shows the system prompt and, when granted, attaches this phone at once.
  Future<PushPermission> requestPermission() async {
    if (!await start()) return PushPermission.blocked;
    final result = await messaging.requestPermission();
    if (result == PushPermission.granted) unawaited(sync());
    return result;
  }

  /// Attaches this phone's token to the signed-in account when it is not
  /// already: after sign-in, when permission is given, when the token changes
  /// and whenever the app comes back to the foreground. Never throws.
  Future<void> sync() => _serial(() async {
        final userId = currentUserId();
        if (userId == null || !await start()) return;
        if (await messaging.permission() != PushPermission.granted) return;
        final token = await messaging.token();
        if (token == null || token.isEmpty) return;
        if (_attached == (userId: userId, token: token)) return;
        await devices
            .register(
              installationId: await installationId(),
              platform: messaging.platform,
              token: token,
              locale: locale,
              appVersion: await appVersion(),
            )
            .timeout(_serverTimeout);
        _detached = false;
        // Signed out meanwhile: the sign-out's own detach comes right after.
        if (currentUserId() == userId) _attached = (userId: userId, token: token);
      });

  /// Before signing out, while the session is still valid: the server forgets
  /// this phone. Completes within a few seconds whatever happens, so signing
  /// out never waits for the network. If the server could not be told, the
  /// token itself is thrown away, so nothing meant for this account can still
  /// arrive here.
  Future<void> detach() {
    if (!messaging.available) return Future.value();
    final told = Completer<void>();
    _serial(() async {
      _attached = null;
      var confirmed = false;
      try {
        await devices.unregister(await installationId()).timeout(_detachTimeout);
        confirmed = true;
      } catch (error) {
        debugPrint('Push: detach: $error');
      }
      told.complete();
      if (!confirmed) await _discardToken();
      // Either way nothing of this account is left to clean up.
      _detached = true;
    }).whenComplete(() {
      if (!told.isCompleted) told.complete();
    });
    return told.future.timeout(_detachTimeout + const Duration(seconds: 1), onTimeout: () {});
  }

  /// The session ended. After an ordinary sign-out [detach] has already run;
  /// when it ended elsewhere (expired, revoked, account deleted) the server
  /// can no longer be asked, so the token is thrown away instead.
  Future<void> signedOut() {
    if (!messaging.available) return Future.value();
    return _serial(() async {
      _attached = null;
      final detached = _detached;
      _detached = false;
      if (!detached && _started != null) await _discardToken();
    });
  }

  Future<void> _discardToken() async {
    try {
      await messaging.deleteToken().timeout(_serverTimeout);
    } catch (error) {
      debugPrint('Push: token not discarded: $error');
    }
  }

  /// One change at a time, in order: an attach can never land after the
  /// detach that followed it.
  Future<void> _serial(Future<void> Function() work) {
    final next = _queue.then((_) => work()).catchError((Object error) {
      debugPrint('Push: $error');
    });
    _queue = next;
    return next;
  }
}
