import 'package:flutter/foundation.dart';

/// Counts requests and times phases while developing and in tests. In a
/// release build every call is a no-op the compiler removes.
class PerfTrace {
  static final Map<String, int> _counts = {};
  static final Map<String, Duration> _times = {};

  /// One more request (or step) named [label].
  static void count(String label) {
    if (kReleaseMode) return;
    _counts[label] = (_counts[label] ?? 0) + 1;
  }

  /// Runs [action] and adds how long it took to [label].
  static Future<T> time<T>(String label, Future<T> Function() action) async {
    if (kReleaseMode) return action();
    final watch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      _times[label] = (_times[label] ?? Duration.zero) + watch.elapsed;
    }
  }

  static Map<String, int> get counts => Map.unmodifiable(_counts);
  static Map<String, Duration> get times => Map.unmodifiable(_times);
  static int get total => _counts.values.fold(0, (a, b) => a + b);

  static void reset() {
    _counts.clear();
    _times.clear();
  }

  /// Prints what was counted and timed since the last [reset] (debug only).
  static void dump(String title) {
    if (!kDebugMode) return;
    debugPrint('[perf] $title: requests=$_counts times=${_times.map((k, v) => MapEntry(k, '${v.inMilliseconds}ms'))}');
  }
}
