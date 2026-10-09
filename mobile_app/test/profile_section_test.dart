import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/features/student/profile/data/profile_repository.dart';
import 'package:basak_mobile/features/student/profile/presentation/profile_editor.dart';

typedef _Saved = ({String? email, String? college, DateTime? birthDate, String? specialisation, bool changed});

class _FakeRepo extends ProfileRepository {
  final saved = <_Saved>[];

  /// A database that cannot hold the specialisation yet: the rest is saved.
  bool specialisationReady = true;

  /// What the server refuses the save with.
  String? refusal;

  @override
  Future<bool> updateDetails({
    String? email,
    String? college,
    DateTime? birthDate,
    String? specialisation,
    bool specialisationChanged = false,
  }) async {
    if (refusal != null) throw Exception(refusal);
    saved.add((
      email: email,
      college: college,
      birthDate: birthDate,
      specialisation: specialisation,
      changed: specialisationChanged,
    ));
    return !specialisationChanged || specialisationReady;
  }
}

void main() {
  test('emails and birth dates', () {
    expect(isValidEmail('student@example.com'), isTrue);
    expect(isValidEmail('not an email'), isFalse);
    expect(isValidEmail('a@b'), isFalse);
    expect(birthDateLabel(DateTime(2005, 3, 14)), '14 مارس 2005');
  });

  Future<_FakeRepo> open(WidgetTester tester, Map<String, dynamic> profile, {Size size = const Size(390, 933)}) async {
    final repo = _FakeRepo();
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [profileRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: ProfileSection(userId: 'u1', profile: profile, fallbackName: 'طالب', fallbackPhone: '010'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  const full = <String, dynamic>{
    'full_name': 'محمد عادل', 'phone': '01055512301', 'university': 'جامعة المنصورة الجديدة',
    'college': 'كلية الهندسة', 'specialisation': 'مدني', 'email': 'old@example.com', 'birth_date': '2005-03-14',
  };

  testWidgets('the profile shows what is fixed and what can be added', (tester) async {
    // A row as an older database gives it: no specialisation key at all.
    await open(tester, {
      'full_name': 'محمد عادل', 'phone': '01055512301', 'university': 'جامعة المنصورة الجديدة', 'college': 'غير محدد',
    });
    expect(find.text('محمد عادل'), findsOneWidget);
    expect(find.text('010 5551 2301'), findsOneWidget, reason: 'the phone, in its three groups');
    expect(find.text('جامعة المنصورة الجديدة'), findsOneWidget);
    expect(find.byIcon(LucideIcons.lock), findsOneWidget, reason: 'only the university is locked');
    for (final label in ['بياناتي', 'الجامعة', 'الكلية', 'التخصص', 'البريد الإلكتروني']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Nothing optional has been added yet: college, specialisation, email.
    expect(find.text('لم يُضف بعد'), findsNWidgets(3));
    expect(find.text('تاريخ الميلاد'), findsNothing, reason: 'the birth date is in «تعديل», not on the page');
    expect(find.byKey(const Key('profile-change-photo')), findsOneWidget);
    expect(find.byKey(const Key('profile-edit')), findsOneWidget);
    expect(find.text('تعديل'), findsOneWidget);
  });

  testWidgets('the photo control is a full tap target and nothing overflows on a small phone', (tester) async {
    await open(tester, {...full, 'full_name': 'محمد عادل فؤاد عبد الرحمن العزول'}, size: const Size(360, 640));
    expect(tester.takeException(), isNull);
    final control = tester.getSize(find.byKey(const Key('profile-change-photo')));
    expect(control.width, greaterThanOrEqualTo(48));
    expect(control.height, greaterThanOrEqualTo(48));
    final edit = tester.getSize(find.byKey(const Key('profile-edit')));
    expect(edit.height, greaterThanOrEqualTo(48));
  });

  testWidgets('email is optional, a wrong one is caught before saving, and the college is picked from the list',
      (tester) async {
    final repo = await open(tester, full);
    expect(find.text('كلية الهندسة'), findsOneWidget);
    expect(find.text('مدني'), findsOneWidget);
    expect(find.text('old@example.com'), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-edit')));
    await tester.pumpAndSettle();
    expect(find.text('تعديل بياناتي'), findsOneWidget);
    expect(find.text('14 مارس 2005'), findsOneWidget);
    expect(find.text('الاسم والهاتف والجامعة لا تتغيّر من هنا.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('profile-email')), 'wrong');
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(find.text('اكتب بريداً إلكترونياً صحيحاً.'), findsOneWidget);
    expect(repo.saved, isEmpty);

    await tester.enterText(find.byKey(const Key('profile-email')), '');
    await tester.tap(find.byKey(const Key('profile-college')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الطب'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('college-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.email, '');
    expect(repo.saved.single.college, 'الطب');
    expect(repo.saved.single.birthDate, DateTime(2005, 3, 14));
    expect(repo.saved.single.changed, isFalse, reason: 'the specialisation was not touched');
    expect(find.text('تعديل بياناتي'), findsNothing, reason: 'the sheet closed');
    expect(find.text('تم حفظ بياناتك.'), findsOneWidget);
  });

  testWidgets('the birth date can be cleared', (tester) async {
    final repo = await open(tester, full);
    await tester.tap(find.byKey(const Key('profile-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('حذف'));
    await tester.pumpAndSettle();
    expect(find.text('14 مارس 2005'), findsNothing);
    expect(find.text('اختر التاريخ'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(repo.saved.single.birthDate, isNull);
    expect(repo.saved.single.college, 'كلية الهندسة', reason: 'a college of their own is kept as it was');
  });

  testWidgets('a new specialisation is sent as changed and saved', (tester) async {
    final repo = await open(tester, full);
    await tester.tap(find.byKey(const Key('profile-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-specialisation')), 'ميكاترونكس');
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(repo.saved.single.specialisation, 'ميكاترونكس');
    expect(repo.saved.single.changed, isTrue);
    expect(find.text('تم حفظ بياناتك.'), findsOneWidget);
    expect(find.text(ProfileSection.specialisationLater), findsNothing);
  });

  testWidgets('a database that cannot hold the specialisation yet: the rest is saved and the student is told',
      (tester) async {
    final repo = await open(tester, full)..specialisationReady = false;
    await tester.tap(find.byKey(const Key('profile-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-specialisation')), '');
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(repo.saved.single.changed, isTrue, reason: 'emptying it is a change too');
    expect(find.text('تعديل بياناتي'), findsNothing, reason: 'the sheet closed: the other details were saved');
    expect(find.text(ProfileSection.specialisationLater), findsOneWidget);
    expect(find.text('تم حفظ بياناتك.'), findsNothing);
  });

  testWidgets('a refused save keeps the sheet open and shows the reason', (tester) async {
    final repo = await open(tester, full)..refusal = 'هذا البريد مستخدم في حساب آخر.';
    await tester.tap(find.byKey(const Key('profile-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(repo.saved, isEmpty);
    expect(find.text('هذا البريد مستخدم في حساب آخر.'), findsOneWidget);
    expect(find.text('تعديل بياناتي'), findsOneWidget);
  });
}
