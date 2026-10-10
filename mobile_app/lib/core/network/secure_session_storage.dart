import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where the Supabase session (its access and refresh tokens) is kept: the
/// phone's Keychain / Keystore, not the plain app preferences supabase_flutter
/// uses by default, which anyone with a rooted phone or a backup can read.
///
/// A session an older version saved in the preferences moves over the first
/// time, so the update signs nobody out. iOS keeps Keychain items after the
/// app is deleted: a session found there with no trace of this install in the
/// preferences belongs to an earlier install and is removed, as deleting the
/// app always did.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this.key, FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// The same name supabase_flutter gives it: `sb-{project ref}-auth-token`.
  final String key;
  final FlutterSecureStorage _storage;

  /// Set in the preferences once this install keeps its session securely.
  static const installMarker = 'basak.secure_session';

  /// supabase_flutter's own name for the session of the project at [url].
  static String keyFor(String url) => 'sb-${Uri.parse(url).host.split('.').first}-auth-token';

  @override
  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    final legacy = preferences.getString(key);
    if (legacy != null) {
      await _storage.write(key: key, value: legacy);
      await preferences.remove(key);
    } else if (preferences.getBool(installMarker) != true) {
      await _storage.delete(key: key);
    }
    await preferences.setBool(installMarker, true);
  }

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: key);

  @override
  Future<String?> accessToken() => _storage.read(key: key);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: key);

  @override
  Future<void> persistSession(String persistSessionString) => _storage.write(key: key, value: persistSessionString);
}
