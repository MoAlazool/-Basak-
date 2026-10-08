import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../network/network_errors.dart';

/// Small encrypted cache that keeps the app readable on a bus with
/// intermittent connectivity. It never queues or stores attendance writes.
class OfflineCache {
  static const _storage = FlutterSecureStorage();
  static const _prefix = 'basak.offline.';
  static const _userIdKey = '${_prefix}user_id';
  static const _roleKey = '${_prefix}role';
  static const _studentPassKey = '${_prefix}student_pass';
  static const _studentLookupPrefix = '${_prefix}student_lookup.';
  static const _dataPrefix = '${_prefix}data.';

  /// When the screens are showing saved data because the server is
  /// unreachable: the time that data was saved. Null while online.
  static final ValueNotifier<DateTime?> offlineSince = ValueNotifier(null);

  static Future<void> saveSession(User user, String role) async {
    // A different account on this device (the previous session expired or was
    // revoked without a sign-out): drop everything saved for the old one.
    if (await _safeRead(_userIdKey) != user.id) await clearAll();
    await _storage.write(key: _userIdKey, value: user.id);
    await _storage.write(key: _roleKey, value: role);
  }

  static Future<String?> readRoleFor(String userId) async {
    final cachedId = await _storage.read(key: _userIdKey);
    if (cachedId != userId) return null;
    return _storage.read(key: _roleKey);
  }

  /// Bumped when a read that was answered from the saved copy turns out to have
  /// newer data on the server. Whoever shows that data reads it again (and gets
  /// the fresh value from memory, without a second request).
  static final ValueNotifier<int> refreshed = ValueNotifier(0);

  /// How long a request may take before the saved copy is used instead. A phone
  /// "connected" to a network with no internet would otherwise wait for ever.
  static Duration requestTimeout = const Duration(seconds: 12);

  /// Keys already answered once in this run of the app.
  static final Set<String> _readOnce = {};

  /// Values just fetched behind a saved copy, waiting to be shown.
  static final Map<String, ({Object? value, DateTime at})> _fresh = {};
  static const _freshFor = Duration(seconds: 10);

  /// Cache first, for everything the app shows.
  ///
  /// The first time [key] is read after the app starts, the last saved result
  /// is returned at once and the server is asked behind it: nothing waits for
  /// the network, online or not. If the server has something newer, it is saved
  /// and [refreshed] is bumped. Later reads (pull to refresh, a live change)
  /// ask the server first and fall back to the saved result when it cannot be
  /// reached. Only with nothing saved is a network error rethrown.
  ///
  /// Saved results belong to the signed-in user; a server that answers with a
  /// refusal (signed out, removed, not allowed) is never papered over.
  static Future<dynamic> readThrough(
      String key, Future<dynamic> Function() fetch) async {
    final userId = _currentUserId();
    if (userId == null) return fetch();
    final storageKey = '$_dataPrefix$userId.$key';

    final fresh = _fresh.remove(storageKey);
    if (fresh != null && DateTime.now().difference(fresh.at) < _freshFor) {
      return fresh.value;
    }

    if (_readOnce.add(storageKey)) {
      final saved = _decode(await _safeRead(storageKey));
      if (saved != null) {
        unawaited(_revalidate(storageKey, fetch, saved));
        return saved['v'];
      }
    }

    try {
      final value = await fetch().timeout(requestTimeout);
      offlineSince.value = null;
      // Saved in the background: the encrypted write must not delay the screen.
      unawaited(_save(storageKey, value));
      return value;
    } catch (error) {
      if (!isNetworkFailure(error)) rethrow;
      final saved = _decode(await _safeRead(storageKey));
      if (saved == null) rethrow;
      markOffline(DateTime.tryParse(saved['at'] as String? ?? ''));
      return saved['v'];
    }
  }

  /// Asks the server for what was just shown from the saved copy.
  static Future<void> _revalidate(String storageKey, Future<dynamic> Function() fetch,
      Map<String, dynamic> saved) async {
    try {
      final value = await fetch().timeout(requestTimeout);
      offlineSince.value = null;
      await _save(storageKey, value);
      if (jsonEncode(value) != jsonEncode(saved['v'])) {
        _fresh[storageKey] = (value: value, at: DateTime.now());
        refreshed.value++;
      }
    } catch (error) {
      if (isNetworkFailure(error)) {
        // No connection: what is on screen stays, marked with when it was saved.
        markOffline(DateTime.tryParse(saved['at'] as String? ?? ''));
        return;
      }
      // The server refused: the saved copy must not outlive the right to see it.
      try {
        await _storage.delete(key: storageKey);
      } catch (_) {}
      refreshed.value++;
    }
  }

  static Future<void> _save(String storageKey, Object? value) async {
    try {
      await _storage.write(
          key: storageKey,
          value: jsonEncode({'v': value, 'at': DateTime.now().toIso8601String()}));
    } catch (_) {
      // A full or locked keystore must never break a successful load.
    }
  }

  /// A new run of the app (tests), or another account: nothing counts as read yet.
  @visibleForTesting
  static void resetSession() {
    _readOnce.clear();
    _fresh.clear();
    offlineSince.value = null;
  }

  /// Stands in for the signed-in user where Supabase is not started (tests).
  @visibleForTesting
  static String? debugUserId;

  /// For reads with their own cache (the student pass): saved data saved at
  /// [savedAt] is on screen. The banner shows the oldest such time.
  static void markOffline(DateTime? savedAt) {
    final at = savedAt ?? DateTime.now();
    final previous = offlineSince.value;
    if (previous == null || at.isBefore(previous)) offlineSince.value = at;
  }

  /// Called after any successful server read that does not go through
  /// [readThrough], so the offline banner disappears as soon as we reconnect.
  static void markOnline() => offlineSince.value = null;

  static Future<void> saveStudentPass(Map<String, dynamic> pass) async {
    await _storage.write(
        key: _studentPassKey,
        value: jsonEncode({...pass, '_user_id': _currentUserId()}));
  }

  /// The saved pass, only if it belongs to the signed-in student.
  static Future<Map<String, dynamic>?> readStudentPass() async {
    final pass = _decode(await _safeRead(_studentPassKey));
    final userId = _currentUserId();
    if (pass == null || userId == null || pass['_user_id'] != userId) return null;
    return pass;
  }

  static Future<void> clearStudentPass() => _storage.delete(key: _studentPassKey);

  /// Removes everything saved for offline use (on sign-out or account
  /// deletion) so the next person on this device never sees it.
  static Future<void> clearAll() async {
    offlineSince.value = null;
    _readOnce.clear();
    _fresh.clear();
    try {
      final all = await _storage.readAll();
      for (final key in all.keys.where((k) => k.startsWith(_prefix))) {
        await _storage.delete(key: key);
      }
    } catch (_) {
      await clearStudentPass();
    }
  }

  /// Lookups are kept per supervisor: on a shared phone, another supervisor
  /// (possibly of another company) never reads what this one scanned.
  static Future<void> saveStudentLookup(
      String supervisorId, String qrValue, Map<String, dynamic> details) async {
    await _storage.write(
      key: _lookupKey(supervisorId, qrValue),
      value: jsonEncode({
        ...details,
        '_cached_at': DateTime.now().toIso8601String(),
      }),
    );
  }

  static Future<Map<String, dynamic>?> readStudentLookup(
          String supervisorId, String qrValue) async =>
      _decode(await _safeRead(_lookupKey(supervisorId, qrValue)));

  /// Removes every cached lookup. Called on sign-out, so nothing a supervisor
  /// saw offline stays on the device for the next account.
  static Future<void> clearStudentLookups() async {
    try {
      final all = await _storage.readAll();
      for (final key in all.keys.where((k) => k.startsWith(_studentLookupPrefix))) {
        await _storage.delete(key: key);
      }
    } catch (_) {
      // A locked keystore must never block signing out.
    }
  }

  static String _lookupKey(String supervisorId, String qrValue) =>
      '$_studentLookupPrefix$supervisorId.${_safeKey(qrValue)}';

  static Map<String, dynamic>? _decode(String? raw) {
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static String? _currentUserId() {
    if (debugUserId != null) return debugUserId;
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null; // Supabase not initialized (tests, previews).
    }
  }

  static Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  static String _safeKey(String value) => base64Url.encode(utf8.encode(value));
}
