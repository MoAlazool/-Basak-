import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/storage/snapshot_store.dart';
import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/core/sync/sync_hub.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/notifications/data/notification_feed.dart';
import 'package:basak_mobile/features/notifications/data/notification_preferences.dart';
import 'package:basak_mobile/features/notifications/data/quick_templates.dart';
import 'package:basak_mobile/features/student/invites/invites.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/supervisor/data/supervisor_repository.dart';

/// A provider under test: counts server reads and returns whatever `server` holds.
class _Probe extends SnapshotNotifier<String?> {
  static int fetches = 0;
  static String? server;

  @override
  String get snapshotName => 'probe';
  @override
  String? get signedOut => null;
  @override
  Future<Object?> fetchJson() async {
    fetches++;
    return server;
  }

  @override
  String? parse(Object? json) => json as String?;
}

final _probeProvider = AsyncNotifierProvider<_Probe, String?>(_Probe.new);

ProviderContainer _container(String? userId) {
  final container = ProviderContainer(overrides: [sessionUserIdProvider.overrideWith((ref) => userId)]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    _Probe.fetches = 0;
    _Probe.server = 'fresh';
  });

  test('first start: nothing saved, so the value comes from the server and is saved', () async {
    final container = _container('user-a');
    expect(await container.read(_probeProvider.future), 'fresh');
    expect(_Probe.fetches, 1);
    expect(await SnapshotStore.read('user-a', 'probe'), 'fresh');
  });

  test('next start: the saved copy shows at once, then the fresh value replaces it', () async {
    await SnapshotStore.write('user-a', 'probe', 'saved');
    final container = _container('user-a');
    expect(await container.read(_probeProvider.future), 'saved');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(_probeProvider).value, 'fresh');
    expect(await SnapshotStore.read('user-a', 'probe'), 'fresh');
  });

  test('a refresh keeps the previous value on screen and always asks the server', () async {
    await SnapshotStore.write('user-a', 'probe', 'saved');
    final container = _container('user-a');
    await container.read(_probeProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    _Probe.server = 'newer';
    container.invalidate(_probeProvider);
    final during = container.read(_probeProvider);
    expect(during.hasValue && during.value == 'fresh', isTrue, reason: 'no blank state while refreshing');
    expect(await container.read(_probeProvider.future), 'newer');
  });

  test('offline at start: the saved copy stays', () async {
    await SnapshotStore.write('user-a', 'probe', 'saved');
    _Probe.server = null;
    final container = ProviderContainer(overrides: [
      sessionUserIdProvider.overrideWith((ref) => 'user-a'),
      _probeProvider.overrideWith(_Offline.new),
    ]);
    addTearDown(container.dispose);
    expect(await container.read(_probeProvider.future), 'saved');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(_probeProvider).value, 'saved');
  });

  test('one account never sees another account\'s saved copy', () async {
    await SnapshotStore.write('user-a', 'probe', 'saved for a');
    _Probe.server = 'b from server';
    final container = _container('user-b');
    expect(await container.read(_probeProvider.future), 'b from server');
  });

  test('signed out: no server read, no saved copy', () async {
    await SnapshotStore.write('user-a', 'probe', 'saved');
    final container = _container(null);
    expect(await container.read(_probeProvider.future), isNull);
    expect(_Probe.fetches, 0);
  });

  test('sign-out clears every saved copy', () async {
    await SnapshotStore.write('user-a', 'probe', 'saved');
    await SnapshotStore.write('user-b', 'other', {'x': 1});
    await SnapshotStore.clear();
    expect(await SnapshotStore.read('user-a', 'probe'), isNull);
    expect(await SnapshotStore.read('user-b', 'other'), isNull);
  });

  group('live events', () {
    test('every signed-in role listens to its own user topic, next to its role\'s topics', () {
      expect(SyncScope.topicsFor(userId: 'u1', role: UserRole.student, lineId: 'l1'),
          {'user:u1', 'student:u1', 'line:l1'});
      expect(SyncScope.topicsFor(userId: 'u1', role: UserRole.student), {'user:u1', 'student:u1'});
      expect(SyncScope.topicsFor(userId: 's1', role: UserRole.supervisor, companyId: 'c1'),
          {'user:s1', 'company:c1'});
      expect(SyncScope.topicsFor(userId: 's1', role: UserRole.supervisor, companyId: ''), {'user:s1'});
      expect(SyncScope.topicsFor(userId: 'x', role: UserRole.unknown), {'user:x'});
      expect(SyncScope.topicsFor(userId: null, role: UserRole.student, lineId: 'l1'), isEmpty);
    });

    test('a notification arriving, deleted, or read on another phone is a notifications change', () {
      for (final op in ['INSERT', 'DELETE', 'READ']) {
        expect(SyncScope.tableOf({'table': 'notifications', 'op': op, 'id': 'n1', 'company_id': 'c1'}),
            'notifications');
        // Older clients of the realtime library wrap the body in `payload`.
        expect(
            SyncScope.tableOf({
              'event': 'change',
              'payload': {'table': 'notifications', 'op': op, 'id': 'n1'},
            }),
            'notifications');
      }
      expect(SyncScope.tableOf(const {}), '');
    });

    test('a notifications change re-reads the inbox and nothing else', () {
      for (final role in [UserRole.student, UserRole.supervisor]) {
        final invalidated = <ProviderOrFamily>[];
        SyncScope.invalidateFor(invalidated.add, const {'notifications'}, role, 'u1');
        expect(invalidated, [notificationFeedProvider], reason: role.name);
      }

      // Other tables still refresh what they always did, without the inbox.
      final student = <ProviderOrFamily>[];
      SyncScope.invalidateFor(student.add, const {'subscriptions'}, UserRole.student, 'u1');
      expect(student, contains(currentSubscriptionProvider));
      expect(student, isNot(contains(notificationFeedProvider)));

      final supervisor = <ProviderOrFamily>[];
      SyncScope.invalidateFor(supervisor.add, const {'supervisor_scan_events'}, UserRole.supervisor, 's1');
      expect(supervisor, contains(supervisorDashboardProvider));
      expect(supervisor, isNot(contains(notificationFeedProvider)));

      // A burst touching both refreshes both.
      final both = <ProviderOrFamily>[];
      SyncScope.invalidateFor(both.add, const {'notifications', 'supervisors'}, UserRole.supervisor, 's1');
      expect(both, containsAll([notificationFeedProvider, supervisorDashboardProvider]));
    });

    test('a saved copy that turned out stale re-reads only its own screen', () {
      expect(SyncScope.tablesFor('notifications.page'), {'notifications'});
      expect(SyncScope.tablesFor('notification_preferences'), {'notification_preferences'});
      expect(SyncScope.tablesFor('notification_templates'), {'notification_templates'});
      expect(SyncScope.tablesFor('subscriptions'), {'subscriptions'});

      final preferences = <ProviderOrFamily>[];
      SyncScope.invalidateFor(
          preferences.add, SyncScope.tablesFor('notification_preferences'), UserRole.student, 'u1');
      expect(preferences, [notificationPreferencesProvider]);

      final templates = <ProviderOrFamily>[];
      SyncScope.invalidateFor(
          templates.add, SyncScope.tablesFor('notification_templates'), UserRole.supervisor, 's1');
      expect(templates, [quickTemplatesProvider]);
    });
  });

  test('a phone typed on an Arabic keyboard is the same number', () {
    expect(AuthRepository.normalizeEgyptianPhone('٠١٠٢٥٧٤٨٣٦٣'), '01025748363');
    expect(AuthRepository.normalizeEgyptianPhone('+20 102 574 8363'), '01025748363');
    expect(AuthRepository.normalizeEgyptianPhone('۰۱۰۲۵۷۴۸۳۶۳'), '01025748363');
  });

  test('an invitation is read from what the server sends', () {
    final invite = CompanyInvite.fromJson({
      'id': 'i1', 'company_name': 'المستقبل', 'line_name': 'الزرقا', 'station_name': 'السرو',
      'subscription_type': 'yearly', 'price': 7500,
    });
    expect(invite.companyName, 'المستقبل');
    expect(invite.typeLabel, 'اشتراك سنوي');
    expect(invite.price, 7500);
  });
}

class _Offline extends _Probe {
  @override
  Future<Object?> fetchJson() async => throw Exception('offline');
}
