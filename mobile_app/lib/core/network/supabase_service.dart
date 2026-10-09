import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/supabase_config.dart';
import 'session_keeping_client.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser => client.auth.currentUser;

  /// Every request goes through it; it only ever answers a sign-out itself
  /// (see [signOutOnThisPhone]).
  static final SessionKeepingClient _http = SessionKeepingClient();

  /// Removes the session from this phone and leaves it alive on the server:
  /// its refresh token was put aside for signing in again with Face ID or a
  /// fingerprint. Everything that listens for a sign-out hears this one too.
  static Future<void> signOutOnThisPhone() => _http.withoutRevoking(() => client.auth.signOut());

  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.supabaseUrl,
        anonKey: SupabaseConfig.supabaseAnonKey,
        httpClient: _http,
        debug: kDebugMode,
      );
    } catch (e) {
      debugPrint('Error initializing Supabase: $e');
      rethrow;
    }
  }
}
