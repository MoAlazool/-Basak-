import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/features/student/profile/data/profile_repository.dart';
import 'package:basak_mobile/features/student/profile/presentation/profile_editor.dart';

class _FakeRepo extends ProfileRepository {
  final saved = <({String? email, String? college, DateTime? birthDate})>[];

  @override
  Future<void> updateDetails({String? email, String? college, DateTime? birthDate}) async {
    saved.add((email: email, college: college, birthDate: birthDate));
  }
}

void main() {
  test('emails and birth dates', () {
    expect(isValidEmail('student@example.com'), isTrue);
    expect(isValidEmail('not an email'), isFalse);
    expect(isValidEmail('a@b'), isFalse);
    expect(birthDateLabel(DateTime(2005, 3, 14)), '14 مارس 2005');
  });

  Future<_FakeRepo> open(WidgetTester tester, Map<String, dynamic> profile) async {
    final repo = _FakeRepo();
    tester.view.physicalSize = const Size(1170, 2800);
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

  testWidgets('the profile shows what is fixed and what can be added', (tester) async {
    await open(tester, {
      'full_name': 'محمد عادل', 'phone': '01055512301', 'university': 'جامعة المنصورة الجديدة', 'college': 'غير محدد',
    });
    expect(find.text('محمد عادل'), findsOneWidget);
    expect(find.text('جامعة المنصورة الجديدة'), findsOneWidget);
    // Nothing optional has been added yet.
    expect(find.text('لم يُضف بعد'), findsNWidgets(3));
    expect(find.byKey(const Key('profile-change-photo')), findsOneWidget);
    expect(find.byKey(const Key('profile-edit')), findsOneWidget);
  });

  testWidgets('email and college are optional, and a wrong email is caught before saving', (tester) async {
    final repo = await open(tester, {
      'full_name': 'محمد عادل', 'phone': '01055512301', 'university': 'جامعة المنصورة الجديدة',
      'college': 'كلية الهندسة', 'email': 'old@example.com', 'birth_date': '2005-03-14',
    });
    expect(find.text('كلية الهندسة'), findsOneWidget);
    expect(find.text('old@example.com'), findsOneWidget);
    expect(find.text('14 مارس 2005'), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-email')), 'wrong');
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(find.text('اكتب بريداً إلكترونياً صحيحاً.'), findsOneWidget);
    expect(repo.saved, isEmpty);

    await tester.enterText(find.byKey(const Key('profile-email')), '');
    await tester.enterText(find.byKey(const Key('profile-college')), 'كلية الطب');
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.email, '');
    expect(repo.saved.single.college, 'كلية الطب');
    expect(repo.saved.single.birthDate, DateTime(2005, 3, 14));
  });
}
