import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/media/signed_url_cache.dart';
import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/sync/sync_hub.dart';
import 'package:basak_mobile/features/notifications/data/notification_feed.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/notifications/data/quick_templates.dart';
import 'package:basak_mobile/features/supervisor/data/supervisor_repository.dart';
import 'package:basak_mobile/features/supervisor/notifications/supervisor_notifications_screen.dart';
import 'package:basak_mobile/features/supervisor/rider_counts/presentation/rider_counts_screen.dart';
import 'package:basak_mobile/features/supervisor/trips/presentation/supervisor_trips_screen.dart';

import '../support/notification_fakes.dart';
import '../support/perf_fakes.dart';
import '../support/student_world.dart' show settle;
import '../support/supervisor_world.dart';

/// How many requests a supervisor's phone makes in its most used flows.
///
/// Run: flutter test test/perf/supervisor_request_count_test.dart
///
/// As in request_count_test.dart: everything below the repositories is a
/// counting fake of the server; the repositories, the providers, the saved
/// copies and the live-event mapping are the real ones.
void report(String flow, RequestLog log) {
  // ignore: avoid_print
  print('[requests] supervisor, $flow: $log');
}

const ManifestKey going = (lineId: 'line-a', direction: 'departure', tripId: null);
const ManifestKey returning = (lineId: 'line-a', direction: 'return', tripId: null);

/// What the supervisor's home tab keeps loaded.
Future<void> watchHome(ProviderContainer c) async {
  c.listen(supervisorDashboardProvider, (_, __) {});
  c.listen(supervisorPhotoUrlProvider, (_, __) {});
  c.listen(offeredSubscriptionTypesProvider(companyId), (_, __) {});
  c.listen(notificationFeedProvider, (_, __) {});
  await loaded(c);
}

Future<void> loaded(ProviderContainer c) async {
  for (var i = 0; i < 3; i++) {
    await c.read(supervisorDashboardProvider.future);
    await c.read(supervisorPhotoUrlProvider.future);
    await c.read(offeredSubscriptionTypesProvider(companyId).future);
    await c.read(notificationFeedProvider.future);
    await settle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    OfflineCache.debugUserId = supervisorId;
    OfflineCache.resetSession();
  });
  tearDown(() => OfflineCache.debugUserId = null);

  test('(e) a supervisor start, first and with everything saved, and coming back to the home tab', () async {
    final world = SupervisorWorld();
    var c = world.open();
    await watchHome(c);
    report('first start', world.log);
    const start = {
      'get_supervisor_dashboard': 1, 'supervisors.photo': 1, 'storage.sign': 1, 'get_subscription_switches': 1,
    };
    expect(world.log.calls, start);
    expect(world.inbox.pageRequests, 1);

    // Leaving the home tab and coming back reads nothing.
    await loaded(c);
    expect(world.log.calls, start, reason: 'what the home tab shows is kept for the session');

    // The next run of the app: everything is on the phone, and is checked once.
    c.dispose();
    OfflineCache.resetSession();
    SignedUrlCache.clear(); // memory is gone with the old run
    world.log.reset();
    var announced = 0;
    void listener() => announced++;
    OfflineCache.refreshed.addListener(listener);
    addTearDown(() => OfflineCache.refreshed.removeListener(listener));
    c = world.open();
    await watchHome(c);
    report('start with everything saved', world.log);
    expect(world.log.calls, {
      'get_supervisor_dashboard': 1, 'supervisors.photo': 1, 'get_subscription_switches': 1, 'storage.sign': 1,
    });
    expect(announced, 0, reason: 'nothing changed on the server, so nothing is read or drawn again');
  });

  test('(f) the trips tab: one read per trip list, none on coming back', () async {
    final world = SupervisorWorld();
    final c = world.open();
    await watchHome(c);
    world.log.reset();

    c.listen(tripManifestProvider(going), (_, __) {});
    await c.read(tripManifestProvider(going).future);
    expect(world.log.calls, {'get_supervisor_trip_manifest': 1});
    // The return trips are another list; going back to the first costs nothing.
    c.listen(tripManifestProvider(returning), (_, __) {});
    await c.read(tripManifestProvider(returning).future);
    await c.read(tripManifestProvider(going).future);
    report('trips: both directions, and back', world.log);
    expect(world.log.calls, {'get_supervisor_trip_manifest': 2});
  });

  test('(g) rider counts: every line in one request', () async {
    final world = SupervisorWorld();
    final c = world.open();
    await watchHome(c);
    world.log.reset();
    final day = DateTime(2026, 10, 9);
    final lines = [for (final line in c.read(supervisorDashboardProvider).value!.lines) line.id];

    final counts = await c.read(riderCountsRepoProvider).getAssignedStationRiderCounts(targetDate: day, lineIds: lines);
    report('rider counts, ${lines.length} lines', world.log);
    expect(counts.map((s) => s.lineId), lineIds, reason: 'every line, in the order of their names');
    expect(counts.every((s) => s.ridingCount == 3 && s.returningCount == 2), isTrue);
    expect(world.log.calls, {'get_lines_rider_counts': 1},
        reason: 'the dashboard already lists the lines; all of them are counted in one request');

    // A quiet refresh (a student voted) is one request again.
    await c.read(riderCountsRepoProvider).getAssignedStationRiderCounts(targetDate: day, lineIds: lines);
    expect(world.log.calls, {'get_lines_rider_counts': 2});

    // Opened before the dashboard is known: the lines are asked for first.
    world.log.reset();
    await c.read(riderCountsRepoProvider).getAssignedStationRiderCounts(targetDate: DateTime(2026, 10, 10));
    expect(world.log.calls, {'get_supervisor_assigned_line_ids': 1, 'get_lines_rider_counts': 1});
  });

  test('(g) rider counts on a database without the one-request function: line by line, as before', () async {
    final world = SupervisorWorld()..server.hasBatchCounts = false;
    final c = world.open();
    final day = DateTime(2026, 10, 9);

    final counts = await c.read(riderCountsRepoProvider).getAssignedStationRiderCounts(targetDate: day, lineIds: lineIds);
    report('rider counts, older database', world.log);
    expect(counts.map((s) => s.lineId), lineIds);
    expect(world.log.calls, {'get_lines_rider_counts': 1, 'get_line_rider_counts_with_returns': 3});

    // The missing function is asked for once in a run of the app, not every time.
    await c.read(riderCountsRepoProvider).getAssignedStationRiderCounts(targetDate: day, lineIds: lineIds);
    expect(world.log.calls, {'get_lines_rider_counts': 1, 'get_line_rider_counts_with_returns': 6});

    // What was counted is on the phone for a start without a connection.
    await settle();
    final saved = await OfflineCache.peek('rider_counts.2026-10-09.${lineIds.join(',')}') as Map;
    expect(saved.keys, lineIds);
  });

  test('(h) a scan: the check-in, then one read of the day\'s numbers and the trip list', () async {
    final world = SupervisorWorld();
    final c = world.open();
    await watchHome(c);
    c.listen(tripManifestProvider(going), (_, __) {});
    await c.read(tripManifestProvider(going).future);
    world.log.reset();

    final result = await c.read(supervisorRepoProvider).checkIn('QR-1', direction: 'departure', tripId: 'trip-1');
    // What the scanner does with a check-in.
    c.invalidate(supervisorMonthlySummaryProvider);
    c.invalidate(supervisorDashboardProvider);
    c.invalidate(tripManifestProvider);
    await loaded(c);
    await c.read(tripManifestProvider(going).future);
    const scanned = {
      'supervisor_check_in_student': 1, 'get_supervisor_dashboard': 1, 'get_supervisor_trip_manifest': 1,
    };
    expect(result.outcome.isSuccess, isTrue);
    expect(world.log.calls, scanned);
    expect(c.read(tripManifestProvider(going)).value?.trip?.students, 1, reason: 'the list shows the check-in');

    // The server announces the scan back to this phone.
    await world.events(c, const [SyncEvent('supervisor_scan_events', op: 'INSERT', id: 'scan-1')]);
    await loaded(c);
    await c.read(tripManifestProvider(going).future);
    report('scan, with its live echo', world.log);
    expect(world.log.calls, scanned, reason: 'its own scan is not read again because the server said so');

    // Another supervisor of the company scans: that is news.
    await world.events(c, const [SyncEvent('supervisor_scan_events', op: 'INSERT', id: 'scan-2')]);
    await loaded(c);
    await c.read(tripManifestProvider(going).future);
    expect(world.log.of('get_supervisor_dashboard'), 2);
    expect(world.log.of('get_supervisor_trip_manifest'), 2);
  });

  test('(h) two supervisors scanning at the same moment: the other one\'s scan is still heard', () async {
    final world = SupervisorWorld();
    final c = world.open();
    await watchHome(c);
    world.log.reset();

    await c.read(supervisorRepoProvider).checkIn('QR-1', direction: 'departure');
    await world.events(c, const [
      SyncEvent('supervisor_scan_events', op: 'INSERT', id: 'mine'),
      SyncEvent('supervisor_scan_events', op: 'INSERT', id: 'theirs'),
    ]);
    await loaded(c);
    expect(world.log.of('get_supervisor_dashboard'), 1, reason: 'one announcement was its own, the other was not');
  });

  test('(i) what happens in the company and shows nowhere in the supervisor\'s app reads nothing', () async {
    final world = SupervisorWorld();
    final c = world.open();
    await watchHome(c);
    c.listen(tripManifestProvider(going), (_, __) {});
    await c.read(tripManifestProvider(going).future);
    world.log.reset();
    world.inbox.pageRequests = 0;

    // A student sends a receipt, the company reviews it, edits its payment
    // methods, its prices and its Wallet card; a student asks for a password.
    for (final table in SyncScope.supervisorUnrelatedTables.difference(
        const {'notifications', 'notification_preferences', 'notification_templates'})) {
      await world.events(c, [SyncEvent(table, op: 'INSERT', id: 'x-$table')]);
    }
    await loaded(c);
    report('unrelated company events', world.log);
    expect(world.log.total, 0);
    expect(world.inbox.pageRequests, 0);

    // A student votes: the numbers and the trip list, nothing else.
    await world.events(c, const [SyncEvent('daily_ride_status', op: 'UPDATE', id: 'student-1')]);
    await loaded(c);
    await c.read(tripManifestProvider(going).future);
    report('a student\'s vote', world.log);
    expect(world.log.calls, {'get_supervisor_dashboard': 1, 'get_supervisor_trip_manifest': 1});

    // The company changes its settings: what is on sale is read too.
    world.log.reset();
    await world.events(c, const [SyncEvent('companies', op: 'UPDATE', id: companyId)]);
    await loaded(c);
    await c.read(tripManifestProvider(going).future);
    expect(world.log.calls,
        {'get_supervisor_dashboard': 1, 'get_supervisor_trip_manifest': 1, 'get_subscription_switches': 1});

    // A table this version does not know is taken as news.
    world.log.reset();
    await world.events(c, const [SyncEvent('something_new', op: 'UPDATE', id: '1')]);
    await loaded(c);
    expect(world.log.of('get_supervisor_dashboard'), 1);
  });

  test('(j) the month: one read per month, none on coming back; a scan reads it again', () async {
    final world = SupervisorWorld();
    final c = world.open();
    final october = DateTime(2026, 10), september = DateTime(2026, 9);

    c.listen(supervisorMonthlySummaryProvider(october), (_, __) {});
    await c.read(supervisorMonthlySummaryProvider(october).future);
    await c.read(supervisorMonthlySummaryProvider(september).future);
    await c.read(supervisorMonthlySummaryProvider(october).future);
    report('monthly: two months, and back', world.log);
    expect(world.log.calls, {'get_supervisor_monthly_summary': 2});

    await world.events(c, const [SyncEvent('supervisor_scan_events', op: 'INSERT', id: 'scan-9')]);
    await c.read(supervisorMonthlySummaryProvider(october).future);
    expect(world.log.of('get_supervisor_monthly_summary'), 3);
  });

  test('(k) sending a notification: the send and one read of the inbox, its echo included', () async {
    final world = SupervisorWorld();
    world.inbox.templates = const [QuickNotificationTemplate(key: 'delay', title: 'تأخير', body: 'تأخير {minutes}')];
    final c = world.open();
    await watchHome(c);
    c.listen(quickTemplatesProvider, (_, __) {});
    await c.read(quickTemplatesProvider.future);
    world.inbox.pageRequests = 0;

    final result = await sendAnnouncedOnce(() => world.inbox
        .sendQuick(templateKey: 'delay', lineId: 'line-a', minutes: 10, idempotencyKey: 'key-1'));
    world.inbox.inbox.add(note('sent-1', 'تأخير'));
    // What the screen does when the sheet closes.
    c.invalidate(notificationFeedProvider);
    await loaded(c);
    expect(result.duplicate, isFalse);
    expect(world.inbox.pageRequests, 1);

    await world.events(c, const [SyncEvent('notifications', op: 'INSERT', id: 'sent-1')]);
    await loaded(c);
    expect(world.inbox.pageRequests, 1, reason: 'the announcement of its own notification reads nothing');
    expect(world.inbox.quickSent, hasLength(1));

    // The company's admin sends one: that is read.
    world.inbox.inbox.add(note('other-1', 'إعلان'));
    await world.events(c, const [SyncEvent('notifications', op: 'INSERT', id: 'other-1')]);
    await loaded(c);
    expect(world.inbox.pageRequests, 2);
    expect(c.read(notificationFeedProvider).value?.items.map((n) => n.id), containsAll(['sent-1', 'other-1']));
  });
}
