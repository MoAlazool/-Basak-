import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/sync/sync_hub.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/presentation/force_password_change_screen.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/notifications/data/notification_feed.dart';
import 'package:basak_mobile/features/student/daily_ride/data/daily_ride_repository.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/invites/invites.dart';
import 'package:basak_mobile/features/student/qr/data/student_qr_repository.dart';
import 'package:basak_mobile/features/student/qr/presentation/student_qr_screen.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_draft.dart';
import 'package:basak_mobile/features/student/subscription/presentation/purchase_flow.dart';
import 'package:basak_mobile/features/student/subscription/presentation/subscription_screen.dart';

import '../support/notification_fakes.dart';
import '../support/perf_fakes.dart';
import '../support/student_world.dart';

/// The student's remaining flows, by request: what each one reads when it is
/// opened, when it is opened again, after its own change and on a live event.
///
/// Run: flutter test test/perf/student_flows_test.dart
void report(String flow, RequestLog log) {
  // ignore: avoid_print
  print('[requests] student, $flow: $log');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    OfflineCache.debugUserId = studentId;
    OfflineCache.resetSession();
  });
  tearDown(() => OfflineCache.debugUserId = null);

  test('opening the tabs again reads nothing', () async {
    final world = StudentWorld();
    final c = world.open();
    await watchScreens(c);
    world.log.reset();
    world.inbox.pageRequests = 0;

    await loaded(c); // home, subscriptions, card and account, all visited again
    await c.read(notificationFeedProvider.future); // and the Notification Center
    expect(world.log.total, 0);
    expect(world.inbox.pageRequests, 0);
  });

  group('the card', () {
    test('is made from the profile and the current subscription: no request of its own', () async {
      final world = StudentWorld()..server.sub(subscriptionId)['status'] = 'active';
      final c = world.open();
      c.listen(studentQrProvider, (_, __) {});
      final pass = await c.read(studentQrProvider.future);
      await settle();

      report('the card, opened first', world.log);
      expect(pass?.qrValue, 'QR-1');
      expect([pass?.lineName, pass?.stationName, pass?.subscriptionStatus], ['منية النصر', 'البجلات', 'active']);
      expect(world.log.calls, {'profile.summary': 1, 'subscriptions.current': 1, 'pass.wallet_refresh': 1},
          reason: 'the two reads every other screen shares, and the Wallet refresh');
      expect((await OfflineCache.readStudentPass())?['qr_value'], 'QR-1', reason: 'kept under its own key too');

      // The home screen and the account page open on the same two reads.
      await c.read(currentSubscriptionProvider.future);
      await c.read(studentProfileSummaryProvider(studentId).future);
      await c.read(mustChangePasswordProvider.future);
      expect(world.log.total, 3);
    });

    test('follows the subscription and the profile without being told', () async {
      final world = StudentWorld();
      final c = world.open();
      await watchScreens(c);
      world.log.reset();

      world.server.approve(subscriptionId);
      world.pass.college = 'طب';
      c.invalidate(currentSubscriptionProvider);
      c.invalidate(studentProfileSummaryProvider(studentId));
      await loaded(c);

      final pass = c.read(studentQrProvider).value;
      expect([pass?.subscriptionStatus, pass?.college], ['active', 'طب']);
      expect(world.log.calls, {'subscriptions.current': 1, 'profile.summary': 1});
    });

    test('the Wallet card is refreshed once a day in a run, and again after a failure', () async {
      final gateway = _Wallet();
      final repository = StudentQrRepository(gateway: gateway);
      Future<StudentPassDetails?> read() => repository.getStudentPassDetails(
          student: () async => {'qr_code_value': 'QR-1', 'full_name': 'محمد'}, subscription: () async => null);

      gateway.fails = true;
      await read();
      await settle();
      expect(gateway.refreshes, 1);
      gateway.fails = false;
      await read();
      await read();
      await settle();
      expect(gateway.refreshes, 2, reason: 'tried again after the failure, then not again today');
    });

    test('a profile saved by the previous version (no code in it) still shows the saved QR', () async {
      await OfflineCache.saveStudentPass({'qr_value': 'QR-OLD', 'full_name': 'محمد'});
      final repository = StudentQrRepository(gateway: _Wallet());
      final pass = await repository.getStudentPassDetails(
          student: () async => {'full_name': 'محمد', 'profile_image_url': ' '}, subscription: () async => null);
      expect(pass?.qrValue, 'QR-OLD');
      expect(pass?.profileImagePath, isNull);
    });

    test('with no connection and nothing else saved, the pass kept under its own key is shown', () async {
      await OfflineCache.saveStudentPass({'qr_value': 'QR-1', 'full_name': 'محمد', 'subscription_status': 'active'});
      final repository = StudentQrRepository(gateway: _Wallet());
      final pass = await repository.getStudentPassDetails(
          student: () async => throw const SocketException('Failed host lookup'),
          subscription: () async => throw const SocketException('Failed host lookup'));
      expect([pass?.qrValue, pass?.subscriptionStatus, pass?.isOfflineCache], ['QR-1', 'active', true]);
      expect(OfflineCache.offlineSince.value, isNotNull);

      // A refusal is never papered over with a valid-looking QR.
      await expectLater(
          repository.getStudentPassDetails(
              student: () async => throw Exception('JWT expired'), subscription: () async => null),
          throwsException);
    });
  });

  test('the forced password change is read with the profile, not on its own', () async {
    final world = StudentWorld()..profile.mustChangePassword = true;
    final c = world.open();
    c.listen(mustChangePasswordProvider, (_, __) {});
    c.listen(studentProfileSummaryProvider(studentId), (_, __) {});
    expect(await c.read(mustChangePasswordProvider.future), isTrue);
    expect(world.log.calls, {'profile.summary': 1});

    // What the screen does once the new password is saved: this phone's copy
    // of the row is corrected, and nothing is read again.
    world.profile.mustChangePassword = false;
    await OfflineCache.applyLocal(
        'profile.summary', (row) => row is Map ? {...row, 'must_change_password': false} : row);
    c.invalidate(studentProfileSummaryProvider(studentId));
    expect(await c.read(mustChangePasswordProvider.future), isFalse);
    expect(world.log.calls, {'profile.summary': 1});
  });

  test('a forced change saved from last time is lifted as soon as the server says it is done', () async {
    final world = StudentWorld()..profile.mustChangePassword = true;
    var c = world.open();
    c.listen(mustChangePasswordProvider, (_, __) {});
    expect(await c.read(mustChangePasswordProvider.future), isTrue);
    await settle();

    // The password was changed on another phone; this one starts again.
    c.dispose();
    world.profile.mustChangePassword = false;
    OfflineCache.resetSession();
    world.log.reset();
    c = world.open();
    c.listen(mustChangePasswordProvider, (_, __) {});
    expect(await c.read(mustChangePasswordProvider.future), isTrue, reason: 'the saved copy, at once');
    await settle();
    await settle();
    expect(await c.read(mustChangePasswordProvider.future), isFalse, reason: 'the server\'s answer, taken at once');
    expect(world.log.calls, {'profile.summary': 1});
  });

  test('the ride votes: the week and the ride day\'s choices come from one read', () {
    final rides = RideDays.fromRows([
      {'ride_date': '2026-10-10', 'is_riding': true, 'departure_time': '07:00', 'return_time': '15:00', 'is_returning': true},
      {'ride_date': '2026-10-11', 'is_riding': false, 'departure_time': null, 'return_time': null, 'is_returning': false},
    ]);
    expect(rides.statuses, {DateTime(2026, 10, 10): true, DateTime(2026, 10, 11): false});
    final day = rides.detailsFor(DateTime(2026, 10, 10));
    expect([day.isRiding, day.departureTime, day.returnTime, day.isReturning], [true, '07:00', '15:00', true]);
    expect(rides.detailsFor(DateTime(2026, 10, 11)).isReturning, isFalse);
    // A day with no vote: not riding, and returning by default, as before.
    final none = rides.detailsFor(DateTime(2026, 10, 12));
    expect([none.isRiding, none.isReturning, none.departureTime], [false, true, null]);
  });

  group('the Notification Center', () {
    test('older pages one request each; a read mark is one write and no read, its echo included', () async {
      final world = StudentWorld();
      world.inbox
        ..perPage = 2
        ..inbox = [
          for (var i = 0; i < 5; i++) note('n$i', 'إشعار $i', at: DateTime(2026, 10, 9, 10).subtract(Duration(hours: i)))
        ];
      final c = world.open();
      c.listen(notificationFeedProvider, (_, __) {});
      await c.read(notificationFeedProvider.future);
      expect(world.inbox.pageRequests, 1, reason: 'the first page, read once for the bell and the list');

      final feed = c.read(notificationFeedProvider.notifier);
      await feed.loadMore();
      await feed.loadMore();
      expect(world.inbox.pageRequests, 3);
      expect(c.read(notificationFeedProvider).value?.items, hasLength(5));

      await feed.markRead(['n0']);
      // The server tells every phone of the account, this one included.
      await world.events(c, const [SyncEvent('notifications', op: 'READ')]);
      await c.read(notificationFeedProvider.future);
      expect(world.inbox.marked, [
        ['n0']
      ]);
      expect(world.inbox.pageRequests, 3, reason: 'already shown as read: nothing is read again');
      expect(c.read(notificationFeedProvider).value?.unread, 4);

      // Read on another phone: that is news, and the first page is read again.
      world.inbox.inbox = [for (final n in world.inbox.inbox) n.id == 'n1' ? n.markedRead() : n];
      await world.events(c, const [SyncEvent('notifications', op: 'READ')]);
      await c.read(notificationFeedProvider.future);
      expect(world.inbox.pageRequests, 4);
      expect(c.read(notificationFeedProvider).value?.unread, 3);
    });

    test('a read mark that failed leaves nothing waiting: the next announcement is acted on', () async {
      final world = StudentWorld();
      world.inbox.inbox = [note('n0', 'إشعار')];
      final c = world.open();
      c.listen(notificationFeedProvider, (_, __) {});
      await c.read(notificationFeedProvider.future);

      world.inbox.offline = true;
      await expectLater(c.read(notificationFeedProvider.notifier).markRead(['n0']), throwsA(anything));
      world.inbox.offline = false;
      await world.events(c, const [SyncEvent('notifications', op: 'READ')]);
      await c.read(notificationFeedProvider.future);
      expect(world.inbox.pageRequests, 2);
    });
  });

  testWidgets('an invitation: one answer however fast it is tapped, the subscription read once, no echo',
      (tester) async {
    final world = StudentWorld();
    world.invites.waiting.add({
      'id': 'invite-1', 'company_name': 'المستقبل', 'line_name': 'منية النصر', 'station_name': 'البجلات',
      'subscription_type': 'termly', 'price': 8000,
    });
    late ProviderContainer c;
    await tester.pumpWidget(ProviderScope(
      overrides: world.overrides,
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          c = ProviderScope.containerOf(context);
          // What the tabs keep loaded.
          ref.watch(currentSubscriptionProvider);
          ref.watch(allSubscriptionsProvider);
          ref.watch(studentQrProvider);
          return const Scaffold(body: InvitesCard());
        }),
      ),
    ));
    Future<void> rest() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(settle);
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await rest();
    expect(find.text('دعوة للاشتراك من'), findsOneWidget);
    expect(find.text('المستقبل'), findsOneWidget);
    world.log.reset();

    world.invites.gate = Completer<void>();
    await tester.tap(find.text('رفض'));
    await tester.tap(find.text('رفض'), warnIfMissed: false);
    await tester.pump();
    world.invites.gate!.complete();
    await rest();
    expect(world.invites.answers, [(id: 'invite-1', accept: false)], reason: 'the second tap did nothing');
    expect(find.text('دعوة للاشتراك من'), findsNothing, reason: 'gone from the answer, without asking for the list');
    expect(world.log.calls, {'invites.respond': 1});

    // Accepting opens a subscription on the server: it is read once, here.
    world.invites.gate = null;
    world.invites.waiting.add({
      'id': 'invite-2', 'company_name': 'المستقبل', 'line_name': 'منية النصر', 'station_name': 'البجلات',
      'subscription_type': 'termly',
    });
    c.invalidate(myInvitesProvider);
    await rest();
    world.log.reset();
    await tester.tap(find.text('قبول الدعوة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('موافق، انضم'));
    await rest();
    final settled = Map.of(world.log.calls);
    await tester.runAsync(() => world.events(c, const [
          SyncEvent('company_invites', op: 'UPDATE', id: 'invite-2'),
          SyncEvent('company_students', op: 'INSERT', id: studentId),
          SyncEvent('subscriptions', op: 'INSERT', id: 'sub-invited'),
        ]));
    await rest();

    report('invitation accepted, with its live echo', world.log);
    expect(c.read(allSubscriptionsProvider).value?.map((s) => s.id), contains('sub-invited'));
    expect(settled, {'invites.respond': 1, 'subscriptions.current': 1, 'subscriptions.all': 1});
    expect(world.log.calls, settled, reason: 'the announcements of its own answer read nothing');
  });

  group('what is on sale (the catalog) is read only while it is on screen', () {
    /// The Subscriptions tab as the app builds it: in the background first
    /// ([front] false), in front when the student opens it.
    Future<ProviderContainer> pumpTab(WidgetTester tester, StudentWorld world, ValueNotifier<bool> front) async {
      late ProviderContainer c;
      await tester.pumpWidget(ProviderScope(
        overrides: world.overrides,
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Consumer(builder: (context, ref, _) {
              c = ProviderScope.containerOf(context);
              return ValueListenableBuilder<bool>(
                  valueListenable: front, builder: (_, visible, __) => SubscriptionScreen(visible: visible));
            }),
          ),
        ),
      ));
      return c;
    }

    Future<void> rest(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(settle);
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('a student with a running subscription: not at start, once when the tab is opened, '
        'and on a change only while the tab is in front', (tester) async {
      final world = StudentWorld()..server.sub(subscriptionId)['status'] = 'active';
      final front = ValueNotifier(false);
      final c = await pumpTab(tester, world, front);
      await rest(tester);
      expect(find.text('اشتراكي'), findsOneWidget, reason: 'the tab is built, behind the home tab');
      expect(world.log.of('sale_catalog'), 0, reason: 'built in the background: nothing on sale is shown');

      // Changes while the tab is behind: marked stale, read by nobody.
      await tester.runAsync(() => world.events(c, const [SyncEvent('lines', op: 'UPDATE', id: 'line-1')]));
      await tester.runAsync(() => world.events(c, const [SyncEvent('subscriptions', op: 'DELETE', id: 'gone')]));
      SyncScope.invalidateFor(c.invalidate, const {'subscriptions', 'lines'}, UserRole.student, studentId); // resume
      await rest(tester);
      expect(world.log.of('sale_catalog'), 0);

      // The student opens the tab: the "next period" card needs it, once.
      front.value = true;
      await rest(tester);
      expect(world.log.of('sale_catalog'), 1);
      // Away and back within the session: nothing.
      front.value = false;
      await rest(tester);
      front.value = true;
      await rest(tester);
      expect(world.log.of('sale_catalog'), 1);

      // A line changes while the tab is in front: read again, once.
      await tester.runAsync(() => world.events(c, const [SyncEvent('lines', op: 'UPDATE', id: 'line-1')]));
      await rest(tester);
      expect(world.log.of('sale_catalog'), 2);

      // The same change with the tab behind waits for the tab to be opened.
      front.value = false;
      await rest(tester);
      await tester.runAsync(() => world.events(c, const [SyncEvent('line_period_prices', op: 'UPDATE', id: 'p1')]));
      await rest(tester);
      expect(world.log.of('sale_catalog'), 2);
      front.value = true;
      await rest(tester);
      report('the catalog, running subscription', world.log);
      expect(world.log.of('sale_catalog'), 3);
    });

    testWidgets('a student with no subscription: not at app start, once when the Subscriptions tab is opened',
        (tester) async {
      final world = StudentWorld()..server.subs.clear();
      final front = ValueNotifier(false);
      final c = await pumpTab(tester, world, front);
      await rest(tester);
      expect(world.log.of('sale_catalog'), 0, reason: 'the purchase flow is built but not on screen');
      expect(find.byType(PurchaseFlow), findsOneWidget);

      front.value = true;
      await rest(tester);
      expect(world.log.of('sale_catalog'), 1);
      expect(find.textContaining('لا توجد حالياً شركات'), findsOneWidget, reason: 'the flow shows what was read');

      // To the home tab and back: what was shown stays, nothing is read.
      front.value = false;
      await rest(tester);
      expect(find.textContaining('لا توجد حالياً شركات'), findsOneWidget);
      await tester.runAsync(() => world.events(c, const [SyncEvent('lines', op: 'UPDATE', id: 'line-1')]));
      await rest(tester);
      expect(world.log.of('sale_catalog'), 1, reason: 'the change waits');
      front.value = true;
      await rest(tester);
      report('the catalog, no subscription', world.log);
      expect(world.log.of('sale_catalog'), 2, reason: 'read when the flow is shown again');
    });

    test('marking it stale reads nothing by itself; the next reader reads it once', () async {
      final world = StudentWorld();
      final c = world.open();
      await c.read(saleCatalogProvider.future); // the purchase flow was open, and is closed again
      await settle();
      expect(world.log.of('sale_catalog'), 1);

      c.invalidate(saleCatalogProvider);
      SyncScope.invalidateFor(c.invalidate, const {'lines', 'subscriptions'}, UserRole.student, studentId);
      await world.events(c, const [SyncEvent('lines', op: 'UPDATE', id: 'line-1')]);
      await settle();
      await settle();
      expect(world.log.of('sale_catalog'), 1, reason: 'nobody is watching: nothing is read');

      await c.read(saleCatalogProvider.future);
      expect(world.log.of('sale_catalog'), 2);
    });

    test('creating a subscription does not read it again: the student has left the purchase flow', () async {
      final world = StudentWorld();
      final c = world.open();
      await watchScreens(c);
      await c.read(saleCatalogProvider.future); // read by the flow that is about to close
      world.log.reset();

      final created = await c.read(subscriptionCreatorProvider)(const SubscriptionRequest(
          lineId: 'line-1', stationId: 'station-1', departureTripId: 't1', departureTime: '07:00:00',
          type: 'termly', price: 8000, periodCode: 'second', academicYear: 2026));
      c.invalidate(saleCatalogProvider); // what the screen does once the flow is off screen
      await loaded(c);
      await world.events(c, [SyncEvent('subscriptions', op: 'INSERT', id: created.id)]);
      await loaded(c);
      expect(world.log.calls, {'subscriptions.insert': 1});
    });
  });

  test('back in the app (or reconnected): everything is read once, the card costs nothing', () async {
    final world = StudentWorld();
    final c = world.open();
    await watchScreens(c);
    c.listen(myInvitesProvider, (_, __) {});
    c.listen(voteSettingsProvider, (_, __) {});
    await c.read(myInvitesProvider.future);
    await c.read(voteSettingsProvider.future);
    world.log.reset();
    world.inbox.pageRequests = 0;

    // What SyncScope does on resume and on reconnect.
    SyncScope.invalidateFor(c.invalidate, const {'subscriptions', 'lines', 'company_invites', 'students', 'notifications'},
        UserRole.student, studentId);
    c.invalidate(voteSettingsProvider);
    await loaded(c);
    await c.read(myInvitesProvider.future);
    await c.read(voteSettingsProvider.future);
    await c.read(notificationFeedProvider.future);

    report('resume', world.log);
    expect(world.log.calls, {
      'subscriptions.current': 1, 'subscriptions.all': 1, 'receipts.list': 1,
      'profile.summary': 1, 'invites.list': 1, 'vote_settings': 1,
    });
    expect(world.inbox.pageRequests, 1);
  });
}

class _Wallet implements StudentPassGateway {
  int refreshes = 0;
  bool fails = false;

  @override
  String? userId = studentId;

  @override
  Future<void> refreshWalletCard() async {
    refreshes++;
    if (fails) throw const SocketException('Failed host lookup');
  }
}
