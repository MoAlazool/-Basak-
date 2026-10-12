import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/perf_trace.dart';
import '../../../../core/network/supabase_service.dart';
import '../../../../core/storage/offline_cache.dart';
import '../../../../core/storage/prefetched_reads.dart';
import '../../daily_ride/data/daily_ride_repository.dart';
import '../../daily_ride/models/vote_settings.dart';
import '../../offers/offers_repository.dart';

/// The one request behind a student's launch (replaced in tests).
abstract class StudentHomeGateway {
  /// `get_student_home` (migration 20261125000001): everything the app reads
  /// on launch, each part exactly as its own request answers it.
  Future<Object?> fetch({required String today, String? rideFrom, String? rideTo});
}

class SupabaseStudentHomeGateway implements StudentHomeGateway {
  const SupabaseStudentHomeGateway();

  @override
  Future<Object?> fetch({required String today, String? rideFrom, String? rideTo}) {
    PerfTrace.count('student_home');
    return SupabaseService.client.rpc('get_student_home', params: {
      'p_today': today,
      'p_ride_from': rideFrom,
      'p_ride_to': rideTo,
    });
  }
}

/// The student's launch (and return to the app, and pull to refresh) in one
/// request instead of ten-odd: their row, their subscriptions and the current
/// one, the vote settings and the week's votes, the current subscription's
/// receipts, the inbox, the invitations, the offers, the line's supervisors,
/// the recap releases and the boarded rides.
///
/// Nothing reads from here directly. [prefetch] hands the answers to
/// PrefetchedReads under the names the reads already use, and each read takes
/// its own when it is made; a read with no answer (an older database without
/// the function, no connection, a part this answer does not have) asks the
/// server itself, as it always did.
class StudentHomeBundle {
  StudentHomeBundle._();

  static StudentHomeGateway gateway = const SupabaseStudentHomeGateway();

  /// The reads one answer stands in for: names of reads made through
  /// OfflineCache, and of the three made without it ([answerOr]: invites,
  /// line_supervisors, boarded_rides).
  static bool covers(String key) =>
      const {'profile.summary', 'subscriptions', 'subscriptions.current', 'notifications.page', 'recap.releases',
            OffersRepository.cacheKey, 'invites', 'line_supervisors', 'boarded_rides'}
          .contains(key) ||
      key.startsWith('vote_settings.') ||
      key.startsWith('ride.days.') ||
      key.startsWith('receipts.');

  /// Asks for everything at once, for [userId]. [vote] is the vote settings the
  /// home screen will use to choose which days of votes to read (those on
  /// screen; by default the ones saved on this phone, as the home screen opens
  /// with them).
  static void prefetch(String userId, {VoteSettings? vote}) {
    PrefetchedReads.begin(userId: userId, covers: covers, answers: _answers(vote));
  }

  static Future<Map<String, Object?>?> _answers(VoteSettings? vote) async {
    try {
      final now = DateTime.now();
      final settings = vote ?? await _savedVoteSettings();
      final range = homeRideRange(settings, now);
      final from = _day(range.start), to = _day(range.end);
      final answer = await gateway.fetch(today: _day(now), rideFrom: from, rideTo: to);
      if (answer is! Map || answer['v'] != 1) return null;
      return {
        'profile.summary': answer['profile'],
        'subscriptions': answer['subscriptions'],
        'subscriptions.current': answer['current'],
        'vote_settings.${answer['vote_company'] ?? 'platform'}': answer['vote_settings'],
        if (answer['ride_days'] != null) rideDaysKey(range.start, range.end): answer['ride_days'],
        if (answer['receipts_of'] != null) 'receipts.${answer['receipts_of']}': answer['receipts'],
        'notifications.page': answer['inbox'],
        OffersRepository.cacheKey: answer['offers'],
        'recap.releases': answer['recap_releases'],
        'invites': answer['invites'],
        'line_supervisors': answer['line_supervisors'],
        'boarded_rides': answer['boarded_rides'],
      };
    } catch (_) {
      // An older database, no connection, anything: every read asks for itself.
      return null;
    }
  }

  /// For reads that are not made through OfflineCache: the answer fetched
  /// ahead for [key] when there is one, otherwise [ask]'s.
  static Future<Object?> answerOr(String key, Future<Object?> Function() ask) async {
    final ahead = await PrefetchedReads.take(key, userId: OfflineCache.signedInUserId);
    return ahead.found ? ahead.value : ask();
  }

  /// The settings the home screen opens with: those saved for the company of
  /// the saved current subscription (the platform's when there is none).
  static Future<VoteSettings> _savedVoteSettings() async {
    final current = await OfflineCache.peek('subscriptions.current');
    final companyId = current is Map ? current['company_id'] as String? : null;
    final saved = await OfflineCache.peek('vote_settings.${companyId ?? 'platform'}');
    return saved is Map ? VoteSettings.fromJson(Map<String, dynamic>.from(saved)) : VoteSettings.fallback;
  }

  static String _day(DateTime date) => date.toIso8601String().substring(0, 10);
}

/// The launch's one request, once per signed-in student: AuthGate watches it
/// before anything of the student's is read, so every first read finds it.
final studentLaunchBundleProvider =
    Provider.autoDispose.family<void, String>((ref, userId) => StudentHomeBundle.prefetch(userId));
