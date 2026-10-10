// What signing in with Face ID or a fingerprint keeps on the phone, and what
// that costs.
//
// WHAT IS KEPT (all of it in the phone's keychain / keystore)
//   Per account that switched the sign-in on, under its own keys:
//   * `basak.biometric.account.<user id>`: that it is switched on, and the
//     little the sign-in screens show before anyone has proved anything: a
//     first name, the phone number with its middle hidden, where the photo
//     is, the role. Never the password, never the full number.
//   * `basak.biometric.token.<user id>`: the refresh token of that account's
//     Supabase session, and ONLY between its sign-out and its next sign-in.
//     While the account is signed in the session lives where Supabase keeps
//     it and this entry does not exist.
//   And once for the phone:
//   * `basak.biometric.index`: the ids of those accounts, the most recently
//     used first. At most [BiometricVault.accountLimit]; the oldest goes.
//   * `basak.biometric.offered`: the ids of the accounts already asked
//     «دخول أسرع؟» on this phone (the last few), so none is asked twice.
//
//   Before accounts were kept side by side there was one `basak.biometric.account`
//   and one `basak.biometric.token`. They are moved into the layout above the
//   first time the vault is read, and nobody is asked anything.
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
//   With several accounts saved, each has a session of its own left alive,
//   and each token is the one that was valid at that account's sign-out.
//   Nothing another account does can spend it: tokens are per session, and a
//   sign-out (of any scope) ends sessions of the account signing out only.
//
//   What "signed out" still promises: nobody who opens the app sees or loads
//   anything of the account. What it no longer promises: that the session is
//   dead on the server. Whoever can pass this phone's biometric check gets
//   back in — which is the feature — and the token sits in the phone's
//   keychain / keystore until then. With the switch off, signing out ends the
//   session on the server as it always did.
//
//   A token is released by one method only, [BiometricVault.unlock], which
//   runs the phone's check itself and reads the entry after it passed. (The
//   two places that end a session on the server read it to hand it straight
//   to the server, and keep nothing.) The check is the app's, not the
//   keystore's: flutter_secure_storage 9 cannot bind an entry to biometrics,
//   so a phone that is rooted or whose backup of the app's sandbox is opened
//   is protected by the keystore's encryption alone. On iPhone the entries
//   are `unlocked_this_device` (not in backups, not synced, unreadable while
//   the phone is locked).
//
// WHEN AN ACCOUNT'S ENTRIES ARE DROPPED (the others stay)
//   Switching it off in the account, deleting the account, a token the server
//   refuses (revoked, expired), a change of the phone's enrolled faces or
//   fingers since it was switched on, a sixth account being saved, and a
//   reinstall (the iPhone keychain outlives the app; the marker file does
//   not). «حساب آخر» and another account signing in drop nothing.
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

/// The entries described at the top of this file.
class BiometricVault {
  BiometricVault({SecretStore store = const SecureSecretStore(), InstallMarker? install = const FileInstallMarker()})
      : _store = store,
        _install = install;

  final SecretStore _store;
  final InstallMarker? _install;

  static const _prefix = 'basak.biometric.';
  static const indexKey = '${_prefix}index';
  static const offeredKey = '${_prefix}offered';

  /// The one account and its token, as they were kept before accounts were
  /// saved side by side. Read once more, to move them.
  static const legacyAccountKey = '${_prefix}account';
  static const legacyTokenKey = '${_prefix}token';

  static String accountKeyOf(String userId) => '$legacyAccountKey.$userId';
  static String tokenKeyOf(String userId) => '$legacyTokenKey.$userId';

  /// How many accounts can have the sign-in switched on, on one phone.
  static const accountLimit = 5;

  bool _moved = false;

  /// Before anything is read: entries left by an earlier installation go
  /// (asked every time: the marker is one small file), and, once per run, the
  /// old single entry moves into the per-account layout.
  Future<void> _ready() async {
    if (!await _sameInstall()) {
      for (final id in await _readIndex()) {
        await _drop(id);
      }
      for (final key in const [indexKey, legacyAccountKey, legacyTokenKey]) {
        await _store.delete(key);
      }
      return;
    }
    if (_moved) return;
    _moved = true;
    final raw = await _store.read(legacyAccountKey);
    if (raw == null) return;
    final old = _decode(raw);
    if (old != null) {
      final token = await _store.read(legacyTokenKey);
      await _store.write(accountKeyOf(old.userId), jsonEncode(old.toJson()));
      if (token != null && token.isNotEmpty) await _store.write(tokenKeyOf(old.userId), token);
      await _writeIndex([old.userId, ...(await _readIndex()).where((id) => id != old.userId)]);
    }
    await _store.delete(legacyAccountKey);
    await _store.delete(legacyTokenKey);
  }

  static BiometricAccount? _decode(String raw) {
    try {
      return BiometricAccount.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _readIndex() async {
    final raw = await _store.read(indexKey);
    if (raw == null) return [];
    try {
      return [for (final id in jsonDecode(raw) as List) if (id is String && id.isNotEmpty) id];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(List<String> ids) =>
      ids.isEmpty ? _store.delete(indexKey) : _store.write(indexKey, jsonEncode(ids));

  Future<void> _drop(String userId) async {
    for (final key in [tokenKeyOf(userId), accountKeyOf(userId)]) {
      try {
        await _store.delete(key);
      } catch (_) {}
    }
  }

  Future<bool> _sameInstall() async {
    try {
      return await _install?.exists() ?? true;
    } catch (_) {
      return true; // the folder cannot be asked: not a reason to sign anyone out
    }
  }

  /// Everyone the sign-in is switched on for, the most recently used first.
  /// A keystore that cannot be read counts as "nobody".
  Future<List<BiometricAccount>> accounts() async {
    try {
      await _ready();
      final found = <BiometricAccount>[];
      for (final id in await _readIndex()) {
        final raw = await _store.read(accountKeyOf(id));
        final account = raw == null ? null : _decode(raw);
        if (account != null && account.userId == id) found.add(account);
      }
      return found;
    } catch (_) {
      return const [];
    }
  }

  /// [userId]'s entry, or null when the sign-in is not switched on for them.
  Future<BiometricAccount?> account(String userId) async {
    try {
      await _ready();
      if (!(await _readIndex()).contains(userId)) return null;
      final raw = await _store.read(accountKeyOf(userId));
      final account = raw == null ? null : _decode(raw);
      return account?.userId == userId ? account : null;
    } catch (_) {
      return null;
    }
  }

  /// Switches the sign-in on for [account], beside whoever has it already. No
  /// token is kept yet: the account is signed in. Answers with the tokens of
  /// the accounts that had to make room (see [accountLimit]), for their
  /// sessions to be ended on the server.
  Future<List<String>> enable(BiometricAccount account) async {
    try {
      await _install?.create();
    } catch (_) {}
    await _ready();
    await _store.delete(tokenKeyOf(account.userId));
    await _store.write(accountKeyOf(account.userId), jsonEncode(account.toJson()));
    final ids = [account.userId, ...(await _readIndex()).where((id) => id != account.userId)];
    final orphaned = <String>[];
    while (ids.length > accountLimit) {
      final oldest = ids.removeLast();
      try {
        final token = await _store.read(tokenKeyOf(oldest));
        if (token != null && token.isNotEmpty) orphaned.add(token);
      } catch (_) {}
      await _drop(oldest);
    }
    await _writeIndex(ids);
    return orphaned;
  }

  /// Switches it off for [userId] and forgets their stored sign-in. Nobody
  /// else's is touched.
  Future<void> disable(String userId) async {
    try {
      await _ready();
      await _drop(userId);
      await _writeIndex((await _readIndex()).where((id) => id != userId).toList());
    } catch (_) {}
  }

  /// [userId] is signed in: a token put aside for them is no longer the
  /// session's and goes; their entry stays (the sign-in is still switched
  /// on) and they become the most recently used. Other accounts keep
  /// everything.
  Future<void> signedIn(String userId) async {
    try {
      await _ready();
      await _store.delete(tokenKeyOf(userId));
      final ids = await _readIndex();
      if (ids.contains(userId) && ids.first != userId) {
        await _writeIndex([userId, ...ids.where((id) => id != userId)]);
      }
    } catch (_) {}
  }

  /// [userId] signed in with their password while an earlier sign-out's token
  /// was still waiting: that older session is handed to [revoke] to be ended
  /// on the server, and then this is [signedIn].
  Future<void> supersede(String userId, {Future<void> Function(String token)? revoke}) async {
    String? stale;
    if (revoke != null) {
      try {
        await _ready();
        stale = await _store.read(tokenKeyOf(userId));
      } catch (_) {}
    }
    await signedIn(userId);
    if (stale != null && stale.isNotEmpty) {
      try {
        await revoke!(stale);
      } catch (_) {
        // Best effort: without its token the session cannot be used anyway.
      }
    }
  }

  /// Signing out: keeps [refreshToken] for the next sign-in when the sign-in
  /// is switched on for [userId]. True when it was kept, and the session must
  /// then be left alive on the server.
  Future<bool> hold(String userId, String? refreshToken) async {
    if (refreshToken == null || refreshToken.isEmpty) return false;
    if (await account(userId) == null) return false;
    try {
      await _store.write(tokenKeyOf(userId), refreshToken);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether a sign-in is waiting for [userId] (asked without reading it).
  Future<bool> hasToken(String userId) async {
    try {
      await _ready();
      return await _store.has(tokenKeyOf(userId));
    } catch (_) {
      return false;
    }
  }

  /// The only way a token leaves the vault to be signed in with: [device]
  /// shows the phone's prompt, and [userId]'s entry is read after the check
  /// passed.
  Future<({BiometricCheck check, String? token})> unlock(BiometricDevice device, String userId) async {
    final check = await device.check();
    if (check != BiometricCheck.passed) return (check: check, token: null);
    try {
      return (check: check, token: await _store.read(tokenKeyOf(userId)));
    } catch (_) {
      return (check: check, token: null);
    }
  }

  /// Forgets [userId]'s stored sign-in for good. [revoke] is handed the token
  /// once, to end its session on the server; it is not kept anywhere after.
  Future<void> forget(String userId, {Future<void> Function(String token)? revoke}) async {
    String? token;
    if (revoke != null) {
      try {
        token = await _store.read(tokenKeyOf(userId));
      } catch (_) {}
    }
    await disable(userId);
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
