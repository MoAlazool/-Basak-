import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'offline_cache.dart';

/// The last good copy of a few screens' data, kept per account in the device's
/// encrypted storage. The app shows it at once on start and refreshes behind it.
/// It is never the source of truth and holds nothing that is not already shown.
class SnapshotStore {
  static const _storage = FlutterSecureStorage();
  static const _prefix = 'basak.snapshot.v1.';

  static bool isSnapshotKey(String key) => key.startsWith(_prefix);

  static String _key(String userId, String name) => '$_prefix$userId.$name';

  static Future<void> write(String userId, String name, Object? json) async {
    try {
      await _storage.write(key: _key(userId, name), value: jsonEncode(json));
    } catch (_) {
      // A snapshot that cannot be saved only costs a spinner next time.
    }
  }

  /// The decoded snapshot, or null when there is none (or it is unreadable).
  static Future<Object?> read(String userId, String name) async {
    try {
      final raw = await _storage.read(key: _key(userId, name));
      return raw == null ? null : jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  /// Removes every snapshot. Called on sign-out and account deletion.
  static Future<void> clear() async {
    try {
      await OfflineCache.deleteWhere(isSnapshotKey);
    } catch (_) {}
  }
}
