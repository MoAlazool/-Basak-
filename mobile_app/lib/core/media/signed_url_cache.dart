import 'dart:async';

import '../constants/supabase_config.dart';
import '../network/perf_trace.dart';
import '../network/supabase_service.dart';

/// Short-lived links to private storage files, kept in memory.
///
/// What the app saves on the device is the file's path, never a link: a link
/// changes every time it is signed, so saving it made every saved copy look
/// "changed". A link is signed once and reused until shortly before it
/// expires, by every screen that shows the same photo.
class SignedUrlCache {
  /// How long a link is valid, and how long before its end it is replaced.
  static const lifetime = Duration(hours: 1);
  static const renewBefore = Duration(minutes: 5);

  /// Asks the storage service for a link. Replaced in tests.
  static Future<String> Function(String bucket, String path, int seconds) signer = _sign;

  /// The clock. Replaced in tests.
  static DateTime Function() now = DateTime.now;

  static final Map<String, ({String url, DateTime expires})> _urls = {};
  static final Map<String, Future<String>> _signing = {};

  static Future<String> _sign(String bucket, String path, int seconds) =>
      SupabaseService.client.storage.from(bucket).createSignedUrl(path, seconds);

  static String _key(String bucket, String path) => '$bucket/$path';

  /// The link already in memory for this file, if it is still good.
  static String? peek(String bucket, String path) {
    final saved = _urls[_key(bucket, path)];
    return saved != null && now().isBefore(saved.expires.subtract(renewBefore)) ? saved.url : null;
  }

  /// A link to [path] in [bucket]: the one in memory, or a new one. Screens
  /// asking for the same file at the same moment share one request.
  static Future<String> url(String bucket, String path) {
    final known = peek(bucket, path);
    if (known != null) return Future.value(known);
    final key = _key(bucket, path);
    return _signing[key] ??= () async {
      try {
        PerfTrace.count('storage.sign');
        final signed = await signer(bucket, path, lifetime.inSeconds);
        // Signed out meanwhile: the link is handed back but not kept.
        if (_signing.containsKey(key)) _urls[key] = (url: signed, expires: now().add(lifetime));
        return signed;
      } finally {
        _signing.remove(key);
      }
    }();
  }

  /// [url], or when it cannot be signed now (offline) the file's address
  /// without a token: it cannot be downloaded, but it names the same copy in
  /// the image cache on disk, so a photo seen before still shows.
  static Future<String> urlOrOffline(String bucket, String path) async {
    try {
      return await url(bucket, path).timeout(const Duration(seconds: 8));
    } catch (_) {
      return offlineUrl(bucket, path);
    }
  }

  static String offlineUrl(String bucket, String path) =>
      '${SupabaseConfig.supabaseUrl}/storage/v1/object/sign/$bucket/$path';

  /// Sign-out: nothing signed for one account is kept for the next.
  static void clear() {
    _urls.clear();
    _signing.clear();
  }
}
