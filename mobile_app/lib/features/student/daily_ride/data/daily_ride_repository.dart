import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';

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

  /// Voting opens at 4 PM on the day before a ride and closes at 6 AM
  /// on the ride day (device local time, configured for Africa/Cairo).
  bool isVotingOpen() {
    return isVotingOpenAt(DateTime.now());
  }

  static bool isVotingOpenAt(DateTime now) {
    return now.hour >= 16 || now.hour < 6;
  }

  /// During the evening window students vote for tomorrow; before 6 AM they
  /// vote for today's ride. Between windows, today's submitted vote is shown
  /// read-only until the next evening.
  DateTime rideDateForCurrentWindow() {
    return rideDateFor(DateTime.now());
  }

  static DateTime rideDateFor(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return now.hour >= 16 ? today.add(const Duration(days: 1)) : today;
  }

  /// Get ride status for a specific date
  Future<bool> getRideStatusForDate(DateTime date) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    final dateStr = date.toIso8601String().substring(0, 10);
    final response = await _client
        .from(SupabaseTables.dailyRideStatus)
        .select('is_riding')
        .eq('student_id', user.id)
        .eq('ride_date', dateStr)
        .maybeSingle();

    if (response == null) return false;
    return response['is_riding'] as bool? ?? false;
  }

  Future<DailyRideDetails> getRideDetailsForDate(DateTime date) async {
    final user = _client.auth.currentUser;
    if (user == null) return const DailyRideDetails(isRiding: false);

    final dateStr = date.toIso8601String().substring(0, 10);
    final row = await _client
        .from(SupabaseTables.dailyRideStatus)
        .select('is_riding, departure_time, return_time, is_returning')
        .eq('student_id', user.id)
        .eq('ride_date', dateStr)
        .maybeSingle();
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
    final rows = await _client
        .from(SupabaseTables.dailyRideStatus)
        .select('ride_date, is_riding')
        .eq('student_id', user.id)
        .gte('ride_date', start.toIso8601String().substring(0, 10))
        .lte('ride_date', end.toIso8601String().substring(0, 10));
    return {
      for (final row in rows as List<dynamic>)
        DateTime.parse(row['ride_date'] as String):
            (row['is_riding'] as bool? ?? false),
    };
  }

  /// Toggle ride status for a specific date (Calls stored procedure with 1:00 PM cutoff enforcement)
  Future<bool> toggleRide({
    required DateTime rideDate,
    required bool isRiding,
  }) async {
    final dateStr = rideDate.toIso8601String().substring(0, 10);

    final response = await _client.rpc(
      SupabaseRpcs.toggleStudentDailyRide,
      params: {
        'p_ride_date': dateStr,
        'p_is_riding': isRiding,
      },
    );

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
    final response = await _client.rpc(
      SupabaseRpcs.toggleStudentDailyRide,
      params: {
        'p_ride_date': dateStr,
        'p_is_riding': isRiding,
        'p_departure_time': departureTime,
        'p_return_time': isReturning ? returnTime : null,
        'p_is_returning': isReturning,
      },
    );
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
