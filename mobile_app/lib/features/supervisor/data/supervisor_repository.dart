import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/supabase_tables.dart';
import '../../../core/media/company_brand.dart';
import '../../../core/media/signed_url_cache.dart';
import '../../../core/network/supabase_service.dart';
import '../../../core/storage/offline_cache.dart';
import '../../../core/sync/own_changes.dart';
import '../../../core/sync/session.dart';
import '../models/supervisor_models.dart';
import '../qr_scanner/data/qr_scanner_repository.dart';

/// The requests behind the supervisor's screens (replaced in tests).
abstract class SupervisorGateway {
  String? get userId;

  /// A database function, by name.
  Future<dynamic> rpc(String function, [Map<String, dynamic>? params]);

  /// The supervisor's own row: where their photo is stored.
  Future<Map<String, dynamic>?> photoRow(String userId);

  /// The supervisor's own company: its name and where its logo and emblem are.
  Future<Map<String, dynamic>?> companyRow(String companyId);
}

class SupabaseSupervisorGateway implements SupervisorGateway {
  const SupabaseSupervisorGateway();

  SupabaseClient get _client => SupabaseService.client;

  @override
  String? get userId => _client.auth.currentUser?.id;

  @override
  Future<dynamic> rpc(String function, [Map<String, dynamic>? params]) => _client.rpc(function, params: params);

  @override
  Future<Map<String, dynamic>?> photoRow(String userId) =>
      _client.from('supervisors').select('profile_image_url').eq('id', userId).maybeSingle();

  @override
  Future<Map<String, dynamic>?> companyRow(String companyId) async {
    Future<Map<String, dynamic>?> read(String columns) =>
        _client.from('companies').select(columns).eq('id', companyId).maybeSingle();
    try {
      return await read('id,name,logo_path,emblem_path');
    } on PostgrestException catch (error) {
      // A database without the emblem yet: the logo alone, as before.
      if (error.code != '42703') rethrow;
      return read('id,name,logo_path');
    }
  }
}

/// Supervisor backend: every call goes through SECURITY DEFINER RPCs that are
/// scoped to auth.uid() and the supervisor's assigned lines on the server.
class SupervisorRepository {
  final SupervisorGateway _gateway;
  final QrScannerRepository _lookup;

  SupervisorRepository({SupervisorGateway? gateway, QrScannerRepository? lookup})
      : _gateway = gateway ?? const SupabaseSupervisorGateway(),
        _lookup = lookup ?? QrScannerRepository();

  Future<SupervisorDashboard> getDashboard() async =>
      SupervisorDashboard.fromJson(await getDashboardJson());

  /// [getDashboard] as the server sent it, so it can be saved for the next start.
  Future<Map<String, dynamic>> getDashboardJson() async {
    final response = await OfflineCache.readThrough('supervisor.dashboard',
        () => _gateway.rpc(SupabaseRpcs.getSupervisorDashboard));
    return Map<String, dynamic>.from(response as Map);
  }

  /// Verifies the QR and records a check-in for today's [direction] trip.
  /// Offline: falls back to the cached read-only lookup (nothing is recorded).
  Future<CheckInResult> checkIn(String qrValue, {required String direction, String? tripId}) async {
    final qr = qrValue.trim();
    // Every scan is logged, and the server announces it back to this phone
    // too. The scanner refreshes what shows it itself, so that one
    // announcement is not acted on again (another supervisor's still is).
    final echo = OwnChanges.begin('supervisor_scan_events', op: 'INSERT', once: true);
    try {
      final response = await _gateway.rpc(SupabaseRpcs.supervisorCheckInStudent,
          {'p_qr_code': qr, 'p_direction': direction, if (tripId != null) 'p_trip_id': tripId});
      echo.done();
      final json = Map<String, dynamic>.from(response as Map);
      if (json['student'] is Map) {
        final me = _gateway.userId;
        if (me != null) {
          await OfflineCache.saveStudentLookup(me, qr, Map<String, dynamic>.from(json['student'] as Map));
        }
      }
      return CheckInResult.fromJson(json);
    } on PostgrestException catch (error) {
      echo.failed();
      // An invalid (non-UUID) code is a "not found", not a crash.
      if (error.code == '22P02') {
        return CheckInResult(outcome: CheckInOutcome.notFound, direction: direction);
      }
      rethrow;
    } catch (error) {
      echo.failed();
      final details = await _lookup.lookupStudentByQr(qr); // offline cache path
      if (!details.isOfflineCache) rethrow;
      return CheckInResult(
          outcome: CheckInOutcome.offlineLookup, direction: direction, student: details);
    }
  }

  /// One Going (departure) or Return trip of a line: route, stop times and the
  /// students per station with their check-in state for today.
  Future<TripManifest> getTripManifest(
      {required String lineId, required String direction, String? tripId}) async {
    final day = DateTime.now().toIso8601String().substring(0, 10);
    final response = await OfflineCache.readThrough(
        'supervisor.manifest.$day.$lineId.$direction.${tripId ?? '-'}',
        () => _gateway.rpc(SupabaseRpcs.getSupervisorTripManifest, {
              'p_line_id': lineId,
              'p_direction': direction,
              if (tripId != null) 'p_trip_id': tripId,
            }));
    return TripManifest.fromJson(Map<String, dynamic>.from(response as Map));
  }

  Future<({bool annual, bool daily})> getOfferedTypes(String companyId) async {
    final response = await OfflineCache.readThrough(
        'supervisor.offered.$companyId',
        () => _gateway.rpc(SupabaseRpcs.getSubscriptionSwitches, {'p_company_id': companyId}));
    final switches = Map<String, dynamic>.from(response as Map);
    return (annual: switches['annual_effective'] == true, daily: switches['daily_effective'] == true);
  }

  Future<SupervisorMonthlySummary> getMonthlySummary(DateTime month) async {
    final first = DateTime(month.year, month.month, 1);
    final monthStr = first.toIso8601String().substring(0, 10);
    final response = await OfflineCache.readThrough(
        'supervisor.monthly.$monthStr',
        () => _gateway.rpc(SupabaseRpcs.getSupervisorMonthlySummary, {'p_month': monthStr}));

    return SupervisorMonthlySummary.fromJson(Map<String, dynamic>.from(response as Map));
  }

  /// Seats of one bus per line, as the company set them: `{line id: seats}`.
  /// A line without a number is left out. Empty on a database that has no
  /// `get_my_line_capacities` yet, and whenever it cannot be read: the screens
  /// then simply say nothing about buses.
  Future<Map<String, int>> getLineCapacities() async {
    try {
      final response = await OfflineCache.readThrough(
          'supervisor.capacities', () => _gateway.rpc(SupabaseRpcs.getMyLineCapacities));
      return {
        for (final row in response as List? ?? const [])
          if (row is Map && row['line_id'] != null && (row['bus_capacity'] as num? ?? 0) > 0)
            '${row['line_id']}': (row['bus_capacity'] as num).toInt(),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Where the supervisor's own photo is stored (null: none).
  Future<String?> getPhotoPath(String userId) async {
    final row = await OfflineCache.readThrough('supervisor.photo', () => _gateway.photoRow(userId));
    final path = (row as Map?)?['profile_image_url'] as String?;
    return path == null || path.isEmpty ? null : path;
  }

  /// The logo and emblem of the supervisor's company: from the saved copy at
  /// once, and asked of the server once behind it.
  Future<CompanyBrand> getCompanyBrand(String companyId) async => CompanyBrand.fromJson(
      await OfflineCache.readThrough('supervisor.company.$companyId', () => _gateway.companyRow(companyId)));
}

final supervisorRepoProvider = Provider((ref) => SupervisorRepository());

/// Subscription types the company offers now (platform AND company switches).
/// Kept for the session, so coming back to the home tab does not ask again;
/// refreshed when the company changes and on return to the app.
final offeredSubscriptionTypesProvider =
    FutureProvider.family<({bool annual, bool daily}), String>((ref, companyId) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(supervisorRepoProvider).getOfferedTypes(companyId);
});

/// The supervisor's lines and today's numbers: from the saved copy at once, then
/// from the server; kept between tabs and refreshed by live events.
class SupervisorDashboardNotifier extends SnapshotNotifier<SupervisorDashboard> {
  @override
  String get snapshotName => 'supervisor_dashboard';
  @override
  SupervisorDashboard get signedOut => throw StateError('not signed in');
  @override
  Future<Object?> fetchJson() => ref.read(supervisorRepoProvider).getDashboardJson();
  @override
  SupervisorDashboard parse(Object? json) =>
      SupervisorDashboard.fromJson(Map<String, dynamic>.from(json as Map));
}

final supervisorDashboardProvider =
    AsyncNotifierProvider<SupervisorDashboardNotifier, SupervisorDashboard>(SupervisorDashboardNotifier.new);

/// The supervisor's own photo, added by the company in the dashboard: a
/// short-lived link, or null (no photo, or it cannot be loaded now).
final supervisorPhotoUrlProvider = FutureProvider<String?>((ref) async {
  final userId = ref.watch(sessionUserIdProvider);
  if (userId == null) return null;
  try {
    final path = await ref.watch(supervisorRepoProvider).getPhotoPath(userId);
    if (path == null) return null;
    return await SignedUrlCache.urlOrOffline('supervisor-avatars', path);
  } catch (_) {
    return null;
  }
});

/// The supervisor's company's logo and emblem, kept for the session. Read
/// only by the account page, where the company is named; with no answer (or a
/// refusal) the company is its name alone.
final supervisorCompanyBrandProvider = FutureProvider.family<CompanyBrand, String>((ref, companyId) async {
  ref.watch(sessionUserIdProvider);
  try {
    return await ref.watch(supervisorRepoProvider).getCompanyBrand(companyId);
  } catch (_) {
    return CompanyBrand.none;
  }
});

/// Seats of one bus per line (`{line id: seats}`), kept for the session.
/// Empty when the company set none or the database cannot say.
final lineCapacitiesProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(supervisorRepoProvider).getLineCapacities();
});

// Kept per month for the session, so going back to a month does not reload it.
final supervisorMonthlySummaryProvider =
    FutureProvider.family<SupervisorMonthlySummary, DateTime>((ref, month) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(supervisorRepoProvider).getMonthlySummary(month);
});
