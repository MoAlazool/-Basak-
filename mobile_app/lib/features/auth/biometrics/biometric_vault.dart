// What signing in with Face ID or a fingerprint keeps on the phone, and what
// that costs.
//
// WHAT IS KEPT
//   * `basak.biometric.account`: that the sign-in is switched on, for whom,
//     and the little the returning sign-in shows before anyone has proved
//     anything: a first name, the phone number with its middle hidden, where
//     the photo is, the role. Never the password, never the full number.
//   * `basak.biometric.token`: the refresh token of the Supabase session,
//     and ONLY between a sign-out and the next sign-in. While the account is
//     signed in the session lives where Supabase keeps it and this entry does
//     not exist.
//   * `basak.biometric.offered`: the ids of the accounts already asked
//     «دخول أسرع؟» on this phone (the last few), so none is asked twice.
//
// THE TRADE-OFF
//   A refresh token is only good while its session is alive on the server,
//   and an ordinary sign-out ends that session. So when the sign-in is
//   switched on, «تسجيل الخروج» is a sign-out of THIS PHONE: the session is
//   removed from the app and everything saved for the account is deleted
//   exactly as before (the offline cache, the snapshots, signed links, the
//   reminders, the push registration), but the server is not told to end the
//   session, and its refresh token moves here. Without that there would be
//   nothing to sign in again with, short of keeping the password.
//
//   What "signed out" still promises: nobody who opens the app sees or loads
//   anything of the account. What it no longer promises: that the session is
//   dead on the server. Whoever can pass this phone's biometric check gets
//   back in — which is the feature — and the token sits in the phone's
//   keychain / keystore until then. With the switch off, signing out ends the
//   session on the server as it always did.
//
//   The token is released by one method only, [BiometricVault.unlock], which
//   runs the phone's check itself and reads the entry after it passed. The
//   check is the app's, not the keystore's: flutter_secure_storage 9 cannot
//   bind an entry to biometrics, so a phone that is rooted or whose backup of
//   the app's sandbox is opened is protected by the keystore's encryption
//   alone. On iPhone the entry is `unlocked_this_device` (not in backups, not
//   synced, unreadable while the phone is locked).
//
// WHEN IT IS DROPPED
//   «حساب آخر», deleting the account, switching it off, another account
//   signing in on this phone, a token the server refuses (revoked, expired),
//   a change of the phone's enrolled faces or fingers, and a reinstall (the
//   iPhone keychain outlives the app; the marker file does not).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'biometric_device.dart';

/// Where the entries are kept (the phone's keychain / keystore). Replaced in
/// tests.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<bool> has(String key);
}

class SecureSecretStore implements SecretStore {
  const SecureSecretStore();

  static const _storage = FlutterSecureStorage();
  static const _ios = IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device);

  @override
  Future<String?> read(String key) => _storage.read(key: key, iOptions: _ios);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value, iOptions: _ios);

  @override
  Future<void> delete(String key) => _storage.delete(key: key, iOptions: _ios);

  @override
  Future<bool> has(String key) => _storage.containsKey(key: key, iOptions: _ios);
}

/// Tells this installation from an earlier one: a file in the app's own
/// folder, which a reinstall removes and the iPhone keychain does not.
abstract class InstallMarker {
  Future<bool> exists();
  Future<void> create();
}

class FileInstallMarker implements InstallMarker {
  const FileInstallMarker();

  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/biometric_sign_in');

  @override
  Future<bool> exists() async => (await _file()).exists();

  @override
  Future<void> create() async {
    await (await _file()).create(recursive: true);
  }
}

/// Who the sign-in is switched on for, and what the returning sign-in shows.
@immutable
class BiometricAccount {
  final String userId;

  /// The role's name (`student`, `supervisor`): which words the screen uses.
  final String role;

  /// «سارة».
  final String firstName;

  /// «010 •••• 6789».
  final String maskedPhone;

  /// The photo's address without its token: it names the copy the image cache
  /// kept on disk and cannot download anything.
  final String? photoUrl;

  /// What the phone offered when this was switched on.
  final BiometricKind kind;
  final String enrolled;
  final String? mark;

  const BiometricAccount({
    required this.userId,
    required this.role,
    required this.firstName,
    required this.maskedPhone,
    this.photoUrl,
    required this.kind,
    required this.enrolled,
    this.mark,
  });

  bool get isSupervisor => role == 'supervisor';

  /// The first word of a full name.
  static String firstNameOf(String fullName) {
    final words = fullName.trim().split(RegExp(r'\s+'));
    return words.isEmpty ? '' : words.first;
  }

  /// An Egyptian mobile as «010 •••• 6789»; anything else (a supervisor's
  /// e-mail) keeps its first two characters and what follows the @.
  static String mask(String identifier) {
    final value = identifier.trim();
    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    // +20 10… and 10… are the same number as 010…
    if (digits.startsWith('20') && digits.length >= 12) digits = digits.substring(2);
    if (digits.length == 10 && digits.startsWith('1')) digits = '0$digits';
    if (!value.contains('@') && digits.length >= 10) {
      return '${digits.substring(0, 3)} •••• ${digits.substring(digits.length - 4)}';
    }
    final at = value.indexOf('@');
    if (at > 0) return '${value.substring(0, at < 2 ? at : 2)}••••${value.substring(at)}';
    return value.length <= 2 ? value : '${value.substring(0, 2)}••••';
  }

  Map<String, Object?> toJson() => {
        'user_id': userId,
        'role': role,
        'first_name': firstName,
        'masked_phone': maskedPhone,
        if (photoUrl != null) 'photo_url': photoUrl,
        'kind': kind.name,
        'enrolled': enrolled,
        if (mark != null) 'mark': mark,
      };

  static BiometricAccount? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = BiometricKind.named(json['kind'] as String?);
    final userId = json['user_id'];
    if (kind == null || userId is! String || userId.isEmpty) return null;
    return BiometricAccount(
      userId: userId,
      role: json['role'] as String? ?? 'student',
      firstName: json['first_name'] as String? ?? '',
      maskedPhone: json['masked_phone'] as String? ?? '',
      photoUrl: json['photo_url'] as String?,
      kind: kind,
      enrolled: json['enrolled'] as String? ?? '',
      mark: json['mark'] as String?,
    );
  }
}

/// The three entries described at the top of this file.
class BiometricVault {
  BiometricVault({SecretStore store = const SecureSecretStore(), InstallMarker? install = const FileInstallMarker()})
      : _store = store,
        _install = install;

  final SecretStore _store;
  final InstallMarker? _install;

  static const _prefix = 'basak.biometric.';
  static const accountKey = '${_prefix}account';
  static const tokenKey = '${_prefix}token';
  static const offeredKey = '${_prefix}offered';

  /// Who the sign-in is switched on for, or null. A keystore that cannot be
  /// read, or entries left by an earlier installation, count as "nobody".
  Future<BiometricAccount?> account() async {
    try {
      final raw = await _store.read(accountKey);
      if (raw == null) return null;
      final account = BiometricAccount.fromJson(jsonDecode(raw));
      if (account == null || !await _sameInstall()) {
        await disable();
        return null;
      }
      return account;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _sameInstall() async {
    try {
      return await _install?.exists() ?? true;
    } catch (_) {
      return true; // the folder cannot be asked: not a reason to sign anyone out
    }
  }

  /// Switches the sign-in on for [account]. No token is kept yet: the account
  /// is signed in.
  Future<void> enable(BiometricAccount account) async {
    try {
      await _install?.create();
    } catch (_) {}
    await _store.delete(tokenKey);
    await _store.write(accountKey, jsonEncode(account.toJson()));
  }

  /// Switches it off and forgets the stored sign-in.
  Future<void> disable() async {
    for (final key in const [tokenKey, accountKey]) {
      try {
        await _store.delete(key);
      } catch (_) {}
    }
  }

  /// A password sign-in as [userId]: a sign-in stored for anyone else on this
  /// phone goes, and so does a token that is no longer the session's.
  Future<void> signedIn(String userId) async {
    final current = await account();
    if (current != null && current.userId != userId) return disable();
    try {
      await _store.delete(tokenKey);
    } catch (_) {}
  }

  /// Signing out: keeps [refreshToken] for the next sign-in when the sign-in
  /// is switched on for [userId]. True when it was kept, and the session must
  /// then be left alive on the server.
  Future<bool> hold(String userId, String? refreshToken) async {
    if (refreshToken == null || refreshToken.isEmpty) return false;
    final current = await account();
    if (current == null || current.userId != userId) return false;
    try {
      await _store.write(tokenKey, refreshToken);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether a sign-in is waiting (asked without reading it).
  Future<bool> hasToken() async {
    try {
      return await _store.has(tokenKey);
    } catch (_) {
      return false;
    }
  }

  /// The only way the token leaves the vault: [device] shows the phone's
  /// prompt, and the entry is read after the check passed.
  Future<({BiometricCheck check, String? token})> unlock(BiometricDevice device) async {
    final check = await device.check();
    if (check != BiometricCheck.passed) return (check: check, token: null);
    try {
      return (check: check, token: await _store.read(tokenKey));
    } catch (_) {
      return (check: check, token: null);
    }
  }

  /// Forgets the stored sign-in for good. [revoke] is handed the token once,
  /// to end its session on the server; it is not kept anywhere after.
  Future<void> forget({Future<void> Function(String token)? revoke}) async {
    String? token;
    if (revoke != null) {
      try {
        token = await _store.read(tokenKey);
      } catch (_) {}
    }
    await disable();
    if (token != null && token.isNotEmpty) {
      try {
        await revoke!(token);
      } catch (_) {
        // Best effort: without its token the session cannot be used anyway.
      }
    }
  }

  /// How many accounts' answers are remembered on one phone.
  static const offeredLimit = 8;

  /// The ids of the accounts already asked, oldest first. (An entry written
  /// by an earlier version is one id, which reads as a list of one.)
  Future<List<String>> _offered() async =>
      (await _store.read(offeredKey) ?? '').split(',').where((id) => id.isNotEmpty).toList();

  /// Whether [userId] was already asked «دخول أسرع؟» on this phone.
  Future<bool> wasOffered(String userId) async {
    try {
      return (await _offered()).contains(userId);
    } catch (_) {
      return true; // a keystore that cannot be read is not asked to keep more
    }
  }

  /// Remembers that [userId] was asked, beside the others asked on this
  /// phone: two people sharing it are each asked once.
  Future<void> markOffered(String userId) async {
    try {
      final asked = (await _offered())..remove(userId);
      asked.add(userId);
      final kept = asked.length > offeredLimit ? asked.sublist(asked.length - offeredLimit) : asked;
      await _store.write(offeredKey, kept.join(','));
    } catch (_) {}
  }
}
