import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, User;

import 'package:basak_mobile/core/network/session_keeping_client.dart';
import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/storage/snapshot_store.dart';
import 'package:basak_mobile/features/auth/biometrics/biometric_device.dart';
import 'package:basak_mobile/features/auth/biometrics/biometric_sign_in.dart';
import 'package:basak_mobile/features/auth/biometrics/biometric_vault.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';

import 'support/biometric_fakes.dart';

class _Native extends BiometricNative {
  const _Native({this.sensors, this.state});

  final Map<String, bool>? sensors;
  final String? state;

  @override
  Future<Map<String, bool>?> hardware() async => sensors;

  @override
  Future<String?> mark({required bool renew}) async => state;
}

LocalAuthDevice _phone(
  TargetPlatform platform,
  List<BiometricType> enrolled, {
  Map<String, bool>? sensors,
  String? state,
  Future<bool> Function()? authenticate,
}) =>
    LocalAuthDevice(
      platform: platform,
      native: _Native(sensors: sensors, state: state),
      enrolled: () async => enrolled,
      authenticate: authenticate ?? () async => true,
    );

const _user = User(id: 'student-1', appMetadata: {}, userMetadata: {}, aud: '', createdAt: '');

/// The server side of signing in and out, recorded.
class _Repo extends AuthRepository {
  final List<String> log = [];
  String? refreshToken = 'refresh-live';
  Object? restoreError;

  @override
  String? get currentRefreshToken => refreshToken;

  @override
  Future<void> signOut() async => log.add('signOut (session ended on the server)');

  @override
  Future<void> signOutKeepingSession() async => log.add('signOut (this phone only)');

  @override
  Future<({User user, UserRole role})> restoreSession(String refreshToken) async {
    log.add('restore $refreshToken');
    if (restoreError != null) throw restoreError!;
    return (user: _user, role: UserRole.student);
  }

  @override
  Future<void> deleteStudentAccount() async => log.add('delete');
}

class _SignedIn extends AuthNotifier {
  _SignedIn(super.repo, {super.biometrics}) {
    state = const AuthState(user: _user, role: UserRole.student);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what the phone offers', () {
    test('an iPhone is named after its own method', () async {
      final face = await _phone(TargetPlatform.iOS, [BiometricType.face], state: 'abc').offer();
      expect(face!.kind, BiometricKind.faceId);
      expect(face.kind.signInLabel, 'الدخول بـ Face ID');
      expect(face.kind.hint, 'انظر إلى الهاتف للدخول');
      expect(face.mark, 'abc');

      final touch = await _phone(TargetPlatform.iOS, [BiometricType.fingerprint]).offer();
      expect(touch!.kind, BiometricKind.touchId);
      expect(touch.kind.settingLabel, 'الدخول بـ Touch ID');
      expect(touch.kind.hint, 'ضع إصبعك على مستشعر البصمة');
    });

    test('Android says «البصمة» only when a fingerprint reader is all the phone has', () async {
      const enrolled = [BiometricType.strong, BiometricType.weak];
      final only = await _phone(TargetPlatform.android, enrolled,
          sensors: {'fingerprint': true, 'face': false, 'iris': false}).offer();
      expect(only!.kind, BiometricKind.fingerprint);
      expect(only.kind.settingLabel, 'الدخول بالبصمة');
      expect(only.kind.alsoLine, isNull);
      expect(only.enrolled, 'strong,weak');

      final both = await _phone(TargetPlatform.android, enrolled,
          sensors: {'fingerprint': true, 'face': true, 'iris': false}).offer();
      expect(both!.kind, BiometricKind.fingerprintOrFace);
      expect(both.kind.settingLabel, 'الدخول بالبصمة أو الوجه');
      expect(both.kind.signInLabel, 'الدخول بالبصمة');
      expect(both.kind.alsoLine, 'أو بالوجه، حسب ما فعّلته في إعدادات هاتفك.');

      // A phone that cannot say what it has is not promised to be a fingerprint.
      final unknown = await _phone(TargetPlatform.android, enrolled).offer();
      expect(unknown!.kind, BiometricKind.fingerprintOrFace);
    });

    test('nothing enrolled, no plugin, or another platform: nothing is offered', () async {
      expect(await _phone(TargetPlatform.iOS, const []).offer(), isNull);
      expect(await _phone(TargetPlatform.android, const []).offer(), isNull);
      expect(await _phone(TargetPlatform.windows, [BiometricType.face]).offer(), isNull);
      final broken = LocalAuthDevice(
          platform: TargetPlatform.android, enrolled: () async => throw StateError('no plugin'));
      expect(await broken.offer(), isNull);
      // The real plugin, which a test host does not have.
      expect(await LocalAuthDevice(platform: TargetPlatform.android).offer(), isNull);
    });

    test('how a check ends', () async {
      Future<BiometricCheck> ends(Future<bool> Function() authenticate) =>
          _phone(TargetPlatform.iOS, [BiometricType.face], authenticate: authenticate).check();
      Future<bool> fails(LocalAuthExceptionCode code) async => throw LocalAuthException(code: code);

      expect(await ends(() async => true), BiometricCheck.passed);
      expect(await ends(() async => false), BiometricCheck.notRecognised);
      expect(await ends(() => fails(LocalAuthExceptionCode.userCanceled)), BiometricCheck.notRecognised);
      expect(await ends(() => fails(LocalAuthExceptionCode.systemCanceled)), BiometricCheck.notRecognised);
      expect(await ends(() => fails(LocalAuthExceptionCode.temporaryLockout)), BiometricCheck.lockedOut);
      expect(await ends(() => fails(LocalAuthExceptionCode.biometricLockout)), BiometricCheck.lockedOut);
      expect(await ends(() => fails(LocalAuthExceptionCode.noBiometricsEnrolled)), BiometricCheck.unavailable);
      expect(await ends(() => fails(LocalAuthExceptionCode.userRequestedFallback)), BiometricCheck.usePassword);
      expect(await ends(() async => throw StateError('anything else')), BiometricCheck.notRecognised);
    });

    test('a changed enrolment is seen in the list or in the mark, and an unknown mark is not a change', () {
      const offer = BiometricOffer(kind: BiometricKind.faceId, enrolled: 'face', mark: 'b');
      expect(offer.sameAs(enrolled: 'face', mark: 'b'), isTrue);
      expect(offer.sameAs(enrolled: 'face', mark: 'a'), isFalse);
      expect(offer.sameAs(enrolled: 'face,fingerprint', mark: 'b'), isFalse);
      expect(offer.sameAs(enrolled: 'face', mark: null), isTrue);
    });
  });

  group('what is kept', () {
    test('a first name and a number with its middle hidden, never the number itself', () async {
      final fake = FakeVault();
      final signIn = BiometricSignIn(device: FakeBiometricDevice(), vault: fake.vault, restore: (_) async {});
      expect(await signIn.enable(saraDraft), BiometricCheck.passed);

      final account = (await fake.vault.account())!;
      expect(account.firstName, 'سارة');
      expect(account.maskedPhone, '010 •••• 6789');
      expect(account.kind, BiometricKind.faceId);
      expect(fake.store.values.values.join(), isNot(contains('01012346789')));
      expect(fake.token, isNull, reason: 'signed in: the session is Supabase\'s to keep');
      expect(await signIn.isEnabledFor('student-1'), isTrue);
      expect(await signIn.isEnabledFor('someone-else'), isFalse);

      expect(BiometricAccount.mask('supervisor@example.com'), 'su••••@example.com');
      expect(BiometricAccount.mask('+20 101 234 6789'), '010 •••• 6789');
    });

    test('switching it on needs the phone to confirm its owner', () async {
      for (final check in [BiometricCheck.notRecognised, BiometricCheck.lockedOut]) {
        final fake = FakeVault();
        final signIn = BiometricSignIn(
            device: FakeBiometricDevice(checks: [check]), vault: fake.vault, restore: (_) async {});
        expect(await signIn.enable(saraDraft), check);
        expect(fake.enabled, isFalse);
      }
    });

    test('the token leaves the vault only after the check passed', () async {
      final fake = FakeVault();
      await storeSignIn(fake);
      fake.store.reads.clear();

      final refused = await fake.vault.unlock(FakeBiometricDevice(checks: [BiometricCheck.notRecognised]));
      expect(refused.token, isNull);
      expect(await fake.vault.hasToken(), isTrue);
      expect(fake.store.readsOf(BiometricVault.tokenKey), 0, reason: 'not even read');

      final passed = await fake.vault.unlock(FakeBiometricDevice());
      expect(passed.token, 'refresh-1');
    });

    test('entries left by an earlier installation are not a stored sign-in', () async {
      final fake = FakeVault();
      await storeSignIn(fake);
      fake.install.there = false; // reinstalled: the keychain survived, the app's folder did not
      expect(await fake.vault.account(), isNull);
      expect(fake.enabled, isFalse);
      expect(fake.token, isNull);
    });

    test('another account signing in with its password drops the one stored', () async {
      final fake = FakeVault();
      await storeSignIn(fake);
      await fake.vault.signedIn('student-1');
      expect(fake.enabled, isTrue, reason: 'the same account: still switched on');
      expect(fake.token, isNull, reason: 'its old token is not the session\'s any more');

      await fake.vault.hold('student-1', 'refresh-2');
      await fake.vault.signedIn('student-2');
      expect(fake.enabled, isFalse);
      expect(fake.token, isNull);
    });
  });

  group('signing in with the stored sign-in', () {
    late FakeVault fake;
    late List<String> restored;
    late List<String> revoked;
    Object? restoreError;

    BiometricSignIn signIn(FakeBiometricDevice device) => BiometricSignIn(
          device: device,
          vault: fake.vault,
          restore: (token) async {
            restored.add(token);
            if (restoreError != null) throw restoreError!;
          },
          revoke: (token) async => revoked.add(token),
        );

    setUp(() async {
      fake = FakeVault();
      restored = [];
      revoked = [];
      restoreError = null;
      await storeSignIn(fake);
    });

    test('recognised: the session is restored and the token is used up', () async {
      final device = FakeBiometricDevice();
      final flow = signIn(device);
      expect((await flow.entry()).stored!.account.firstName, 'سارة');
      expect(await flow.signIn(), BiometricSignInResult.signedIn);
      expect(device.prompts, 1);
      expect(restored, ['refresh-1']);
      expect(fake.token, isNull);
      expect(fake.enabled, isTrue, reason: 'still on for the next sign-out');
    });

    test('not recognised: nothing is released and nothing is lost', () async {
      final flow = signIn(FakeBiometricDevice(checks: [BiometricCheck.notRecognised, BiometricCheck.passed]));
      expect(await flow.signIn(), BiometricSignInResult.notRecognised);
      expect(restored, isEmpty);
      expect(fake.token, 'refresh-1');
      // «حاول مرة أخرى»
      expect(await flow.signIn(), BiometricSignInResult.signedIn);
    });

    test('locked out by the phone: the ordinary sign-in, and the stored one waits', () async {
      final flow = signIn(FakeBiometricDevice(checks: [BiometricCheck.lockedOut]));
      final result = await flow.signIn();
      expect(result, BiometricSignInResult.lockedOut);
      expect(result.fallback, BiometricFallback.lockedOut);
      expect(restored, isEmpty);
      expect(fake.token, 'refresh-1');
      expect(fake.enabled, isTrue);
    });

    test('the phone\'s own prompt offered the password', () async {
      final flow = signIn(FakeBiometricDevice(checks: [BiometricCheck.usePassword]));
      expect(await flow.signIn(), BiometricSignInResult.usePassword);
      expect(fake.token, 'refresh-1');
    });

    test('a token the server no longer takes is dropped', () async {
      restoreError = const AuthException('Invalid Refresh Token: Refresh Token Not Found', statusCode: '400');
      final result = await signIn(FakeBiometricDevice()).signIn();
      expect(result, BiometricSignInResult.expired);
      expect(result.fallback, BiometricFallback.expired);
      expect(fake.enabled, isFalse);
      expect(fake.token, isNull);
    });

    test('no connection is not a refusal: the stored sign-in stays', () async {
      restoreError = const SocketException('Failed host lookup');
      expect(await signIn(FakeBiometricDevice()).signIn(), BiometricSignInResult.offline);
      expect(fake.token, 'refresh-1');
      expect(fake.enabled, isTrue);
    });

    test('a face or a finger was added: dropped before the phone is even asked', () async {
      const added = BiometricOffer(kind: BiometricKind.faceId, enrolled: 'face', mark: 'state-2');
      final device = FakeBiometricDevice(current: added);
      final flow = signIn(device);

      final entry = await flow.entry();
      expect(entry.stored, isNull);
      expect(entry.fallback, BiometricFallback.changed);
      expect(entry.fallbackLine, 'تغيّر Face ID في هاتفك، فأوقفنا الدخول به. ادخل بكلمة المرور مرة واحدة لتفعيله من جديد.');
      expect(device.prompts, 0);
      expect(fake.enabled, isFalse);
      expect(fake.token, isNull);
      expect(revoked, ['refresh-1'], reason: 'its session is ended on the server');

      // Asked again there is nothing stored, and nothing more to say.
      expect((await flow.entry()).fallback, isNull);
    });

    test('the same at the moment of signing in, and when nothing is enrolled any more', () async {
      final changed = signIn(FakeBiometricDevice(
          current: const BiometricOffer(kind: BiometricKind.faceId, enrolled: 'face,fingerprint', mark: 'state-1')));
      expect(await changed.signIn(), BiometricSignInResult.changed);
      expect(fake.enabled, isFalse);

      await storeSignIn(fake);
      final gone = signIn(FakeBiometricDevice(current: null));
      expect((await gone.entry()).fallback, BiometricFallback.changed);
      expect(fake.enabled, isFalse);
    });

    test('«حساب آخر» forgets the stored sign-in and ends its session', () async {
      await signIn(FakeBiometricDevice()).useAnotherAccount();
      expect(fake.enabled, isFalse);
      expect(fake.token, isNull);
      expect(revoked, ['refresh-1']);
    });

    test('supervisors are told who to turn to', () {
      expect(BiometricFallback.lockedOut.line(BiometricKind.fingerprint, supervisor: true),
          endsWith('ادخل بكلمة المرور، أو تواصل مع شركتك.'));
      expect(biometricNotRecognisedLine(supervisor: false),
          'لم يتعرّف الهاتف عليك. حاول مرة أخرى، أو ادخل بكلمة المرور.');
      expect(biometricNotRecognisedLine(supervisor: true), endsWith('ادخل بكلمة المرور، أو تواصل مع شركتك.'));
    });
  });

  group('the offer', () {
    test('once per account, and never on a phone with nothing enrolled', () async {
      final fake = FakeVault();
      final device = FakeBiometricDevice();
      final flow = BiometricSignIn(device: device, vault: fake.vault, restore: (_) async {});

      expect((await flow.offerFor('student-1'))!.kind, BiometricKind.faceId);
      await flow.markOffered('student-1');
      expect(await flow.offerFor('student-1'), isNull);
      expect(await flow.offerFor('student-2'), isNotNull, reason: 'another account has not been asked');

      device.current = null;
      expect(await flow.offerFor('student-2'), isNull);
    });
  });

  group('signing out', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      OfflineCache.debugUserId = 'student-1';
      OfflineCache.resetSession();
    });
    tearDown(() => OfflineCache.debugUserId = null);

    Future<Map<String, String>> leaveData() async {
      await OfflineCache.readThrough('profile.summary', () async => {'full_name': 'سارة'});
      await SnapshotStore.write('student-1', 'current_subscription', {'id': 's1'});
      await Future<void>.delayed(Duration.zero);
      return const FlutterSecureStorage().readAll();
    }

    Future<Iterable<String>> accountData() async => (await const FlutterSecureStorage().readAll())
        .keys
        .where((key) => key.startsWith('basak.offline.') || key.startsWith('basak.snapshot.'));

    test('with the sign-in on: this phone forgets everything, and the session is kept for next time', () async {
      final fake = FakeVault();
      await BiometricSignIn(device: FakeBiometricDevice(), vault: fake.vault, restore: (_) async {})
          .enable(saraDraft);
      final repo = _Repo();
      final auth = _SignedIn(repo, biometrics: fake.vault);
      addTearDown(auth.dispose);
      expect((await leaveData()).keys.where((k) => k.startsWith('basak.')), isNotEmpty);

      await auth.signOut();

      expect(repo.log, ['signOut (this phone only)']);
      expect(auth.state.isAuthenticated, isFalse);
      expect(await accountData(), isEmpty, reason: 'the next person sees nothing of this account');
      expect(fake.token, 'refresh-live');
      expect(fake.enabled, isTrue);
      // …and what is kept says no more than the returning sign-in shows.
      expect(fake.store.values.keys, unorderedEquals([BiometricVault.accountKey, BiometricVault.tokenKey, BiometricVault.offeredKey]));
    });

    test('with it off, or on for someone else: an ordinary sign-out, nothing kept', () async {
      final off = FakeVault();
      final repo = _Repo();
      final auth = _SignedIn(repo, biometrics: off.vault);
      addTearDown(auth.dispose);
      await leaveData();
      await auth.signOut();
      expect(repo.log, ['signOut (session ended on the server)']);
      expect(off.store.values, isEmpty);
      expect(await accountData(), isEmpty);

      final other = FakeVault();
      await BiometricSignIn(device: FakeBiometricDevice(), vault: other.vault, restore: (_) async {})
          .enable(supervisorDraft);
      final repo2 = _Repo();
      final auth2 = _SignedIn(repo2, biometrics: other.vault);
      addTearDown(auth2.dispose);
      await auth2.signOut();
      expect(repo2.log, ['signOut (session ended on the server)']);
      expect(other.token, isNull);
    });

    test('no session to keep: an ordinary sign-out', () async {
      final fake = FakeVault();
      await BiometricSignIn(device: FakeBiometricDevice(), vault: fake.vault, restore: (_) async {})
          .enable(saraDraft);
      final repo = _Repo()..refreshToken = null;
      final auth = _SignedIn(repo, biometrics: fake.vault);
      addTearDown(auth.dispose);
      await auth.signOut();
      expect(repo.log, ['signOut (session ended on the server)']);
      expect(fake.token, isNull);
    });

    test('signing in again with the stored session makes the account the signed-in one', () async {
      final fake = FakeVault();
      await storeSignIn(fake);
      final repo = _Repo();
      final auth = AuthNotifier(repo, biometrics: fake.vault);
      addTearDown(auth.dispose);
      final flow = BiometricSignIn(
          device: FakeBiometricDevice(), vault: fake.vault, restore: auth.signInWithStoredSession);

      expect(await flow.signIn(), BiometricSignInResult.signedIn);
      expect(repo.log, ['restore refresh-1']);
      expect(auth.state.user?.id, 'student-1');
      expect(auth.state.role, UserRole.student);
      expect(fake.token, isNull);
    });

    test('a refused session leaves nobody signed in', () async {
      final fake = FakeVault();
      await storeSignIn(fake);
      final repo = _Repo()..restoreError = const AuthException('Invalid Refresh Token', statusCode: '400');
      final auth = AuthNotifier(repo, biometrics: fake.vault);
      addTearDown(auth.dispose);
      final flow = BiometricSignIn(
          device: FakeBiometricDevice(), vault: fake.vault, restore: auth.signInWithStoredSession);
      expect(await flow.signIn(), BiometricSignInResult.expired);
      expect(auth.state.isAuthenticated, isFalse);
      expect(auth.state.isLoading, isFalse);
      expect(fake.enabled, isFalse);
    });

    test('deleting the account forgets the stored sign-in', () async {
      final fake = FakeVault();
      await BiometricSignIn(device: FakeBiometricDevice(), vault: fake.vault, restore: (_) async {})
          .enable(saraDraft);
      final repo = _Repo();
      final auth = _SignedIn(repo, biometrics: fake.vault);
      addTearDown(auth.dispose);
      await auth.deleteStudentAccount();
      expect(repo.log, ['delete']);
      expect(fake.enabled, isFalse);
      expect(fake.token, isNull);
      expect(auth.state.isAuthenticated, isFalse);
    });
  });

  group('leaving the session alive on the server', () {
    test('only the sign-out request is held back, and only while asked', () async {
      final sent = <String>[];
      final client = SessionKeepingClient(MockClient((request) async {
        sent.add('${request.method} ${request.url.path}');
        return http.Response('{}', 200);
      }));
      final logout = Uri.parse('https://x.supabase.co/auth/v1/logout?scope=local');
      final token = Uri.parse('https://x.supabase.co/auth/v1/token?grant_type=refresh_token');

      await client.post(logout);
      expect(sent, ['POST /auth/v1/logout'], reason: 'an ordinary sign-out reaches the server');

      sent.clear();
      final answer = await client.withoutRevoking(() async {
        await client.post(token);
        return client.post(logout);
      });
      expect(answer.statusCode, 204);
      expect(sent, ['POST /auth/v1/token']);

      sent.clear();
      await client.post(logout);
      expect(sent, ['POST /auth/v1/logout'], reason: 'and the next ordinary one does again');
    });
  });
}
