import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/core/widgets/skeleton.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/notifications/notification_router.dart';
import 'package:basak_mobile/features/notifications/presentation/notifications_page.dart';
import 'package:basak_mobile/features/notifications/push/push_messaging.dart';
import 'package:basak_mobile/features/notifications/push/push_providers.dart';
import 'package:basak_mobile/features/student/home/presentation/notifications_screen.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';

import 'support/notification_fakes.dart';

class _Sub extends CurrentSubscriptionNotifier {
  final String? supervisorPhone;
  _Sub(this.supervisorPhone);

  @override
  Future<SubscriptionModel?> build() async => SubscriptionModel(
      id: 'sub', studentId: 's', lineId: 'l', stationId: 'st', type: 'termly', status: 'active', price: 3000,
      createdAt: '2026-09-01', startDate: '2020-01-01', endDate: '2099-12-31',
      supervisorName: 'محمود السيد', supervisorPhone: supervisorPhone);
}

/// An inbox whose first page never arrives.
class _Waiting extends FakeNotificationsRepo {
  @override
  Future<NotificationsPageData> page({String? before, bool unreadOnly = false}) =>
      Completer<NotificationsPageData>().future;
}

/// The student's inbox, in every state it has (boards Inbox, InboxDetail,
/// InboxEmpty, and the alerts line of Coverage).
void main() {
  Widget app(
    FakeNotificationsRepo repo, {
    String? supervisorPhone = '01011223344',
    PushMessaging? push,
    NotificationRouter? router,
    Widget home = const NotificationsScreen(),
    double textScale = 1,
  }) =>
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          sessionUserIdProvider.overrideWithValue('student-1'),
          currentSubscriptionProvider.overrideWith(() => _Sub(supervisorPhone)),
          notificationsRepoProvider.overrideWithValue(repo),
          if (push != null) pushMessagingProvider.overrideWithValue(push),
          if (router != null) notificationRouterProvider.overrideWithValue(router),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Directionality(textDirection: TextDirection.rtl, child: child!),
          ),
          home: home,
        ),
      );

  FontWeight? weightOf(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style?.fontWeight;

  testWidgets('first load: the skeleton, the title and the way back; nothing to filter or mark yet', (tester) async {
    await tester.pumpWidget(app(_Waiting()));
    await tester.pump();
    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.text('التنبيهات'), findsOneWidget);
    expect(find.bySemanticsLabel('رجوع'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('an inbox that could not be read says so and reads again on "retry"', (tester) async {
    final repo = FakeNotificationsRepo([note('a', 'إجازة رسمية')])..offline = true;
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحميل الإشعارات'), findsOneWidget);
    expect(find.text('إجازة رسمية'), findsNothing);

    repo.offline = false;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('إجازة رسمية'), findsOneWidget);
    expect(find.text('تعذر تحميل الإشعارات'), findsNothing);
  });

  testWidgets('nothing yet: the empty page alone, with no filter and no "read all"', (tester) async {
    await tester.pumpWidget(app(FakeNotificationsRepo()));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد تنبيهات بعد'), findsOneWidget);
    expect(find.text('ستظهر هنا حركة الباص، رسائل المشرف، وحالة اشتراكك.'), findsOneWidget);
    expect(find.text('قراءة الكل'), findsNothing);
    expect(find.text('الكل'), findsNothing);
    expect(find.byKey(const Key('push-off-card')), findsNothing, reason: 'this build has no push to switch on');
  });

  testWidgets('unread is heavier and carries a dot; read is not', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
        app(FakeNotificationsRepo([note('a', 'جديد', at: now), note('b', 'قديم', read: true, at: now)])));
    await tester.pumpAndSettle();
    expect(weightOf(tester, 'جديد'), FontWeight.w600);
    expect(weightOf(tester, 'قديم'), FontWeight.w400);
    expect(find.bySemanticsLabel(RegExp('غير مقروء')), findsOneWidget);
    expect(find.text('غير المقروءة · 1'), findsOneWidget);
    // The hour it came at, not "an hour ago": the day is the group's heading.
    expect(find.text('اليوم'), findsOneWidget);
    expect(find.textContaining('منذ'), findsNothing);
  });

  testWidgets('days are grouped: today, yesterday, then the date', (tester) async {
    final now = DateTime.now();
    DateTime day(int ago) => DateTime(now.year, now.month, now.day - ago, 0, 1);
    await tester.pumpWidget(app(FakeNotificationsRepo([
      note('a', 'أ', at: day(0)),
      note('b', 'ب', at: day(1)),
      note('c', 'ج', at: day(1)),
      note('d', 'د', at: day(9)),
    ])));
    await tester.pumpAndSettle();
    expect(find.text('اليوم'), findsOneWidget);
    expect(find.text('أمس'), findsOneWidget);
    expect(find.text(notificationDayLabel(day(9), now)), findsOneWidget);
    expect(find.byType(AlertRows), findsNWidgets(3), reason: 'one card per day');
    expect(find.text('12:01 ص'), findsNWidgets(4));
  });

  testWidgets('older alerts are one tap away, and the link goes when there are no more', (tester) async {
    final now = DateTime.now();
    final repo = FakeNotificationsRepo([
      for (var i = 0; i < 5; i++) note('n$i', 'تنبيه $i', at: now.subtract(Duration(minutes: i + 1))),
    ])
      ..perPage = 3;
    tester.view.physicalSize = const Size(390, 2000) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    expect(find.text('تنبيه 2'), findsOneWidget);
    expect(find.text('تنبيه 3'), findsNothing);

    await tester.tap(find.text('عرض تنبيهات أقدم'));
    await tester.pumpAndSettle();
    expect(find.text('تنبيه 4'), findsOneWidget);
    expect(find.text('عرض تنبيهات أقدم'), findsNothing);
    expect(repo.pageRequests, 2);
  });

  testWidgets('a message from the supervisor can be answered with a call; one from the company cannot',
      (tester) async {
    final repo = FakeNotificationsRepo([
      note('a', 'تغيير مكان الركوب', role: 'supervisor', type: 'announcement.supervisor'),
      note('b', 'إجازة رسمية'),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إجازة رسمية'));
    await tester.pumpAndSettle();
    expect(find.text('إدارة الشركة'), findsOneWidget);
    expect(find.text('اتصل بالمشرف'), findsNothing);
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تغيير مكان الركوب'));
    await tester.pumpAndSettle();
    expect(find.text('أحمد · مشرف الباص'), findsOneWidget);
    expect(find.text('اتصل بالمشرف'), findsOneWidget);
    // The call belongs to the page: the sheet closes first.
    await tester.tap(find.byKey(const Key('alert-detail-action')));
    await tester.pumpAndSettle();
    expect(find.text('اتصل بالمشرف'), findsNothing);
    expect(find.text('أحمد · مشرف الباص'), findsNothing);
  });

  testWidgets('an alert about a screen opens that screen, not a sheet', (tester) async {
    final shell = FakeShell();
    final router = NotificationRouter(currentUserId: () => 'student-1')..attach('student-1', shell);
    final repo = FakeNotificationsRepo([
      note('a', 'تم تفعيل اشتراكك', type: 'subscription.approved', data: {'route': 'subscription'}),
      note('b', 'الباص تحرّك', type: 'transport.departed', data: {'route': 'home'}),
      note('c', 'شيء جديد', data: {'route': 'somewhere-new'}),
    ]);
    await tester.pumpWidget(app(repo, router: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تم تفعيل اشتراكك'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الباص تحرّك'));
    await tester.pumpAndSettle();
    expect(shell.shown, [NotificationDestination.subscription, NotificationDestination.home]);
    expect(find.text('إغلاق'), findsNothing);

    // A route this version does not know: its text, at least.
    await tester.tap(find.text('شيء جديد'));
    await tester.pumpAndSettle();
    expect(shell.shown.length, 2);
    expect(find.text('إغلاق'), findsOneWidget);
  });

  testWidgets('the phone refuses notifications: one card on top, also over an empty inbox', (tester) async {
    final push = FakePushMessaging(granted: PushPermission.blocked);
    await tester.pumpWidget(app(FakeNotificationsRepo(), push: push));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('push-off-card')), findsOneWidget);
    expect(find.text('الإشعارات متوقفة'), findsOneWidget);
    expect(find.text('لا توجد تنبيهات بعد'), findsOneWidget);
    expect(
        tester.getTopLeft(find.text('الإشعارات متوقفة')).dy, lessThan(tester.getTopLeft(find.text('لا توجد تنبيهات بعد')).dy));
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('nothing overflows on a 360 x 640 phone at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(360, 640) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      final repo = FakeNotificationsRepo([
        note('a', 'الباص تحرّك من موقف الزرقا بعد تأخير طويل جداً هذا الصباح', at: now.subtract(const Duration(minutes: 1))),
        note('b', 'تغيير مكان الركوب غداً', role: 'supervisor', at: now.subtract(const Duration(days: 1))),
        note('c', 'قديم', read: true, at: now.subtract(const Duration(days: 20))),
      ]);
      await tester.pumpWidget(
          app(repo, push: FakePushMessaging(granted: PushPermission.blocked), textScale: scale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('تغيير مكان الركوب غداً'));
      await tester.pumpAndSettle();
      expect(find.text('اتصل بالمشرف'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('إغلاق'));
      await tester.pumpAndSettle();

      // The same page with the supervisor's gear and search.
      await tester.pumpWidget(app(repo, home: const NotificationsPage(), textScale: scale));
      await tester.pumpAndSettle();
      expect(find.byTooltip('إعدادات الإشعارات'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
