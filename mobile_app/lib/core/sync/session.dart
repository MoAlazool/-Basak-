import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../storage/snapshot_store.dart';

/// Who is signed in. Every provider that loads server data watches this, so
/// nothing one account loaded is ever shown to the next one.
final sessionUserIdProvider =
    Provider<String?>((ref) => ref.watch(authStateProvider.select((s) => s.user?.id)));

/// Server data that appears at once from the last saved copy and is then
/// refreshed behind it. Invalidating the provider refetches without a spinner:
/// the previous value stays on screen until the new one arrives.
abstract class SnapshotNotifier<T> extends AsyncNotifier<T> {
  /// Name of the saved copy (unique per provider).
  String get snapshotName;

  /// Loads the raw JSON from the server.
  Future<Object?> fetchJson();

  /// Builds the value from raw JSON (fresh or saved).
  T parse(Object? json);

  /// The value when nobody is signed in.
  T get signedOut;

  bool _servedSnapshot = false;

  @override
  Future<T> build() async {
    final userId = ref.watch(sessionUserIdProvider);
    if (userId == null) return signedOut;

    // Only the very first build of a session may answer from the saved copy;
    // later rebuilds (pull to refresh, a live event) always ask the server.
    if (!_servedSnapshot) {
      _servedSnapshot = true;
      final saved = await SnapshotStore.read(userId, snapshotName);
      if (saved != null) {
        try {
          final value = parse(saved);
          Future.microtask(() => _revalidate(userId));
          return value;
        } catch (_) {
          // An unreadable copy (e.g. after an app update) is simply ignored.
        }
      }
    }
    return _fetchAndSave(userId);
  }

  Future<T> _fetchAndSave(String userId) async {
    final json = await fetchJson();
    await SnapshotStore.write(userId, snapshotName, json);
    return parse(json);
  }

  Future<void> _revalidate(String userId) async {
    try {
      final fresh = await _fetchAndSave(userId);
      if (ref.read(sessionUserIdProvider) == userId) state = AsyncData(fresh);
    } catch (_) {
      // Offline: the saved copy stays on screen.
    }
  }
}
