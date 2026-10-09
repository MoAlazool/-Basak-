import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/session.dart';
import 'notifications_repository.dart';

/// A supervisor's push switches: from the device at once, then from the server.
/// (Students have no switches in the app: what reaches them is decided by the
/// phone's own notification permission, and this is never read for them.)
/// A change shows immediately and is taken back if the server refuses it.
class NotificationPreferencesNotifier extends AsyncNotifier<NotificationPreferences> {
  /// The newest change wins: an older answer never overwrites a newer switch.
  int _changes = 0;

  @override
  Future<NotificationPreferences> build() async {
    if (ref.watch(sessionUserIdProvider) == null) return NotificationPreferences.all;
    return ref.watch(notificationsRepoProvider).preferences();
  }

  Future<void> setPushEnabled(bool enabled) =>
      _save((current) => current.copyWith(pushEnabled: enabled));

  Future<void> setCategory(NotificationCategory category, bool enabled) =>
      _save((current) => current.copyWith(category: category, enabled: enabled));

  /// Rethrows what the server said, after putting the switch back.
  Future<void> _save(NotificationPreferences Function(NotificationPreferences) change) async {
    final before = state.valueOrNull;
    if (before == null) return;
    final wanted = change(before);
    final mine = ++_changes;
    state = AsyncData(wanted);
    try {
      final saved = await ref.read(notificationsRepoProvider).setPreferences(wanted);
      if (mine == _changes) state = AsyncData(saved);
    } catch (_) {
      if (mine == _changes) state = AsyncData(before);
      rethrow;
    }
  }
}

final notificationPreferencesProvider =
    AsyncNotifierProvider<NotificationPreferencesNotifier, NotificationPreferences>(
        NotificationPreferencesNotifier.new);
