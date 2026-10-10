import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/signed_url_cache.dart';
import '../../../core/network/network_errors.dart';
import '../../../core/sync/session.dart';
import '../../supervisor/data/supervisor_repository.dart';
import '../providers/auth_provider.dart';
import 'biometric_device.dart';
import 'biometric_vault.dart';

/// Signing in with Face ID or a fingerprint: a faster sign-in for someone who
/// signed out (or whose phone was signed out), never a lock in front of the
/// app. This file is its rules; biometric_vault.dart is what it keeps and
/// biometric_device.dart is the phone.

/// Why the ordinary sign-in is shown where the returning one was expected.
/// Each is said in one line above the fields.
enum BiometricFallback {
  /// A face or a finger was added or removed, or none is enrolled any more.
  changed,

  /// The server no longer takes the stored sign-in (revoked, expired).
  expired,

  /// The phone locked its biometrics after too many tries.
  lockedOut;

  /// The one line. Supervisors have no password recovery of their own, so
  /// theirs ends with who to turn to.
  String line(BiometricKind kind, {required bool supervisor}) {
    final password = supervisor ? 'ادخل بكلمة المرور، أو تواصل مع شركتك.' : 'ادخل بكلمة المرور.';
    final again = supervisor
        ? 'ادخل بكلمة المرور مرة واحدة لتفعيله من جديد، أو تواصل مع شركتك.'
        : 'ادخل بكلمة المرور مرة واحدة لتفعيله من جديد.';
    return switch (this) {
      BiometricFallback.changed => switch (kind) {
          BiometricKind.faceId => 'تغيّر Face ID في هاتفك، فأوقفنا الدخول به. $again',
          BiometricKind.touchId => 'تغيّر Touch ID في هاتفك، فأوقفنا الدخول به. $again',
          BiometricKind.fingerprint => 'تغيّرت بصمات هاتفك، فأوقفنا الدخول بالبصمة. $again',
          BiometricKind.fingerprintOrFace =>
            'تغيّرت البصمة أو الوجه في هاتفك، فأوقفنا الدخول السريع. $again',
        },
      BiometricFallback.expired => 'انتهت جلستك على هذا الهاتف. $again',
      BiometricFallback.lockedOut => 'أوقف هاتفك التحقق مؤقتاً بعد عدة محاولات. $password',
    };
  }
}

/// What the phone did not recognise, under the amber glyph.
String biometricNotRecognisedLine({required bool supervisor}) => supervisor
    ? 'لم يتعرّف الهاتف عليك. حاول مرة أخرى، أو ادخل بكلمة المرور، أو تواصل مع شركتك.'
    : 'لم يتعرّف الهاتف عليك. حاول مرة أخرى، أو ادخل بكلمة المرور.';

/// A sign-in that is waiting on this phone, and what the phone offers for it.
class StoredSignIn {
  final BiometricAccount account;
  final BiometricOffer offer;

  const StoredSignIn(this.account, this.offer);

  BiometricKind get kind => offer.kind;
}

/// What a phone nobody is signed in on opens with: the returning sign-in
/// ([stored], the most recently used of [saved]), or the ordinary one, with a
/// line when the stored sign-ins were just dropped ([fallback]).
class BiometricEntry {
  /// Every sign-in waiting on this phone that it can still use, the most
  /// recently used first.
  final List<StoredSignIn> saved;
  final BiometricFallback? fallback;

  /// Whose words the [fallback] line is said in.
  final BiometricKind? fallbackKind;
  final bool fallbackSupervisor;

  const BiometricEntry({this.saved = const [], this.fallback, this.fallbackKind, this.fallbackSupervisor = false});

  static const none = BiometricEntry();

  StoredSignIn? get stored => saved.isEmpty ? null : saved.first;

  String? get fallbackLine => fallback?.line(fallbackKind ?? BiometricKind.fingerprintOrFace, supervisor: fallbackSupervisor);
}

/// How an attempt to sign in with the stored sign-in ended.
enum BiometricSignInResult {
  signedIn,

  /// Stay on the returning sign-in, amber: try again or use the password.
  notRecognised,

  /// The phone's prompt offered the password and it was chosen.
  usePassword,

  /// No connection: nothing was lost, try again.
  offline,

  /// The ordinary sign-in, with its line. Only [lockedOut] keeps the stored
  /// sign-in.
  lockedOut,
  changed,
  expired;

  BiometricFallback? get fallback => switch (this) {
        BiometricSignInResult.lockedOut => BiometricFallback.lockedOut,
        BiometricSignInResult.changed => BiometricFallback.changed,
        BiometricSignInResult.expired => BiometricFallback.expired,
        _ => null,
      };
}

class BiometricSignIn {
  BiometricSignIn({required this.device, required this.vault, required this.restore, this.revoke});

  final BiometricDevice device;
  final BiometricVault vault;

  /// Signs in with a released refresh token; throws what the server answers.
  final Future<void> Function(String refreshToken) restore;

  /// Ends a stored session on the server when it is thrown away.
  final Future<void> Function(String refreshToken)? revoke;

  /// What a signed-out phone opens with. A sign-in switched on before the
  /// phone's faces or fingers changed is dropped here, and only that one.
  Future<BiometricEntry> entry() async {
    final waiting = [
      for (final account in await vault.accounts())
        if (await vault.hasToken(account.userId)) account,
    ];
    if (waiting.isEmpty) return BiometricEntry.none;
    final offer = await device.offer();
    final saved = <StoredSignIn>[];
    BiometricAccount? dropped;
    for (final account in waiting) {
      if (offer != null && offer.sameAs(enrolled: account.enrolled, mark: account.mark)) {
        saved.add(StoredSignIn(account, offer));
      } else {
        await vault.forget(account.userId, revoke: revoke);
        dropped ??= account;
      }
    }
    // Said only when nothing is left to sign in with: the form is then all
    // there is, and it says why.
    if (saved.isEmpty && dropped != null) {
      return BiometricEntry(
        fallback: BiometricFallback.changed,
        fallbackKind: offer?.kind ?? dropped.kind,
        fallbackSupervisor: dropped.isSupervisor,
      );
    }
    return BiometricEntry(saved: saved);
  }

  /// Which of [saved] the form's button signs in, when it can tell without
  /// asking: the only one, or the one whose number is typed in the form.
  /// Null: several and nothing typed that says which (the screen then asks).
  static StoredSignIn? pick(List<StoredSignIn> saved, String typed) {
    if (saved.isEmpty) return null;
    if (saved.length == 1) return saved.single;
    final identifier = typed.trim();
    if (identifier.isEmpty) return null;
    // Only the masked form of a number is kept, so that is what is compared.
    final masked = BiometricAccount.mask(identifier);
    for (final stored in saved) {
      if (stored.account.maskedPhone == masked) return stored;
    }
    // Something else was typed: the most recently used, as on the returning sign-in.
    return saved.first;
  }

  /// The phone's prompt, then the stored sign-in of [userId] (null: the most
  /// recently used one that is waiting). Whatever goes wrong touches that
  /// account's entry alone.
  Future<BiometricSignInResult> signIn({String? userId}) async {
    BiometricAccount? account;
    if (userId != null) {
      account = await vault.account(userId);
    } else {
      for (final candidate in await vault.accounts()) {
        if (await vault.hasToken(candidate.userId)) {
          account = candidate;
          break;
        }
      }
    }
    if (account == null) return BiometricSignInResult.expired;
    final id = account.userId;
    final offer = await device.offer();
    if (offer == null || !offer.sameAs(enrolled: account.enrolled, mark: account.mark)) {
      await vault.forget(id, revoke: revoke);
      return BiometricSignInResult.changed;
    }
    final unlocked = await vault.unlock(device, id);
    switch (unlocked.check) {
      case BiometricCheck.passed:
        break;
      case BiometricCheck.notRecognised:
        return BiometricSignInResult.notRecognised;
      case BiometricCheck.usePassword:
        return BiometricSignInResult.usePassword;
      case BiometricCheck.lockedOut:
        return BiometricSignInResult.lockedOut;
      case BiometricCheck.unavailable:
        await vault.forget(id, revoke: revoke);
        return BiometricSignInResult.changed;
    }
    final token = unlocked.token;
    if (token == null || token.isEmpty) {
      await vault.disable(id);
      return BiometricSignInResult.expired;
    }
    try {
      await restore(token);
    } catch (error) {
      // No answer from the server: the token is as good as it was.
      if (isNetworkFailure(error)) return BiometricSignInResult.offline;
      // Refused: revoked, expired, the account is gone.
      await vault.disable(id);
      return BiometricSignInResult.expired;
    }
    // The session has it now (and has already replaced it with a newer one).
    await vault.signedIn(id);
    return BiometricSignInResult.signedIn;
  }

  /// Switches the sign-in on for the signed-in [account] (built by
  /// [BiometricAccountReader]), after the phone confirmed its owner once: on
  /// an iPhone this is also where it asks to allow Face ID.
  Future<BiometricCheck> enable(BiometricAccountDraft account) async {
    final check = await device.check();
    if (check != BiometricCheck.passed) return check;
    final offer = await device.offer(renew: true);
    if (offer == null) return BiometricCheck.unavailable;
    final orphaned = await vault.enable(BiometricAccount(
      userId: account.userId,
      role: account.role,
      firstName: BiometricAccount.firstNameOf(account.fullName),
      maskedPhone: BiometricAccount.mask(account.identifier),
      photoUrl: account.photoUrl,
      kind: offer.kind,
      enrolled: offer.enrolled,
      mark: offer.mark,
    ));
    await vault.markOffered(account.userId);
    // An account that had to make room is signed out for good.
    for (final token in orphaned) {
      try {
        await revoke?.call(token);
      } catch (_) {}
    }
    return BiometricCheck.passed;
  }

  /// Switches it off for [userId]: their entry goes, nobody else's.
  Future<void> disable(String userId) => vault.disable(userId);

  /// Whether it is switched on for [userId] on this phone: signed in or not,
  /// and whoever else has it on.
  Future<bool> isEnabledFor(String userId) async => await vault.account(userId) != null;

  /// Whether to ask [userId] «دخول أسرع؟» now: the phone offers something, it
  /// is not on already, and they were not asked before.
  Future<BiometricOffer?> offerFor(String userId) async {
    if (await vault.wasOffered(userId) || await isEnabledFor(userId)) return null;
    return device.offer();
  }

  Future<void> markOffered(String userId) => vault.markOffered(userId);
}

/// What is known about the signed-in account when the sign-in is switched on.
class BiometricAccountDraft {
  final String userId;
  final String role;
  final String fullName;

  /// The phone number (or a supervisor's e-mail): only its masked form is kept.
  final String identifier;
  final String? photoUrl;

  const BiometricAccountDraft({
    required this.userId,
    required this.role,
    required this.fullName,
    required this.identifier,
    this.photoUrl,
  });
}

typedef BiometricAccountReader = Future<BiometricAccountDraft?> Function();

final biometricDeviceProvider = Provider<BiometricDevice>((ref) => LocalAuthDevice());

final biometricSignInProvider = Provider<BiometricSignIn>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return BiometricSignIn(
    device: ref.watch(biometricDeviceProvider),
    vault: ref.watch(biometricVaultProvider),
    restore: (token) => ref.read(authStateProvider.notifier).signInWithStoredSession(token),
    revoke: repo.revokeSession,
  );
});

/// What the phone offers now; null when nothing is enrolled. Asked again when
/// the app comes back from the phone's settings (invalidate it).
final biometricOfferProvider =
    FutureProvider<BiometricOffer?>((ref) => ref.watch(biometricDeviceProvider).offer());

/// Whether the sign-in is switched on for the signed-in account.
final biometricEnabledProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(sessionUserIdProvider);
  if (userId == null) return false;
  return ref.watch(biometricSignInProvider).isEnabledFor(userId);
});

/// What the entry opens with. Read again every time someone signs in or out.
final biometricEntryProvider = FutureProvider<BiometricEntry>((ref) async {
  if (ref.watch(sessionUserIdProvider) != null) return BiometricEntry.none;
  try {
    return await ref.watch(biometricSignInProvider).entry();
  } catch (_) {
    return BiometricEntry.none;
  }
});

/// What the app's gate waits for before it shows a first screen to a phone
/// nobody is signed in on: [biometricEntryProvider], but never for long. A
/// keystore that is slow to answer costs the returning sign-in its first
/// frame, not the app its start.
final biometricEntryReadyProvider = FutureProvider<void>((ref) async {
  await ref
      .watch(biometricEntryProvider.future)
      .timeout(const Duration(milliseconds: 400), onTimeout: () => BiometricEntry.none);
});

/// Set by a sign-in with a password or a new account: the app, as soon as it
/// is up, asks «دخول أسرع؟» (see BiometricOfferHost).
final biometricOfferPendingProvider = StateProvider<bool>((ref) => false);

/// The question is on screen, or about to be. Whatever else the app wants to
/// ask at its start (the notifications explainer) waits while this or
/// [biometricOfferPendingProvider] is set: this question goes first.
final biometricOfferOpenProvider = StateProvider<bool>((ref) => false);

/// Whether another of the app's first questions must wait for this one.
bool biometricOfferComesFirst(WidgetRef ref) =>
    ref.read(biometricOfferPendingProvider) || ref.read(biometricOfferOpenProvider);

/// The signed-in account as the returning sign-in will show it, from what the
/// account's own screens load anyway (the profile, the supervisor's dashboard
/// and photo).
final biometricAccountReaderProvider = Provider<BiometricAccountReader>((ref) {
  String? withoutToken(String? url) {
    final uri = url == null ? null : Uri.tryParse(url);
    return uri == null || !uri.hasScheme ? null : '${uri.origin}${uri.path}';
  }

  return () async {
    final auth = ref.read(authStateProvider);
    final user = auth.user;
    if (user == null) return null;
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    var fullName = metadata['full_name'] as String? ?? '';
    var identifier = metadata['phone'] as String? ?? (user.email ?? '').replaceFirst(RegExp(r'@busak\.app$'), '');
    String? photoUrl;
    try {
      if (auth.isSupervisor) {
        final profile =
            (await ref.read(supervisorDashboardProvider.future).timeout(const Duration(seconds: 4))).profile;
        fullName = profile.fullName;
        if (profile.phone.trim().isNotEmpty) identifier = profile.phone;
        photoUrl = withoutToken(
            await ref.read(supervisorPhotoUrlProvider.future).timeout(const Duration(seconds: 4)));
      } else {
        final profile =
            await ref.read(studentProfileSummaryProvider(user.id).future).timeout(const Duration(seconds: 4));
        fullName = profile?['full_name'] as String? ?? fullName;
        identifier = profile?['phone'] as String? ?? identifier;
        final path = profile?['profile_image_url'] as String?;
        if (path != null && path.isNotEmpty) photoUrl = SignedUrlCache.offlineUrl('student-avatars', path);
      }
    } catch (_) {
      // Not loaded yet, or offline: the name and number the account itself carries.
    }
    return BiometricAccountDraft(
      userId: user.id,
      role: auth.role.name,
      fullName: fullName,
      identifier: identifier,
      photoUrl: photoUrl,
    );
  };
});
