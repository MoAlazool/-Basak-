// Draws the inbox and the account page in each of their states, and the
// sheets they open, to PNG files with the app's real fonts: a look at the
// layout without a device, to hold against the canvas boards (Inbox,
// InboxDetail, InboxEmpty, Profile, EditDetails, DeleteAccount, Help).
// Skipped unless RENDER_DIR is set:
//   RENDER_DIR=/tmp/basak-account flutter test test/ui/alerts_account_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/widgets/floating_glass_nav_bar.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/notifications/presentation/notification_preferences_screen.dart';
import 'package:basak_mobile/features/notifications/presentation/notifications_page.dart';
import 'package:basak_mobile/features/notifications/push/push_messaging.dart';
import 'package:basak_mobile/features/notifications/push/push_providers.dart';
import 'package:basak_mobile/features/student/home/presentation/notifications_screen.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/profile/presentation/help_sheet.dart';
import 'package:basak_mobile/features/student/profile/presentation/profile_screen.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';

import '../support/notification_fakes.dart';

final _dir = Platform.environment['RENDER_DIR'];
final _key = GlobalKey();

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

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

class _Auth extends AuthNotifier {
  _Auth() : super(AuthRepository()) {
    state = const AuthState(
      user: User(id: 'student-1', appMetadata: {}, userMetadata: {'full_name': 'سارة أحمد محمود'}, aud: '', createdAt: ''),
      role: UserRole.student,
    );
  }
}

class _Sub extends CurrentSubscriptionNotifier {
  @override
  Future<SubscriptionModel?> build() async => SubscriptionModel(
        id: 'sub',
        studentId: 'student-1',
        lineId: 'l',
        stationId: 'st',
        type: 'termly',
        status: 'active',
        price: 4500,
        createdAt: '2026-09-01',
        startDate: '2026-09-20',
        endDate: '2027-01-14',
        lineName: 'الزرقا',
        stationName: 'كوبري السرو',
        supervisorName: 'محمود السيد',
        supervisorPhone: '01011223344',
        companyName: 'النورس للنقل',
      );
}

AppNotification _alert(String id, String type, String title, String body, DateTime at,
        {bool read = true, String role = 'system', String name = '', String audience = '', String? route}) =>
    AppNotification(
      id: id,
      type: type,
      category: NotificationCategory.parse(null, type: type),
      title: title,
      body: body,
      createdAt: at,
      senderRole: role,
      senderName: name,
      audience: audience,
      read: read,
      data: {if (route != null) 'route': route},
    );

/// The inbox of the `Inbox` board, on today's date.
List<AppNotification> _inbox() {
  final now = DateTime.now();
  DateTime day(int ago, int hour, int minute) => DateTime(now.year, now.month, now.day - ago, hour, minute);
  return [
    _alert('n1', 'transport.departed', 'الباص تحرّك من موقف الزرقا', 'رحلة 7:00 ص · خط الزرقا', day(0, 0, 3),
        read: false, route: 'home'),
    _alert('n2', 'announcement.supervisor', 'تغيير مكان الركوب غداً',
        'غداً الاثنين الركوب من أمام البنك الأهلي بدل موقف الزرقا بسبب أعمال في الطريق. المواعيد كما هي.', day(0, 0, 1),
        read: false, role: 'supervisor', name: 'محمود السيد', audience: 'خط الزرقا'),
    _alert('n3', 'reminder.vote', 'لم تؤكد رحلة الغد بعد', 'التأكيد متاح حتى 6:00 ص.', day(1, 21, 0), route: 'home'),
    _alert('n4', 'subscription.approved', 'تم تفعيل اشتراكك', 'الفصل الأول · صالح حتى 14 يناير 2027', day(18, 16, 12),
        route: 'subscription'),
    _alert('n5', 'subscription.payment_received', 'استلمنا إيصالك', 'قيد مراجعة شركة النورس للنقل.', day(18, 10, 5),
        route: 'subscription'),
    _alert('n6', 'announcement.admin', 'إجازة رسمية', 'لا توجد رحلات يوم الخميس.', day(30, 9, 0)),
  ];
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required Size size,
  FakeNotificationsRepo? repo,
  PushMessaging? push,
  Map<String, dynamic>? profile,
  List<HelpEntry>? support,
  bool tabBar = false,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      sessionUserIdProvider.overrideWithValue('student-1'),
      authStateProvider.overrideWith((ref) => _Auth()),
      currentSubscriptionProvider.overrideWith(_Sub.new),
      studentProfileSummaryProvider.overrideWith((ref, id) async =>
          profile ??
          {'full_name': 'سارة أحمد محمود', 'phone': '01023456789', 'university': 'المنصورة الجديدة', 'college': 'الهندسة'}),
      notificationsRepoProvider.overrideWithValue(repo ?? FakeNotificationsRepo()),
      if (push != null) pushMessagingProvider.overrideWithValue(push),
      if (support != null) helpSupportProvider.overrideWithValue(support),
    ],
    child: RepaintBoundary(
      key: _key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: tabBar
            // Framed as in the app: the floating tab bar over the page's bottom.
            ? Scaffold(
                extendBody: true,
                body: home,
                bottomNavigationBar: FloatingGlassNavBar(
                  currentIndex: 3,
                  onTabSelected: (_) {},
                  items: FloatingGlassNavBar.studentNavItems,
                ),
              )
            : home,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

const _sizes = {'390': Size(390, 844), '360': Size(360, 640)};

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'باصك', packageName: 'basak', version: '1.0.6', buildNumber: '35', buildSignature: '');
  });

  testWidgets('draw the inbox', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(_fonts);
    Directory(_dir!).createSync(recursive: true);

    for (final MapEntry(key: w, value: size) in _sizes.entries) {
      FakeNotificationsRepo repo() => FakeNotificationsRepo(_inbox())..perPage = 5;

      await _pump(tester, const NotificationsScreen(), size: size, repo: repo(), push: FakePushMessaging());
      await _shot(tester, 'inbox-1-all-$w');

      await tester.tap(find.byKey(const Key('alert-n2')));
      await _shot(tester, 'inbox-3-detail-$w');
      await tester.tap(find.text('إغلاق'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('غير المقروءة · 1'));
      await _shot(tester, 'inbox-2-unread-$w');

      await _pump(tester, const NotificationsScreen(),
          size: size, push: FakePushMessaging(granted: PushPermission.blocked));
      await _shot(tester, 'inbox-4-empty-push-off-$w');

      await _pump(tester, const NotificationsScreen(), size: size, push: FakePushMessaging());
      await _shot(tester, 'inbox-5-empty-$w');

      await _pump(tester, const NotificationsScreen(),
          size: size, repo: FakeNotificationsRepo([_inbox()[5]]), push: FakePushMessaging());
      await tester.tap(find.text('غير المقروءة'));
      await _shot(tester, 'inbox-6-nothing-unread-$w');

      await _pump(tester, const NotificationsScreen(),
          size: size, repo: repo(), push: FakePushMessaging(granted: PushPermission.notAsked));
      await _shot(tester, 'inbox-7-push-not-asked-$w');

      await _pump(tester, const NotificationsScreen(), size: size, repo: FakeNotificationsRepo()..offline = true);
      await _shot(tester, 'inbox-8-error-$w');

      // The same page as a supervisor gets it: the gear and the search.
      await _pump(tester, const NotificationsPage(), size: size, repo: repo(), push: FakePushMessaging());
      await _shot(tester, 'inbox-9-supervisor-$w');

      await _pump(tester, const NotificationPreferencesScreen(),
          size: size, push: FakePushMessaging(granted: PushPermission.blocked));
      await _shot(tester, 'inbox-10-preferences-$w');
    }
    debugDisableShadows = true;
  }, skip: _dir == null);

  testWidgets('draw the account page', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(_fonts);
    Directory(_dir!).createSync(recursive: true);

    for (final MapEntry(key: w, value: size) in _sizes.entries) {
      final page = Size(size.width, w == '390' ? 896 : size.height);
      await _pump(tester, const ProfileScreen(), size: page, tabBar: true, push: FakePushMessaging());
      await _shot(tester, 'account-1-profile-$w');

      await tester.tap(find.byKey(const Key('profile-edit')));
      await _shot(tester, 'account-2-edit-$w');
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.byKey(const Key('profile-help')), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-help')));
      await _shot(tester, 'account-3-help-$w');
      await tester.tap(find.text('إغلاق'));
      await tester.pumpAndSettle();

      // The page is a lazy list: the row is built once it is scrolled to.
      await tester.scrollUntilVisible(find.byKey(const Key('profile-delete')), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-delete')));
      await _shot(tester, 'account-4-delete-$w');
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      // Everything filled in, long values, and both help groups.
      await _pump(
        tester,
        const ProfileScreen(),
        size: page,
        tabBar: true,
        push: FakePushMessaging(granted: PushPermission.blocked),
        profile: {
          'full_name': 'محمد عادل فؤاد عبد الرحمن العزول', 'phone': '01055512301',
          'university': 'جامعة المنصورة الجديدة الأهلية', 'college': 'الحاسبات والمعلومات',
          'specialisation': 'هندسة البرمجيات', 'email': 'mohamed.adel.fouad@students.example.edu.eg',
          'birth_date': '2005-03-14',
        },
        support: [
          HelpEntry(icon: LucideIcons.messageCircle, title: '[قناة الدعم 1]', subtitle: '[وصف قصير أو أوقات العمل]', action: (_) {}),
          HelpEntry(icon: LucideIcons.badgeHelp, title: '[قناة الدعم 2]', subtitle: '[وصف قصير]', action: (_) {}),
        ],
      );
      await _shot(tester, 'account-5-profile-full-$w');
      await tester.tap(find.byKey(const Key('profile-edit')));
      await _shot(tester, 'account-6-edit-full-$w');
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('profile-help')), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-help')));
      await _shot(tester, 'account-7-help-two-groups-$w');
      await tester.tap(find.text('إغلاق'));
      await tester.pumpAndSettle();
    }
    debugDisableShadows = true;
  }, skip: _dir == null);
}
