import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:basak_mobile/core/media/signed_url_cache.dart';
import 'package:basak_mobile/core/sync/sync_hub.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/supervisor/data/supervisor_repository.dart';
import 'package:basak_mobile/features/supervisor/rider_counts/data/rider_counts_repository.dart';
import 'package:basak_mobile/features/supervisor/rider_counts/presentation/rider_counts_screen.dart';

import 'notification_fakes.dart';
import 'perf_fakes.dart';

const supervisorId = 'supervisor-1';
const companyId = 'company-1';
const lineIds = ['line-a', 'line-b', 'line-c'];

/// The server as a supervisor's phone sees it: every database function it
/// calls, counted by name.
class FakeSupervisorServer implements SupervisorGateway, RiderCountsGateway {
  final RequestLog log;
  FakeSupervisorServer(this.log);

  /// A database that does not have `get_lines_rider_counts` yet.
  bool hasBatchCounts = true;
  int checkedIn = 0;

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
            for (final id in lineIds) {'id': id, 'name': 'خط $id', 'registered_students': 12}
          ],
          'trip_times': <dynamic>[],
        };
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

  @override
  Future<dynamic> assignedLineIds() async {
    log.hit('get_supervisor_assigned_line_ids');
    return [
      for (final id in lineIds) {'line_id': id}
    ];
  }

  List<Map<String, dynamic>> _rows(String lineId) => [
        {
          'line_id': lineId, 'line_name': 'خط $lineId', 'station_id': 'st-$lineId', 'station_name': 'محطة',
          'order_index': 1, 'departure_time': '07:00:00', 'return_time': '15:00:00',
          'riding_count': 3, 'returning_count': 2,
        }
      ];

  @override
  Future<dynamic> countsForLines(List<String> lineIds, String date) async {
    log.hit('get_lines_rider_counts');
    if (!hasBatchCounts) throw const LinesRiderCountsUnavailable();
    return {for (final id in lineIds) id: _rows(id)};
  }

  @override
  Future<dynamic> countsForLine(String lineId, String date) async {
    log.hit('get_line_rider_counts_with_returns');
    return _rows(lineId);
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
        riderCountsRepoProvider.overrideWithValue(RiderCountsRepository(gateway: server)),
        notificationsRepoProvider.overrideWithValue(inbox),
      ];

  ProviderContainer open() {
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    return container;
  }
}
