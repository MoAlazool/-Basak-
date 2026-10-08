import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/constants/firebase_config.dart';
import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/storage/snapshot_store.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/notifications/notification_router.dart';
import 'package:basak_mobile/features/notifications/push/device_store.dart';
import 'package:basak_mobile/features/notifications/push/notification_platform.dart';
import 'package:basak_mobile/features/notifications/push/push_controller.dart';
import 'package:basak_mobile/features/notifications/push/push_messaging.dart';
import 'package:basak_mobile/features/notifications/push/push_providers.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';

import 'support/notification_fakes.dart';

/// Signs out without Supabase, and records when.
class _FakeAuthRepository extends AuthRepository {
  final List<String> log;
  _FakeAuthRepository(this.log);

  @override
  Future<void> signOut() async => log.add('signOut');
}

/// Push: off when the build has no Firebase identifiers, and when it is on,
/// this phone's token belongs to whoever is signed in and to nobody else.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePushMessaging messaging;
  late FakePushDevices devices;
  late NotificationRouter router;
  late List<PushMessage> banners;
  String? signedIn;

  PushController controller({PushMessaging? using}) {
    final controller = PushController(
      messaging: using ?? messaging,
      devices: devices,
      router: router,
      installationId: () async => 'install-1',
      appVersion: () async => '1.0.6',
      currentUserId: () => signedIn,
      onForeground: banners.add,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    signedIn = 'user-a';
    messaging = FakePushMessaging();
    devices = FakePushDevices()..signedIn = () => signedIn;
    router = NotificationRouter(currentUserId: () => signedIn);
    banners = [];
  });

  group('configuration', () {
    PushConfig? resolve(TargetPlatform? platform,
            {String project = 'basak', String sender = '123', String androidApp = '1:123:android:abc',
            String androidKey = 'AIzaAndroid', String iosApp = '1:123:ios:abc', String iosKey = 'AIzaIos',
            String bundle = ''}) =>
        PushConfig.resolve(
          platform: platform,
          projectId: project,
          messagingSenderId: sender,
          androidAppId: androidApp,
          androidApiKey: androidKey,
          iosAppId: iosApp,
          iosApiKey: iosKey,
          iosBundleId: bundle,
        );

    test('this build was given no Firebase identifiers, so it has no push', () {
      expect(FirebaseConfig.current, isNull);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(pushMessagingProvider), isA<DisabledPushMessaging>());
      expect(container.read(pushMessagingProvider).available, isFalse);
    });

    test('each platform uses its own app id and key', () {
      final android = resolve(TargetPlatform.android)!;
      expect((android.platform, android.appId, android.apiKey), ('android', '1:123:android:abc', 'AIzaAndroid'));
      expect(android.iosBundleId, isNull);
      final ios = resolve(TargetPlatform.iOS, bundle: 'com.example.basak')!;
      expect((ios.platform, ios.appId, ios.apiKey), ('ios', '1:123:ios:abc', 'AIzaIos'));
      expect(ios.iosBundleId, 'com.example.basak');
    });

    test('a half-configured build has no push at all', () {
      expect(resolve(TargetPlatform.android, project: ''), isNull);
      expect(resolve(TargetPlatform.android, sender: ' '), isNull);
      expect(resolve(TargetPlatform.android, androidApp: ''), isNull);
      expect(resolve(TargetPlatform.iOS, iosKey: ''), isNull);
      // Only the other platform's values are missing: this one works.
      expect(resolve(TargetPlatform.android, iosApp: '', iosKey: ''), isNotNull);
      expect(resolve(TargetPlatform.macOS), isNull);
      expect(resolve(null), isNull);
    });

    test('without push nothing is started, asked or sent, and nothing breaks', () async {
      const disabled = DisabledPushMessaging();
      final push = controller(using: disabled);
      expect(push.available, isFalse);
      expect(await push.start(), isFalse);
      await push.sync();
      expect(await push.requestPermission(), PushPermission.blocked);
      await push.detach();
      await push.signedOut();
      expect(devices.log, isEmpty);
      expect(await disabled.token(), isNull);
      expect(await disabled.initialMessage(), isNull);
    });

    test('the Android channels are the ones the server names, transport being urgent', () {
      expect(NotificationPlatform.channels.map((c) => c.id),
          ['basak_subscription', 'basak_transport', 'basak_announcement']);
      for (final category in [
        NotificationCategory.subscription,
        NotificationCategory.transport,
        NotificationCategory.announcement,
      ]) {
        expect(NotificationPlatform.channels.map((c) => c.id), contains(NotificationPlatform.channelId(category)));
      }
      final transport = NotificationPlatform.channels.firstWhere((c) => c.id == 'basak_transport');
      expect(transport.importance.value,
          greaterThan(NotificationPlatform.channels.first.importance.value));
      expect(NotificationPlatform.channels.map((c) => c.id), isNot(contains('vote_reminders')));
    });
  });

  group('this phone and the signed-in account', () {
    test('after sign-in the token is attached, once', () async {
      final push = controller();
      await push.sync();
      expect(devices.log, ['register user-a token-1 ios ar 1.0.6']);
      expect(devices.devices['install-1'], (userId: 'user-a', token: 'token-1'));

      // Coming back to the app with the same token: nothing to say.
      await push.sync();
      await push.sync();
      expect(devices.log.length, 1);
      expect(messaging.prompts, 0, reason: 'attaching never asks for permission');
    });

    test('no permission, or no token yet: nothing is attached and nothing is asked', () async {
      messaging.granted = PushPermission.notAsked;
      final push = controller();
      await push.sync();
      expect(devices.log, isEmpty);
      expect(messaging.prompts, 0);

      // The user agrees in the app's own sheet: now the system is asked, and it attaches.
      expect(await push.requestPermission(), PushPermission.granted);
      await settle();
      expect(messaging.prompts, 1);
      expect(devices.log, ['register user-a token-1 ios ar 1.0.6']);

      // iOS has not handed out a token yet.
      devices.log.clear();
      messaging.currentToken = null;
      final waiting = controller();
      await waiting.sync();
      expect(devices.log, isEmpty);
    });

    test('a refused permission attaches nothing', () async {
      messaging
        ..granted = PushPermission.notAsked
        ..promptAnswer = PushPermission.blocked;
      final push = controller();
      expect(await push.requestPermission(), PushPermission.blocked);
      await settle();
      expect(devices.log, isEmpty);
    });

    test('a new token replaces the old one, on refresh and on returning to the app', () async {
      final push = controller();
      await push.sync();

      messaging.currentToken = 'token-2';
      messaging.tokenRefreshes.add('token-2');
      await settle();
      expect(devices.devices['install-1']!.token, 'token-2');

      // Changed while the app was in the background (no event was delivered).
      messaging.currentToken = 'token-3';
      await push.sync();
      expect(devices.devices['install-1']!.token, 'token-3');
      expect(devices.devices.length, 1, reason: 'the same installation, not a second device');
      expect(devices.log.length, 3);
    });

    test('a failed attach is tried again the next time', () async {
      final push = controller();
      devices.offline = true;
      await push.sync();
      expect(devices.devices, isEmpty);
      devices.offline = false;
      await push.sync();
      expect(devices.devices['install-1'], (userId: 'user-a', token: 'token-1'));
    });

    test('signing out detaches the phone while the session is still valid', () async {
      final push = controller();
      await push.sync();

      await push.detach();
      expect(devices.log.last, 'unregister user-a', reason: 'told as the account that is leaving');
      expect(devices.devices, isEmpty);
      signedIn = null;
      await push.signedOut();
      expect(messaging.tokensDeleted, 0, reason: 'the server already forgot it');

      // The next account gets the same phone, under its own name.
      signedIn = 'user-b';
      await push.sync();
      expect(devices.devices['install-1'], (userId: 'user-b', token: 'token-1'));
      expect(devices.devices.values.where((d) => d.userId == 'user-a'), isEmpty);
    });

    test('signing out offline throws the token away, so nothing for that account arrives here', () async {
      final push = controller();
      await push.sync();
      devices.offline = true;

      await push.detach();
      await settle();
      expect(messaging.tokensDeleted, 1);
      signedIn = null;
      await push.signedOut();
      expect(messaging.tokensDeleted, 1, reason: 'once is enough');

      // The token the server still holds for the first account is dead; the
      // next account registers a new one.
      devices.offline = false;
      messaging.currentToken = 'token-new';
      signedIn = 'user-b';
      await push.sync();
      expect(devices.devices['install-1'], (userId: 'user-b', token: 'token-new'));
    });

    test('a session that ended elsewhere also leaves no working token behind', () async {
      final push = controller();
      await push.sync();
      // Expired or revoked: there was no chance to tell the server.
      signedIn = null;
      await push.signedOut();
      expect(messaging.tokensDeleted, 1);
    });

    test('signing out never waits for a server that does not answer', () async {
      final hanging = _HangingDevices();
      final push = PushController(
        messaging: messaging,
        devices: hanging,
        router: router,
        installationId: () async => 'install-1',
        appVersion: () async => '1.0.6',
        currentUserId: () => signedIn,
        onForeground: banners.add,
      );
      addTearDown(push.dispose);
      await push.start();
      final watch = Stopwatch()..start();
      await push.detach();
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      hanging.release();
    });

    test('an attach still on its way can never land after the detach that followed', () async {
      final push = controller();
      final attaching = push.sync();
      final detaching = push.detach();
      await Future.wait([attaching, detaching]);
      expect(devices.log, ['register user-a token-1 ios ar 1.0.6', 'unregister user-a']);
      expect(devices.devices, isEmpty);
    });
  });

  group('messages', () {
    test('while the app is open a push becomes a banner, not for a signed-out phone', () async {
      final push = controller();
      await push.start();
      const message = PushMessage(title: 'تأخير الباص', body: 'سيتأخر 10 دقائق', data: {'notification_id': 'n1'});
      messaging.foreground.add(message);
      await settle();
      expect(banners.single.notificationId, 'n1');

      signedIn = null;
      messaging.foreground.add(message);
      await settle();
      expect(banners.length, 1);
    });

    test('the banner shows each notification once, and nothing empty', () {
      final banner = ForegroundBannerController();
      addTearDown(banner.dispose);
      const first = PushMessage(title: 'تأخير الباص', body: 'سيتأخر', data: {'notification_id': 'n1'});
      banner.show(first);
      expect(banner.state?.notificationId, 'n1');
      banner.dismiss();
      banner.show(first); // delivered again
      expect(banner.state, isNull);
      banner.show(const PushMessage(data: {'notification_id': 'n2'})); // data only
      expect(banner.state, isNull);
      banner.show(const PushMessage(title: 'وصل الباص', data: {'notification_id': 'n3'}));
      expect(banner.state?.notificationId, 'n3');
      // Another account: the first one's banner is gone.
      banner.reset();
      expect(banner.state, isNull);
    });

    test('a tapped system notification goes to the router; the one that opened the app waits', () async {
      const launch = PushMessage(data: {'notification_id': 'n1', 'route': 'card'});
      messaging.launchedBy = launch;
      final push = controller();
      await push.start();
      expect(router.hasWaiting, isTrue, reason: 'no screen is up yet on a cold start');

      // Some launches report the same tap a second time.
      messaging.openedFromTray.add(launch);
      await settle();
      final shell = FakeShell();
      router.attach('user-a', shell);
      expect(shell.shown, [NotificationDestination.card]);

      messaging.openedFromTray.add(const PushMessage(data: {'notification_id': 'n2', 'route': 'home'}));
      await settle();
      expect(shell.shown, [NotificationDestination.card, NotificationDestination.home]);
    });

    test('starting twice listens once', () async {
      final push = controller();
      await Future.wait([push.start(), push.start()]);
      expect(messaging.initialised, 1);
      messaging.foreground.add(const PushMessage(title: 'مرة', data: {'notification_id': 'n1'}));
      await settle();
      expect(banners.length, 1);
    });
  });

  group('signing out of the app', () {
    setUp(() {
      OfflineCache.debugUserId = 'user-a';
      OfflineCache.resetSession();
    });
    tearDown(() => OfflineCache.debugUserId = null);

    test('detaches the phone first, then clears everything saved for the account', () async {
      final log = <String>[];
      final push = controller();
      await push.sync();
      devices.signedIn = () {
        log.add('server call as $signedIn');
        return signedIn;
      };

      // What the account left on the phone: its inbox, its switches, a snapshot.
      await OfflineCache.readThrough('notifications.page', () async => {'items': [], 'unread': 2});
      await OfflineCache.readThrough('notification_preferences', () async => {'push_enabled': true});
      await SnapshotStore.write('user-a', 'current_subscription', {'id': 's1'});
      final installation = await DeviceStore().installationId();
      await settle();

      router.open(NotificationIntent.fromPush(const {'notification_id': 'n9'}), NotificationTapSource.push);
      expect(router.hasWaiting, isTrue);

      final auth = AuthNotifier(_FakeAuthRepository(log), beforeSignOut: push.detach);
      addTearDown(auth.dispose);
      await auth.signOut();
      signedIn = null;
      router.accountChanged(null);
      await push.signedOut();

      expect(log, ['server call as user-a', 'signOut'], reason: 'detached while still signed in');
      expect(devices.devices, isEmpty);
      expect(auth.state.isAuthenticated, isFalse);
      expect(router.hasWaiting, isFalse, reason: 'a tap meant for the account that left is dropped');

      final left = await const FlutterSecureStorage().readAll();
      expect(left.keys.where((k) => k.contains('notifications') || k.contains('notification_preferences')),
          isEmpty, reason: 'the next person never sees this inbox');
      expect(left.keys.where((k) => k.startsWith('basak.offline.') || k.startsWith('basak.snapshot.')), isEmpty);
      // The installation is the same phone for whoever signs in next.
      expect(await DeviceStore().installationId(), installation);
    });

    test('signing out still works when the phone could not be detached', () async {
      final log = <String>[];
      final auth = AuthNotifier(_FakeAuthRepository(log),
          beforeSignOut: () async => throw TimeoutException('no answer'));
      addTearDown(auth.dispose);
      await auth.signOut();
      expect(log, ['signOut']);
      expect(auth.state.isAuthenticated, isFalse);
    });

    test('the installation id is made once and kept apart from the account data', () async {
      final store = DeviceStore();
      final id = await store.installationId();
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(await store.installationId(), id);
      expect(await DeviceStore().installationId(), id, reason: 'the same after a restart');
      await OfflineCache.clearAll();
      await SnapshotStore.clear();
      expect(await DeviceStore().installationId(), id, reason: 'and after signing out');

      expect(await store.pushPrompted(), isFalse);
      await store.markPushPrompted();
      expect(await DeviceStore().pushPrompted(), isTrue);
    });
  });
}

/// A server that never answers.
class _HangingDevices implements PushDeviceApi {
  final _never = Completer<void>();
  void release() => _never.complete();

  @override
  Future<void> register({
    required String installationId,
    required String platform,
    required String token,
    required String locale,
    required String appVersion,
  }) =>
      _never.future;

  @override
  Future<void> unregister(String installationId) => _never.future;
}
