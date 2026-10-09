import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:basak_mobile/core/media/signed_url_cache.dart';
import 'package:basak_mobile/core/sync/sync_hub.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:basak_mobile/features/supervisor/data/supervisor_repository.dart';

import 'notification_fakes.dart';
import 'perf_fakes.dart';

const supervisorId = 'supervisor-1';
const companyId = 'company-1';
const lineIds = ['line-a', 'line-b', 'line-c'];

/// The server as a supervisor's phone sees it: every database function it
/// calls, counted by name.
class FakeSupervisorServer implements SupervisorGateway {
  final RequestLog log;
  FakeSupervisorServer(this.log);

  /// A database that does not have `get_my_line_capacities` yet.
  bool hasCapacities = true;

  /// Seats of one bus per line; a line the company gave no number is null.
  Map<String, int?> capacities = {'line-a': 50, 'line-b': null, 'line-c': 28};
  int checkedIn = 0;

  /// `trip_times` of the dashboard: the riders per trip, today and tomorrow.
  List<Map<String, dynamic>> tripTimes = [];

  /// `trips` of every line of the dashboard. Null: a server that lists none.
  List<Map<String, dynamic>>? lineTrips = [];

  @override
  String? userId = supervisorId;

  @override
  Future<dynamic> rpc(String function, [Map<String, dynamic>? params]) async {
    log.hit(function);
    switch (function) {
      case 'get_supervisor_dashboard':
        return {
          'today': '2026-10-09',
          'profile': {'id': supervisorId, 'full_name': 'محمود', 'company_id': companyId, 'is_active': true},
          'totals': {'checked_in_today': checkedIn},
          'lines': [
            for (final id in lineIds)
              {'id': id, 'name': 'خط $id', 'registered_students': 12, if (lineTrips != null) 'trips': lineTrips}
          ],
          'trip_times': tripTimes,
        };
      case 'get_my_line_capacities':
        if (!hasCapacities) {
          throw const PostgrestException(message: 'Could not find the function', code: 'PGRST202');
        }
        return [
          for (final id in lineIds) {'line_id': id, 'bus_capacity': capacities[id]}
        ];
      case 'get_supervisor_trip_manifest':
        return {
          'line': {'id': params!['p_line_id'], 'name': 'خط'},
          'direction': params['p_direction'],
          'trips': <dynamic>[],
          'trip': {'id': 'trip-1', 'label': '', 'start_time': '07:00:00', 'students': checkedIn},
          'stations': <dynamic>[],
        };
      case 'get_subscription_switches':
        return {'annual_effective': true, 'daily_effective': false};
      case 'get_supervisor_monthly_summary':
        return {'month': params!['p_month'], 'totals': {'checkins': checkedIn}};
      case 'supervisor_check_in_student':
        checkedIn++;
        return {'result': 'checked_in', 'direction': params!['p_direction'], 'message': 'تم'};
    }
    throw StateError('unexpected function $function');
  }

  @override
  Future<Map<String, dynamic>?> photoRow(String userId) async {
    log.hit('supervisors.photo');
    return {'profile_image_url': '$supervisorId/photo.jpg'};
  }

}

class FakeSupervisorAuth extends AuthNotifier {
  FakeSupervisorAuth() : super(AuthRepository()) {
    state = const AuthState(
        user: User(id: supervisorId, appMetadata: {}, userMetadata: {}, aud: '', createdAt: ''),
        role: UserRole.supervisor);
  }
}

/// A signed-in supervisor's app over a fake server: the real repositories,
/// providers, saved copies and live-event handling, with every request counted.
class SupervisorWorld {
  final log = RequestLog();
  late final server = FakeSupervisorServer(log);
  final inbox = FakeNotificationsRepo();

  SupervisorWorld() {
    fakeSigner(log);
    SignedUrlCache.clear();
    OwnChanges.clear();
  }

  /// Live events reaching this phone, handled as SyncScope handles them.
  Future<void> events(ProviderContainer c, List<SyncEvent> events) => SyncScope.onEvents(events,
      invalidate: c.invalidate, read: c.read, role: UserRole.supervisor, userId: supervisorId);

  List<Override> get overrides => [
        authStateProvider.overrideWith((ref) => FakeSupervisorAuth()),
        supervisorRepoProvider.overrideWithValue(SupervisorRepository(gateway: server)),
        notificationsRepoProvider.overrideWithValue(inbox),
      ];

  ProviderContainer open() {
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    return container;
  }
}
