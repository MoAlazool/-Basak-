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

  static Future<void> saveStudentLookup(
      String qrValue, Map<String, dynamic> details) async {
    await _storage.write(
      key: '$_studentLookupPrefix${_safeKey(qrValue)}',
      value: jsonEncode({
        ...details,
        '_cached_at': DateTime.now().toIso8601String(),
      }),
    );
  }

  static Future<Map<String, dynamic>?> readStudentLookup(String qrValue) async {
    final raw = await _storage.read(
        key: '$_studentLookupPrefix${_safeKey(qrValue)}');
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static String _safeKey(String value) => base64Url.encode(utf8.encode(value));
}
