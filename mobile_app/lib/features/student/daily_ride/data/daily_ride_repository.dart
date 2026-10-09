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

/// The votes of a stretch of days, as one read returned them.
class RideDays {
  final Map<String, DailyRideDetails> _byDay;

  const RideDays(this._byDay);

  factory RideDays.fromRows(List<dynamic> rows) => RideDays({
        for (final row in rows)
          (row['ride_date'] as String).substring(0, 10): DailyRideDetails(
            isRiding: row['is_riding'] as bool? ?? false,
            departureTime: row['departure_time'] as String?,
            returnTime: row['return_time'] as String?,
            isReturning: row['is_returning'] as bool? ?? true,
          ),
      });

  /// Every day voted for (riding or not).
  Map<DateTime, bool> get statuses =>
      {for (final entry in _byDay.entries) DateTime.parse(entry.key): entry.value.isRiding};

  /// The vote for [date]; "not riding" when there is none.
  DailyRideDetails detailsFor(DateTime date) =>
      _byDay[_day(date)] ?? const DailyRideDetails(isRiding: false);
}

String _day(DateTime date) => date.toIso8601String().substring(0, 10);

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

  /// The student's votes from [start] to [end], in one request: whether they
  /// ride each day, and the times they chose.
  Future<RideDays> getRides(DateTime start, DateTime end) async {
    final user = _client.auth.currentUser;
    if (user == null) return const RideDays({});
    final from = _day(start);
    final to = _day(end);
    final rows = await OfflineCache.readThrough(
        'ride.days.$from.$to',
        () => _client
            .from(SupabaseTables.dailyRideStatus)
            .select('ride_date, is_riding, departure_time, return_time, is_returning')
            .eq('student_id', user.id)
            .gte('ride_date', from)
            .lte('ride_date', to));
    return RideDays.fromRows(rows as List<dynamic>);
  }

  Future<DailyRideDetails> confirmRide({
    required DateTime rideDate,
    required bool isRiding,
    required String? departureTime,
    required String? returnTime,
    required bool isReturning,
  }) async {
    final dateStr = _day(rideDate);
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
