import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/media/signed_photo.dart';
import 'package:basak_mobile/core/media/signed_url_cache.dart';
import 'package:basak_mobile/core/widgets/avatar_image.dart';
import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/sync/sync_hub.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/profile/data/profile_repository.dart';
import 'package:basak_mobile/features/student/qr/presentation/student_qr_screen.dart';
import 'package:basak_mobile/features/student/subscription/data/subscription_repository.dart';
import 'package:basak_mobile/features/student/subscription/presentation/purchase_flow.dart';
import 'package:basak_mobile/features/student/subscription/presentation/subscription_screen.dart';

import '../support/perf_fakes.dart';
import '../support/student_world.dart';

/// How many requests the app makes in its most used flows.
///
/// Run: flutter test test/perf/request_count_test.dart
///
/// Everything below the repositories is a counting fake of the server; the
/// repositories, the providers, the saved copies and the live-event mapping
/// are the real ones (see support/student_world.dart).
void report(String flow, RequestLog log) {
  // ignore: avoid_print
  print('[requests] $flow: $log');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    OfflineCache.debugUserId = studentId;
    OfflineCache.resetSession();
  });
  tearDown(() => OfflineCache.debugUserId = null);

  test('(a) one receipt upload, from the tap to a settled screen, with its live echo', () async {
    final world = StudentWorld();
    final c = world.open();
    await watchScreens(c);
    world.log.reset();
    world.inbox.pageRequests = 0;

    // The tap.
    final receipt = await c.read(receiptSubmitterProvider).submit(
        attempt: ReceiptAttempt.start(subscriptionId), bytes: Uint8List(8), paymentMethodId: 'pm-1');
    await loaded(c);
    final afterTap = world.log.total;
    expect(c.read(currentSubscriptionProvider).value?.status, 'pending_review',
        reason: 'shown from the answer, before any live event');
    // The server announces the student's own change back to this phone, and
    // the "proof received" notice arrives.
    await world.events(c, [
      SyncEvent('receipts', op: 'INSERT', id: receipt.id),
      const SyncEvent('subscriptions', op: 'UPDATE', id: subscriptionId),
      const SyncEvent('notifications', op: 'INSERT', id: 'notice-1'),
    ]);
    await loaded(c);

    report('receipt upload (tap to settled)', world.log);
    // ignore: avoid_print
    print('[requests] receipt upload: before the echo $afterTap, the echo ${world.log.total - afterTap}, '
        'inbox pages for the new notice ${world.inbox.pageRequests}');
    expect(c.read(subscriptionReceiptsProvider(subscriptionId)).value, hasLength(1));
    expect(world.log.calls, {'receipts.upload': 1, 'receipts.insert': 1},
        reason: 'the image and the receipt: nothing is read again, with or without the echo');
    expect(world.inbox.pageRequests, lessThanOrEqualTo(1), reason: 'the new notice is the only thing read');
  });

  test('(b) an approval arriving as a live event', () async {
    final world = StudentWorld();
    world.server.sub(subscriptionId)['status'] = 'pending_review';
    final c = world.open();
    await watchScreens(c);
    world.log.reset();

    world.server.approve(subscriptionId);
    await world.events(c, const [
      SyncEvent('receipts', op: 'UPDATE', id: 'receipt-1'),
      SyncEvent('subscriptions', op: 'UPDATE', id: subscriptionId),
    ]);
    await loaded(c);

    report('approval event', world.log);
    expect(c.read(currentSubscriptionProvider).value?.status, 'active');
    expect((await c.read(studentQrProvider.future))?.subscriptionStatus, 'active',
        reason: 'an approval reaches the card promptly');
    expect(world.log.total, lessThanOrEqualTo(7));
    expect(world.log.of('storage.sign'), 0, reason: 'the photo link is reused');
  });

  testWidgets('(c) a student cold start with everything saved from last time', (tester) async {
    final world = StudentWorld()..server.sub(subscriptionId)['status'] = 'active';
    debugAvatarImage = (_) => MemoryImage(onePixel);
    addTearDown(() => debugAvatarImage = null);

    Future<void> start() async {
      // A new run of the app: memory is gone, the device storage stays.
      SignedUrlCache.clear();
      await tester.runAsync(() async {
        // The role is confirmed with the server behind the saved one.
        await AuthRepository(roles: FakeRoles(world.log)).detectUserRole(studentId);
      });
      late ProviderContainer container;
      void onRefreshed() {
        // What SyncScope does when a saved copy turned out to be stale.
        final tables = <String>{};
        for (final key in OfflineCache.takeRefreshedKeys()) {
          final provider = SyncScope.providerFor(key, studentId);
          if (provider != null) {
            container.invalidate(provider);
          } else if (!key.startsWith('ride.')) {
            tables.addAll(SyncScope.tablesFor(key));
          }
        }
        if (tables.isNotEmpty) {
          SyncScope.invalidateFor(container.invalidate, tables, UserRole.student, studentId, subscriptionChanged: false);
        }
      }

      OfflineCache.refreshed.addListener(onRefreshed);
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: world.overrides,
        child: MaterialApp(
          home: Consumer(builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            // The other tabs, built in the background a moment after the home
            // tab. The card tab's provider is also what saves the pass for
            // offline use at sign-in.
            ref.watch(allSubscriptionsProvider);
            ref.watch(saleCatalogProvider);
            final pass = ref.watch(studentQrProvider).valueOrNull;
            final photo = studentPhoto(pass?.profileImagePath);
            if (photo != null) ref.watch(signedPhotoProvider(photo));
            return StudentHomeScreen(onNavigateToSubscription: () {}, onNavigateToQr: () {});
          }),
        ),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(settle);
        await tester.pump(const Duration(milliseconds: 200));
      }
      OfflineCache.refreshed.removeListener(onRefreshed);
      await tester.pumpWidget(const SizedBox());
    }

    await start(); // first run on this phone: fills the saved copies
    OfflineCache.resetSession();
    world.log.reset();
    await start();

    report('cold start (warm cache)', world.log);
    expect(world.log.of('role.rpc') + world.log.of('role.select'), 1);
    expect(world.log.of('pass.student'), 1, reason: 'the pass is fetched once, through its provider');
    expect(world.log.of('vote_settings'), 1);
    expect(world.log.of('ride.range') + world.log.of('ride.details'), lessThanOrEqualTo(2));
    expect(world.log.of('storage.sign'), lessThanOrEqualTo(2), reason: 'one per photo: the student and the supervisor');
    expect(world.log.total, lessThanOrEqualTo(13));
  });

  test('(d) changing the profile photo, with its live echo', () async {
    final world = StudentWorld();
    final c = world.open();
    await watchScreens(c);
    c.listen(signedPhotoProvider((bucket: 'student-avatars', path: world.pass.photoPath!)), (_, __) {});
    await settle();
    world.log.reset();

    final path = await c.read(profileRepositoryProvider).changePhoto(Uint8List(8));
    final released = world.log.total;
    // What the profile section does next: the screens show the new photo.
    c.invalidate(studentProfileSummaryProvider(studentId));
    c.invalidate(studentQrProvider);
    c.listen(signedPhotoProvider((bucket: 'student-avatars', path: path)), (_, __) {});
    await loaded(c);
    final afterTap = world.log.total;
    await world.events(c, const [SyncEvent('students', op: 'UPDATE', id: studentId)]);
    await loaded(c);

    report('profile photo', world.log);
    // ignore: avoid_print
    print('[requests] profile photo: until the screen is released $released, settled $afterTap, '
        'the echo ${world.log.total - afterTap}');
    expect((await c.read(studentProfileSummaryProvider(studentId).future))?['profile_image_url'], path);
    expect((await c.read(studentQrProvider.future))?.profileImagePath, path);
    expect(world.profile.files, {path}, reason: 'the old photo is removed, behind the screen');
    expect(released, 2, reason: 'upload and save; the clean-up no longer holds the screen');
    expect(world.log.total - afterTap, 0, reason: 'the echo of its own change reads nothing');
    expect(world.log.total, lessThanOrEqualTo(5));
  });
}
