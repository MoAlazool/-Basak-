import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/notifications/notification_router.dart';
import 'package:basak_mobile/features/notifications/presentation/notification_preferences_screen.dart';
import 'package:basak_mobile/features/notifications/presentation/notifications_host.dart';
import 'package:basak_mobile/features/notifications/presentation/notifications_page.dart';
import 'package:basak_mobile/features/notifications/push/push_messaging.dart';
import 'package:basak_mobile/features/notifications/push/push_providers.dart';

import 'support/notification_fakes.dart';

/// Signed in with a role, without Supabase.
class _Auth extends AuthNotifier {
  _Auth(UserRole role) : super(AuthRepository()) {
    state = AuthState(
      user: const User(id: 'user-1', appMetadata: {}, userMetadata: {}, aud: '', createdAt: ''),
      role: role,
    );
  }
}

/// The settings screen, the permission sheet and the in-app banner.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'باصك', packageName: 'basak', version: '1.0.6', buildNumber: '35', buildSignature: '');
  });

  Widget app(
    Widget home, {
    required FakeNotificationsRepo repo,
    UserRole role = UserRole.student,
    PushMessaging? push,
    NotificationRouter? router,
    bool hosted = false,
  }) =>
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('user-1'),
          authStateProvider.overrideWith((ref) => _Auth(role)),
          notificationsRepoProvider.overrideWithValue(repo),
          if (push != null) pushMessagingProvider.overrideWithValue(push),
          if (router != null) notificationRouterProvider.overrideWithValue(router),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('ar'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: hosted ? NotificationsHost(child: child!) : child!,
          ),
          home: home,
        ),
      );

  Switch switchOf(WidgetTester tester, String title) => tester.widget<Switch>(find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(SwitchListTile)).first,
      matching: find.byType(Switch)));

  group('notification settings', () {
    testWidgets('without push: says so calmly, keeps the switches, and the inbox keeps everything',
        (tester) async {
      final repo = FakeNotificationsRepo();
      await tester.pumpWidget(app(const NotificationPreferencesScreen(), repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('الإشعارات الفورية غير متاحة بعد'), findsOneWidget);
      expect(find.textContaining('مركز الإشعارات داخل التطبيق يحتفظ بكل إشعاراتك دائماً', skipOffstage: false),
          findsOneWidget);
      expect(find.text('تفعيل الإشعارات'), findsNothing, reason: 'nothing is asked of the user');
      expect(find.text('حركة الباص'), findsOneWidget);
      expect(find.text('الاشتراك والدفع'), findsOneWidget);
      expect(find.text('إعلانات الشركة والمشرف'), findsOneWidget);
      expect(find.text('تذكير تأكيد الرحلة'), findsNothing, reason: 'reminders are the student app\'s own');

      await tester.tap(find.text('حركة الباص'));
      await tester.pumpAndSettle();
      expect(repo.savedPreferences.allows(NotificationCategory.transport), isFalse);
      expect(switchOf(tester, 'حركة الباص').value, isFalse);

      // Everything off: the categories have nothing left to choose.
      await tester.tap(find.text('تصلك على الهاتف حتى والتطبيق مغلق'));
      await tester.pumpAndSettle();
      expect(repo.savedPreferences.pushEnabled, isFalse);
      expect(switchOf(tester, 'الاشتراك والدفع').onChanged, isNull);
      expect(switchOf(tester, 'الاشتراك والدفع').value, isFalse);
    });

    testWidgets('a refused change moves the switch back and shows the server\'s words', (tester) async {
      final repo = FakeNotificationsRepo()..refusal = 'تعذر حفظ الإعدادات الآن.';
      await tester.pumpWidget(app(const NotificationPreferencesScreen(), repo: repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إعلانات الشركة والمشرف'));
      await tester.pumpAndSettle();
      expect(find.text('تعذر حفظ الإعدادات الآن.'), findsOneWidget);
      expect(switchOf(tester, 'إعلانات الشركة والمشرف').value, isTrue);
    });

    testWidgets('permission not given yet: the app explains first, then the system is asked',
        (tester) async {
      final repo = FakeNotificationsRepo();
      final push = FakePushMessaging(granted: PushPermission.notAsked);
      await tester.pumpWidget(app(const NotificationPreferencesScreen(), repo: repo, push: push));
      await tester.pumpAndSettle();
      expect(find.text('الإشعارات غير مفعّلة على هذا الهاتف'), findsOneWidget);
      expect(push.prompts, 0, reason: 'opening the screen asks nothing');

      // "Not now" asks nothing.
      await tester.tap(find.text('تفعيل الإشعارات'));
      await tester.pumpAndSettle();
      expect(find.text('فعّل إشعارات باصك'), findsOneWidget);
      await tester.tap(find.text('ليس الآن'));
      await tester.pumpAndSettle();
      expect(push.prompts, 0);

      await tester.tap(find.text('تفعيل الإشعارات'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تفعيل الإشعارات').last); // the sheet's own button
      await tester.pumpAndSettle();
      expect(push.prompts, 1);
      expect(find.text('الإشعارات مفعّلة على هذا الهاتف'), findsOneWidget);
      expect(repo.calls.single, startsWith('register '), reason: 'and the phone is attached at once');
      expect(repo.calls.single, endsWith(' ios token-1'));
    });

    testWidgets('switched off in the phone\'s settings: the way there is offered instead of a prompt',
        (tester) async {
      final push = FakePushMessaging(granted: PushPermission.blocked);
      await tester.pumpWidget(
          app(const NotificationPreferencesScreen(), repo: FakeNotificationsRepo(), push: push));
      await tester.pumpAndSettle();
      expect(find.text('الإشعارات متوقفة من إعدادات الهاتف'), findsOneWidget);
      expect(find.text('فتح إعدادات الهاتف'), findsOneWidget);
      expect(push.prompts, 0);
    });

    testWidgets('the Notification Center makes no offer when the build has no push', (tester) async {
      await tester.pumpWidget(app(const NotificationsPage(), repo: FakeNotificationsRepo()));
      await tester.pumpAndSettle();
      expect(find.textContaining('فعّل الإشعارات لتصلك التنبيهات'), findsNothing);
    });

    testWidgets('the Notification Center offers to switch pushes on; a final "no" leads to the settings',
        (tester) async {
      final push = FakePushMessaging(granted: PushPermission.notAsked)..promptAnswer = PushPermission.blocked;
      await tester.pumpWidget(app(const NotificationsPage(), repo: FakeNotificationsRepo(), push: push));
      await tester.pumpAndSettle();
      expect(find.textContaining('فعّل الإشعارات لتصلك التنبيهات'), findsOneWidget);

      // Refused for good in the system prompt: the settings are offered next.
      await tester.tap(find.textContaining('فعّل الإشعارات لتصلك التنبيهات'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تفعيل الإشعارات').last); // the sheet's own button
      await tester.pumpAndSettle();
      expect(push.prompts, 1);
      expect(find.text('فتح إعدادات الهاتف'), findsOneWidget);
    });
  });

  group('the banner inside the app', () {
    testWidgets('shows a push that arrives while the app is open; a tap goes through the router',
        (tester) async {
      final repo = FakeNotificationsRepo([note('n1', 'تأخير الباص', type: 'transport.delay')]);
      final shell = FakeShell();
      late final ProviderContainer container;
      final router = NotificationRouter(
        currentUserId: () => 'user-1',
        onOpened: (intent) => repo.opened(intent.notificationId!),
      )..attach('user-1', shell);
      await tester.pumpWidget(app(
        Builder(builder: (context) {
          container = ProviderScope.containerOf(context);
          return const Scaffold(body: Text('الرئيسية'));
        }),
        repo: repo,
        router: router,
        hosted: true,
      ));
      await tester.pumpAndSettle();

      const message = PushMessage(
        title: 'تأخير الباص',
        body: 'سيتأخر الباص نحو 10 دقائق.',
        data: {'notification_id': 'n1', 'type': 'transport.delay', 'category': 'transport', 'route': 'home'},
      );
      container.read(foregroundBannerProvider.notifier).show(message);
      await tester.pumpAndSettle();
      expect(find.text('سيتأخر الباص نحو 10 دقائق.'), findsOneWidget);

      await tester.tap(find.text('سيتأخر الباص نحو 10 دقائق.'));
      await tester.pumpAndSettle();
      expect(find.text('سيتأخر الباص نحو 10 دقائق.'), findsNothing);
      expect(shell.shown, [NotificationDestination.home]);
      expect(repo.openedIds, ['n1']);

      // The same message delivered again shows no second banner, and its
      // system notification (had there been one) would not be acted on twice.
      container.read(foregroundBannerProvider.notifier).show(message);
      await tester.pumpAndSettle();
      expect(find.text('سيتأخر الباص نحو 10 دقائق.'), findsNothing);
      expect(router.open(message.intent, NotificationTapSource.push), isFalse);
    });

    testWidgets('goes away by itself, or when closed', (tester) async {
      late final ProviderContainer container;
      await tester.pumpWidget(app(
        Builder(builder: (context) {
          container = ProviderScope.containerOf(context);
          return const Scaffold(body: Text('الرئيسية'));
        }),
        repo: FakeNotificationsRepo(),
        hosted: true,
      ));
      await tester.pumpAndSettle();
      final banner = container.read(foregroundBannerProvider.notifier);

      banner.show(const PushMessage(title: 'وصل الباص', data: {'notification_id': 'a'}));
      await tester.pumpAndSettle();
      expect(find.text('وصل الباص'), findsOneWidget);
      await tester.pump(ForegroundBannerController.shownFor);
      await tester.pumpAndSettle();
      expect(find.text('وصل الباص'), findsNothing);

      banner.show(const PushMessage(title: 'تحرك الباص', data: {'notification_id': 'b'}));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pumpAndSettle();
      expect(find.text('تحرك الباص'), findsNothing);
    });
  });
}
