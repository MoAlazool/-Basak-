// Draws the biometric sign-in (boards SignInFace, SignInTouch, SignInPrompt,
// SignInBioFailed, BioEnable, the square button of SignIn and the account's
// switch row) to PNG files with the app's real fonts, at 390 × 844 and at
// 360 × 640. Skipped unless RENDER_DIR is set:
//   RENDER_DIR=/tmp/basak-bio flutter test test/ui/biometric_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/features/auth/biometrics/biometric_device.dart';
import 'package:basak_mobile/features/auth/biometrics/biometric_sign_in.dart';
import 'package:basak_mobile/features/auth/biometrics/presentation/biometric_offer.dart';
import 'package:basak_mobile/features/auth/biometrics/presentation/biometric_setting_row.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/presentation/login_register_screen.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/onboarding/onboarding_controller.dart';

import '../support/biometric_fakes.dart';
import '../support/entry_fakes.dart';

final _dir = Platform.environment['RENDER_DIR'];
final _key = GlobalKey();

const _sizes = [Size(390, 844), Size(360, 640)];

Future<void> _fonts() async {
  Future<ByteData> file(String name) async =>
      ByteData.view((await File('assets/fonts/$name').readAsBytes()).buffer);
  final readex = FontLoader('ReadexPro');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    readex.addFont(file('ReadexPro-$f.ttf'));
  }
  await readex.load();
  await (FontLoader('Lucide')..addFont(file('lucide.ttf'))).load();
}

class _SignedIn extends AuthNotifier {
  _SignedIn(super.repo) {
    state = const AuthState(
        user: User(id: 'student-1', appMetadata: {}, userMetadata: {}, aud: '', createdAt: ''),
        role: UserRole.student);
  }
}

Future<void> _show(
  WidgetTester tester,
  Size size,
  Widget home, {
  required FakeBiometricDevice device,
  required FakeVault fake,
  bool signedIn = false,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  debugDisableShadows = false;
  await tester.pumpWidget(RepaintBoundary(
    key: _key,
    child: ProviderScope(
      overrides: [
        authStateProvider.overrideWith(
            (ref) => signedIn ? _SignedIn(FakeEntryRepository()) : AuthNotifier(FakeEntryRepository())),
        biometricDeviceProvider.overrideWithValue(device),
        biometricVaultProvider.overrideWithValue(fake.vault),
        biometricSignInProvider.overrideWith(
            (ref) => BiometricSignIn(device: device, vault: fake.vault, restore: (_) async {})),
        biometricAccountReaderProvider.overrideWithValue(() async => saraDraft),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: home,
      ),
    ),
  ));
  await tester.pump();
  await tester.runAsync(() async {
    final context = tester.element(find.byType(MaterialApp));
    await precacheImage(const AssetImage('assets/images/basak_icon.webp'), context);
    await Future<void>.delayed(const Duration(milliseconds: 60));
  });
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name, {bool settle = true}) async {
  if (settle) await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: name);
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pump();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await _fonts();
    PackageInfo.setMockInitialValues(
        appName: 'باصك', packageName: 'com.basak.basak_mobile', version: '1.0.2', buildNumber: '14', buildSignature: '');
  });
  setUp(() {
    authEntryOpensSignup = false;
    authEntryOpensSignIn = false;
  });

  final skip = _dir == null;

  for (final size in _sizes) {
    final tag = '${size.width.toInt()}';

    testWidgets('returning sign-in, Face ID, then not recognised $tag', skip: skip, (tester) async {
      final device = FakeBiometricDevice(checks: [BiometricCheck.notRecognised]);
      final fake = FakeVault();
      await storeSignIn(fake);
      await _show(tester, size, const LoginRegisterScreen(), device: device, fake: fake);
      await _shot(tester, 'signin_face_$tag');
      await _tap(tester, 'returning-submit');
      await _shot(tester, 'signin_bio_failed_$tag');
      await _tap(tester, 'returning-password');
      await _shot(tester, 'signin_square_$tag');
    });

    testWidgets('returning sign-in, Android $tag', skip: skip, (tester) async {
      final device = FakeBiometricDevice(current: FakeBiometricDevice.android, checks: [BiometricCheck.lockedOut]);
      final fake = FakeVault();
      await storeSignIn(fake, offer: FakeBiometricDevice.android);
      await _show(tester, size, const LoginRegisterScreen(), device: device, fake: fake);
      await _shot(tester, 'signin_touch_$tag');
      await _tap(tester, 'returning-submit');
      await _shot(tester, 'signin_locked_out_$tag');
    });

    testWidgets('the offer sheet and the account row $tag', skip: skip, (tester) async {
      final device = FakeBiometricDevice();
      final fake = FakeVault();
      await _show(
        tester,
        size,
        BiometricOfferHost(
          child: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsetsDirectional.all(BasakSpace.gutter),
                child: Consumer(builder: (context, ref, _) {
                  final row = biometricSettingRow(context, ref);
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    GroupSection(
                      title: 'التطبيق',
                      child: SettingRows(rows: [
                        SettingRow(label: 'المساعدة والدعم', onTap: () {}),
                        if (row != null) row,
                        SettingRow(label: 'إشعارات الهاتف', value: 'مفعّلة', external: true, onTap: () {}),
                      ]),
                    ),
                    const SizedBox(height: BasakSpace.s16),
                    const BasakCard(
                      padding: EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s18),
                      child: BiometricSettingRow(),
                    ),
                  ]);
                }),
              ),
            ),
          ),
        ),
        device: device,
        fake: fake,
        signedIn: true,
      );
      await _shot(tester, 'account_row_off_$tag');
      final container = ProviderScope.containerOf(tester.element(find.byType(BiometricOfferHost)));
      container.read(biometricOfferPendingProvider.notifier).state = true;
      await tester.pump();
      await tester.pump(BiometricOfferHost.delay);
      await _shot(tester, 'bio_enable_$tag');
      await _tap(tester, 'biometric-offer-enable');
      await _shot(tester, 'account_row_on_$tag', settle: false);
      await tester.pump(const Duration(seconds: 4));
    });
  }
}
