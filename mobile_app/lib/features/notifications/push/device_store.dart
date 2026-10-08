import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/notifications_repository.dart';

/// What this installation of the app remembers about itself, whoever is
/// signed in. Unlike the per-account caches, it is not removed on sign-out.
class DeviceStore {
  static const _storage = FlutterSecureStorage();
  static const _installationKey = 'basak.device.installation_id';
  static const _promptedKey = 'basak.device.push_prompted';

  String? _installationId;

  /// A random id made once for this installation. The server knows a phone by
  /// it, so a new push token replaces the old one instead of adding a device.
  Future<String> installationId() async {
    final known = _installationId;
    if (known != null) return known;
    try {
      final saved = await _storage.read(key: _installationKey);
      if (saved != null && saved.isNotEmpty) return _installationId = saved;
    } catch (_) {
      // Unreadable storage: an id for this run is still better than none.
    }
    final created = newUuid();
    _installationId = created;
    try {
      await _storage.write(key: _installationKey, value: created);
    } catch (_) {}
    return created;
  }

  /// Whether the app already offered, by itself, to switch notifications on.
  Future<bool> pushPrompted() async {
    try {
      return await _storage.read(key: _promptedKey) == 'true';
    } catch (_) {
      return true; // never nag when we cannot remember having asked
    }
  }

  Future<void> markPushPrompted() async {
    try {
      await _storage.write(key: _promptedKey, value: 'true');
    } catch (_) {}
  }
}
