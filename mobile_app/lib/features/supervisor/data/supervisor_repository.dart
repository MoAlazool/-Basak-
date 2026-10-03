import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/supabase_tables.dart';
import '../../../core/network/supabase_service.dart';
import '../../../core/storage/offline_cache.dart';
import '../models/supervisor_models.dart';
import '../qr_scanner/data/qr_scanner_repository.dart';

/// Supervisor backend: every call goes through SECURITY DEFINER RPCs that are
/// scoped to auth.uid() and the supervisor's assigned lines on the server.
class SupervisorRepository {
  final SupabaseClient _client = SupabaseService.client;
  final QrScannerRepository _lookup = QrScannerRepository();

  Future<SupervisorDashboard> getDashboard() async {
    final response = await _client.rpc(SupabaseRpcs.getSupervisorDashboard);
    return SupervisorDashboard.fromJson(Map<String, dynamic>.from(response as Map));
  }

  /// Verifies the QR and records a check-in for today's [direction] trip.
  /// Offline: falls back to the cached read-only lookup (nothing is recorded).
  Future<CheckInResult> checkIn(String qrValue, {required String direction}) async {
    final qr = qrValue.trim();
    try {
      final response = await _client.rpc(SupabaseRpcs.supervisorCheckInStudent,
          params: {'p_qr_code': qr, 'p_direction': direction});
      final json = Map<String, dynamic>.from(response as Map);
      if (json['student'] is Map) {
        await OfflineCache.saveStudentLookup(qr, Map<String, dynamic>.from(json['student'] as Map));
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

  Future<SupervisorMonthlySummary> getMonthlySummary(DateTime month) async {
    final first = DateTime(month.year, month.month, 1);
    final response = await _client.rpc(SupabaseRpcs.getSupervisorMonthlySummary,
        params: {'p_month': first.toIso8601String().substring(0, 10)});
    return SupervisorMonthlySummary.fromJson(Map<String, dynamic>.from(response as Map));
  }
}

final supervisorRepoProvider = Provider((ref) => SupervisorRepository());

final supervisorDashboardProvider = FutureProvider.autoDispose<SupervisorDashboard>(
    (ref) => ref.watch(supervisorRepoProvider).getDashboard());

final supervisorMonthlySummaryProvider = FutureProvider.autoDispose
    .family<SupervisorMonthlySummary, DateTime>(
        (ref, month) => ref.watch(supervisorRepoProvider).getMonthlySummary(month));
