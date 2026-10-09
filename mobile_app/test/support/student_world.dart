import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:basak_mobile/core/media/signed_url_cache.dart';
import 'package:basak_mobile/core/sync/sync_hub.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/notifications/data/notification_feed.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/invites/invites.dart';
import 'package:basak_mobile/features/student/profile/data/profile_repository.dart';
import 'package:basak_mobile/features/student/qr/data/student_qr_repository.dart';
import 'package:basak_mobile/features/student/qr/presentation/student_qr_screen.dart';
import 'package:basak_mobile/features/student/subscription/data/subscription_repository.dart';
import 'package:basak_mobile/features/student/subscription/presentation/subscription_screen.dart';

import 'notification_fakes.dart';
import 'perf_fakes.dart';

/// A signed-in student's app over a fake server: the real repositories,
/// providers, saved copies and live-event handling, with every request counted.
class FakeStudentAuth extends AuthNotifier {
  FakeStudentAuth() : super(AuthRepository());
  void signInAs(String id) => state = AuthState(
      user: User(id: id, appMetadata: const {}, userMetadata: const {'full_name': 'محمد عادل فؤاد العزول'}, aud: '', createdAt: ''),
      role: UserRole.student);
}

class StudentWorld {
  final log = RequestLog();
  late final server = FakeSubscriptionServer(log);
  late final pass = FakePassServer(log, server);
  late final profile = FakeProfileServer(log, pass);
  late final rides = FakeRides(log);
  late final invites = FakeInvites(log, server);
  final inbox = FakeNotificationsRepo();

  StudentWorld() {
    fakeSigner(log);
    SignedUrlCache.clear();
    OwnChanges.clear();
  }

  /// Live events reaching this phone, handled as SyncScope handles them.
  Future<void> events(ProviderContainer c, List<SyncEvent> events) => SyncScope.onEvents(events,
      invalidate: c.invalidate, read: c.read, role: UserRole.student, userId: studentId);

  List<Override> get overrides => [
        authStateProvider.overrideWith((ref) => FakeStudentAuth()..signInAs(studentId)),
        subscriptionRepoProvider.overrideWithValue(SubscriptionRepository(gateway: server)),
        studentQrRepoProvider.overrideWithValue(StudentQrRepository(gateway: pass)),
        profileRepositoryProvider.overrideWithValue(ProfileRepository(gateway: profile)),
        dailyRideRepoProvider.overrideWithValue(rides),
        invitesGatewayProvider.overrideWithValue(invites),
        notificationsRepoProvider.overrideWithValue(inbox),
      ];

  /// A running app: its providers, kept alive like the screens keep them.
  ProviderContainer open() {
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    return container;
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 40));

/// What the student's four tabs keep loaded while a payment is awaited. (Not
/// the catalog: it is read only while the purchase UI is on screen.)
Future<void> watchScreens(ProviderContainer c) async {
  c.listen(currentSubscriptionProvider, (_, __) {});
  c.listen(allSubscriptionsProvider, (_, __) {});
  c.listen(subscriptionReceiptsProvider(subscriptionId), (_, __) {});
  c.listen(paymentMethodsProvider('company-1'), (_, __) {});
  c.listen(studentQrProvider, (_, __) {});
  c.listen(studentProfileSummaryProvider(studentId), (_, __) {});
  c.listen(notificationFeedProvider, (_, __) {});
  await loaded(c);
}

Future<void> loaded(ProviderContainer c) async {
  for (var i = 0; i < 3; i++) {
    await c.read(currentSubscriptionProvider.future);
    await c.read(allSubscriptionsProvider.future);
    await c.read(subscriptionReceiptsProvider(subscriptionId).future);
    await c.read(studentQrProvider.future);
    await c.read(studentProfileSummaryProvider(studentId).future);
    await settle();
  }
}

