import 'dart:async';

/// Answers fetched ahead, in one request, for reads that are about to be made
/// one by one (the student's launch: StudentHomeBundle).
///
/// A read whose key the batch covers waits for the batch instead of asking the
/// server itself, and takes its answer when the batch has one. Anything else —
/// no batch, another account, a batch that failed, a key it did not answer, an
/// answer already taken or no longer fresh — and the read asks the server
/// exactly as it always did. So a batch can only spare requests, never change
/// what a read returns.
///
/// Each answer is taken once: a later read of the same key (a pull to refresh,
/// a live change) asks the server. News that could make an answer out of date
/// drops the whole batch ([discard]): a live event, or a write from this phone.
class PrefetchedReads {
  PrefetchedReads._();

  /// How long after it arrived an answer may still stand in for a read.
  static const freshFor = Duration(seconds: 5);

  /// How long a read waits for a batch still in flight before asking itself.
  static Duration waitAtMost = const Duration(seconds: 6);

  /// The clock. Replaced in tests.
  static DateTime Function() now = DateTime.now;

  static _Batch? _batch;

  /// Starts a batch for [userId]: from now on, reads of the keys [covers]
  /// accepts wait for [answers] (key → answer; null when the batch failed).
  /// Replaces any earlier batch.
  static void begin({
    required String userId,
    required bool Function(String key) covers,
    required Future<Map<String, Object?>?> answers,
  }) {
    final batch = _Batch(userId, covers);
    _batch = batch;
    unawaited(answers.then((value) {
      batch.answers = value;
      batch.arrivedAt = now();
    }, onError: (Object _) {
      batch.answers = null;
      batch.arrivedAt = now();
    }).whenComplete(() => batch.done.complete()));
  }

  /// The batch's answer for [key], if it has a fresh one for [userId] that
  /// nobody took yet. Waits for a batch still in flight (at most [waitAtMost]).
  static Future<({bool found, Object? value})> take(String key, {required String? userId}) async {
    const none = (found: false, value: null);
    final batch = _batch;
    if (batch == null || userId == null || batch.userId != userId || !batch.covers(key)) return none;
    if (!batch.done.isCompleted) {
      try {
        await batch.done.future.timeout(waitAtMost);
      } on TimeoutException {
        return none;
      }
    }
    // Dropped (or replaced) while this read waited.
    if (!identical(_batch, batch)) return none;
    final answers = batch.answers;
    final arrivedAt = batch.arrivedAt;
    if (answers == null || arrivedAt == null || !answers.containsKey(key) || !batch.taken.add(key)) return none;
    if (now().difference(arrivedAt) > freshFor) return none;
    return (found: true, value: answers[key]);
  }

  /// Something may have changed since the batch was asked: nothing in it is
  /// used any more.
  static void discard() => _batch = null;
}

class _Batch {
  final String userId;
  final bool Function(String key) covers;
  final Completer<void> done = Completer<void>();
  final Set<String> taken = {};
  Map<String, Object?>? answers;
  DateTime? arrivedAt;

  _Batch(this.userId, this.covers);
}
