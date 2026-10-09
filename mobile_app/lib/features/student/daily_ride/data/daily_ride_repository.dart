import 'package:flutter/foundation.dart';
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

/// The votes this run of the app has already read or written, day by day, for
/// whoever shows one without a read of its own: the card's "رحلة اليوم" strip.
/// A day is known once a read covered it (null: no vote that day).
abstract final class KnownRides {
  static final ValueNotifier<({String userId, Map<String, DailyRideDetails?> days})?> _known = ValueNotifier(null);

  /// Tells its listeners whenever a day becomes known or changes.
  static Listenable get changes => _known;

  /// The signed-in student's vote for [date]: `known` is false until a read
  /// has covered that day (and for anyone but the student who made the read).
  static ({bool known, DailyRideDetails? ride}) on(DateTime date) {
    final held = _known.value;
    final day = _day(date);
    if (held == null || held.userId != _signedIn() || !held.days.containsKey(day)) {
      return (known: false, ride: null);
    }
    return (known: true, ride: held.days[day]);
  }

  /// Stands in for the signed-in student where Supabase is not started (tests).
  @visibleForTesting
  static String? debugUserId;

  static String? _signedIn() {
    if (debugUserId != null) return debugUserId;
    try {
      return SupabaseService.client.auth.currentUser?.id;
    } catch (_) {
      return null; // Supabase not started (tests, previews).
    }
  }

  /// Every day from [start] to [end] is now known: [rides] holds its votes.
  static void read(String userId, DateTime start, DateTime end, RideDays rides) {
    final first = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    final days = <String, DailyRideDetails?>{};
    // A week or two at most; never an endless loop on a wrong range.
    for (var i = 0; i < 62; i++) {
      final day = DateTime(first.year, first.month, first.day + i);
      if (day.isAfter(last)) break;
      days[_day(day)] = rides._byDay[_day(day)];
    }
    _merge(userId, days);
  }

  /// The vote just saved for [date].
  static void voted(String userId, DateTime date, DailyRideDetails ride) => _merge(userId, {_day(date): ride});

  /// Another account, or a new run (tests): nothing is known.
  static void clear() => _known.value = null;

  static void _merge(String userId, Map<String, DailyRideDetails?> days) {
    final held = _known.value;
    _known.value = (userId: userId, days: {if (held != null && held.userId == userId) ...held.days, ...days});
  }
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
    final rides = RideDays.fromRows(rows as List<dynamic>);
    KnownRides.read(user.id, start, end, rides);
    return rides;
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
      final saved = DailyRideDetails(
        isRiding: response['is_riding'] as bool? ?? false,
        departureTime: response['departure_time'] as String?,
        returnTime: response['return_time'] as String?,
        isReturning: response['is_returning'] as bool? ?? true,
      );
      final user = _client.auth.currentUser;
      if (user != null) KnownRides.voted(user.id, rideDate, saved);
      return saved;
    }
    throw Exception('فشل تأكيد حضور الرحلة.');
  }
}
