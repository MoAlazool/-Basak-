// Draws the entry screens (splash, onboarding, welcome, sign-in, sign-up,
// recovery, the photo screens) to PNG files with the app's real fonts, at the
// boards' 390 × 844 and at 360 × 640: a look at the layout without a device,
// to hold against the canvas boards. Skipped unless RENDER_DIR is set:
//   RENDER_DIR=/tmp/basak-entry flutter test test/ui/entry_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:basak_mobile/core/widgets/photo_adjust_screen.dart';
import 'package:basak_mobile/features/auth/presentation/force_password_change_screen.dart';
import 'package:basak_mobile/features/auth/presentation/forgot_password_screen.dart';
import 'package:basak_mobile/features/auth/presentation/login_register_screen.dart';
import 'package:basak_mobile/features/auth/presentation/signup_screen.dart';
import 'package:basak_mobile/features/auth/presentation/wrong_role_screen.dart';
import 'package:basak_mobile/features/onboarding/onboarding_controller.dart';
import 'package:basak_mobile/features/onboarding/onboarding_screen.dart';
import 'package:basak_mobile/features/splash/splash_gate.dart';

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

/// A stand-in portrait, 600 × 800: a face-like shape on a tint.
final Uint8List _portrait = () {
  final image = img.Image(width: 600, height: 800);
  img.fill(image, color: img.ColorRgb8(0xD6, 0xEB, 0xF5));
  img.fillCircle(image, x: 300, y: 300, radius: 110, color: img.ColorRgb8(0x8D, 0xBF, 0xD6));
  img.fillCircle(image, x: 300, y: 720, radius: 240, color: img.ColorRgb8(0x8D, 0xBF, 0xD6));
  return Uint8List.fromList(img.encodePng(image));
}();

String _tag(Size size) => '${size.width.toInt()}';

Future<void> _show(WidgetTester tester, Size size, Widget home, {List<Override> overrides = const []}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  debugDisableShadows = false;
  await tester.pumpWidget(RepaintBoundary(
    key: _key,
    child: entryApp(home, FakeEntryRepository(), overrides: overrides),
  ));
  await _settle(tester);
}

/// Lets real decoding finish (the logo, a photo), then draws.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() async {
    final context = tester.element(find.byType(MaterialApp));
    await precacheImage(const AssetImage('assets/images/basak_icon.webp'), context);
    await Future<void>.delayed(const Duration(milliseconds: 60));
  });
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: name);
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

Finder _input(String key) => find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
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
    final tag = _tag(size);

    testWidgets('splash $tag', skip: skip, (tester) async {
      await _show(tester, size, const SplashView(progress: .5));
      await _shot(tester, 'splash_$tag');
    });

    testWidgets('onboarding $tag', skip: skip, (tester) async {
      await _show(tester, size, const OnboardingScreen(),
          overrides: [onboardingProvider.overrideWith((ref) => OnboardingController.completed())]);
      for (var page = 1; page <= 4; page++) {
        await _shot(tester, 'onboarding${page}_$tag');
        if (page < 4) await _tap(tester, 'next');
      }
    });

    testWidgets('welcome, sign-in, supervisor sign-in $tag', skip: skip, (tester) async {
      await _show(tester, size, const LoginRegisterScreen());
      await _shot(tester, 'welcome_$tag');

      await _tap(tester, 'welcome-signin');
      await tester.enterText(_input('login-identifier'), '010 2345 6789');
      await tester.enterText(_input('login-password'), '12345678');
      await _shot(tester, 'signin_$tag');

      await _tap(tester, 'login-submit');
      await _shot(tester, 'signin_wrong_$tag');

      await _tap(tester, 'login-supervisors');
      await _shot(tester, 'supsignin_$tag');
    });

    testWidgets('sign-up, its sheets and its errors $tag', skip: skip, (tester) async {
      final repo = FakeEntryRepository();
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      debugDisableShadows = false;
      await tester.pumpWidget(RepaintBoundary(
        key: _key,
        child: entryApp(SignupScreen(onBack: () {}, pickPhoto: (context, source) async => _portrait), repo),
      ));
      await _settle(tester);

      await tester.enterText(_input('signup-name'), 'سارة أحمد محمود');
      await _shot(tester, 'signup1_$tag');
      await _tap(tester, 'signup-next');
      await _shot(tester, 'signup1_error_$tag');
      await tester.enterText(_input('signup-phone'), '01012345678');
      await _tap(tester, 'signup-next');

      await _shot(tester, 'signup2_empty_$tag');
      await _tap(tester, 'signup-university');
      await tester.tap(find.text('جامعة المنصورة الجديدة'));
      await _shot(tester, 'university_sheet_$tag');
      await _tap(tester, 'university-confirm');
      await _tap(tester, 'signup-college');
      await tester.tap(find.text('الهندسة'));
      await _shot(tester, 'college_sheet_$tag');
      await _tap(tester, 'college-other');
      await tester.enterText(_input('college-other-field'), 'العلوم الصحية التطبيقية');
      await _shot(tester, 'college_sheet_other_$tag');
      await tester.enterText(_input('college-other-field'), '');
      await tester.pump();
      await tester.ensureVisible(find.text('الهندسة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الهندسة'));
      await tester.pump();
      await _tap(tester, 'college-confirm');
      await _shot(tester, 'signup2_$tag');
      await _tap(tester, 'signup-next');

      await _shot(tester, 'signup3_$tag');
      await _tap(tester, 'signup-photo');
      await _shot(tester, 'photo_source_$tag');
      await tester.tap(find.byKey(const Key('photo-source-gallery')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await precacheImage(MemoryImage(_portrait), tester.element(find.byType(MaterialApp)));
      });
      await _shot(tester, 'signup3_photo_$tag');
      await _tap(tester, 'signup-next');

      await _shot(tester, 'signup4_empty_$tag');
      await tester.enterText(_input('signup-password'), 'Abcd1234!x');
      await tester.enterText(_input('signup-confirmation'), 'Abcd1234!x');
      await tester.tap(find.byKey(const Key('signup-terms')));
      await _shot(tester, 'signup4_$tag');
    });

    testWidgets('photo adjust $tag', skip: skip, (tester) async {
      await _show(tester, size, PhotoAdjustScreen(source: _portrait));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_dir/photo_adjust_$tag.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
      debugDisableShadows = true;
    });

    testWidgets('password recovery $tag', skip: skip, (tester) async {
      await _show(tester, size, const ForgotPasswordScreen(initialPhone: '010 2345 6789'));
      await _shot(tester, 'forgot_request_$tag');
      await _tap(tester, 'forgot-have-code');
      await tester.enterText(_input('forgot-code'), '482716');
      await _shot(tester, 'forgot_code_$tag');
      await _tap(tester, 'forgot-verify');
      await tester.enterText(_input('forgot-password'), 'abcdefg1');
      await _shot(tester, 'forgot_reset_$tag');
    });

    testWidgets('forced password change, wrong role $tag', skip: skip, (tester) async {
      await _show(tester, size, const ForcePasswordChangeScreen());
      await _shot(tester, 'force_password_$tag');
      await _tap(tester, 'force-password-save');
      await _shot(tester, 'force_password_error_$tag');

      await _show(tester, size, const WrongRoleScreen());
      await _shot(tester, 'wrong_role_$tag');
    });
  }
}
