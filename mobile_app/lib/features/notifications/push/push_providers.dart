import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/constants/firebase_config.dart';
import '../../../core/network/supabase_service.dart';
import '../../../core/sync/session.dart';
import '../data/notification_feed.dart';
import '../data/notifications_repository.dart';
import '../notification_router.dart';
import 'device_store.dart';
import 'push_controller.dart';
import 'push_messaging.dart';

final deviceStoreProvider = Provider((ref) => DeviceStore());

/// Firebase when this build was given its identifiers, otherwise no push.
final pushMessagingProvider = Provider<PushMessaging>((ref) {
  final config = FirebaseConfig.current;
  return config == null ? const DisabledPushMessaging() : FirebasePushMessaging(config);
});

/// Who is signed in. The session restored from the device counts from the
/// first moment of a start, before the role is known and any screen is up.
String? _signedInUserId(Ref ref) {
  final known = ref.read(sessionUserIdProvider);
  if (known != null) return known;
  try {
    return SupabaseService.currentUser?.id;
  } catch (_) {
    return null; // Supabase not initialised (tests, previews).
  }
}

/// Where every notification tap goes (see [NotificationRouter]).
final notificationRouterProvider = Provider<NotificationRouter>((ref) => NotificationRouter(
      currentUserId: () => _signedInUserId(ref),
      onOpened: (intent) {
        final id = intent.notificationId;
        if (id != null) unawaited(ref.read(notificationFeedProvider.notifier).opened(id));
      },
    ));

/// The push that arrived while the app is open, shown as a banner inside the
/// app (the system shows nothing in that case). Each notification once.
class ForegroundBannerController extends StateNotifier<PushMessage?> {
  ForegroundBannerController() : super(null);

  static const shownFor = Duration(seconds: 6);

  final Set<String> _shown = {};
  Timer? _timer;

  void show(PushMessage message) {
    if (message.title.isEmpty && message.body.isEmpty) return;
    final id = message.notificationId;
    if (id != null && !_shown.add(id)) return;
    _timer?.cancel();
    _timer = Timer(shownFor, dismiss);
    state = message;
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (mounted) state = null;
  }

  /// Another account, or nobody: nothing of the previous one stays on screen.
  void reset() {
    _shown.clear();
    dismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final foregroundBannerProvider =
    StateNotifierProvider<ForegroundBannerController, PushMessage?>((ref) => ForegroundBannerController());

class _RepositoryDevices implements PushDeviceApi {
  final NotificationsRepository Function() _repo;
  _RepositoryDevices(this._repo);

  @override
  Future<void> register({
    required String installationId,
    required String platform,
    required String token,
    required String locale,
    required String appVersion,
  }) =>
      _repo().registerDevice(
        installationId: installationId,
        platform: platform,
        token: token,
        locale: locale,
        appVersion: appVersion,
      );

  @override
  Future<void> unregister(String installationId) => _repo().unregisterDevice(installationId);
}

final pushControllerProvider = Provider<PushController>((ref) {
  final controller = PushController(
    messaging: ref.watch(pushMessagingProvider),
    devices: _RepositoryDevices(() => ref.read(notificationsRepoProvider)),
    router: ref.watch(notificationRouterProvider),
    installationId: ref.watch(deviceStoreProvider).installationId,
    appVersion: () async => (await PackageInfo.fromPlatform()).version,
    currentUserId: () => _signedInUserId(ref),
    onForeground: (message) {
      ref.read(foregroundBannerProvider.notifier).show(message);
      // Usually the live channel already said so; this covers it being down.
      ref.invalidate(notificationFeedProvider);
    },
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Whether this build has push and the push service started.
final pushReadyProvider =
    FutureProvider<bool>((ref) => ref.watch(pushControllerProvider).start());

/// Whether the system lets the app show notifications. Read again whenever
/// the app comes back (the user may have changed it in the system settings).
final pushPermissionProvider =
    FutureProvider<PushPermission>((ref) => ref.watch(pushControllerProvider).permission());
