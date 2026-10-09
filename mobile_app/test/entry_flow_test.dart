import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/core/widgets/photo_adjust_screen.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/data/colleges.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/presentation/college_picker_sheet.dart';
import 'package:basak_mobile/features/auth/presentation/forgot_password_screen.dart';
import 'package:basak_mobile/features/auth/presentation/login_register_screen.dart';
import 'package:basak_mobile/features/auth/presentation/login_screen.dart';
import 'package:basak_mobile/features/auth/presentation/password_strength.dart';
import 'package:basak_mobile/features/auth/presentation/signup_screen.dart';
import 'package:basak_mobile/features/auth/presentation/signup_steps.dart';
import 'package:basak_mobile/features/auth/presentation/university_picker_sheet.dart';
import 'package:basak_mobile/features/auth/presentation/wrong_role_screen.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/onboarding/onboarding_controller.dart';
import 'package:basak_mobile/features/onboarding/onboarding_screen.dart';
import 'package:basak_mobile/features/splash/splash_gate.dart';
import 'package:basak_mobile/main.dart';

import 'support/entry_fakes.dart';
import 'support/perf_fakes.dart' show onePixel;

/// A phone: the boards' 390 × 844.
void _phone(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder _input(String key) => find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(_input(key), text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// An account with a role this app is not for.
class _SignedIn extends AuthNotifier {
  _SignedIn(super.repo, UserRole role) {
    state = AuthState(
        user: const User(id: 'a1', appMetadata: {}, userMetadata: {}, aud: '', createdAt: ''), role: role);
  }
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
        appName: 'باصك', packageName: 'com.basak.basak_mobile', version: '1.0.2', buildNumber: '14', buildSignature: '');
    authEntryOpensSignup = false;
    authEntryOpensSignIn = false;
  });

  group('sign-up', () {
    late FakeEntryRepository repo;
    late int photosAsked;

    Future<void> open(WidgetTester tester, {VoidCallback? onBack}) async {
      _phone(tester);
      repo = FakeEntryRepository();
      photosAsked = 0;
      await tester.pumpWidget(entryApp(
        SignupScreen(
          onBack: onBack ?? () {},
          pickPhoto: (context, source) async {
            photosAsked++;
            return onePixel;
          },
        ),
        repo,
      ));
      await tester.pump();
    }

    Future<void> fillDetails(WidgetTester tester) async {
      await _type(tester, 'signup-name', 'سارة أحمد محمود');
      await _type(tester, 'signup-phone', '01012345678');
      await _tap(tester, 'signup-next');
    }

    Future<void> pickUniversity(WidgetTester tester) async {
      await _tap(tester, 'signup-university');
      await tester.tap(find.text('جامعة المنصورة الجديدة'));
      await tester.pump();
      await _tap(tester, 'university-confirm');
    }

    Future<void> pickCollege(WidgetTester tester, String name) async {
      await _tap(tester, 'signup-college');
      await tester.tap(find.text(name));
      await tester.pump();
      await _tap(tester, 'college-confirm');
    }

    Future<void> fillPassword(WidgetTester tester) async {
      await _type(tester, 'signup-password', 'Abcd1234!');
      await _type(tester, 'signup-confirmation', 'Abcd1234!');
      await tester.tap(find.byKey(const Key('signup-terms')));
      await tester.pump();
    }

    testWidgets('the rail names the four steps and each step asks its own question', (tester) async {
      await open(tester);
      for (final step in signupSteps) {
        expect(find.text(step.rail), findsOneWidget);
      }
      expect([for (final s in signupSteps) s.rail], ['بياناتك', 'دراستك', 'صورتك', 'كلمة المرور']);
      expect(find.text('من أنت؟'), findsOneWidget);
      expect(find.text('اسمك كما في بطاقتك الجامعية، ورقم هاتفك هو اسم دخولك.'), findsOneWidget);
      expect(find.bySemanticsLabel('الخطوة 1 من 4: بياناتك'), findsOneWidget);

      await fillDetails(tester);
      expect(find.text('أين تدرس؟'), findsOneWidget);
      expect(find.text('لا يمكن تغيير الجامعة بعد التسجيل.'), findsOneWidget);
      expect(find.bySemanticsLabel('الخطوة 2 من 4: دراستك'), findsOneWidget);

      await pickUniversity(tester);
      await pickCollege(tester, 'الهندسة');
      await _tap(tester, 'signup-next');
      expect(find.text('صورة واضحة لوجهك'), findsOneWidget);

      await _tap(tester, 'signup-photo-gallery');
      await _tap(tester, 'signup-next');
      expect(find.text('كلمة مرور'), findsOneWidget);
      expect(find.text('8 أحرف على الأقل. اختر شيئاً لا تستخدمه في مكان آخر.'), findsOneWidget);
      expect(find.text('إنشاء الحساب'), findsOneWidget);
      expect(find.byKey(const Key('signup-next')), findsNothing);
    });

    testWidgets('step 1 says what is wrong under the field, and does not move on', (tester) async {
      await open(tester);
      await _tap(tester, 'signup-next');
      expect(find.text(SignupDetailsStep.nameMessage), findsOneWidget);
      expect(find.text(SignupDetailsStep.phoneMessage), findsOneWidget);
      expect(find.text('من أنت؟'), findsOneWidget);

      await _type(tester, 'signup-name', 'سارة أحمد');
      await _type(tester, 'signup-phone', '0101234');
      await _tap(tester, 'signup-next');
      expect(find.text(SignupDetailsStep.nameMessage), findsOneWidget);
      expect(find.text(SignupDetailsStep.phoneMessage), findsOneWidget);

      // Typing takes the complaint away; Arabic digits are a phone number too.
      await _type(tester, 'signup-name', 'سارة أحمد محمود');
      expect(find.text(SignupDetailsStep.nameMessage), findsNothing);
      await _type(tester, 'signup-phone', '٠١٠١٢٣٤٥٦٧٨');
      await _tap(tester, 'signup-next');
      expect(find.text('أين تدرس؟'), findsOneWidget);
    });

    testWidgets('the university and the college are both required; the specialisation is not', (tester) async {
      await open(tester);
      await fillDetails(tester);
      expect(find.text('التخصص (اختياري)'), findsOneWidget);

      await _tap(tester, 'signup-next');
      expect(find.text(SignupStudyStep.universityMessage), findsOneWidget);
      expect(find.text(SignupStudyStep.collegeMessage), findsOneWidget);
      expect(find.text('أين تدرس؟'), findsOneWidget);

      await pickUniversity(tester);
      expect(find.text(SignupStudyStep.universityMessage), findsNothing);
      expect(find.text('جامعة المنصورة الجديدة'), findsOneWidget);
      await _tap(tester, 'signup-next');
      expect(find.text(SignupStudyStep.collegeMessage), findsOneWidget, reason: 'the college is still missing');

      await pickCollege(tester, 'الصيدلة');
      expect(find.text('الصيدلة'), findsOneWidget);
      await _tap(tester, 'signup-next');
      expect(find.text('صورة واضحة لوجهك'), findsOneWidget, reason: 'no specialisation was asked for');
    });

    testWidgets('the photo step waits for a photo', (tester) async {
      await open(tester);
      await fillDetails(tester);
      await pickUniversity(tester);
      await pickCollege(tester, 'الهندسة');
      await _tap(tester, 'signup-next');

      await _tap(tester, 'signup-next');
      expect(find.text('صورة واضحة لوجهك'), findsOneWidget, reason: 'التالي is off until a photo is in');
      expect(find.bySemanticsLabel('مكان الصورة'), findsOneWidget);

      await _tap(tester, 'signup-photo-camera');
      expect(photosAsked, 1);
      expect(find.bySemanticsLabel('تغيير الصورة'), findsOneWidget);
      await _tap(tester, 'signup-next');
      expect(find.text('كلمة مرور'), findsOneWidget);
    });

    testWidgets('a tap on the photo circle asks where the photo comes from', (tester) async {
      await open(tester);
      await fillDetails(tester);
      await pickUniversity(tester);
      await pickCollege(tester, 'الهندسة');
      await _tap(tester, 'signup-next');

      await _tap(tester, 'signup-photo');
      expect(find.text('صورة الحساب'), findsOneWidget);
      expect(find.text('التقاط صورة بالكاميرا'), findsOneWidget);
      expect(find.text('صورة واضحة لوجهك: المشرف يطابقها عند الصعود.'), findsOneWidget);
      await tester.tap(find.text('اختيار من الصور'));
      await tester.pumpAndSettle();
      expect(photosAsked, 1);
      expect(find.text('صورة الحساب'), findsNothing);
    });

    testWidgets('the password step: length, confirmation and the terms, each said in place', (tester) async {
      await open(tester);
      await fillDetails(tester);
      await pickUniversity(tester);
      await pickCollege(tester, 'الهندسة');
      await _tap(tester, 'signup-next');
      await _tap(tester, 'signup-photo-gallery');
      await _tap(tester, 'signup-next');

      await _tap(tester, 'signup-submit');
      expect(find.text(passwordTooShortMessage), findsOneWidget);
      expect(find.text(SignupPasswordStep.termsMessage), findsOneWidget);
      expect(repo.registrations, isEmpty);

      await _type(tester, 'signup-password', 'abcdefgh');
      expect(find.text('ضعيفة'), findsOneWidget);
      await _type(tester, 'signup-password', 'Abcd1234!');
      expect(find.text('قوية'), findsOneWidget);
      await _type(tester, 'signup-confirmation', 'Abcd1234');
      await _tap(tester, 'signup-submit');
      expect(find.text(passwordMismatchMessage), findsOneWidget);
      expect(repo.registrations, isEmpty);

      await _type(tester, 'signup-confirmation', 'Abcd1234!');
      await tester.tap(find.byKey(const Key('signup-terms')));
      await tester.pump();
      expect(find.text(SignupPasswordStep.termsMessage), findsNothing);
      await _tap(tester, 'signup-submit');
      expect(repo.registrations, hasLength(1));
    });

    testWidgets('a phone that is already registered: back on step 1, said under the phone field', (tester) async {
      await open(tester);
      repo.registerError = Exception(AuthRepository.phoneAlreadyRegisteredMessage);
      await fillDetails(tester);
      await pickUniversity(tester);
      await pickCollege(tester, 'الهندسة');
      await _tap(tester, 'signup-next');
      await _tap(tester, 'signup-photo-gallery');
      await _tap(tester, 'signup-next');
      await fillPassword(tester);
      await _tap(tester, 'signup-submit');

      expect(find.text('من أنت؟'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('signup-phone')),
              matching: find.text('رقم الهاتف مسجل بالفعل. سجّل الدخول به، أو استخدم نسيت كلمة المرور.')),
          findsOneWidget);
      // What was typed is still there.
      expect(find.text('سارة أحمد محمود'), findsOneWidget);
    });

    testWidgets('one registration carries the college chosen from the list, and no specialisation', (tester) async {
      await open(tester);
      await fillDetails(tester);
      await pickUniversity(tester);
      await pickCollege(tester, 'طب الأسنان');
      await _tap(tester, 'signup-next');
      await _tap(tester, 'signup-photo-gallery');
      await _tap(tester, 'signup-next');
      await fillPassword(tester);
      await _tap(tester, 'signup-submit');

      expect(repo.registrations, hasLength(1));
      final sent = repo.registrations.single;
      expect(sent['phone'], '01012345678');
      expect(sent['fullName'], 'سارة أحمد محمود');
      expect(sent['university'], 'جامعة المنصورة الجديدة');
      expect(sent['college'], 'طب الأسنان');
      expect(sent['specialisation'], '');
      expect(sent['photo'], onePixel);
      // Any other failure stays on the last step, in one line.
      expect(find.text('كلمة مرور'), findsOneWidget);
      expect(find.text('تعذر إنشاء الحساب الآن.'), findsOneWidget);
    });

    testWidgets('«كلية أخرى» takes a name of the student\'s own, and the specialisation travels when typed',
        (tester) async {
      await open(tester);
      await fillDetails(tester);
      await pickUniversity(tester);

      await _tap(tester, 'signup-college');
      expect(find.text('كليتك'), findsOneWidget);
      await _tap(tester, 'college-other');
      // Nothing typed yet: nothing to confirm.
      await _tap(tester, 'college-confirm');
      expect(find.text('كليتك'), findsOneWidget);
      await _type(tester, 'college-other-field', '  العلوم الصحية   التطبيقية ');
      await _tap(tester, 'college-confirm');
      expect(find.text('كليتك'), findsNothing);
      expect(find.text('العلوم الصحية التطبيقية'), findsOneWidget);

      await _type(tester, 'signup-specialisation', 'تكنولوجيا الأشعة');
      await _tap(tester, 'signup-next');
      await _tap(tester, 'signup-photo-gallery');
      await _tap(tester, 'signup-next');
      await fillPassword(tester);
      await _tap(tester, 'signup-submit');

      expect(repo.registrations.single['college'], 'العلوم الصحية التطبيقية');
      expect(repo.registrations.single['specialisation'], 'تكنولوجيا الأشعة');
    });

    testWidgets('back walks the steps, then leaves the sign-up', (tester) async {
      var left = 0;
      await open(tester, onBack: () => left++);
      await fillDetails(tester);
      expect(find.text('أين تدرس؟'), findsOneWidget);

      await tester.tap(find.byType(BasakIconButton));
      await tester.pumpAndSettle();
      expect(find.text('من أنت؟'), findsOneWidget);
      expect(find.text('سارة أحمد محمود'), findsOneWidget);
      expect(left, 0);

      await tester.tap(find.byType(BasakIconButton));
      await tester.pumpAndSettle();
      expect(left, 1);
    });
  });

  group('pickers', () {
    testWidgets('the university sheet searches names and cities, and confirms one choice', (tester) async {
      _phone(tester);
      String? picked = 'unset';
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                picked = await UniversityPickerSheet.show(context, universities: entryUniversities, selectedId: 'mu'),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('جامعتك'), findsOneWidget);
      expect(find.byType(SheetRadioRow), findsNWidgets(5));
      expect(tester.widget<SheetRadioRow>(find.widgetWithText(SheetRadioRow, 'جامعة المنصورة')).selected, isTrue);

      await tester.enterText(find.byType(TextField), 'دمياط');
      await tester.pump();
      expect(find.byType(SheetRadioRow), findsNWidgets(2), reason: 'two universities are in that city');

      await tester.enterText(find.byType(TextField), 'جامعه حورس');
      await tester.pump();
      expect(find.byType(SheetRadioRow), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'القاهرة');
      await tester.pump();
      expect(find.text('لا توجد جامعة بهذا الاسم.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'حورس');
      await tester.pump();
      await tester.tap(find.text('جامعة حورس'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('university-confirm')));
      await tester.pumpAndSettle();
      expect(picked, 'horus');
    });

    testWidgets('no universities at all: the sheet says so and offers nothing to confirm', (tester) async {
      _phone(tester);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: UniversityPickerSheet(universities: []))));
      expect(find.text('لا توجد جامعات متاحة حالياً.'), findsOneWidget);
      expect(find.text('تأكيد'), findsNothing);
    });

    testWidgets('the college sheet: the fixed list, searched, and a typed college comes back in its field',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: CollegePickerSheet(selected: 'العلوم الصحية التطبيقية'))));
      // A name that is not in the list was typed before: it is offered again.
      expect(find.text('العلوم الصحية التطبيقية'), findsOneWidget);
      expect(find.byKey(const Key('college-other-field')), findsOneWidget);
      expect(find.byType(SheetRadioRow), findsNWidgets(kColleges.length));

      await tester.enterText(find.byType(TextField).first, 'هندسه');
      await tester.pump();
      expect(find.byType(SheetRadioRow), findsOneWidget);
      expect(find.text('الهندسة'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'فلك');
      await tester.pump();
      expect(find.text('لا توجد كلية بهذا الاسم. اكتبها تحت «كلية أخرى».'), findsOneWidget);
    });
  });

  group('sign-in', () {
    late FakeEntryRepository repo;

    Future<void> open(WidgetTester tester) async {
      _phone(tester);
      repo = FakeEntryRepository();
      await tester.pumpWidget(entryApp(const LoginRegisterScreen(), repo));
      await tester.pump();
    }

    testWidgets('the welcome screen leads to the three ways in', (tester) async {
      await open(tester);
      expect(find.text('باصك'), findsOneWidget);
      expect(find.text('اشتراك الباص الجامعي، بكل بساطة.'), findsOneWidget);
      expect(find.text('إنشاء حساب طالب'), findsOneWidget);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(find.text('دخول المشرفين'), findsOneWidget);

      await _tap(tester, 'welcome-signup');
      expect(find.byKey(const ValueKey('signup')), findsOneWidget);
      expect(find.text('من أنت؟'), findsOneWidget);
      await tester.tap(find.byType(BasakIconButton));
      await tester.pumpAndSettle();

      await _tap(tester, 'welcome-signin');
      expect(find.byKey(const ValueKey('login')), findsOneWidget);
      expect(find.text('أهلاً بعودتك'), findsOneWidget);
      expect(find.text('سجّل دخولك وكمّل رحلتك.'), findsOneWidget);
      expect(find.text('نسيت كلمة المرور؟'), findsOneWidget);
      expect(find.text('تذكّر رقمي'), findsOneWidget);
    });

    testWidgets('supervisors have their own screen, reached from the welcome screen', (tester) async {
      await open(tester);
      await _tap(tester, 'welcome-supervisor');
      expect(find.text('دخول المشرف'), findsOneWidget);
      expect(find.text('تابع رحلات خطوطك وسجّل صعود الطلاب.'), findsOneWidget);
      expect(find.text('رقم الهاتف أو البريد الإلكتروني'), findsOneWidget);
      expect(find.text('حسابات المشرفين ينشئها مسؤول النظام فقط. لتغيير كلمة المرور تواصل مع إدارة شركتك.'),
          findsOneWidget);
      // No recovery and no sign-up for a supervisor: the company's admin does both.
      expect(find.text('نسيت كلمة المرور؟'), findsNothing);
      expect(find.text('إنشاء حساب'), findsNothing);

      // An e-mail address is taken as it is; the role is the server's to say.
      await _type(tester, 'login-identifier', 'supervisor@example.com');
      await _type(tester, 'login-password', 'secret-pass');
      await _tap(tester, 'login-submit');
      expect(repo.signIns.single, (identifier: 'supervisor@example.com', password: 'secret-pass'));

      await _tap(tester, 'login-students');
      expect(find.text('أهلاً بعودتك'), findsOneWidget);
      await _tap(tester, 'login-supervisors');
      expect(find.text('دخول المشرف'), findsOneWidget);

      // Back from either sign-in is the welcome screen.
      await tester.tap(find.byType(BasakIconButton));
      await tester.pumpAndSettle();
      expect(find.text('إنشاء حساب طالب'), findsOneWidget);
    });

    testWidgets('empty fields are said in place; wrong credentials under the password field', (tester) async {
      await open(tester);
      await _tap(tester, 'welcome-signin');

      await _tap(tester, 'login-submit');
      expect(find.text('اكتب رقم الهاتف.'), findsOneWidget);
      expect(find.text('اكتب كلمة المرور.'), findsOneWidget);
      expect(repo.signIns, isEmpty);

      await _type(tester, 'login-identifier', '01012345678');
      await _type(tester, 'login-password', 'wrong-pass');
      await _tap(tester, 'login-submit');
      expect(repo.signIns.single, (identifier: '01012345678', password: 'wrong-pass'));
      expect(LoginScreen.wrongCredentialsMessage, 'رقم الهاتف أو كلمة المرور غير صحيحة.');
      expect(
          find.descendant(
              of: find.byKey(const Key('login-password')), matching: find.text('رقم الهاتف أو كلمة المرور غير صحيحة.')),
          findsOneWidget);

      // Typing again takes the complaint away.
      await _type(tester, 'login-password', 'another');
      expect(find.text('رقم الهاتف أو كلمة المرور غير صحيحة.'), findsNothing);
    });

    testWidgets('«تذكّر رقمي» works as before: the number comes back, only when it was asked for', (tester) async {
      FlutterSecureStorage.setMockInitialValues({'basak.remembered_phone': '01012345678'});
      addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
      await open(tester);
      await _tap(tester, 'welcome-signin');
      expect(find.text('01012345678'), findsOneWidget);
      expect(tester.widget<CheckRow>(find.byKey(const Key('login-remember'))).value, isTrue);

      // Unticked: the next sign-in forgets it.
      await tester.tap(find.byKey(const Key('login-remember')));
      await tester.pump();
      await _type(tester, 'login-password', 'whatever1');
      await _tap(tester, 'login-submit');
      expect(await const FlutterSecureStorage().read(key: 'basak.remembered_phone'), isNull);

      await tester.tap(find.byKey(const Key('login-remember')));
      await tester.pump();
      await _tap(tester, 'login-submit');
      expect(await const FlutterSecureStorage().read(key: 'basak.remembered_phone'), '01012345678');
    });

    testWidgets('no connection is not blamed on a field', (tester) async {
      await open(tester);
      await _tap(tester, 'welcome-signin');
      repo.signInError = Exception('ClientException with SocketException: Failed host lookup');
      await _type(tester, 'login-identifier', '01012345678');
      await _type(tester, 'login-password', 'whatever1');
      await _tap(tester, 'login-submit');
      expect(find.widgetWithText(InlineError, 'تعذر الاتصال بالإنترنت. تحقق من الاتصال وحاول مرة أخرى.'),
          findsOneWidget);
    });

    testWidgets('onboarding\'s last page opens the sign-up or the sign-in directly, once', (tester) async {
      authEntryOpensSignup = true;
      await open(tester);
      expect(find.text('من أنت؟'), findsOneWidget);
      expect(authEntryOpensSignup, isFalse, reason: 'signing out later lands on the welcome screen');

      authEntryOpensSignIn = true;
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      expect(find.text('أهلاً بعودتك'), findsOneWidget);
    });
  });

  group('password recovery', () {
    late FakeEntryRepository repo;
    Object? result;

    Future<void> open(WidgetTester tester, {String phone = ''}) async {
      _phone(tester);
      repo = FakeEntryRepository();
      result = 'unset';
      await tester.pumpWidget(entryApp(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await Navigator.of(context)
                  .push<String>(MaterialPageRoute(builder: (_) => ForgotPasswordScreen(initialPhone: phone))),
              child: const Text('open'),
            ),
          ),
        ),
        repo,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('step 1 asks for the phone and says where the code comes from', (tester) async {
      await open(tester);
      expect(find.text('استعادة كلمة المرور'), findsOneWidget);
      expect(find.text('اكتب رقم هاتفك، ونرسل طلباً لإدارة شركتك لتعطيك رمز الاستعادة.'), findsOneWidget);
      expect(find.text('الرمز لا يصل برسالة نصية. تأخذه من إدارة الشركة، وهو صالح 30 دقيقة.'), findsOneWidget);

      // Neither way forward works without a phone number.
      await _tap(tester, 'forgot-send');
      expect(find.text('اكتب رقم هاتف مصري صحيح من 11 رقماً.'), findsOneWidget);
      expect(repo.resetRequests, isEmpty);
      await _tap(tester, 'forgot-have-code');
      expect(find.text('استعادة كلمة المرور'), findsOneWidget);

      await _type(tester, 'forgot-phone', '01012345678');
      await _tap(tester, 'forgot-send');
      expect(repo.resetRequests, ['01012345678']);
      expect(find.text('أدخل الرمز'), findsOneWidget);
      expect(find.text('ستة أرقام من إدارة الشركة، صالحة 30 دقيقة من لحظة إصدارها.'), findsOneWidget);
    });

    testWidgets('step 2 takes the six digits and the new password, then goes back with the phone', (tester) async {
      await open(tester, phone: '01012345678');
      await _tap(tester, 'forgot-have-code');
      expect(repo.resetRequests, isEmpty, reason: 'a code in hand needs no new request');
      expect(find.text('أدخل الرمز'), findsOneWidget);

      // Off until there is a whole code and both passwords.
      await _tap(tester, 'forgot-reset-submit');
      expect(repo.resets, isEmpty);
      await _type(tester, 'forgot-code', '4827');
      await _type(tester, 'forgot-password', 'NewPass12');
      await _type(tester, 'forgot-confirm', 'NewPass1');
      await _tap(tester, 'forgot-reset-submit');
      expect(repo.resets, isEmpty);

      await _type(tester, 'forgot-code', '٤٨٢٧١٦');
      expect(find.text('متوسطة'), findsOneWidget);
      await _tap(tester, 'forgot-reset-submit');
      expect(find.text(passwordMismatchMessage), findsOneWidget);
      expect(repo.resets, isEmpty);

      await _type(tester, 'forgot-confirm', 'NewPass12');
      await _tap(tester, 'forgot-reset-submit');
      expect(repo.resets.single, (phone: '01012345678', code: '482716', newPassword: 'NewPass12'));
      expect(result, '01012345678');
      expect(find.text('تم تغيير كلمة المرور. سجّل الدخول بكلمة المرور الجديدة.'), findsOneWidget);
    });

    testWidgets('what the server refuses is shown, and the request can be sent again', (tester) async {
      await open(tester, phone: '01012345678');
      await _tap(tester, 'forgot-have-code');
      repo.resetError = Exception('الرمز غير صحيح أو انتهت صلاحيته.');
      await _type(tester, 'forgot-code', '111111');
      await _type(tester, 'forgot-password', 'NewPass12');
      await _type(tester, 'forgot-confirm', 'NewPass12');
      await _tap(tester, 'forgot-reset-submit');
      expect(find.widgetWithText(InlineError, 'الرمز غير صحيح أو انتهت صلاحيته.'), findsOneWidget);
      expect(result, 'unset');

      await _tap(tester, 'forgot-resend');
      expect(repo.resetRequests, ['01012345678']);

      // Back leaves the code step for the phone step, not the whole screen.
      await tester.tap(find.byType(BasakIconButton));
      await tester.pumpAndSettle();
      expect(find.text('استعادة كلمة المرور'), findsOneWidget);
    });
  });

  group('onboarding', () {
    testWidgets('four pages, then creating an account or signing in', (tester) async {
      _phone(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [onboardingProvider.overrideWith((ref) => OnboardingController.completed())],
        child: const MaterialApp(home: OnboardingScreen()),
      ));
      expect(onboardingPages, hasLength(4));

      for (var i = 0; i < onboardingPages.length; i++) {
        expect(find.text(onboardingPages[i].title), findsOneWidget);
        expect(find.text(onboardingPages[i].body), findsOneWidget);
        expect(find.bySemanticsLabel('الصفحة ${i + 1} من 4'), findsOneWidget);
        if (i < onboardingPages.length - 1) {
          expect(find.text('تخطي'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('next')));
          await tester.pumpAndSettle();
        }
      }
      expect(onboardingPages.first.title, 'كل شركات النقل في مكان واحد');
      expect(onboardingPages.last.title, 'بطاقتك دائماً معك');

      expect(find.byKey(const ValueKey('next')), findsNothing);
      expect(find.text('تخطي'), findsNothing);
      expect(find.widgetWithText(BasakButton, 'إنشاء حساب'), findsOneWidget);
      expect(find.text('لديّ حساب'), findsOneWidget);

      await tester.tap(find.text('لديّ حساب'));
      await tester.pump();
      expect((authEntryOpensSignup, authEntryOpensSignIn), (false, true));
      await tester.tap(find.byKey(const ValueKey('final')));
      await tester.pump();
      expect((authEntryOpensSignup, authEntryOpensSignIn), (true, false));
    });

    testWidgets('«تخطي» ends it on the welcome screen; someone already signed in is only told to start',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [onboardingProvider.overrideWith((ref) => OnboardingController.completed())],
        child: const MaterialApp(home: OnboardingScreen(isSignedIn: true)),
      ));
      await tester.tap(find.text('تخطي'));
      await tester.pump();
      expect((authEntryOpensSignup, authEntryOpensSignIn), (false, false));

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('ابدأ الآن'), findsOneWidget);
      expect(find.text('لديّ حساب'), findsNothing);
    });

    testWidgets('nothing clips on a small phone at the largest text', (tester) async {
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(ProviderScope(
        overrides: [onboardingProvider.overrideWith((ref) => OnboardingController.completed())],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)), child: child!),
          home: const OnboardingScreen(),
        ),
      ));
      for (var i = 0; i < 3; i++) {
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('next')));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('the rest of the entry', () {
    testWidgets('the splash settles and leaves the screen under it', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SplashGate(child: Scaffold(body: Text('under')))));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('النقل الجامعي'), findsOneWidget);
      expect(find.byType(SplashRail), findsOneWidget);
      // Nothing loops: it comes to rest by itself.
      await tester.pumpAndSettle();
      expect(find.byType(SplashRail), findsNothing);
      expect(find.text('under'), findsOneWidget);
    });

    testWidgets('an account that is not for this app is told so, with the way out', (tester) async {
      _phone(tester);
      final repo = FakeEntryRepository();
      await tester.pumpWidget(entryApp(const AuthGate(), repo, overrides: [
        authStateProvider.overrideWith((ref) => _SignedIn(repo, UserRole.admin)),
        onboardingProvider.overrideWith((ref) => OnboardingController.completed()),
      ]));
      await tester.pump();
      expect(find.byType(WrongRoleScreen), findsOneWidget);
      expect(find.text('هذا الحساب لا يعمل هنا'), findsOneWidget);
      expect(find.text('تطبيق باصك للطلاب والمشرفين. حسابات الإدارة تدخل من لوحة التحكم على الويب.'), findsOneWidget);
      expect(find.widgetWithText(BasakButton, 'تسجيل الخروج'), findsOneWidget);
    });

    testWidgets('the photo source sheet answers with the source', (tester) async {
      _phone(tester);
      Object? source = 'unset';
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => source = await PhotoSourceSheet.show(context),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('صورة الحساب'), findsOneWidget);
      await tester.tap(find.byKey(const Key('photo-source-camera')));
      await tester.pumpAndSettle();
      expect(source.toString(), 'ImageSource.camera');
    });

    test('password strength: three levels', () {
      expect(passwordStrength('abc'), (level: 1, label: 'ضعيفة'));
      expect(passwordStrength('abcdefgh'), (level: 1, label: 'ضعيفة'));
      expect(passwordStrength('abcdefg1'), (level: 2, label: 'متوسطة'));
      expect(passwordStrength('Abcdefg1'), (level: 2, label: 'متوسطة'));
      expect(passwordStrength('Abcdefg1!'), (level: 3, label: 'قوية'));
    });

  });
}
