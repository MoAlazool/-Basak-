import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// What this phone remembers about the things the app asks by itself, so each
/// is asked once: the store rating (once per installed version) and the
/// optional update (once per version in the store).
///
/// Storage that cannot be read answers "already asked": the app never nags
/// when it cannot remember.
class PromptStore {
  const PromptStore();

  static const _storage = FlutterSecureStorage();
  static const _ratingKey = 'basak.prompt.rating_asked_version';
  static const _updateKey = 'basak.prompt.update_offered_version';

  /// The installed version the rating was last asked on; null when never.
  /// [unreadable] is answered when storage fails.
  Future<String?> ratingAskedVersion({required String unreadable}) => _read(_ratingKey, unreadable);

  Future<void> markRatingAsked(String version) => _write(_ratingKey, version);

  /// The store version the update sheet was last shown for; null when never.
  Future<String?> updateOfferedVersion({required String unreadable}) => _read(_updateKey, unreadable);

  Future<void> markUpdateOffered(String version) => _write(_updateKey, version);

  Future<String?> _read(String key, String unreadable) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return unreadable;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
  }
}

final promptStoreProvider = Provider<PromptStore>((ref) => const PromptStore());
