import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';

class DailyRideRepository {
  final SupabaseClient _client = SupabaseService.client;

  /// Check if ride toggling for today is locked (after 1:00 PM local time)
  bool isTodayRideLocked() {
    final now = DateTime.now();
    return now.hour >= 13;
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
}
