import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Small encrypted cache for identity and QR lookup data needed on a bus with
/// intermittent connectivity. It never queues or stores attendance writes.
class OfflineCache {
  static const _storage = FlutterSecureStorage();
  static const _userIdKey = 'basak.offline.user_id';
  static const _roleKey = 'basak.offline.role';
  static const _studentPassKey = 'basak.offline.student_pass';
  static const _studentLookupPrefix = 'basak.offline.student_lookup.';

  static Future<void> saveSession(User user, String role) async {
    await _storage.write(key: _userIdKey, value: user.id);
    await _storage.write(key: _roleKey, value: role);
  }

  static Future<String?> readRoleFor(String userId) async {
    final cachedId = await _storage.read(key: _userIdKey);
    if (cachedId != userId) return null;
    return _storage.read(key: _roleKey);
  }

  static Future<void> saveStudentPass(Map<String, dynamic> pass) async {
    await _storage.write(key: _studentPassKey, value: jsonEncode(pass));
  }

  static Future<Map<String, dynamic>?> readStudentPass() async {
    final raw = await _storage.read(key: _studentPassKey);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearStudentPass() => _storage.delete(key: _studentPassKey);

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
      String supervisorId, String qrValue) async {
    final raw = await _storage.read(key: _lookupKey(supervisorId, qrValue));
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  /// Removes every cached lookup. Called on sign-out, so nothing a supervisor
  /// saw offline stays on the device for the next account.
  static Future<void> clearStudentLookups() async {
    final all = await _storage.readAll();
    for (final key in all.keys.toList()) {
      if (key.startsWith(_studentLookupPrefix)) {
        await _storage.delete(key: key);
      }
    }
  }

  static String _lookupKey(String supervisorId, String qrValue) =>
      '$_studentLookupPrefix$supervisorId.${_safeKey(qrValue)}';

  static String _safeKey(String value) => base64Url.encode(utf8.encode(value));
}
