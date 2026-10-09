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
  static const _notePrefix = '${_prefix}note.';

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

  /// Which saved reads turned out to be out of date since the listener last
  /// looked (their names, as passed to [readThrough]). The listener takes them
  /// with [takeRefreshedKeys] and re-reads only what shows them.
  static final Set<String> _refreshedKeys = {};

  static Set<String> takeRefreshedKeys() {
    final keys = Set<String>.from(_refreshedKeys);
    _refreshedKeys.clear();
    return keys;
  }

  /// How long a request may take before the saved copy is used instead. A phone
  /// "connected" to a network with no internet would otherwise wait for ever.
  static Duration requestTimeout = const Duration(seconds: 12);

  /// Keys already answered once in this run of the app.
  static final Set<String> _readOnce = {};

  /// Values just fetched behind a saved copy, waiting to be shown.
  static final Map<String, ({Object? value, DateTime at})> _fresh = {};
  static const _freshFor = Duration(seconds: 10);

  /// The last value each key was answered with in this run of the app.
  static final Map<String, Object?> _last = {};

  /// Keys whose waiting value was written by this phone ([applyLocal]).
  static final Set<String> _local = {};

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
    _local.remove(storageKey);
    if (fresh != null && DateTime.now().difference(fresh.at) < _freshFor) {
      return fresh.value;
    }

    if (_readOnce.add(storageKey)) {
      final saved = _decode(await _safeRead(storageKey));
      if (saved != null) {
        unawaited(_revalidate(key, storageKey, fetch, saved));
        return _last[storageKey] = saved['v'];
      }
    }

    try {
      final value = await fetch().timeout(requestTimeout);
      offlineSince.value = null;
      // Saved in the background: the encrypted write must not delay the screen.
      unawaited(_save(storageKey, value));
      return _last[storageKey] = value;
    } catch (error) {
      if (!isNetworkFailure(error)) rethrow;
      final saved = _decode(await _safeRead(storageKey));
      if (saved == null) rethrow;
      markOffline(DateTime.tryParse(saved['at'] as String? ?? ''));
      return _last[storageKey] = saved['v'];
    }
  }

  /// Asks the server for what was just shown from the saved copy.
  static Future<void> _revalidate(String key, String storageKey, Future<dynamic> Function() fetch,
      Map<String, dynamic> saved) async {
    try {
      final value = await fetch().timeout(requestTimeout);
      offlineSince.value = null;
      await _save(storageKey, value);
      // Changed on this phone while the server was answering: that is newer.
      if (_local.contains(storageKey)) return;
      _last[storageKey] = value;
      if (jsonEncode(value) != jsonEncode(saved['v'])) {
        _fresh[storageKey] = (value: value, at: DateTime.now());
        _refreshedKeys.add(key);
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
      _last.remove(storageKey);
      _refreshedKeys.add(key);
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

  /// Replaces the saved copy of [key] with what a write just returned, so the
  /// screen that shows it opens with the new value next time.
  static Future<void> put(String key, Object? value) async {
    final userId = _currentUserId();
    if (userId != null) await _save('$_dataPrefix$userId.$key', value);
  }

  /// Applies a change this phone just made on the server to what [key] holds,
  /// in memory and in the saved copy, so the screens (now, and after a restart)
  /// show it without reading it again. [change] gets a copy of the current
  /// value and returns the new one.
  ///
  /// The caller then invalidates the provider that reads [key]: its next read
  /// is answered with the new value and makes no request. Returns false when
  /// this phone holds nothing for [key] (nothing to change; read it normally).
  static Future<bool> applyLocal(String key, Object? Function(Object? current) change) async {
    final userId = _currentUserId();
    if (userId == null) return false;
    final storageKey = '$_dataPrefix$userId.$key';
    Object? current;
    if (_last.containsKey(storageKey)) {
      current = _last[storageKey];
    } else {
      final saved = _decode(await _safeRead(storageKey));
      if (saved == null) return false;
      current = saved['v'];
    }
    // Through JSON both ways: the change works on a copy, and what is kept
    // has the same shapes as a value read from the server or from the device.
    final next = jsonDecode(jsonEncode(change(jsonDecode(jsonEncode(current)))));
    _last[storageKey] = next;
    _fresh[storageKey] = (value: next, at: DateTime.now());
    _local.add(storageKey);
    await _save(storageKey, next);
    return true;
  }

  /// News from the server about data changed elsewhere: whatever this phone
  /// wrote itself and nobody has read yet must not answer for it.
  static void forgetLocal() {
    for (final storageKey in _local) {
      _fresh.remove(storageKey);
    }
    _local.clear();
  }

  /// The saved copy of [key] as it is on the device (tests, and reads that
  /// must never touch the network).
  static Future<Object?> peek(String key) async {
    final userId = _currentUserId();
    if (userId == null) return null;
    return _decode(await _safeRead('$_dataPrefix$userId.$key'))?['v'];
  }

  /// A small value kept for the signed-in account outside the screens' data
  /// (e.g. uploads still to be tidied up). Removed with everything else on
  /// sign-out.
  static Future<void> writeNote(String name, Object? value) async {
    final userId = _currentUserId();
    if (userId == null) return;
    try {
      await _storage.write(key: '$_notePrefix$userId.$name', value: jsonEncode({'v': value}));
    } catch (_) {}
  }

  static Future<Object?> readNote(String name) async {
    final userId = _currentUserId();
    if (userId == null) return null;
    return _decode(await _safeRead('$_notePrefix$userId.$name'))?['v'];
  }

  /// A new run of the app (tests), or another account: nothing counts as read yet.
  @visibleForTesting
  static void resetSession() {
    _forgetMemory();
    _refreshedKeys.clear();
  }

  static void _forgetMemory() {
    offlineSince.value = null;
    _readOnce.clear();
    _fresh.clear();
    _last.clear();
    _local.clear();
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
        value: jsonEncode({...pass, '_user_id': _currentUserId(), '_saved_at': DateTime.now().toIso8601String()}));
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
  ///
  /// [also] names further keys to remove in the same pass (the snapshots).
  static Future<void> clearAll({bool Function(String key)? also}) async {
    _forgetMemory();
    try {
      await deleteWhere((key) => key.startsWith(_prefix) || (also?.call(key) ?? false));
    } catch (_) {
      await clearStudentPass();
    }
  }

  /// Deletes every stored entry whose key matches, all at once (one listing,
  /// the deletions side by side) instead of one after another.
  static Future<void> deleteWhere(bool Function(String key) matches) async {
    final all = await _storage.readAll();
    final keys = all.keys.where(matches).toList();
    await Future.wait([for (final key in keys) _storage.delete(key: key)]);
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
      await deleteWhere((key) => key.startsWith(_studentLookupPrefix));
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
