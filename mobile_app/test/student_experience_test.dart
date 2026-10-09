import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/core/widgets/greeting_header.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/notifications/presentation/notification_preferences_screen.dart';
import 'package:basak_mobile/features/notifications/presentation/push_permission_sheet.dart';
import 'package:basak_mobile/features/notifications/push/push_messaging.dart';
import 'package:basak_mobile/features/notifications/push/push_providers.dart';
import 'package:basak_mobile/features/student/daily_ride/data/daily_ride_repository.dart';
import 'package:basak_mobile/features/student/home/presentation/notifications_screen.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/profile/presentation/profile_screen.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';

import 'support/notification_fakes.dart';
import 'support/perf_fakes.dart';

const _fullName = 'محمد عادل فؤاد العزول';

class _Auth extends AuthNotifier {
  _Auth() : super(AuthRepository()) {
    state = const AuthState(
      user: User(id: 'student-1', appMetadata: {}, userMetadata: {'full_name': _fullName}, aud: '', createdAt: ''),
      role: UserRole.student,
    );
  }
}

class _Active extends CurrentSubscriptionNotifier {
  @override
  Future<SubscriptionModel?> build() async => SubscriptionModel(
      id: 'sub', studentId: 's', lineId: 'l', stationId: 'st', type: 'termly', status: 'active', price: 3000,
      createdAt: '2026-09-01', startDate: '2020-01-01', endDate: '2099-12-31');
}

/// What a student sees: greeted by two names, and no notification settings in
/// the app (only the phone's own permission).
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'باصك', packageName: 'basak', version: '1.0.6', buildNumber: '35', buildSignature: '');
  });

  Widget app(Widget home, {FakeNotificationsRepo? repo, PushMessaging? push}) => ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('student-1'),
          authStateProvider.overrideWith((ref) => _Auth()),
          currentSubscriptionProvider.overrideWith(_Active.new),
          voteSettingsProvider.overrideWith((ref) async => FakeRides.settings),
          dailyRideRepoProvider.overrideWithValue(FakeRides(RequestLog()) as DailyRideRepository),
          studentProfileSummaryProvider.overrideWith((ref, id) async => {'full_name': _fullName, 'phone': '01055512301'}),
          notificationsRepoProvider.overrideWithValue(repo ?? FakeNotificationsRepo()),
          if (push != null) pushMessagingProvider.overrideWithValue(push),
        ],
        child: MaterialApp(
          home: Directionality(textDirection: TextDirection.rtl, child: home),
        ),
      );

  group('the greeting name', () {
    test('the first two names of a full name', () {
      expect(GreetingHeader.firstTwoNames(_fullName), 'محمد عادل');
      expect(GreetingHeader.firstTwoNames('سارة أحمد محمود'), 'سارة أحمد');
      expect(GreetingHeader.firstTwoNames('Mohamed Adel Fouad'), 'Mohamed Adel');
    });

    test('one name, two names and nothing stay as they are', () {
      expect(GreetingHeader.firstTwoNames('محمد'), 'محمد');
      expect(GreetingHeader.firstTwoNames('محمد عادل'), 'محمد عادل');
      expect(GreetingHeader.firstTwoNames(''), '');
      expect(GreetingHeader.firstTwoNames('   '), '');
    });

    test('spaces of any kind and number, and invisible marks, are tidied', () {
      expect(GreetingHeader.firstTwoNames('  محمد   عادل \t فؤاد\n'), 'محمد عادل');
      expect(GreetingHeader.firstTwoNames('محمد عادل فؤاد'), 'محمد عادل', reason: 'non-breaking spaces');
      expect(GreetingHeader.firstTwoNames('‏محمد‏ ‎عادل فؤاد'), 'محمد عادل', reason: 'direction marks');
    });

    test('a name of two words is never cut in half', () {
      expect(GreetingHeader.firstTwoNames('محمد عبد الرحمن علي'), 'محمد عبد الرحمن');
      expect(GreetingHeader.firstTwoNames('عبد الله محمد أحمد'), 'عبد الله محمد');
      expect(GreetingHeader.firstTwoNames('أبو بكر عمر حسن'), 'أبو بكر عمر');
      expect(GreetingHeader.firstTwoNames('نور الدين محمد علي'), 'نور الدين محمد');
      expect(GreetingHeader.firstTwoNames('أحمد جاد الله سيد'), 'أحمد جاد الله');
      expect(GreetingHeader.firstTwoNames('عبد'), 'عبد');
    });

    test('the full name is not changed by it', () {
      const name = _fullName;
      GreetingHeader.firstTwoNames(name);
      expect(name, 'محمد عادل فؤاد العزول');
    });

    testWidgets('the header: the greeting first, the name right under it', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: GreetingHeader(
                name: GreetingHeader.firstTwoNames(_fullName), photoUrl: null, unread: 0, onNotifications: () {}),
          ),
        ),
      ));
      final greeting = find.text(GreetingHeader.greetingFor(DateTime.now()));
      expect(greeting, findsOneWidget);
      expect(find.text('محمد عادل'), findsOneWidget);
      expect(find.textContaining('فؤاد'), findsNothing);
      expect(tester.getTopLeft(greeting).dy, lessThan(tester.getTopLeft(find.text('محمد عادل')).dy));
      expect(GreetingHeader.greetingFor(DateTime(2026, 10, 9, 20)), 'مساء الخير');
    });

    testWidgets('the student home greets by two names', (tester) async {
      await tester.pumpWidget(app(StudentHomeScreen(onNavigateToSubscription: () {}, onNavigateToQr: () {})));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('محمد عادل'), findsOneWidget);
      expect(find.text(_fullName), findsNothing);
      expect(find.text(GreetingHeader.greetingFor(DateTime.now())), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the profile keeps the full name', (tester) async {
      tester.view.physicalSize = const Size(1170, 3600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const ProfileScreen()));
      await tester.pumpAndSettle();
      expect(find.text(_fullName), findsWidgets);
    });
  });

  group('a student has no notification settings in the app', () {
    testWidgets('the profile has no way to them', (tester) async {
      tester.view.physicalSize = const Size(1170, 3600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final repo = FakeNotificationsRepo();
      await tester.pumpWidget(app(const ProfileScreen(), repo: repo));
      await tester.pumpAndSettle();
      expect(find.text('إعدادات الإشعارات'), findsNothing);
      expect(find.byType(NotificationPreferencesScreen), findsNothing);
      expect(find.text('تسجيل الخروج'), findsOneWidget, reason: 'the rest of the page is there');
      expect(repo.preferenceRequests, 0);
    });

    testWidgets('the Notification Center has no settings button and no switches, and never asks for them',
        (tester) async {
      final repo = FakeNotificationsRepo([note('n1', 'تأخير الباص')]);
      await tester.pumpWidget(app(const NotificationsScreen(), repo: repo, push: FakePushMessaging()));
      await tester.pumpAndSettle();
      expect(find.byTooltip('إعدادات الإشعارات'), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.text('تأخير الباص'), findsOneWidget);
      expect(find.text('تذكير تأكيد الرحلة'), findsNothing, reason: 'the reminder-days card is not built');
      expect(find.byType(TextField), findsNothing, reason: 'no search either');
      expect(find.textContaining('أوقفت التذكيرات'), findsNothing);
      expect(repo.preferenceRequests, 0, reason: 'the switches are neither read nor written for a student');
    });

    testWidgets('notifications refused on the phone: the inbox still loads, with one line to the settings',
        (tester) async {
      final push = FakePushMessaging(granted: PushPermission.blocked);
      final repo = FakeNotificationsRepo([note('n1', 'تم اعتماد اشتراكك'), note('n2', 'تأخير الباص')]);
      await tester.pumpWidget(app(const NotificationsScreen(), repo: repo, push: push));
      await tester.pumpAndSettle();

      expect(find.text('تم اعتماد اشتراكك'), findsOneWidget);
      expect(find.text('تأخير الباص'), findsOneWidget);
      expect(find.text('الإشعارات متوقفة'), findsOneWidget);
      expect(find.text('فعّلها من إعدادات الهاتف لتصلك التنبيهات.'), findsOneWidget);
      expect(find.text('فتح إعدادات الهاتف'), findsOneWidget);

      // The line leads to the phone's settings: no sheet of the app, no prompt.
      await tester.tap(find.text('فتح إعدادات الهاتف'));
      await tester.pumpAndSettle();
      expect(push.prompts, 0);
      expect(find.text('تفعيل الإشعارات'), findsNothing);
      expect(find.text('تأخير الباص'), findsOneWidget);
    });

    testWidgets('not asked yet: the line asks the phone directly, with no sheet of choices', (tester) async {
      final push = FakePushMessaging(granted: PushPermission.notAsked)..promptAnswer = PushPermission.granted;
      await tester.pumpWidget(app(const NotificationsScreen(), repo: FakeNotificationsRepo(), push: push));
      await tester.pumpAndSettle();

      expect(find.text('الإشعارات غير مفعّلة على هذا الهاتف'), findsOneWidget);
      await tester.tap(find.text('تفعيل الإشعارات'));
      await tester.pumpAndSettle();

      expect(push.prompts, 1, reason: 'the system prompt, at once');
      expect(find.text('ليس الآن'), findsNothing, reason: 'no explanation sheet in between');
      expect(find.textContaining('تختار ما يصلك'), findsNothing);
      expect(find.byKey(const Key('push-off-card')), findsNothing, reason: 'granted: the card goes');
    });

    testWidgets('after sign-in the app says why first, then the phone asks its one question, once',
        (tester) async {
      final push = FakePushMessaging(granted: PushPermission.notAsked)..promptAnswer = PushPermission.denied;
      late WidgetRef ref;
      late BuildContext context;
      await tester.pumpWidget(app(
          Consumer(builder: (c, r, _) {
            context = c;
            ref = r;
            return const Scaffold(body: Text('home'));
          }),
          push: push));

      late Future<void> offer;
      await tester.runAsync(() async {
        offer = offerPushNotificationsOnce(context, ref);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('فعّل إشعارات باصك'), findsOneWidget, reason: 'the app explains before the phone asks');
      expect(find.textContaining('بعدها يسألك الهاتف مرة واحدة'), findsOneWidget);
      expect(push.prompts, 0, reason: 'nothing is asked of the phone until the student agrees');

      await tester.tap(find.text('تفعيل الإشعارات'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => offer);
      await tester.pumpAndSettle();
      expect(push.prompts, 1);
      expect(find.text('فعّل إشعارات باصك'), findsNothing);

      // Refused: the answer is respected, the app does not ask again by itself.
      await tester.runAsync(() => offerPushNotificationsOnce(context, ref));
      await tester.pumpAndSettle();
      expect(push.prompts, 1);
      expect(find.text('فعّل إشعارات باصك'), findsNothing);
    });

    testWidgets('"not now" on the explainer asks the phone nothing', (tester) async {
      final push = FakePushMessaging(granted: PushPermission.notAsked);
      late WidgetRef ref;
      late BuildContext context;
      await tester.pumpWidget(app(
          Consumer(builder: (c, r, _) {
            context = c;
            ref = r;
            return const Scaffold(body: Text('home'));
          }),
          push: push));
      late Future<void> offer;
      await tester.runAsync(() async {
        offer = offerPushNotificationsOnce(context, ref);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('ليس الآن'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => offer);
      expect(push.prompts, 0);
    });
  });
}
