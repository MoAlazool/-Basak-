import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/sync/sync_hub.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/notifications/data/notification_feed.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/invites/invites.dart';
import 'package:basak_mobile/features/student/profile/data/profile_repository.dart';
import 'package:basak_mobile/features/student/qr/presentation/student_qr_screen.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_draft.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';
import 'package:basak_mobile/features/student/subscription/presentation/purchase_flow.dart';
import 'package:basak_mobile/features/student/subscription/presentation/subscription_screen.dart';
import 'package:basak_mobile/features/supervisor/data/supervisor_repository.dart';

import 'support/perf_fakes.dart';
import 'support/student_world.dart';

/// A live event re-reads what it is about and nothing else, and what this
/// phone changed itself is never read again because the server said so.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    OfflineCache.debugUserId = studentId;
    OfflineCache.resetSession();
    OwnChanges.now = DateTime.now;
    OwnChanges.clear();
  });
  tearDown(() {
    OfflineCache.debugUserId = null;
    OwnChanges.now = DateTime.now;
  });

  List<ProviderOrFamily> stale(Set<String> tables, {bool subscriptionChanged = true, UserRole role = UserRole.student}) {
    final list = <ProviderOrFamily>[];
    SyncScope.invalidateFor(list.add, tables, role, studentId, subscriptionChanged: subscriptionChanged);
    return list;
  }

  group('which screens a table\'s change re-reads', () {
    test('a receipt: the subscriptions and their receipts; not the card, the catalog or issued receipts', () {
      expect(stale(const {'receipts'}),
          unorderedEquals([currentSubscriptionProvider, allSubscriptionsProvider, subscriptionReceiptsProvider]));
    });

    test('a subscription whose status, line and dates did not change: the lists only', () {
      expect(stale(const {'subscriptions'}, subscriptionChanged: false),
          unorderedEquals([currentSubscriptionProvider, allSubscriptionsProvider, subscriptionReceiptsProvider]));
    });

    test('a subscription that did change (or cannot be told): also the card, the catalog and its receipt', () {
      expect(
          stale(const {'subscriptions'}),
          unorderedEquals([
            currentSubscriptionProvider, allSubscriptionsProvider, subscriptionReceiptsProvider,
            studentQrProvider, saleCatalogProvider, subscriptionReceiptDocProvider,
          ]));
    });

    test('lines and prices: the subscriptions, the card and what is on sale', () {
      expect(
          stale(const {'lines'}),
          unorderedEquals(
              [currentSubscriptionProvider, allSubscriptionsProvider, studentQrProvider, saleCatalogProvider]));
      expect(stale(const {'line_period_prices'}), [saleCatalogProvider]);
    });

    test('the student\'s own row: the profile and the card', () {
      expect(stale(const {'students'}), unorderedEquals([studentQrProvider, studentProfileSummaryProvider(studentId)]));
    });

    test('invitations: the invitations (and membership also the subscriptions and the card)', () {
      expect(stale(const {'company_invites'}), [myInvitesProvider]);
      expect(stale(const {'company_students'}), containsAll([myInvitesProvider, allSubscriptionsProvider]));
    });

    test('notifications: the inbox only, for every role', () {
      expect(stale(const {'notifications'}), [notificationFeedProvider]);
      expect(stale(const {'notifications'}, role: UserRole.supervisor), [notificationFeedProvider]);
    });

    test('a supervisor: the dashboard and trips; the photo only when the supervisor row changed', () {
      expect(stale(const {'supervisor_scan_events'}, role: UserRole.supervisor),
          containsAll([supervisorDashboardProvider, supervisorMonthlySummaryProvider]));
      expect(stale(const {'supervisor_scan_events'}, role: UserRole.supervisor),
          isNot(contains(supervisorPhotoUrlProvider)));
      expect(stale(const {'supervisors'}, role: UserRole.supervisor), contains(supervisorPhotoUrlProvider));
    });

    test('a saved copy that turned out stale re-reads exactly the provider that shows it', () {
      expect(SyncScope.providerFor('subscriptions', studentId), allSubscriptionsProvider);
      expect(SyncScope.providerFor('subscriptions.current', studentId), currentSubscriptionProvider);
      expect(SyncScope.providerFor('student_pass', studentId), studentQrProvider);
      expect(SyncScope.providerFor('profile.summary', studentId), studentProfileSummaryProvider(studentId));
      expect(SyncScope.providerFor('sale_catalog', studentId), saleCatalogProvider);
      expect(SyncScope.providerFor('receipts.sub-9', studentId), subscriptionReceiptsProvider('sub-9'));
      expect(SyncScope.providerFor('payment_methods.c1', studentId), paymentMethodsProvider('c1'));
      expect(SyncScope.providerFor('subscription_receipt.v2.sub-9', studentId), subscriptionReceiptDocProvider('sub-9'));
      expect(SyncScope.providerFor('vote_settings.c1', studentId), voteSettingsProvider);
      expect(SyncScope.providerFor('supervisor.photo', 's1'), supervisorPhotoUrlProvider);
      expect(SyncScope.providerFor('notifications.page', studentId), isNull, reason: 'by its tables, as before');
    });
  });

  group('whether a subscription event matters to the card and the catalog', () {
    SubscriptionModel sub(String status, {String id = 's1', String line = 'l1', String? end = '2027-01-30'}) =>
        SubscriptionModel(
            id: id, studentId: 'me', lineId: line, stationId: 'st', type: 'termly', status: status, price: 1,
            createdAt: '2026-10-01', startDate: '2026-09-05', endDate: end);
    const update = [SyncEvent('subscriptions', op: 'UPDATE', id: 's1')];

    test('nothing the card shows changed: no', () {
      expect(SyncScope.subscriptionChangeMatters([sub('pending_review')], [sub('pending_review')], update), isFalse);
    });

    test('status, line or dates changed: yes', () {
      expect(SyncScope.subscriptionChangeMatters([sub('pending_review')], [sub('active')], update), isTrue);
      expect(SyncScope.subscriptionChangeMatters([sub('active')], [sub('expired')], update), isTrue);
      expect(SyncScope.subscriptionChangeMatters([sub('active')], [sub('active', line: 'l2')], update), isTrue);
      expect(SyncScope.subscriptionChangeMatters([sub('active')], [sub('active', end: '2027-06-30')], update), isTrue);
    });

    test('created, deleted, appeared, or not known before: yes', () {
      expect(
          SyncScope.subscriptionChangeMatters(
              [sub('active')], [sub('active')], const [SyncEvent('subscriptions', op: 'INSERT', id: 's2')]),
          isTrue);
      expect(
          SyncScope.subscriptionChangeMatters(
              [sub('active')], const [], const [SyncEvent('subscriptions', op: 'DELETE', id: 's1')]),
          isTrue);
      expect(SyncScope.subscriptionChangeMatters(const [], [sub('active')], update), isTrue);
      expect(SyncScope.subscriptionChangeMatters(null, [sub('active')], update), isTrue);
    });
  });

  group('the event itself', () {
    test('its table, what happened and which row are read from either wrapping', () {
      final plain = SyncScope.eventOf({'table': 'receipts', 'op': 'INSERT', 'id': 'r1', 'company_id': 'c1'});
      expect([plain.table, plain.op, plain.id], ['receipts', 'INSERT', 'r1']);
      final wrapped = SyncScope.eventOf({
        'event': 'change',
        'payload': {'table': 'subscriptions', 'op': 'UPDATE', 'id': 's1'},
      });
      expect([wrapped.table, wrapped.op, wrapped.id], ['subscriptions', 'UPDATE', 's1']);
      expect(SyncScope.eventOf(const {}).table, '');
    });
  });

  group('this phone\'s own changes', () {
    test('an echo is recognised by table, row and what happened, while in flight and shortly after', () {
      var now = DateTime(2026, 10, 9, 10);
      OwnChanges.now = () => now;
      final receipt = OwnChanges.begin('receipts', op: 'INSERT');
      final status = OwnChanges.begin('subscriptions', id: 's1', op: 'UPDATE');

      // The announcement can overtake the answer.
      expect(OwnChanges.isEcho(const SyncEvent('receipts', op: 'INSERT', id: 'r1')), isTrue);
      expect(OwnChanges.isEcho(const SyncEvent('subscriptions', op: 'UPDATE', id: 's1')), isTrue);
      expect(OwnChanges.isEcho(const SyncEvent('subscriptions', op: 'UPDATE', id: 's2')), isFalse);
      expect(OwnChanges.isEcho(const SyncEvent('receipts', op: 'UPDATE', id: 'r1')), isFalse);
      expect(OwnChanges.isEcho(const SyncEvent('lines', op: 'UPDATE', id: 'l1')), isFalse);

      receipt.done(id: 'r1', keep: const Duration(minutes: 1));
      status.done();
      expect(OwnChanges.isEcho(const SyncEvent('receipts', op: 'INSERT', id: 'r1')), isTrue);
      expect(OwnChanges.isEcho(const SyncEvent('receipts', op: 'INSERT', id: 'r2')), isFalse,
          reason: 'now the row is known: another receipt is news');

      now = now.add(OwnChanges.echoWindow + const Duration(milliseconds: 1));
      expect(OwnChanges.isEcho(const SyncEvent('subscriptions', op: 'UPDATE', id: 's1')), isFalse,
          reason: 'a later change of the same subscription is someone else\'s');
      expect(OwnChanges.isEcho(const SyncEvent('receipts', op: 'INSERT', id: 'r1')), isTrue);
    });

    test('a write that failed expects nothing', () {
      OwnChanges.begin('subscriptions', id: 's1').failed();
      expect(OwnChanges.isEcho(const SyncEvent('subscriptions', op: 'UPDATE', id: 's1')), isFalse);
    });

    test('a notification announced twice (push, then live) refreshes the inbox once', () {
      expect(OwnChanges.firstSight('notifications', 'n1'), isTrue);
      const event = SyncEvent('notifications', op: 'INSERT', id: 'n1');
      expect(SyncScope.withoutEchoes(const [event]), isEmpty, reason: 'the push already refreshed the inbox');
      // Another notification, or one read on another phone, is news.
      expect(SyncScope.withoutEchoes(const [SyncEvent('notifications', op: 'INSERT', id: 'n2')]), hasLength(1));
      expect(SyncScope.withoutEchoes(const [SyncEvent('notifications', op: 'READ', id: 'n1')]), hasLength(1));
    });

    test('a created subscription is written into the saved lists from the answer', () async {
      final world = StudentWorld();
      final c = world.open();
      await watchScreens(c);
      world.log.reset();

      final echo = OwnChanges.begin('subscriptions', op: 'INSERT');
      final created = await c.read(subscriptionRepoProvider).createSubscription(
          lineId: 'line-1', stationId: 'station-1', departureTime: '07:00:00', type: 'termly', price: 8000,
          periodCode: 'second', academicYear: 2026);
      echo.done(id: created.id, keep: const Duration(minutes: 1));
      c.invalidate(currentSubscriptionProvider);
      c.invalidate(allSubscriptionsProvider);
      await loaded(c);
      await world.events(c, [SyncEvent('subscriptions', op: 'INSERT', id: created.id)]);
      await loaded(c);

      expect(c.read(allSubscriptionsProvider).value?.map((s) => s.id), contains(created.id));
      expect((await OfflineCache.peek('subscriptions') as List).map((s) => s['id']), contains(created.id));
      expect(world.log.calls, {'subscriptions.insert': 1}, reason: 'no list is read again, echo included');
    });

    test('the purchase flow: lists from the answer, the catalog read once, the echo reads nothing', () async {
      final world = StudentWorld();
      final c = world.open();
      await watchScreens(c);
      world.log.reset();

      final created = await c.read(subscriptionCreatorProvider)(const SubscriptionRequest(
          lineId: 'line-1', stationId: 'station-1', departureTripId: 't1', departureTime: '07:00:00',
          type: 'termly', price: 8000, periodCode: 'second', academicYear: 2026));
      await loaded(c);
      final settled = Map.of(world.log.calls);
      await world.events(c, [SyncEvent('subscriptions', op: 'INSERT', id: created.id)]);
      await loaded(c);

      expect(c.read(allSubscriptionsProvider).value?.map((s) => s.id), contains(created.id));
      expect(world.log.of('subscriptions.all') + world.log.of('subscriptions.current'), 0);
      expect(world.log.of('sale_catalog'), 1, reason: 'what is on sale does change with a new subscription');
      expect(world.log.calls, settled, reason: 'the echo adds nothing');
    });

    test('profile details: the server\'s answer is shown; nothing is read again, echo included', () async {
      final world = StudentWorld();
      final c = world.open();
      await watchScreens(c);
      world.log.reset();

      await c.read(profileRepositoryProvider).updateDetails(email: ' A@B.co ', college: 'طب', birthDate: DateTime(2005, 3, 14));
      c.invalidate(studentProfileSummaryProvider(studentId));
      c.invalidate(studentQrProvider);
      await loaded(c);
      await world.events(c, const [SyncEvent('students', op: 'UPDATE', id: studentId)]);
      await loaded(c);

      final profile = c.read(studentProfileSummaryProvider(studentId)).value!;
      expect([profile['college'], profile['birth_date']], ['طب', '2005-03-14']);
      expect(c.read(studentQrProvider).value?.college, 'طب');
      expect((await OfflineCache.peek('profile.summary') as Map)['college'], 'طب');
      expect(world.log.calls, {'profile.update': 1});
    });

    test('a profile photo that could not be saved is taken back and nothing changes', () async {
      final world = StudentWorld();
      final c = world.open();
      await watchScreens(c);
      world.profile.setPhotoFails = StateError('refused');

      await expectLater(c.read(profileRepositoryProvider).changePhoto(Uint8List(4)), throwsStateError);
      await settle();

      expect(world.profile.files, {'$studentId/avatar-1.jpg'}, reason: 'the new upload was removed');
      expect((await OfflineCache.peek('profile.summary') as Map)['profile_image_url'], '$studentId/avatar-1.jpg');
      // And the profile changing elsewhere is still read.
      world.log.reset();
      await world.events(c, const [SyncEvent('students', op: 'UPDATE', id: studentId)]);
      await loaded(c);
      expect(world.log.of('profile.summary'), 1);
    });

    test('an answered invitation leaves the list at once', () async {
      final container = ProviderContainer(overrides: [myInvitesProvider.overrideWith(_Invites.new)]);
      addTearDown(container.dispose);
      container.listen(myInvitesProvider, (_, __) {});
      expect(await container.read(myInvitesProvider.future), hasLength(2));

      container.read(myInvitesProvider.notifier).applyAnswered('i1');

      expect(container.read(myInvitesProvider).value?.map((i) => i.id), ['i2']);
      expect(_Invites.reads, 1, reason: 'the list was not asked for again');
    });
  });

  group('changes applied on the phone', () {
    test('the next read is answered from memory, the saved copy is updated, and a restart shows it', () async {
      var requests = 0;
      Future<dynamic> server() async {
        requests++;
        return [
          {'id': 's1', 'status': 'pending_payment'}
        ];
      }

      await OfflineCache.readThrough('subscriptions', server);
      expect(
          await OfflineCache.applyLocal(
              'subscriptions', (current) => [for (final row in current as List) {...row as Map, 'status': 'pending_review'}]),
          isTrue);

      final shown = await OfflineCache.readThrough('subscriptions', server) as List;
      expect(shown.single['status'], 'pending_review');
      expect(shown.single, isA<Map<String, dynamic>>(), reason: 'the same shapes as a value from the server');
      expect(requests, 1, reason: 'no second request');

      OfflineCache.resetSession();
      final never = OfflineCache.readThrough('subscriptions', () async => throw Exception('SocketException'));
      expect((await never as List).single['status'], 'pending_review');
    });

    test('nothing held for the key: nothing to change, and a normal read follows', () async {
      expect(await OfflineCache.applyLocal('receipts.s9', (current) => ['x']), isFalse);
      expect(await OfflineCache.readThrough('receipts.s9', () async => ['server']), ['server']);
    });

    test('news from the server is not answered with what this phone wrote and nobody read yet', () async {
      await OfflineCache.readThrough('receipts.s1', () async => ['old']);
      await OfflineCache.applyLocal('receipts.s1', (current) => ['mine']);
      OfflineCache.forgetLocal();
      expect(await OfflineCache.readThrough('receipts.s1', () async => ['theirs']), ['theirs']);
    });
  });
}

class _Invites extends MyInvitesNotifier {
  static int reads = 0;

  @override
  Future<List<CompanyInvite>> build() async {
    reads++;
    return [
      for (final id in ['i1', 'i2'])
        CompanyInvite(id: id, companyName: 'المستقبل', lineName: 'خط', stationName: 'محطة', subscriptionType: 'termly'),
    ];
  }
}
