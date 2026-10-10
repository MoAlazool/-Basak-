import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, User;

import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/features/auth/biometrics/biometric_device.dart';
import 'package:basak_mobile/features/auth/biometrics/biometric_sign_in.dart';
import 'package:basak_mobile/features/auth/biometrics/presentation/biometric_offer.dart';
import 'package:basak_mobile/features/auth/biometrics/presentation/biometric_setting_row.dart';
import 'package:basak_mobile/features/auth/biometrics/presentation/returning_sign_in_screen.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/presentation/login_register_screen.dart';
import 'package:basak_mobile/features/auth/presentation/welcome_screen.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/onboarding/onboarding_controller.dart';

import 'support/biometric_fakes.dart';
import 'support/entry_fakes.dart';

class _SignedIn extends AuthNotifier {
  _SignedIn(super.repo, String id, UserRole role) {
    state = AuthState(
        user: User(id: id, appMetadata: const {}, userMetadata: const {}, aud: '', createdAt: ''), role: role);
  }
}

/// One phone: what it offers, what it has stored, and what the server says
/// to a stored sign-in.
class _Phone {
  _Phone({BiometricOffer? offer = FakeBiometricDevice.faceId, List<BiometricCheck>? checks})
      : device = FakeBiometricDevice(current: offer, checks: checks);

  final FakeBiometricDevice device;
  final fake = FakeVault();
  final restored = <String>[];
  final revoked = <String>[];
  Object? restoreError;
  BiometricAccountDraft draft = saraDraft;

  /// Signed in as [draft] (the app's screens), or nobody (the entry).
  bool signedIn = false;

  Widget app(Widget home, {double textScale = 1}) => ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) {
            final repo = FakeEntryRepository();
            return signedIn
                ? _SignedIn(repo, draft.userId, draft.role == 'supervisor' ? UserRole.supervisor : UserRole.student)
                : AuthNotifier(repo);
          }),
          biometricDeviceProvider.overrideWithValue(device),
          biometricVaultProvider.overrideWithValue(fake.vault),
          biometricSignInProvider.overrideWith((ref) => BiometricSignIn(
                device: device,
                vault: fake.vault,
                restore: (token) async {
                  restored.add(token);
                  if (restoreError != null) throw restoreError!;
                },
                revoke: (token) async => revoked.add(token),
              )),
          biometricAccountReaderProvider.overrideWithValue(() async => draft),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
          home: home,
        ),
      );
}

/// Something else the app asks at its start: it takes its turn after «دخول أسرع؟».
class _AsksAfter extends ConsumerStatefulWidget {
  const _AsksAfter({required this.onTurn});

  final VoidCallback onTurn;

  @override
  ConsumerState<_AsksAfter> createState() => _AsksAfterState();
}

class _AsksAfterState extends ConsumerState<_AsksAfter> {
  @override
  void initState() {
    super.initState();
    // As the shells do: three seconds after they come up.
    Future<void>.delayed(const Duration(seconds: 3), () async {
      if (mounted && await afterBiometricOffer(context, ref)) widget.onTurn();
    });
  }

  @override
  Widget build(BuildContext context) => const Text('الرئيسية');
}

void _size(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pump();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// A tap that signs in: the button keeps spinning until the app replaces the
/// entry (which a test never does), so nothing settles.
Future<void> _tapToSignIn(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pump();
  await tester.tap(find.byKey(Key(key)));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The entry of a phone nobody is signed in on.
Future<void> _entry(WidgetTester tester, _Phone phone) async {
  _size(tester);
  await tester.pumpWidget(phone.app(const LoginRegisterScreen()));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
        appName: 'باصك', packageName: 'com.basak.basak_mobile', version: '1.0.2', buildNumber: '14', buildSignature: '');
    authEntryOpensSignup = false;
    authEntryOpensSignIn = false;
  });

  group('the returning sign-in', () {
    testWidgets('an iPhone with Face ID: who it is, the glyph, the button and the password, always', (tester) async {
      final phone = _Phone();
      await storeSignIn(phone.fake);
      await _entry(tester, phone);

      expect(find.byType(ReturningSignInScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.text('أهلاً بعودتك، سارة'), findsOneWidget);
      expect(find.text('010 •••• 6789'), findsOneWidget);
      expect(find.text('انظر إلى الهاتف للدخول'), findsOneWidget);
      expect(find.text('الدخول بـ Face ID'), findsOneWidget);
      expect(find.text('الدخول بكلمة المرور'), findsOneWidget);
      expect(find.text('حساب آخر'), findsOneWidget);
      expect(find.byIcon(LucideIcons.scanFace), findsNWidgets(2));
      expect(find.byType(PhotoRing), findsOneWidget);
      // Nothing is asked of the phone until its owner says so.
      expect(phone.device.prompts, 0);
    });

    testWidgets('Android: the fingerprint, and the face only where the phone may use one', (tester) async {
      final either = _Phone(offer: FakeBiometricDevice.android);
      await storeSignIn(either.fake, offer: FakeBiometricDevice.android);
      await _entry(tester, either);
      expect(find.text('الدخول بالبصمة'), findsOneWidget);
      expect(find.text('ضع إصبعك على مستشعر البصمة'), findsOneWidget);
      expect(find.text('أو بالوجه، حسب ما فعّلته في إعدادات هاتفك.'), findsOneWidget);
      expect(find.byIcon(LucideIcons.fingerprint), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());

      final only = _Phone(offer: FakeBiometricDevice.fingerprint);
      await storeSignIn(only.fake, offer: FakeBiometricDevice.fingerprint);
      await _entry(tester, only);
      expect(find.text('الدخول بالبصمة'), findsOneWidget);
      expect(find.text('أو بالوجه، حسب ما فعّلته في إعدادات هاتفك.'), findsNothing);
    });

    testWidgets('recognised: the stored session is restored', (tester) async {
      final phone = _Phone();
      await storeSignIn(phone.fake);
      await _entry(tester, phone);
      await _tapToSignIn(tester, 'returning-submit');
      expect(phone.device.prompts, 1);
      expect(phone.restored, ['refresh-1']);
      expect(phone.fake.token, isNull);
    });

    testWidgets('not recognised: amber, two buttons, and trying again works', (tester) async {
      final phone = _Phone(checks: [BiometricCheck.notRecognised, BiometricCheck.passed]);
      await storeSignIn(phone.fake);
      await _entry(tester, phone);
      // The glyph asks as the button does.
      await _tap(tester, 'returning-glyph');

      const line = 'لم يتعرّف الهاتف عليك. حاول مرة أخرى، أو ادخل بكلمة المرور.';
      expect(find.text(line), findsOneWidget);
      final colors = tester.element(find.byType(ReturningSignInScreen)).colors;
      expect(tester.widget<Text>(find.byKey(const Key('returning-line'))).style?.color, colors.warning);
      expect(tester.widget<BiometricGlyph>(find.byType(BiometricGlyph)).warning, isTrue);
      expect(find.text('حاول مرة أخرى'), findsOneWidget);
      expect(find.byIcon(LucideIcons.refreshCw), findsOneWidget);
      expect(find.widgetWithText(BasakButton, 'الدخول بكلمة المرور'), findsOneWidget);
      expect(find.text('الدخول بـ Face ID'), findsNothing);
      expect(phone.restored, isEmpty);
      expect(phone.fake.token, 'refresh-1');

      await _tapToSignIn(tester, 'returning-submit');
      expect(phone.device.prompts, 2);
      expect(phone.restored, ['refresh-1']);
    });

    testWidgets('locked out by the phone: the ordinary sign-in says why, and the stored sign-in waits',
        (tester) async {
      final phone = _Phone(checks: [BiometricCheck.lockedOut, BiometricCheck.passed]);
      await storeSignIn(phone.fake);
      await _entry(tester, phone);
      await _tap(tester, 'returning-submit');

      expect(find.byKey(const ValueKey('login')), findsOneWidget);
      expect(find.text('أوقف هاتفك التحقق مؤقتاً بعد عدة محاولات. ادخل بكلمة المرور.'), findsOneWidget);
      expect(find.byKey(const Key('login-password')), findsOneWidget);
      expect(phone.fake.token, 'refresh-1');

      // The square button beside «دخول» goes back to the phone's check.
      expect(find.byKey(const Key('login-biometric')), findsOneWidget);
      await _tapToSignIn(tester, 'login-biometric');
      expect(phone.device.prompts, 2, reason: 'asked at once');
      expect(phone.restored, ['refresh-1']);
    });

    testWidgets('a stored sign-in the server refuses: dropped, and said in one line', (tester) async {
      final phone = _Phone()..restoreError = const AuthException('Invalid Refresh Token', statusCode: '400');
      await storeSignIn(phone.fake);
      await _entry(tester, phone);
      await _tap(tester, 'returning-submit');

      expect(find.byKey(const ValueKey('login')), findsOneWidget);
      expect(find.text('انتهت جلستك على هذا الهاتف. ادخل بكلمة المرور مرة واحدة لتفعيله من جديد.'), findsOneWidget);
      expect(find.byKey(const Key('login-biometric')), findsNothing);
      expect(phone.fake.enabled, isFalse);

      // Back is the welcome screen again: there is no returning sign-in left.
      await tester.tap(find.byType(BasakIconButton));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });

    testWidgets('the phone\'s biometrics changed: the ordinary sign-in opens, with its line', (tester) async {
      final phone = _Phone(offer: const BiometricOffer(kind: BiometricKind.faceId, enrolled: 'face', mark: 'state-2'));
      await storeSignIn(phone.fake);
      await _entry(tester, phone);

      expect(find.byType(ReturningSignInScreen), findsNothing);
      expect(find.byKey(const ValueKey('login')), findsOneWidget);
      expect(find.text('تغيّر Face ID في هاتفك، فأوقفنا الدخول به. ادخل بكلمة المرور مرة واحدة لتفعيله من جديد.'),
          findsOneWidget);
      expect(find.byKey(const Key('login-biometric')), findsNothing);
      expect(phone.fake.enabled, isFalse);
      expect(phone.revoked, ['refresh-1']);
    });

    testWidgets('no connection: said under the glyph, nothing lost', (tester) async {
      final phone = _Phone()..restoreError = Exception('SocketException: Failed host lookup');
      await storeSignIn(phone.fake);
      await _entry(tester, phone);
      await _tap(tester, 'returning-submit');
      expect(find.text(ReturningSignInScreen.offlineLine), findsOneWidget);
      expect(find.text('الدخول بـ Face ID'), findsOneWidget);
      expect(phone.fake.token, 'refresh-1');
    });

    testWidgets('«الدخول بكلمة المرور» is the ordinary sign-in, and back returns', (tester) async {
      final phone = _Phone();
      await storeSignIn(phone.fake);
      await _entry(tester, phone);
      await _tap(tester, 'returning-password');
      expect(find.byKey(const ValueKey('login')), findsOneWidget);
      expect(find.byKey(const Key('login-notice')), findsNothing);
      expect(find.bySemanticsLabel('الدخول بـ Face ID'), findsOneWidget);
      expect(phone.fake.token, 'refresh-1');

      await tester.tap(find.byType(BasakIconButton));
      await tester.pumpAndSettle();
      expect(find.byType(ReturningSignInScreen), findsOneWidget);
    });

    group('the square button beside «دخول»', () {
      /// The ordinary sign-in of a phone that has a sign-in stored.
      Future<void> form(WidgetTester tester, _Phone phone) async {
        await storeSignIn(phone.fake);
        await _entry(tester, phone);
        await _tap(tester, 'returning-password');
        expect(find.byKey(const ValueKey('login')), findsOneWidget);
      }

      testWidgets('is there with the phone\'s own glyph, after «دخول» in reading order, and large enough to hit',
          (tester) async {
        final phone = _Phone();
        await form(tester, phone);
        final button = find.byKey(const Key('login-biometric'));
        expect(find.descendant(of: button, matching: find.byIcon(LucideIcons.scanFace)), findsOneWidget);
        expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        // Arabic reads from the right: «دخول» first, the glyph at its left.
        expect(tester.getCenter(button).dx, lessThan(tester.getCenter(find.byKey(const Key('login-submit'))).dx));
        expect(
          tester.getSemantics(find.bySemanticsLabel('الدخول بـ Face ID')),
          matchesSemantics(label: 'الدخول بـ Face ID', isButton: true, isEnabled: true, hasEnabledState: true,
              hasTapAction: true),
        );
        expect(phone.device.prompts, 0, reason: 'the phone is asked on a tap, never by itself');
      });

      testWidgets('a tap asks the phone and signs in from the form, with nothing typed', (tester) async {
        final phone = _Phone();
        await form(tester, phone);
        await _tapToSignIn(tester, 'login-biometric');
        expect(phone.device.prompts, 1);
        expect(phone.restored, ['refresh-1']);
        expect(find.byType(ReturningSignInScreen), findsNothing, reason: 'no other screen on the way');
        expect(find.byKey(const ValueKey('login')), findsOneWidget);
      });

      testWidgets('closed or not recognised: said above the buttons, and the button tries again', (tester) async {
        final phone = _Phone(checks: [BiometricCheck.notRecognised, BiometricCheck.passed]);
        await form(tester, phone);
        await _tap(tester, 'login-biometric');
        expect(find.byKey(const Key('login-biometric-line')), findsOneWidget);
        expect(find.text('لم يتعرّف الهاتف عليك. حاول مرة أخرى، أو ادخل بكلمة المرور.'), findsOneWidget);
        expect(phone.restored, isEmpty);
        expect(phone.fake.token, 'refresh-1', reason: 'nothing was lost');

        await _tapToSignIn(tester, 'login-biometric');
        expect(find.byKey(const Key('login-biometric-line')), findsNothing);
        expect(phone.restored, ['refresh-1']);
      });

      testWidgets('a session the server ended: one clear line, the fields, and no button any more',
          (tester) async {
        final phone = _Phone()..restoreError = const AuthException('Invalid Refresh Token', statusCode: '400');
        await form(tester, phone);
        await _tap(tester, 'login-biometric');
        expect(find.text('انتهت جلستك على هذا الهاتف. ادخل بكلمة المرور مرة واحدة لتفعيله من جديد.'),
            findsOneWidget);
        expect(find.byKey(const Key('login-biometric')), findsNothing);
        expect(find.byKey(const Key('login-password')), findsOneWidget);
        expect(phone.fake.enabled, isFalse);
      });

      testWidgets('a face or finger added since: dropped, said, and the button is gone', (tester) async {
        final phone = _Phone();
        await form(tester, phone);
        phone.device.current = const BiometricOffer(kind: BiometricKind.faceId, enrolled: 'face', mark: 'state-2');
        await _tap(tester, 'login-biometric');
        expect(find.text('تغيّر Face ID في هاتفك، فأوقفنا الدخول به. ادخل بكلمة المرور مرة واحدة لتفعيله من جديد.'),
            findsOneWidget);
        expect(find.byKey(const Key('login-biometric')), findsNothing);
        expect(phone.device.prompts, 0);
        expect(phone.revoked, ['refresh-1']);
      });

      testWidgets('biometrics removed from the phone: the same, with nothing to prompt', (tester) async {
        final phone = _Phone();
        await form(tester, phone);
        phone.device.current = null;
        await _tap(tester, 'login-biometric');
        expect(find.byKey(const Key('login-notice')), findsOneWidget);
        expect(find.byKey(const Key('login-biometric')), findsNothing);
        expect(phone.fake.enabled, isFalse);
      });

      testWidgets('locked out by the phone: said, and the button stays for when the phone lets go',
          (tester) async {
        final phone = _Phone(checks: [BiometricCheck.lockedOut]);
        await form(tester, phone);
        await _tap(tester, 'login-biometric');
        expect(find.text('أوقف هاتفك التحقق مؤقتاً بعد عدة محاولات. ادخل بكلمة المرور.'), findsOneWidget);
        expect(find.byKey(const Key('login-biometric')), findsOneWidget);
        expect(phone.fake.token, 'refresh-1');
      });

      testWidgets('no connection: said on the form, nothing lost', (tester) async {
        final phone = _Phone()..restoreError = Exception('SocketException: Failed host lookup');
        await form(tester, phone);
        await _tap(tester, 'login-biometric');
        expect(find.text('تعذر الاتصال بالإنترنت. تحقق من الاتصال وحاول مرة أخرى.'), findsOneWidget);
        expect(find.byKey(const Key('login-biometric')), findsOneWidget);
        expect(phone.fake.token, 'refresh-1');
      });
    });

    testWidgets('«حساب آخر» opens the form and forgets nothing: the button is there, now and after a restart',
        (tester) async {
      final phone = _Phone();
      await storeSignIn(phone.fake);
      await _entry(tester, phone);
      await _tap(tester, 'returning-other-account');

      expect(find.byKey(const ValueKey('login')), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(phone.fake.enabled, isTrue);
      expect(phone.fake.token, 'refresh-1');
      expect(phone.revoked, isEmpty, reason: 'its session is not ended either');
      expect(find.byKey(const Key('login-biometric')), findsOneWidget);

      // The app is closed and opened again: the faster sign-in is still offered.
      await tester.pumpWidget(const SizedBox());
      await _entry(tester, phone);
      expect(find.byType(ReturningSignInScreen), findsOneWidget);
      expect(find.text('أهلاً بعودتك، سارة'), findsOneWidget);

      // And from the form, straight in.
      await _tap(tester, 'returning-other-account');
      await _tapToSignIn(tester, 'login-biometric');
      expect(phone.device.prompts, 1);
      expect(phone.restored, ['refresh-1']);
    });

    testWidgets('the sign-up shows the button too, on its first step, and signs in from there', (tester) async {
      final phone = _Phone();
      await storeSignIn(phone.fake);
      await _entry(tester, phone);
      await _tap(tester, 'returning-other-account');
      await _tap(tester, 'login-signup');
      expect(find.byKey(const ValueKey('signup')), findsOneWidget);
      final button = find.byKey(const Key('signup-biometric'));
      expect(button, findsOneWidget);
      expect(find.descendant(of: button, matching: find.byIcon(LucideIcons.scanFace)), findsOneWidget);
      expect(tester.getCenter(button).dx, lessThan(tester.getCenter(find.byKey(const Key('signup-next'))).dx));

      await _tapToSignIn(tester, 'signup-biometric');
      expect(phone.device.prompts, 1);
      expect(phone.restored, ['refresh-1']);
    });

    testWidgets('a phone with nothing stored has no such button on the sign-up', (tester) async {
      final phone = _Phone();
      await _entry(tester, phone);
      await _tap(tester, 'welcome-signup');
      expect(find.byKey(const ValueKey('signup')), findsOneWidget);
      expect(find.byKey(const Key('signup-biometric')), findsNothing);
    });

    group('two accounts stored on one phone', () {
      Future<_Phone> two(WidgetTester tester) async {
        final phone = _Phone();
        await storeSignIn(phone.fake); // سارة, 010 •••• 6789
        await storeSignIn(phone.fake, draft: omarDraft, token: 'refresh-omar'); // عمر, the more recent
        await _entry(tester, phone);
        return phone;
      }

      testWidgets('the returning sign-in is the most recent one\'s; the other is one tap further', (tester) async {
        final phone = await two(tester);
        expect(find.text('أهلاً بعودتك، عمر'), findsOneWidget);
        await _tapToSignIn(tester, 'returning-submit');
        expect(phone.restored, ['refresh-omar']);
        expect(phone.fake.tokenOf('student-1'), 'refresh-1', reason: 'the other account keeps its own');
      });

      testWidgets('nothing typed: the form asks whose, with names and hidden numbers, then the phone', (tester) async {
        final phone = await two(tester);
        await _tap(tester, 'returning-other-account');
        await _tap(tester, 'login-biometric');
        expect(find.text('اختر الحساب'), findsOneWidget);
        expect(find.text('عمر'), findsOneWidget);
        expect(find.text('سارة'), findsOneWidget);
        expect(find.text('010 •••• 6789'), findsOneWidget);
        expect(find.text('011 •••• 7777'), findsOneWidget);
        expect(phone.device.prompts, 0, reason: 'the phone is asked after the choice');

        await tester.tap(find.byKey(const Key('biometric-account-student-1')));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(phone.device.prompts, 1);
        expect(phone.restored, ['refresh-1']);
        expect(phone.fake.tokenOf('student-2'), 'refresh-omar');
      });

      testWidgets('closing the choice signs nobody in', (tester) async {
        final phone = await two(tester);
        await _tap(tester, 'returning-other-account');
        await _tap(tester, 'login-biometric');
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
        expect(find.text('اختر الحساب'), findsNothing);
        expect(phone.device.prompts, 0);
        expect(phone.restored, isEmpty);
      });

      testWidgets('a number typed in the form says whose: no question, that account', (tester) async {
        final phone = await two(tester);
        await _tap(tester, 'returning-other-account');
        await tester.enterText(
            find.descendant(of: find.byKey(const Key('login-identifier')), matching: find.byType(EditableText)),
            '01012346789');
        await tester.pump();
        await _tapToSignIn(tester, 'login-biometric');
        expect(find.text('اختر الحساب'), findsNothing);
        expect(phone.restored, ['refresh-1']);
      });

      testWidgets('one account\'s session was ended: only its entry goes, and the button stays for the other',
          (tester) async {
        final phone = await two(tester)
          ..restoreError = const AuthException('Invalid Refresh Token', statusCode: '400');
        await _tap(tester, 'returning-other-account');
        await _tap(tester, 'login-biometric');
        await tester.tap(find.byKey(const Key('biometric-account-student-1')));
        await tester.pumpAndSettle();

        expect(find.text('انتهت جلستك على هذا الهاتف. ادخل بكلمة المرور مرة واحدة لتفعيله من جديد.'),
            findsOneWidget);
        expect(phone.fake.enabledFor('student-1'), isFalse);
        expect(phone.fake.enabledFor('student-2'), isTrue);
        expect(phone.fake.tokenOf('student-2'), 'refresh-omar');
        expect(find.byKey(const Key('login-biometric')), findsOneWidget);

        // One account left: no question any more.
        phone.restoreError = null;
        await _tapToSignIn(tester, 'login-biometric');
        expect(find.text('اختر الحساب'), findsNothing);
        expect(phone.restored.last, 'refresh-omar');
      });
    });

    testWidgets('a supervisor gets the same screen, their own sign-in behind it, and who to turn to',
        (tester) async {
      final phone = _Phone(offer: FakeBiometricDevice.fingerprint, checks: [BiometricCheck.notRecognised]);
      await storeSignIn(phone.fake, draft: supervisorDraft, offer: FakeBiometricDevice.fingerprint);
      await _entry(tester, phone);
      expect(find.text('أهلاً بعودتك، محمود'), findsOneWidget);
      expect(find.text('011 •••• 0321'), findsOneWidget);

      await _tap(tester, 'returning-submit');
      expect(find.text('لم يتعرّف الهاتف عليك. حاول مرة أخرى، أو ادخل بكلمة المرور، أو تواصل مع شركتك.'),
          findsOneWidget);

      await _tap(tester, 'returning-password');
      expect(find.byKey(const ValueKey('supervisor-login')), findsOneWidget);
      expect(find.text('دخول المشرف'), findsOneWidget);
      expect(find.byKey(const Key('login-biometric')), findsOneWidget);
      // The student's sign-in on the same phone has the button too: it is
      // the phone's stored sign-in, whoever it belongs to.
      await _tap(tester, 'login-students');
      expect(find.byKey(const Key('login-biometric')), findsOneWidget);
    });

    testWidgets('nothing clips on a small phone at the largest text, in either state', (tester) async {
      _size(tester, const Size(360, 640));
      final phone = _Phone(offer: FakeBiometricDevice.android, checks: [BiometricCheck.notRecognised]);
      await storeSignIn(phone.fake, draft: supervisorDraft, offer: FakeBiometricDevice.android);
      await tester.pumpWidget(phone.app(const LoginRegisterScreen(), textScale: 1.3));
      await tester.pumpAndSettle();
      expect(find.byType(ReturningSignInScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tap(tester, 'returning-submit');
      expect(find.text('حاول مرة أخرى'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('a phone with nothing stored, or nothing enrolled', () {
    testWidgets('opens on the welcome screen and shows no biometric button', (tester) async {
      for (final offer in [FakeBiometricDevice.faceId, null]) {
        final phone = _Phone(offer: offer);
        await _entry(tester, phone);
        expect(find.byType(WelcomeScreen), findsOneWidget);
        await _tap(tester, 'welcome-signin');
        expect(find.byKey(const Key('login-submit')), findsOneWidget);
        expect(find.byKey(const Key('login-biometric')), findsNothing);
        expect(find.byKey(const Key('login-notice')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a stored sign-in on a phone that lost its biometrics is dropped, not shown', (tester) async {
      final phone = _Phone(offer: null);
      await storeSignIn(phone.fake);
      await _entry(tester, phone);
      expect(find.byType(ReturningSignInScreen), findsNothing);
      expect(find.byKey(const Key('login-notice')), findsOneWidget);
      expect(phone.fake.enabled, isFalse);
    });
  });

  group('the offer after the first sign-in with a password', () {
    Future<_Phone> open(WidgetTester tester, {BiometricOffer? offer = FakeBiometricDevice.faceId,
        List<BiometricCheck>? checks, bool pending = true}) async {
      _size(tester);
      final phone = _Phone(offer: offer, checks: checks)..signedIn = true;
      await tester.pumpWidget(phone.app(const BiometricOfferHost(child: Scaffold(body: Center(child: Text('الرئيسية'))))));
      if (pending) {
        final container = ProviderScope.containerOf(tester.element(find.byType(BiometricOfferHost)));
        container.read(biometricOfferPendingProvider.notifier).state = true;
      }
      await tester.pump();
      await tester.pump(BiometricOfferHost.delay);
      await tester.pumpAndSettle();
      return phone;
    }

    testWidgets('«تفعيل» asks the phone once and switches it on', (tester) async {
      final phone = await open(tester);
      expect(find.text('دخول أسرع بـ Face ID؟'), findsOneWidget);
      expect(
          find.text('في المرة القادمة تدخل بنظرة، بدون كلمة المرور. بيانات وجهك تبقى على هاتفك ولا تصل إلينا.'),
          findsOneWidget);
      expect(find.text('تفعيل Face ID'), findsOneWidget);
      expect(find.text('ليس الآن'), findsOneWidget);
      expect(phone.device.prompts, 0);

      await _tap(tester, 'biometric-offer-enable');
      expect(phone.device.prompts, 1);
      expect(phone.device.renewals, 1);
      expect((await phone.fake.vault.account('student-1'))?.userId, 'student-1');
      expect(find.text('تم تفعيل الدخول بـ Face ID.'), findsOneWidget);
      expect(find.text('دخول أسرع بـ Face ID؟'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('«ليس الآن» leaves it off and is not asked again', (tester) async {
      final phone = await open(tester, offer: FakeBiometricDevice.android);
      expect(find.text('دخول أسرع بالبصمة أو الوجه؟'), findsOneWidget);
      expect(find.text('تفعيل البصمة أو الوجه'), findsOneWidget);
      await _tap(tester, 'biometric-offer-later');
      expect(phone.fake.enabled, isFalse);
      expect(phone.device.prompts, 0);

      final container = ProviderScope.containerOf(tester.element(find.byType(BiometricOfferHost)));
      container.read(biometricOfferPendingProvider.notifier).state = true;
      await tester.pump();
      await tester.pump(BiometricOfferHost.delay);
      await tester.pumpAndSettle();
      expect(find.text('دخول أسرع بالبصمة أو الوجه؟'), findsNothing);
    });

    testWidgets('the phone did not confirm: said, and left off', (tester) async {
      final phone = await open(tester, checks: [BiometricCheck.notRecognised]);
      await _tap(tester, 'biometric-offer-enable');
      expect(phone.fake.enabled, isFalse);
      expect(find.text('لم يتم تفعيل الدخول بـ Face ID. حاول مرة أخرى.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('it is asked at once, as soon as the app is up, and before anything else the app asks',
        (tester) async {
      _size(tester);
      final phone = _Phone()..signedIn = true;
      var pushAsked = false;
      await tester.pumpWidget(phone.app(BiometricOfferHost(
        child: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => _AsksAfter(onTurn: () => pushAsked = true),
          ),
        ),
      )));
      final container = ProviderScope.containerOf(tester.element(find.byType(BiometricOfferHost)));
      // A sign-in with a password just happened.
      container.read(biometricOfferPendingProvider.notifier).state = true;
      await tester.pump();
      expect(BiometricOfferHost.delay, lessThan(const Duration(seconds: 1)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('دخول أسرع بـ Face ID؟'), findsOneWidget, reason: 'well inside the first second');

      // The notifications explainer's turn would have come three seconds in.
      await tester.pump(const Duration(seconds: 5));
      expect(pushAsked, isFalse, reason: 'it waits behind this question');
      expect(find.text('دخول أسرع بـ Face ID؟'), findsOneWidget);

      await tester.tap(find.byKey(const Key('biometric-offer-later')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(pushAsked, isTrue, reason: 'and comes once this one is answered');
      expect(phone.fake.enabled, isFalse);
    });

    testWidgets('with nothing to ask (no biometrics on the phone) nothing else is kept waiting', (tester) async {
      _size(tester);
      final phone = _Phone(offer: null)..signedIn = true;
      var pushAsked = false;
      await tester.pumpWidget(phone.app(BiometricOfferHost(
        child: Scaffold(body: _AsksAfter(onTurn: () => pushAsked = true)),
      )));
      ProviderScope.containerOf(tester.element(find.byType(BiometricOfferHost)))
          .read(biometricOfferPendingProvider.notifier)
          .state = true;
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BasakSheetFrame), findsNothing);
      expect(pushAsked, isTrue);
    });

    testWidgets('asked once per account on a shared phone, whoever was asked last', (tester) async {
      final phone = await open(tester);
      await _tap(tester, 'biometric-offer-later');
      // Someone else signs in on this phone and is asked too.
      await phone.fake.vault.markOffered('student-2');

      final container = ProviderScope.containerOf(tester.element(find.byType(BiometricOfferHost)));
      container.read(biometricOfferPendingProvider.notifier).state = true;
      await tester.pump();
      await tester.pump(BiometricOfferHost.delay);
      await tester.pumpAndSettle();
      expect(find.byType(BasakSheetFrame), findsNothing, reason: 'the first account already answered');
    });

    testWidgets('not offered to an account that already switched it on', (tester) async {
      _size(tester);
      final phone = _Phone()..signedIn = true;
      await storeSignIn(phone.fake);
      await tester.pumpWidget(phone.app(const BiometricOfferHost(child: Scaffold(body: Text('الرئيسية')))));
      ProviderScope.containerOf(tester.element(find.byType(BiometricOfferHost)))
          .read(biometricOfferPendingProvider.notifier)
          .state = true;
      await tester.pump();
      await tester.pump(BiometricOfferHost.delay);
      await tester.pumpAndSettle();
      expect(find.byType(BasakSheetFrame), findsNothing);
    });

    testWidgets('waits for the app: a host that comes up after another screen still asks', (tester) async {
      // A forced password change stands in for the app; the offer is asked
      // once the app itself is up.
      _size(tester);
      final phone = _Phone()..signedIn = true;
      final gate = ValueNotifier(true);
      addTearDown(gate.dispose);
      await tester.pumpWidget(phone.app(ValueListenableBuilder<bool>(
        valueListenable: gate,
        builder: (context, blocked, _) => blocked
            ? const Scaffold(body: Text('كلمة مرور جديدة'))
            : const BiometricOfferHost(child: Scaffold(body: Text('الرئيسية'))),
      )));
      ProviderScope.containerOf(tester.element(find.text('كلمة مرور جديدة')))
          .read(biometricOfferPendingProvider.notifier)
          .state = true;
      await tester.pump(const Duration(seconds: 10));
      expect(find.byType(BasakSheetFrame), findsNothing, reason: 'never over the password change');

      gate.value = false;
      await tester.pump();
      await tester.pump(BiometricOfferHost.delay);
      await tester.pumpAndSettle();
      expect(find.text('دخول أسرع بـ Face ID؟'), findsOneWidget);
    });

    testWidgets('never on a phone with nothing enrolled, and never without a password sign-in', (tester) async {
      await open(tester, offer: null);
      expect(find.byType(BasakSheetFrame), findsNothing);
      await tester.pumpWidget(const SizedBox());

      await open(tester, pending: false);
      expect(find.byType(BasakSheetFrame), findsNothing);
    });
  });

  group('the switch in the account', () {
    Widget rows() => Scaffold(
          body: Consumer(builder: (context, ref, _) {
            final row = biometricSettingRow(context, ref);
            return Column(children: [
              SettingRows(rows: [const SettingRow(label: 'المساعدة والدعم'), if (row != null) row]),
              const BiometricSettingRow(),
            ]);
          }),
        );

    testWidgets('named after the phone; on asks the phone, off forgets at once', (tester) async {
      _size(tester);
      final phone = _Phone(offer: FakeBiometricDevice.touchId)..signedIn = true;
      await tester.pumpWidget(phone.app(rows()));
      await tester.pumpAndSettle();

      // Once in the card, once as the row that stands on its own.
      expect(find.text('الدخول بـ Touch ID'), findsNWidgets(2));
      final inCard = find.byKey(const Key('biometric-switch'));
      expect(tester.widget<BasakSwitch>(inCard).value, isFalse);

      await tester.tap(inCard);
      await tester.pumpAndSettle();
      expect(phone.device.prompts, 1);
      expect(phone.fake.enabled, isTrue);
      expect(tester.widgetList<BasakSwitch>(find.byType(BasakSwitch)).every((s) => s.value), isTrue);
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(inCard);
      await tester.pumpAndSettle();
      expect(phone.fake.enabled, isFalse);
      expect(phone.device.prompts, 1, reason: 'switching off asks nothing');
      expect(tester.widget<BasakSwitch>(inCard).value, isFalse);
    });

    testWidgets('on for this account already (a password sign-in after a sign-out): shown as on, and not asked',
        (tester) async {
      _size(tester);
      final phone = _Phone()..signedIn = true;
      // Switched on earlier, signed out, and now signed in again with the password.
      await storeSignIn(phone.fake);
      await phone.fake.vault.supersede('student-1');
      await tester.pumpWidget(phone.app(BiometricOfferHost(child: rows())));
      ProviderScope.containerOf(tester.element(find.byType(BiometricOfferHost)))
          .read(biometricOfferPendingProvider.notifier)
          .state = true;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(tester.widgetList<BasakSwitch>(find.byType(BasakSwitch)).every((s) => s.value), isTrue);
      expect(find.byType(BasakSheetFrame), findsNothing, reason: 'nothing to ask: it is on');
      expect(phone.device.prompts, 0);
    });

    testWidgets('someone else has it on, on this phone: this account\'s switch is its own', (tester) async {
      _size(tester);
      final phone = _Phone()..signedIn = true; // سارة is signed in
      await storeSignIn(phone.fake, draft: omarDraft, token: 'refresh-omar');
      await tester.pumpWidget(phone.app(rows()));
      await tester.pumpAndSettle();
      final inCard = find.byKey(const Key('biometric-switch'));
      expect(tester.widget<BasakSwitch>(inCard).value, isFalse);

      // On for her, beside him…
      await tester.tap(inCard);
      await tester.pumpAndSettle();
      expect(tester.widget<BasakSwitch>(inCard).value, isTrue);
      expect(phone.fake.index, ['student-1', 'student-2']);
      await tester.pump(const Duration(seconds: 4));

      // …and off for her alone.
      await tester.tap(inCard);
      await tester.pumpAndSettle();
      expect(tester.widget<BasakSwitch>(inCard).value, isFalse);
      expect(phone.fake.enabledFor('student-1'), isFalse);
      expect(phone.fake.enabledFor('student-2'), isTrue);
      expect(phone.fake.tokenOf('student-2'), 'refresh-omar');
      expect(phone.revoked, isEmpty, reason: 'nobody\'s session is ended by a switch');
    });

    testWidgets('the phone did not confirm: it stays off', (tester) async {
      _size(tester);
      final phone = _Phone(checks: [BiometricCheck.lockedOut])..signedIn = true;
      await tester.pumpWidget(phone.app(rows()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('biometric-switch')));
      await tester.pumpAndSettle();
      expect(phone.fake.enabled, isFalse);
      expect(find.text('أوقف هاتفك التحقق مؤقتاً بعد عدة محاولات. حاول لاحقاً.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('no row at all on a phone with nothing enrolled', (tester) async {
      _size(tester);
      final phone = _Phone(offer: null)..signedIn = true;
      await tester.pumpWidget(phone.app(rows()));
      await tester.pumpAndSettle();
      expect(find.byType(BasakSwitch), findsNothing);
      expect(find.byKey(const Key('profile-biometric')), findsNothing);
      expect(find.text('المساعدة والدعم'), findsOneWidget);
      expect(tester.getSize(find.byType(BiometricSettingRow)), Size.zero);
    });
  });
}
