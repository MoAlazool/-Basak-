import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/network/supabase_service.dart';
import '../../../../core/storage/offline_cache.dart';
import '../models/vote_settings.dart';

class DailyRideDetails {
  final bool isRiding;
  final String? departureTime;
  final String? returnTime;
  final bool isReturning;

  const DailyRideDetails({
    required this.isRiding,
    this.departureTime,
    this.returnTime,
    this.isReturning = true,
  });
}

class DailyRideRepository {
  final SupabaseClient _client = SupabaseService.client;

  /// When [companyId]'s students may vote and how often they are reminded
  /// (the platform's settings when null). Kept for offline starts.
  Future<VoteSettings> getVoteSettings(String? companyId) async {
    final response = await OfflineCache.readThrough(
        'vote_settings.${companyId ?? 'platform'}',
        () => _client.rpc(SupabaseRpcs.getVoteSettings,
            params: {'p_company_id': companyId}));
    return response is Map
        ? VoteSettings.fromJson(Map<String, dynamic>.from(response))
        : VoteSettings.fallback;
  }

  /// Get ride status for a specific date
  Future<bool> getRideStatusForDate(DateTime date) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    final dateStr = date.toIso8601String().substring(0, 10);
    final response = await OfflineCache.readThrough(
        'ride.status.$dateStr',
        () => _client
            .from(SupabaseTables.dailyRideStatus)
            .select('is_riding')
            .eq('student_id', user.id)
            .eq('ride_date', dateStr)
            .maybeSingle());

    if (response == null) return false;
    return response['is_riding'] as bool? ?? false;
  }

  Future<DailyRideDetails> getRideDetailsForDate(DateTime date) async {
    final user = _client.auth.currentUser;
    if (user == null) return const DailyRideDetails(isRiding: false);

    final dateStr = date.toIso8601String().substring(0, 10);
    final row = await OfflineCache.readThrough(
        'ride.details.$dateStr',
        () => _client
            .from(SupabaseTables.dailyRideStatus)
            .select('is_riding, departure_time, return_time, is_returning')
            .eq('student_id', user.id)
            .eq('ride_date', dateStr)
            .maybeSingle());
    if (row == null) return const DailyRideDetails(isRiding: false);
    return DailyRideDetails(
      isRiding: row['is_riding'] as bool? ?? false,
      departureTime: row['departure_time'] as String?,
      returnTime: row['return_time'] as String?,
      isReturning: row['is_returning'] as bool? ?? true,
    );
  }

  Future<Map<DateTime, bool>> getRideStatusesForRange(
      DateTime start, DateTime end) async {
    final user = _client.auth.currentUser;
    if (user == null) return const {};
    final from = start.toIso8601String().substring(0, 10);
    final to = end.toIso8601String().substring(0, 10);
    final rows = await OfflineCache.readThrough(
        'ride.range.$from.$to',
        () => _client
            .from(SupabaseTables.dailyRideStatus)
            .select('ride_date, is_riding')
            .eq('student_id', user.id)
            .gte('ride_date', from)
            .lte('ride_date', to));
    return {
      for (final row in rows as List<dynamic>)
        DateTime.parse(row['ride_date'] as String):
            (row['is_riding'] as bool? ?? false),
    };
  }

  /// Toggle ride status for a specific date (the database enforces the vote window)
  Future<bool> toggleRide({
    required DateTime rideDate,
    required bool isRiding,
  }) async {
    final dateStr = rideDate.toIso8601String().substring(0, 10);

    final response = await requireOnline(() => _client.rpc(
          SupabaseRpcs.toggleStudentDailyRide,
          params: {
            'p_ride_date': dateStr,
            'p_is_riding': isRiding,
          },
        ));

    if (response != null && response['success'] == true) {
      return response['is_riding'] as bool? ?? false;
    }

    throw Exception('فشل تحديث حالة الركوب.');
  }

  Future<DailyRideDetails> confirmRide({
    required DateTime rideDate,
    required bool isRiding,
    required String? departureTime,
    required String? returnTime,
    required bool isReturning,
  }) async {
    final dateStr = rideDate.toIso8601String().substring(0, 10);
    final response = await requireOnline(() => _client.rpc(
          SupabaseRpcs.toggleStudentDailyRide,
          params: {
            'p_ride_date': dateStr,
            'p_is_riding': isRiding,
            'p_departure_time': departureTime,
            'p_return_time': isReturning ? returnTime : null,
            'p_is_returning': isReturning,
          },
        ));
    if (response is Map && response['success'] == true) {
      return DailyRideDetails(
        isRiding: response['is_riding'] as bool? ?? false,
        departureTime: response['departure_time'] as String?,
        returnTime: response['return_time'] as String?,
        isReturning: response['is_returning'] as bool? ?? true,
      );
    }
    throw Exception('فشل تأكيد حضور الرحلة.');
  }
}
