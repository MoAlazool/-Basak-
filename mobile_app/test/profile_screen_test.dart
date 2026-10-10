import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/core/widgets/skeleton.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/notifications/push/push_messaging.dart';
import 'package:basak_mobile/features/notifications/push/push_providers.dart';
import 'package:basak_mobile/features/student/home/data/line_supervisors.dart';
import 'package:basak_mobile/features/student/home/presentation/notifications_screen.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/home/presentation/supervisor_contact_sheet.dart';
import 'package:basak_mobile/features/student/profile/presentation/help_sheet.dart';
import 'package:basak_mobile/features/student/profile/presentation/profile_screen.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';

import 'support/notification_fakes.dart';

class _Auth extends AuthNotifier {
  int signOuts = 0;
  int deletions = 0;
  Object? deletionFails;

  _Auth() : super(AuthRepository()) {
    state = const AuthState(
      user: User(id: 'student-1', appMetadata: {}, userMetadata: {'full_name': 'سارة أحمد محمود'}, aud: '', createdAt: ''),
      role: UserRole.student,
    );
  }

  @override
  Future<void> signOut() async => signOuts++;

  @override
  Future<void> deleteStudentAccount() async {
    if (deletionFails != null) throw deletionFails!;
    deletions++;
  }
}

class _Sub extends CurrentSubscriptionNotifier {
  final bool supervised;
  _Sub(this.supervised);

  @override
  Future<SubscriptionModel?> build() async => SubscriptionModel(
      id: 'sub', studentId: 's', lineId: 'l', stationId: 'st', type: 'termly', status: 'active', price: 3000,
      createdAt: '2026-09-01', startDate: '2020-01-01', endDate: '2099-12-31',
      lineName: 'الزرقا', stationName: 'كوبري السرو', companyName: 'النورس للنقل',
      supervisorName: supervised ? 'محمود السيد' : null, supervisorPhone: supervised ? '01011223344' : null);
}

const _profile = <String, dynamic>{
  'full_name': 'سارة أحمد محمود', 'phone': '01023456789', 'university': 'المنصورة الجديدة', 'college': 'الهندسة',
};

/// The account page (boards Profile, Help, DeleteAccount).
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'باصك', packageName: 'basak', version: '1.0.6', buildNumber: '35', buildSignature: '');
  });

  late _Auth auth;

  Future<void> open(
    WidgetTester tester, {
    bool supervised = true,
    PushMessaging? push,
    List<HelpEntry>? support,
    List<LineSupervisor> supervisors = const [],
    Future<Map<String, dynamic>?> Function()? profile,
    Size size = const Size(390, 1100),
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    auth = _Auth();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionUserIdProvider.overrideWithValue('student-1'),
        authStateProvider.overrideWith((ref) => auth),
        currentSubscriptionProvider.overrideWith(() => _Sub(supervised)),
        studentProfileSummaryProvider.overrideWith((ref, id) => profile?.call() ?? Future.value(_profile)),
        notificationsRepoProvider.overrideWithValue(FakeNotificationsRepo()),
        if (push != null) pushMessagingProvider.overrideWithValue(push),
        if (support != null) helpSupportProvider.overrideWithValue(support),
        lineSupervisorsProvider.overrideWith((ref) async => supervisors),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const Scaffold(body: ProfileScreen()),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('the page: who, their details, the app, signing out, and deleting beside the version', (tester) async {
    await open(tester, push: FakePushMessaging());
    await tester.pumpAndSettle();
    expect(find.text('حسابي'), findsOneWidget);
    expect(find.text('سارة أحمد محمود'), findsOneWidget);
    expect(find.text('010 2345 6789'), findsOneWidget);
    expect(find.text('بياناتي'), findsOneWidget);
    expect(find.text('التطبيق'), findsOneWidget);
    expect(find.text('المساعدة والدعم'), findsOneWidget);
    expect(find.text('إشعارات الهاتف'), findsOneWidget);
    expect(find.text('تسجيل الخروج'), findsOneWidget);
    expect(find.text('حذف الحساب'), findsOneWidget);
    expect(find.text('1.0.6'), findsOneWidget);

    // Not here: the language (Arabic only), Face ID (comes with biometrics),
    // and what Home and the subscription tab already say.
    expect(find.text('اللغة'), findsNothing);
    expect(find.textContaining('Face ID'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.textContaining('الزرقا'), findsNothing);
    expect(find.textContaining('كوبري السرو'), findsNothing);
    expect(find.textContaining('النورس'), findsNothing);
    expect(find.text('محمود السيد'), findsNothing);
    expect(find.text('إعدادات الإشعارات'), findsNothing);
  });

  testWidgets('first load on this phone: the skeleton, and the rest of the page already there', (tester) async {
    await open(tester, profile: () => Completer<Map<String, dynamic>?>().future);
    expect(find.byType(ProfileSkeleton), findsOneWidget);
    expect(find.text('حسابي'), findsOneWidget);
    expect(find.text('تسجيل الخروج'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('phone notifications: says what the phone allows, and is not shown where there is no push',
      (tester) async {
    await open(tester, push: FakePushMessaging());
    await tester.pumpAndSettle();
    expect(find.text('مفعّلة'), findsOneWidget);
    // (The rating row under it leaves the app too, and has the same glyph.)
    expect(
        find.descendant(
            of: find.byKey(const Key('profile-phone-notifications')), matching: find.byIcon(LucideIcons.externalLink)),
        findsOneWidget,
        reason: 'it opens the phone\'s settings');
    await tester.tap(find.byKey(const Key('profile-phone-notifications')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone notifications refused: the row says so', (tester) async {
    final push = FakePushMessaging(granted: PushPermission.blocked);
    await open(tester, push: push);
    await tester.pumpAndSettle();
    expect(find.text('متوقفة'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-phone-notifications')));
    await tester.pumpAndSettle();
    expect(push.prompts, 0, reason: 'the phone\'s settings, never a prompt of the app\'s');
  });

  testWidgets('a build without push has no notifications row', (tester) async {
    await open(tester);
    await tester.pumpAndSettle();
    expect(find.text('إشعارات الهاتف'), findsNothing);
    expect(find.text('المساعدة والدعم'), findsOneWidget);
  });

  testWidgets('help: the supervisor of the line, and no app-support group while it has no entries', (tester) async {
    await open(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-help')));
    await tester.pumpAndSettle();
    expect(find.text('عن رحلتك واشتراكك'), findsOneWidget);
    expect(find.text('محمود السيد'), findsOneWidget);
    expect(find.text(SupervisorContactSheet.roleLabel('الزرقا')), findsOneWidget);
    expect(find.text('دعم التطبيق'), findsNothing);
    expect(find.byType(LinkRows), findsOneWidget);

    // The entry opens the supervisor's contact sheet, in place of this one.
    await tester.tap(find.text('محمود السيد'));
    await tester.pumpAndSettle();
    expect(find.text('عن رحلتك واشتراكك'), findsNothing);
    expect(find.text('010 1122 3344'), findsOneWidget);
    expect(find.byType(SupervisorContactSheet), findsOneWidget);
  });

  testWidgets('help: every supervisor of the line, the primary contact first', (tester) async {
    await open(tester, supervisors: const [
      LineSupervisor(lineId: 'l', name: 'محمود السيد', phone: '01011223344'),
      LineSupervisor(lineId: 'l', name: 'أحمد علي', phone: '01055667788'),
      LineSupervisor(lineId: 'other', name: 'سامي حسن', phone: '01099887766'),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-help')));
    await tester.pumpAndSettle();
    expect(find.text('محمود السيد'), findsOneWidget);
    expect(find.text('أحمد علي'), findsOneWidget);
    expect(find.text('سامي حسن'), findsNothing, reason: 'a supervisor of another line');
    expect(tester.getTopLeft(find.text('محمود السيد')).dy, lessThan(tester.getTopLeft(find.text('أحمد علي')).dy));

    await tester.tap(find.text('أحمد علي'));
    await tester.pumpAndSettle();
    expect(find.text('010 5566 7788'), findsOneWidget, reason: "the contact sheet of the one tapped");
  });

  test("a supervisor's message is answered on that supervisor's number, else the line's primary contact", () {
    const line = [
      LineSupervisor(lineId: 'l', name: 'محمود السيد', phone: '01011223344'),
      LineSupervisor(lineId: 'l', name: 'أحمد علي', phone: '01055667788'),
    ];
    expect(NotificationsScreen.supervisorPhone(line, ' أحمد علي '), '01055667788');
    expect(NotificationsScreen.supervisorPhone(line, 'مشرف آخر'), '01011223344');
    expect(NotificationsScreen.supervisorPhone(const [], 'أحمد علي'), '');
  });

  testWidgets('help: injected support entries make the second group, and each runs its own action', (tester) async {
    final ran = <String>[];
    await open(tester, support: [
      HelpEntry(icon: LucideIcons.messageCircle, title: 'قناة أ', subtitle: 'وصف أ', action: (_) => ran.add('a')),
      HelpEntry(icon: LucideIcons.badgeHelp, title: 'قناة ب', action: (_) => ran.add('b')),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-help')));
    await tester.pumpAndSettle();
    expect(find.text('عن رحلتك واشتراكك'), findsOneWidget);
    expect(find.text('دعم التطبيق'), findsOneWidget);
    expect(find.text('وصف أ'), findsOneWidget);
    expect(find.byType(LinkRows), findsNWidgets(2));

    await tester.tap(find.text('قناة ب'));
    await tester.pumpAndSettle();
    expect(ran, ['b']);
    expect(find.text('دعم التطبيق'), findsNothing, reason: 'the sheet closed first');
  });

  testWidgets('help: with nobody to turn to there is no row at all; with support only, one group', (tester) async {
    await open(tester, supervised: false);
    await tester.pumpAndSettle();
    expect(find.text('المساعدة والدعم'), findsNothing);
    expect(find.text('إشعارات الهاتف'), findsNothing);
    // The group is never empty now: «قيّم التطبيق» is always there, alone here.
    expect(find.text('التطبيق'), findsOneWidget);
    expect(find.byKey(const Key('profile-rate')), findsOneWidget);
    expect(find.byKey(const Key('profile-help')), findsNothing);
    expect(find.byKey(const Key('profile-phone-notifications')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await open(tester, supervised: false, support: [
      HelpEntry(icon: LucideIcons.messageCircle, title: 'قناة أ', action: (_) {}),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-help')));
    await tester.pumpAndSettle();
    expect(find.text('عن رحلتك واشتراكك'), findsNothing);
    expect(find.text('دعم التطبيق'), findsOneWidget);
  });

  testWidgets('signing out asks nothing', (tester) async {
    await open(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-sign-out')));
    await tester.pumpAndSettle();
    expect(auth.signOuts, 1);
    expect(find.byType(BasakDialogFrame), findsNothing);
  });

  testWidgets('deleting the account asks first; "cancel" deletes nothing', (tester) async {
    await open(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-delete')));
    await tester.pumpAndSettle();
    expect(find.text('حذف الحساب نهائياً؟'), findsOneWidget);
    expect(find.text('يُحذف حسابك وبياناتك، وتتوقف بطاقتك عن العمل. لا يمكن التراجع عن الحذف.'), findsOneWidget);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('حذف الحساب نهائياً؟'), findsNothing);
    expect(auth.deletions, 0);

    await tester.tap(find.byKey(const Key('profile-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد الحذف'));
    await tester.pumpAndSettle();
    expect(auth.deletions, 1);
    expect(auth.signOuts, 0);
  });

  testWidgets('a deletion the server refuses says why and leaves the account', (tester) async {
    await open(tester);
    await tester.pumpAndSettle();
    auth.deletionFails = Exception('تعذر حذف الحساب الآن.');
    await tester.tap(find.byKey(const Key('profile-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد الحذف'));
    await tester.pumpAndSettle();
    expect(auth.deletions, 0);
    expect(find.text('فشل الحذف: تعذر حذف الحساب الآن.'), findsOneWidget);
    expect(find.text('حسابي'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('nothing overflows on a 360 x 640 phone at text scale $scale, sheets and dialog included',
        (tester) async {
      await open(
        tester,
        size: const Size(360, 640),
        push: FakePushMessaging(),
        profile: () async => {
          'full_name': 'محمد عادل فؤاد عبد الرحمن العزول', 'phone': '01055512301',
          'university': 'جامعة المنصورة الجديدة الأهلية', 'college': 'الحاسبات والمعلومات',
          'specialisation': 'هندسة البرمجيات', 'email': 'mohamed.adel.fouad@students.example.edu.eg',
          'birth_date': '2005-03-14',
        },
      );
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('profile-edit')));
      await tester.pumpAndSettle();
      expect(find.text('تعديل بياناتي'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('profile-help')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-help')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('إغلاق'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('profile-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-delete')));
      await tester.pumpAndSettle();
      expect(find.text('تأكيد الحذف'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
