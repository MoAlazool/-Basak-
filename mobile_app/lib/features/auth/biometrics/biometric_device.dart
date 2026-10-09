import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show IconData;
import 'package:local_auth/local_auth.dart';
// The prompt's Arabic words can only be given through the two platform
// packages `local_auth` itself brings in (its README says to import them).
// They are in pubspec.lock; naming them in pubspec.yaml removes these ignores.

import 'package:local_auth_android/local_auth_android.dart' show AndroidAuthMessages;

import 'package:local_auth_darwin/local_auth_darwin.dart' show IOSAuthMessages;

import '../../../core/theme/app_icons.dart';

/// What the phone calls its own check. The app's words follow it and never
/// promise more than the phone reports.
enum BiometricKind {
  /// iPhone with Face ID.
  faceId,

  /// iPhone with Touch ID.
  touchId,

  /// Android whose only biometric hardware is a fingerprint reader.
  fingerprint,

  /// Any other Android: it says how strong the enrolled method is, not which
  /// one it is.
  fingerprintOrFace;

  static BiometricKind? named(String? name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// The Arabic of each kind, in one place.
extension BiometricWords on BiometricKind {
  bool get _face => this == BiometricKind.faceId;

  /// «Face ID», «البصمة»: after «تفعيل».
  String get name => switch (this) {
        BiometricKind.faceId => 'Face ID',
        BiometricKind.touchId => 'Touch ID',
        BiometricKind.fingerprint => 'البصمة',
        BiometricKind.fingerprintOrFace => 'البصمة أو الوجه',
      };

  /// The account switch, and what the square button beside «دخول» says.
  String get settingLabel => switch (this) {
        BiometricKind.faceId => 'الدخول بـ Face ID',
        BiometricKind.touchId => 'الدخول بـ Touch ID',
        BiometricKind.fingerprint => 'الدخول بالبصمة',
        BiometricKind.fingerprintOrFace => 'الدخول بالبصمة أو الوجه',
      };

  /// The returning sign-in's button. Android's is the fingerprint either way;
  /// [alsoLine] says the rest.
  String get signInLabel => switch (this) {
        BiometricKind.faceId => 'الدخول بـ Face ID',
        BiometricKind.touchId => 'الدخول بـ Touch ID',
        BiometricKind.fingerprint || BiometricKind.fingerprintOrFace => 'الدخول بالبصمة',
      };

  /// Under the large glyph.
  String get hint => _face ? 'انظر إلى الهاتف للدخول' : 'ضع إصبعك على مستشعر البصمة';

  /// Under the password link, where the phone may use a face instead.
  String? get alsoLine =>
      this == BiometricKind.fingerprintOrFace ? 'أو بالوجه، حسب ما فعّلته في إعدادات هاتفك.' : null;

  IconData get icon => _face ? LucideIcons.scanFace : LucideIcons.fingerprint;

  String get offerTitle => switch (this) {
        BiometricKind.faceId => 'دخول أسرع بـ Face ID؟',
        BiometricKind.touchId => 'دخول أسرع بـ Touch ID؟',
        BiometricKind.fingerprint => 'دخول أسرع بالبصمة؟',
        BiometricKind.fingerprintOrFace => 'دخول أسرع بالبصمة أو الوجه؟',
      };

  String get offerBody => switch (this) {
        BiometricKind.faceId =>
          'في المرة القادمة تدخل بنظرة، بدون كلمة المرور. بيانات وجهك تبقى على هاتفك ولا تصل إلينا.',
        BiometricKind.touchId || BiometricKind.fingerprint =>
          'في المرة القادمة تدخل بلمسة، بدون كلمة المرور. بيانات بصمتك تبقى على هاتفك ولا تصل إلينا.',
        BiometricKind.fingerprintOrFace =>
          'في المرة القادمة تدخل بلمسة أو نظرة، بدون كلمة المرور. بيانات بصمتك ووجهك تبقى على هاتفك ولا تصل إلينا.',
      };

  String get enableLabel => 'تفعيل $name';
}

/// How one check by the phone ended.
enum BiometricCheck {
  passed,

  /// Not recognised, or the phone's prompt was closed.
  notRecognised,

  /// Too many tries: the phone refuses biometrics for now.
  lockedOut,

  /// Nothing is enrolled any more, or the hardware is gone.
  unavailable,

  /// The phone's prompt offered the password and it was chosen.
  usePassword,
}

/// What the phone offers right now.
@immutable
class BiometricOffer {
  final BiometricKind kind;

  /// The enrolled methods as the phone lists them, e.g. `face` or
  /// `strong,weak`.
  final String enrolled;

  /// A value that is different once a face or a finger is added or removed,
  /// where the phone can say (see [LocalAuthDevice]); null where it cannot.
  final String? mark;

  const BiometricOffer({required this.kind, required this.enrolled, this.mark});

  /// Whether the phone's biometrics are what they were when [enrolled] and
  /// [mark] were saved.
  bool sameAs({required String enrolled, required String? mark}) {
    if (enrolled != this.enrolled) return false;
    // Compared only where the phone answered both times.
    if (mark == null || this.mark == null) return true;
    return mark == this.mark;
  }
}

/// The phone's biometrics, as the app needs them. Replaced by a fake in tests.
abstract class BiometricDevice {
  /// What the phone offers, or null when nothing is enrolled (or the phone
  /// has no biometrics): then the app shows no offer, no button and no row.
  ///
  /// [renew] starts a new [BiometricOffer.mark]: asked when the sign-in is
  /// being switched on, so what is saved describes the phone as it is now.
  Future<BiometricOffer?> offer({bool renew = false});

  /// Shows the phone's own prompt. The app draws nothing while it is up.
  Future<BiometricCheck> check();
}

/// The parts of the phone the app's own code asks: which biometric hardware
/// an Android has, and the mark of what is enrolled (`basak/biometrics`, in
/// MainActivity.kt and AppDelegate.swift).
class BiometricNative {
  const BiometricNative();

  static const _channel = MethodChannel('basak/biometrics');

  /// Android: `{fingerprint, face, iris}`. Null where it cannot be asked.
  Future<Map<String, bool>?> hardware() async {
    try {
      final answer = await _channel.invokeMapMethod<String, bool>('hardware');
      return answer;
    } catch (_) {
      return null;
    }
  }

  /// iPhone: the system's own state of the enrolled faces or fingers.
  /// Android: `valid` while the key made when the sign-in was switched on is
  /// usable; `invalidated` once a fingerprint or face was added; `missing`
  /// when the phone removed it. Null where it cannot be asked.
  Future<String?> mark({required bool renew}) async {
    try {
      return await _channel.invokeMethod<String>('enrollmentMark', {'renew': renew});
    } catch (_) {
      return null;
    }
  }
}

/// [BiometricDevice] over the `local_auth` plugin.
///
/// Names: an iPhone lists Face ID or Touch ID. Android (local_auth_android
/// 2.x) lists only "strong" and "weak", so the kind comes from the hardware:
/// a phone with a fingerprint reader and no face or iris sensor is «البصمة»,
/// every other one «البصمة أو الوجه».
///
/// Changes: `local_auth` cannot tell that a finger or a face was added.
/// [BiometricNative.mark] can: on iPhone the system's domain state, on
/// Android a keystore key that the system invalidates on a new enrolment
/// (strong biometrics only; with a weak one alone there is no mark, and only
/// a change in [BiometricOffer.enrolled] is seen).
class LocalAuthDevice implements BiometricDevice {
  LocalAuthDevice({
    LocalAuthentication? auth,
    BiometricNative native = const BiometricNative(),
    TargetPlatform? platform,
    Future<List<BiometricType>> Function()? enrolled,
    Future<bool> Function()? authenticate,
  })  : _native = native,
        _platform = platform,
        _auth = auth ?? LocalAuthentication() {
    _enrolled = enrolled ?? _auth.getAvailableBiometrics;
    _authenticate = authenticate ?? _prompt;
  }

  final LocalAuthentication _auth;
  final BiometricNative _native;
  final TargetPlatform? _platform;
  late final Future<List<BiometricType>> Function() _enrolled;
  late final Future<bool> Function() _authenticate;

  /// What the phone's prompt is told to say.
  static const reason = 'تأكيد هويتك للدخول إلى باصك';

  TargetPlatform get _target => _platform ?? defaultTargetPlatform;

  Future<bool> _prompt() => _auth.authenticate(
        localizedReason: reason,
        // A PIN or a pattern is not what was switched on.
        biometricOnly: true,
        persistAcrossBackgrounding: true,
        authMessages: const [
          AndroidAuthMessages(signInTitle: 'تأكيد هويتك', cancelButton: 'إلغاء'),
          IOSAuthMessages(cancelButton: 'إلغاء', localizedFallbackTitle: 'الدخول بكلمة المرور'),
        ],
      );

  @override
  Future<BiometricOffer?> offer({bool renew = false}) async {
    if (kIsWeb) return null;
    final target = _target;
    if (target != TargetPlatform.iOS && target != TargetPlatform.android) return null;
    final List<BiometricType> types;
    try {
      types = await _enrolled();
    } catch (_) {
      return null; // no plugin (tests), no activity, no hardware
    }
    if (types.isEmpty) return null;

    final BiometricKind kind;
    if (target == TargetPlatform.iOS) {
      if (types.contains(BiometricType.face)) {
        kind = BiometricKind.faceId;
      } else if (types.contains(BiometricType.fingerprint)) {
        kind = BiometricKind.touchId;
      } else {
        return null;
      }
    } else {
      final hardware = await _native.hardware();
      final fingerprintOnly = types.every((type) => type == BiometricType.fingerprint) ||
          (hardware != null &&
              hardware['fingerprint'] == true &&
              hardware['face'] != true &&
              hardware['iris'] != true);
      kind = fingerprintOnly ? BiometricKind.fingerprint : BiometricKind.fingerprintOrFace;
    }

    final names = [for (final type in types) type.name]..sort();
    return BiometricOffer(kind: kind, enrolled: names.join(','), mark: await _native.mark(renew: renew));
  }

  @override
  Future<BiometricCheck> check() async {
    try {
      return await _authenticate() ? BiometricCheck.passed : BiometricCheck.notRecognised;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.temporaryLockout || LocalAuthExceptionCode.biometricLockout => BiometricCheck.lockedOut,
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.noCredentialsSet =>
          BiometricCheck.unavailable,
        LocalAuthExceptionCode.userRequestedFallback => BiometricCheck.usePassword,
        // Closed by the person or the system, timed out, busy: try again.
        _ => BiometricCheck.notRecognised,
      };
    } catch (_) {
      return BiometricCheck.notRecognised;
    }
  }
}
