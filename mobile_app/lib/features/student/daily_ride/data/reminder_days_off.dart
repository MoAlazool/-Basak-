import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/snapshot_store.dart';
import '../../../../core/sync/session.dart';

/// Ride days the student switched the vote reminders off for (notifications
/// page). Kept on this phone for the signed-in account; past days are dropped.
class ReminderDaysOffNotifier extends AsyncNotifier<Set<DateTime>> {
  static const _name = 'vote_reminder_days_off';

  static DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  static String _iso(DateTime day) => '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  @override
  Future<Set<DateTime>> build() async {
    final userId = ref.watch(sessionUserIdProvider);
    if (userId == null) return const {};
    final saved = await SnapshotStore.read(userId, _name);
    final today = _day(DateTime.now());
    return {
      for (final value in saved is List ? saved : const [])
        if (DateTime.tryParse('$value') case final day? when !day.isBefore(today))
          _day(day),
    };
  }

  /// Turns [day]'s reminders off, or back on.
  Future<void> toggle(DateTime day) async {
    final userId = ref.read(sessionUserIdProvider);
    if (userId == null) return;
    final next = {...state.valueOrNull ?? await future};
    final key = _day(day);
    if (!next.remove(key)) next.add(key);
    state = AsyncData(next);
    await SnapshotStore.write(userId, _name, [for (final d in next) _iso(d)]);
  }
}

final reminderDaysOffProvider =
    AsyncNotifierProvider<ReminderDaysOffNotifier, Set<DateTime>>(ReminderDaysOffNotifier.new);
