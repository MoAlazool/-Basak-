import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/supabase_service.dart';
import '../../../core/storage/offline_cache.dart';
import '../../../core/sync/session.dart';
import '../home/presentation/student_home_screen.dart' show currentSubscriptionProvider;
import '../subscription/models/subscription_model.dart';
import 'recap_engine.dart';

/// The server's function. Written but not on every database yet: where it is
/// missing the recap simply does not exist.
const kTermRecapRpc = 'get_my_term_recap';

/// Asks the server for the recap of [subscriptionId]'s term.
typedef RecapFetch = Future<dynamic> Function(String subscriptionId);

Future<dynamic> _rpc(String subscriptionId) =>
    SupabaseService.client.rpc(kTermRecapRpc, params: {'p_subscription_id': subscriptionId});

class TermRecapRepository {
  final RecapFetch _fetch;

  TermRecapRepository({RecapFetch? fetch}) : _fetch = fetch ?? _rpc;

  /// The recap of that subscription's term for [studentId], or null: no rides,
  /// no such function on this database, no connection and nothing saved, or
  /// an answer that cannot be read. Never throws — a missing recap is not an
  /// error anyone should see.
  Future<TermRecap?> load({required String subscriptionId, required String studentId}) async {
    try {
      final json = await OfflineCache.readThrough('recap.$subscriptionId', () => _fetch(subscriptionId));
      final data = RecapData.tryParse(json);
      return data == null ? null : TermRecap.build(data, studentKey: studentId);
    } catch (_) {
      return null;
    }
  }
}

final termRecapRepoProvider = Provider((ref) => TermRecapRepository());

/// A term the recap may be about: the subscription and the day it ends.
typedef RecapTerm = ({String subscriptionId, DateTime end});

/// Which term, if any, Home may ask a recap for today — decided on the phone,
/// from dates it already has, so that no request is made outside the window
/// ([RecapRules.bannerOpensBefore] before the term's end to
/// [RecapRules.bannerStaysAfter] after it).
///
/// [current] is the subscription on Home; [remembered] the one last seen
/// there. A term that ended is no longer "current", so it is remembered until
/// its window has passed: the recap outlives the subscription by a few weeks.
abstract final class RecapGate {
  static const _note = 'recap.term';

  /// The term to ask for, or null: no request.
  static RecapTerm? open(DateTime today, {RecapTerm? current, RecapTerm? remembered}) {
    for (final term in [remembered, current]) {
      if (term != null && recapWindowOpen(today, term.end)) return term;
    }
    return null;
  }

  /// What to keep for next time: the remembered term until its window has
  /// passed, then the current one.
  static RecapTerm? keep(DateTime today, {RecapTerm? current, RecapTerm? remembered}) {
    if (remembered == null || current?.subscriptionId == remembered.subscriptionId) return current ?? remembered;
    final passed = DateTime.utc(today.year, today.month, today.day)
        .isAfter(remembered.end.add(RecapRules.bannerStaysAfter));
    return passed ? current : remembered;
  }

  /// The term of a subscription that can have a recap: a paid term or year
  /// with an end date. A daily ticket has none.
  static RecapTerm? of(SubscriptionModel? sub) {
    if (sub == null || sub.isDaily || !(sub.isActive || sub.status == 'expired')) return null;
    final end = DateTime.tryParse(sub.endDate ?? '');
    if (end == null) return null;
    return (subscriptionId: sub.id, end: DateTime.utc(end.year, end.month, end.day));
  }

  static Future<RecapTerm?> _read() async {
    final saved = await OfflineCache.readNote(_note);
    if (saved is! Map) return null;
    final end = DateTime.tryParse('${saved['end'] ?? ''}');
    final id = saved['id'];
    if (end == null || id is! String || id.isEmpty) return null;
    return (subscriptionId: id, end: DateTime.utc(end.year, end.month, end.day));
  }

  /// Reads what was remembered, decides, and remembers for next time.
  static Future<RecapTerm?> resolve(DateTime today, RecapTerm? current) async {
    final remembered = await _read();
    final next = keep(today, current: current, remembered: remembered);
    if (next != null && (next.subscriptionId != remembered?.subscriptionId || next.end != remembered?.end)) {
      await OfflineCache.writeNote(
          _note, {'id': next.subscriptionId, 'end': next.end.toIso8601String().substring(0, 10)});
    }
    return open(today, current: current, remembered: next);
  }
}

/// The clock the gate reads (tests set their own day).
final recapTodayProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The student's recap when one exists and its banner may show; otherwise
/// null. At most one request per launch, and none outside the window.
final termRecapProvider = FutureProvider<TermRecap?>((ref) async {
  final userId = ref.watch(sessionUserIdProvider);
  if (userId == null) return null;
  // Only what the gate reads: a live change to anything else on the
  // subscription must not ask for the recap again.
  final subscription = ref.watch(currentSubscriptionProvider
      .select((s) => (known: s.hasValue, term: s.hasValue ? RecapGate.of(s.valueOrNull) : null)));
  // Wait for Home's subscription instead of deciding twice.
  if (!subscription.known) return null;
  final today = ref.watch(recapTodayProvider)();
  final term = await RecapGate.resolve(today, subscription.term);
  if (term == null) return null;
  final recap =
      await ref.watch(termRecapRepoProvider).load(subscriptionId: term.subscriptionId, studentId: userId);
  return recap != null && recap.bannerOpen() ? recap : null;
});
