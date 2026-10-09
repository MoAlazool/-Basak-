import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/supabase_tables.dart';
import '../../../core/media/signed_url_cache.dart';
import '../../../core/network/supabase_service.dart';
import '../../../core/storage/offline_cache.dart';
import '../../../core/sync/session.dart';
import '../models/supervisor_models.dart';
import '../qr_scanner/data/qr_scanner_repository.dart';

/// Supervisor backend: every call goes through SECURITY DEFINER RPCs that are
/// scoped to auth.uid() and the supervisor's assigned lines on the server.
class SupervisorRepository {
  final SupabaseClient _client = SupabaseService.client;
  final QrScannerRepository _lookup = QrScannerRepository();

  Future<SupervisorDashboard> getDashboard() async =>
      SupervisorDashboard.fromJson(await getDashboardJson());

  /// [getDashboard] as the server sent it, so it can be saved for the next start.
  Future<Map<String, dynamic>> getDashboardJson() async {
    final response = await OfflineCache.readThrough('supervisor.dashboard',
        () => _client.rpc(SupabaseRpcs.getSupervisorDashboard));
    return Map<String, dynamic>.from(response as Map);
  }

  /// Verifies the QR and records a check-in for today's [direction] trip.
  /// Offline: falls back to the cached read-only lookup (nothing is recorded).
  Future<CheckInResult> checkIn(String qrValue, {required String direction, String? tripId}) async {
    final qr = qrValue.trim();
    try {
      final response = await _client.rpc(SupabaseRpcs.supervisorCheckInStudent,
          params: {'p_qr_code': qr, 'p_direction': direction, if (tripId != null) 'p_trip_id': tripId});
      final json = Map<String, dynamic>.from(response as Map);
      if (json['student'] is Map) {
        final me = _client.auth.currentUser?.id;
        if (me != null) {
          await OfflineCache.saveStudentLookup(me, qr, Map<String, dynamic>.from(json['student'] as Map));
        }
      }
      return CheckInResult.fromJson(json);
    } on PostgrestException catch (error) {
      // An invalid (non-UUID) code is a "not found", not a crash.
      if (error.code == '22P02') {
        return CheckInResult(outcome: CheckInOutcome.notFound, direction: direction);
      }
      rethrow;
    } catch (error) {
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
        () => _client.rpc(SupabaseRpcs.getSupervisorTripManifest, params: {
              'p_line_id': lineId,
              'p_direction': direction,
              if (tripId != null) 'p_trip_id': tripId,
            }));
    return TripManifest.fromJson(Map<String, dynamic>.from(response as Map));
  }

  Future<({bool annual, bool daily})> getOfferedTypes(String companyId) async {
    final response = await OfflineCache.readThrough(
        'supervisor.offered.$companyId',
        () => _client.rpc(SupabaseRpcs.getSubscriptionSwitches,
            params: {'p_company_id': companyId}));
    final switches = Map<String, dynamic>.from(response as Map);
    return (annual: switches['annual_effective'] == true, daily: switches['daily_effective'] == true);
  }

  Future<SupervisorMonthlySummary> getMonthlySummary(DateTime month) async {
    final first = DateTime(month.year, month.month, 1);
    final monthStr = first.toIso8601String().substring(0, 10);
    final response = await OfflineCache.readThrough(
        'supervisor.monthly.$monthStr',
        () => _client.rpc(SupabaseRpcs.getSupervisorMonthlySummary,
            params: {'p_month': monthStr}));
    return SupervisorMonthlySummary.fromJson(Map<String, dynamic>.from(response as Map));
  }
}

final supervisorRepoProvider = Provider((ref) => SupervisorRepository());

/// Subscription types the company offers now (platform AND company switches).
final offeredSubscriptionTypesProvider =
    FutureProvider.autoDispose.family<({bool annual, bool daily}), String>(
        (ref, companyId) => ref.watch(supervisorRepoProvider).getOfferedTypes(companyId));

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
    final client = SupabaseService.client;
    final row = await OfflineCache.readThrough('supervisor.photo',
        () => client.from('supervisors').select('profile_image_url').eq('id', userId).maybeSingle());
    final path = (row as Map?)?['profile_image_url'] as String?;
    if (path == null || path.isEmpty) return null;
    return await SignedUrlCache.urlOrOffline('supervisor-avatars', path);
  } catch (_) {
    return null;
  }
});

// Kept per month for the session, so going back to a month does not reload it.
final supervisorMonthlySummaryProvider =
    FutureProvider.family<SupervisorMonthlySummary, DateTime>((ref, month) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(supervisorRepoProvider).getMonthlySummary(month);
});
