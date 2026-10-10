import 'dart:async';

import 'package:http/http.dart' as http;

/// The HTTP client the Supabase client is built on.
///
/// It does one thing of its own: inside [withoutRevoking] the request that
/// ends the session on the server (`POST /auth/v1/logout`) is answered here
/// and never sent. The Supabase client offers no sign-out that only forgets
/// the session on this phone, and signing in again with Face ID or a
/// fingerprint needs the session to stay alive (see
/// features/auth/biometrics/biometric_vault.dart for what that costs).
class SessionKeepingClient extends http.BaseClient {
  SessionKeepingClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;
  int _keeping = 0;

  /// Runs [signOut] with the session left alive on the server.
  Future<T> withoutRevoking<T>(Future<T> Function() signOut) async {
    _keeping++;
    try {
      return await signOut();
    } finally {
      _keeping--;
    }
  }

  static bool isSignOut(http.BaseRequest request) =>
      request.method == 'POST' && request.url.path.endsWith('/auth/v1/logout');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_keeping > 0 && isSignOut(request)) {
      return Future.value(http.StreamedResponse(const Stream.empty(), 204, request: request));
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
