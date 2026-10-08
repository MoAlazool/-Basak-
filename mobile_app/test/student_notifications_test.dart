import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/widgets/greeting_header.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/notifications/presentation/notifications_page.dart';
import 'package:basak_mobile/features/student/daily_ride/data/daily_ride_repository.dart';
import 'package:basak_mobile/features/student/daily_ride/models/vote_settings.dart';
import 'package:basak_mobile/features/student/home/presentation/notifications_screen.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';
import 'package:basak_mobile/features/supervisor/data/supervisor_repository.dart';
import 'package:basak_mobile/features/supervisor/models/supervisor_models.dart';
import 'package:basak_mobile/features/supervisor/notifications/supervisor_notifications_screen.dart';

class _FakeDailyRideRepo implements DailyRideRepository {
  @override
  Future<VoteSettings> getVoteSettings(String? companyId) async => _reminding;
  @override
  Future<Map<DateTime, bool>> getRideStatusesForRange(DateTime from, DateTime to) async => {};
  @override
  Future<DailyRideDetails> getRideDetailsForDate(DateTime date) async =>
      const DailyRideDetails(isRiding: false, isReturning: false);
  @override
  Future<bool> getRideStatusForDate(DateTime date) async => false;
  @override
  Future<bool> toggleRide({required DateTime rideDate, required bool isRiding}) async => isRiding;
  @override
  Future<DailyRideDetails> confirmRide({
    required DateTime rideDate,
    required bool isRiding,
    required String? departureTime,
    required String? returnTime,
    required bool isReturning,
  }) async =>
      DailyRideDetails(isRiding: isRiding, isReturning: isReturning);
}

class _FakeNotificationsRepo implements NotificationsRepository {
  final List<List<String>?> marked = [];
  final List<Map<String, String?>> sent = [];

  @override
  Future<List<AppNotification>> mine() async => const [];
  @override
  Future<void> markRead([List<String>? ids]) async => marked.add(ids);
  @override
  Future<int> send({
    required String title,
    required String body,
    required String lineId,
    String? tripId,
    String? rideDate,
  }) async {
    sent.add({'title': title, 'body': body, 'line': lineId, 'trip': tripId, 'date': rideDate});
    return 4;
  }
}

const _reminding = VoteSettings(opensAt: 16 * 60, closesAt: 6 * 60, reminderMinutes: 30);

class _Subscription extends CurrentSubscriptionNotifier {
  final String? status;
  _Subscription(this.status);

  @override
  Future<SubscriptionModel?> build() async => status == null
      ? null
      : SubscriptionModel(
          id: 'sub', studentId: 's', lineId: 'l', stationId: 'st', type: 'termly',
          status: status!, price: 3000, createdAt: '2026-09-01',
          startDate: '2020-01-01', endDate: '2099-12-31');
}

AppNotification _note(String id, String title, {bool read = false, String role = 'admin'}) =>
    AppNotification(
      id: id,
      title: title,
      body: 'نص $title',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      senderRole: role,
      senderName: 'أحمد',
      audience: 'خط المنصورة',
      read: read,
    );

Widget _app(Widget home,
        {String? status = 'active',
        List<AppNotification> notes = const [],
        _FakeNotificationsRepo? repo}) =>
    ProviderScope(
      overrides: [
        sessionUserIdProvider.overrideWithValue('student-1'),
        currentSubscriptionProvider.overrideWith(() => _Subscription(status)),
        voteSettingsProvider.overrideWith((ref) async => _reminding),
        dailyRideRepoProvider.overrideWithValue(_FakeDailyRideRepo()),
        myNotificationsProvider.overrideWith((ref) async => notes),
        notificationsRepoProvider.overrideWithValue(repo ?? _FakeNotificationsRepo()),
      ],
      child: MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: home),
      ),
    );

final _dashboardJson = {
  'today': '2026-10-08',
  'profile': {'id': 'sup', 'full_name': 'محمود', 'is_active': true},
  'totals': <String, dynamic>{},
  'lines': [
    {'id': 'line-1', 'name': 'خط المنصورة', 'is_active': true}
  ],
  'trip_times': [
    {'ride_date': '2026-10-08', 'line_id': 'line-1', 'line_name': 'خط المنصورة',
     'direction': 'departure', 'time': '07:00:00', 'students': 4, 'trip_id': 'trip-1'},
    {'ride_date': '2026-10-09', 'line_id': 'line-1', 'line_name': 'خط المنصورة',
     'direction': 'departure', 'time': '07:00:00', 'students': 0, 'trip_id': 'trip-1'},
  ],
};

class _Dashboard extends SupervisorDashboardNotifier {
  @override
  Future<SupervisorDashboard> build() async => SupervisorDashboard.fromJson(_dashboardJson);
}

void main() {
  test('good morning until noon, good evening after', () {
    String at(int hour, [int minute = 0]) =>
        GreetingHeader.greetingFor(DateTime(2026, 10, 8, hour, minute));
    expect(at(7), 'صباح الخير');
    expect(at(11, 59), 'صباح الخير');
    expect(at(12), 'مساء الخير');
    expect(at(21), 'مساء الخير');
    expect(at(3), 'مساء الخير');
  });

  test('how long ago, in Arabic', () {
    final now = DateTime(2026, 10, 8, 15);
    expect(notificationAge(now, now), 'الآن');
    expect(notificationAge(now.subtract(const Duration(minutes: 2)), now), 'منذ دقيقتين');
    expect(notificationAge(now.subtract(const Duration(minutes: 7)), now), 'منذ 7 دقائق');
    expect(notificationAge(now.subtract(const Duration(minutes: 45)), now), 'منذ 45 دقيقة');
    expect(notificationAge(now.subtract(const Duration(hours: 1)), now), 'منذ ساعة');
    expect(notificationAge(now.subtract(const Duration(hours: 10)), now), 'منذ 10 ساعات');
    expect(notificationAge(DateTime(2026, 10, 7, 9), now), 'أمس');
    expect(notificationAge(DateTime(2026, 9, 30, 9), now), '30 سبتمبر');
  });

  test('a notification is found by its title, text, sender or audience', () {
    final n = AppNotification.fromJson({
      'id': 'n1', 'title': 'تأخير الباص', 'body': 'سيتأخر الباص 10 دقائق', 'created_at': '2026-10-08T09:00:00Z',
      'sender_role': 'supervisor', 'sender_name': 'أحمد', 'audience': 'خط المنصورة · ذهاب 7:00 ص', 'read': false,
    });
    expect(n.senderLabel, 'المشرف أحمد');
    expect(n.matches('تأخير'), isTrue);
    expect(n.matches('10 دقائق'), isTrue);
    expect(n.matches('أحمد'), isTrue);
    expect(n.matches('المنصورة'), isTrue);
    expect(n.matches('إجازة'), isFalse);
    expect(n.matches('  '), isTrue);
  });

  test('the scan reads the day\'s vote, and knows when the server sent none', () {
    final voted = CheckInResult.fromJson({
      'result': 'checked_in', 'direction': 'departure',
      'ride_vote': {'is_riding': true, 'is_returning': false, 'departure_time': '07:10:00'},
    });
    expect(voted.hasRideVote, isTrue);
    expect(voted.rideVote?.isRiding, isTrue);
    expect(voted.rideVote?.departureTime, '07:10:00');
    final none = CheckInResult.fromJson({'result': 'checked_in', 'direction': 'departure', 'ride_vote': null});
    expect(none.hasRideVote, isTrue);
    expect(none.rideVote, isNull);
    final older = CheckInResult.fromJson({'result': 'checked_in', 'direction': 'departure'});
    expect(older.hasRideVote, isFalse);
  });

  test('the day strip starts at the next open vote and marks every day', () {
    final vote = VoteSettings(
      opensAt: 16 * 60,
      closesAt: 6 * 60,
      reminderMinutes: 30,
      offWeekdays: {DateTime.friday},
      offDates: {DateTime(2026, 10, 13)},
    );
    // Thursday noon: Thursday's vote closed at 6 AM, so the strip starts Friday.
    final days = reminderDays(
      vote: vote,
      now: DateTime(2026, 10, 8, 12),
      validFrom: DateTime(2026, 9, 5),
      validUntil: DateTime(2026, 10, 14),
      voted: {DateTime(2026, 10, 10): true},
    );
    expect(days.map((d) => d.day.day), [9, 10, 11, 12, 13, 14, 15]);
    expect(days.map((d) => d.state), [
      ReminderDayState.dayOff, // Friday: the company's weekly day off
      ReminderDayState.voted,
      ReminderDayState.on,
      ReminderDayState.on,
      ReminderDayState.dayOff, // a holiday
      ReminderDayState.on,
      ReminderDayState.outside, // after the subscription ends
    ]);

    // Reminders switched off by the company: voted days still show as voted.
    final noReminders = reminderDays(
      vote: const VoteSettings(opensAt: 16 * 60, closesAt: 6 * 60),
      now: DateTime(2026, 10, 8, 17),
      validFrom: null,
      validUntil: null,
      voted: {DateTime(2026, 10, 9): true},
    );
    expect(noReminders.first.day, DateTime(2026, 10, 9));
    expect(noReminders.take(2).map((d) => d.state),
        [ReminderDayState.voted, ReminderDayState.companyOff]);
  });

  testWidgets('the day strip shows the month and cannot be switched off', (tester) async {
    await tester.pumpWidget(_app(const NotificationsScreen()));
    await tester.pumpAndSettle();
    final first = reminderDays(
            vote: _reminding,
            now: DateTime.now(),
            validFrom: DateTime(2020),
            validUntil: DateTime(2099),
            voted: const {})
        .first
        .day;
    expect(find.textContaining(NotificationsPage.months[first.month - 1]), findsWidgets);
    final reminded = tester.widgetList(find.text('تذكير مفعّل')).length;
    expect(reminded, greaterThan(0));
    await tester.tap(find.text('تذكير مفعّل').first);
    await tester.pumpAndSettle();
    expect(tester.widgetList(find.text('تذكير مفعّل')).length, reminded);
  });

  testWidgets('search narrows the list; clear all marks everything read', (tester) async {
    final repo = _FakeNotificationsRepo();
    await tester.pumpWidget(_app(
      const NotificationsScreen(),
      notes: [_note('a', 'إجازة رسمية'), _note('b', 'تأخير الباص', role: 'supervisor'), _note('c', 'قديم', read: true)],
      repo: repo,
    ));
    await tester.pumpAndSettle();
    expect(find.text('2 إشعارات غير مقروءة'), findsOneWidget);
    expect(find.text('المشرف أحمد · خط المنصورة'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'تأخير');
    await tester.pumpAndSettle();
    expect(find.text('تأخير الباص'), findsOneWidget);
    expect(find.text('إجازة رسمية'), findsNothing);

    await tester.enterText(find.byType(TextField), 'غير موجود');
    await tester.pumpAndSettle();
    expect(find.text('لا توجد نتائج'), findsOneWidget);

    await tester.tap(find.text('مسح الكل'));
    await tester.pumpAndSettle();
    expect(repo.marked, [null]);
    expect(find.text('0 إشعارات غير مقروءة'), findsOneWidget);
  });

  testWidgets('opening one notification marks it read', (tester) async {
    final repo = _FakeNotificationsRepo();
    await tester.pumpWidget(_app(const NotificationsScreen(),
        notes: [_note('a', 'إجازة رسمية'), _note('b', 'تأخير الباص')], repo: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إجازة رسمية'));
    await tester.pumpAndSettle();
    expect(repo.marked, [
      ['a']
    ]);
    expect(find.text('1 إشعارات غير مقروءة'), findsOneWidget);
  });

  testWidgets('the home bell shows the unread count and opens the notifications', (tester) async {
    await tester.pumpWidget(_app(
      StudentHomeScreen(onNavigateToSubscription: () {}, onNavigateToQr: () {}),
      status: null,
      notes: [_note('a', 'إجازة'), _note('b', 'تأخير'), _note('c', 'قديم', read: true)],
    ));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.bell));
    await tester.pumpAndSettle();
    expect(find.text('الإشعارات'), findsOneWidget);
    expect(find.text('التذكيرات تعمل بعد تفعيل اشتراكك.'), findsOneWidget);
  });

  testWidgets('a supervisor writes to the riders of one trip with a ready-made message',
      (tester) async {
    final repo = _FakeNotificationsRepo();
    final dashboard = SupervisorDashboard.fromJson(_dashboardJson);
    int? popped;
    await tester.pumpWidget(ProviderScope(
      overrides: [notificationsRepoProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => popped = await showModalBottomSheet<int>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SendNotificationSheet(dashboard: dashboard),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Only trips with riders are offered.
    expect(find.text('اليوم · ذهاب 7:00 ص · 4 طالب'), findsOneWidget);
    expect(find.textContaining('غداً'), findsNothing);

    await tester.tap(find.text('اليوم · ذهاب 7:00 ص · 4 طالب'));
    await tester.tap(find.text('الباص سيتأخر'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('إرسال الإشعار'));
    await tester.tap(find.text('إرسال الإشعار'));
    await tester.pumpAndSettle();

    expect(repo.sent, [
      {'title': 'تأخير الباص', 'body': 'سيتأخر الباص نحو 10 دقائق عن موعده. شكراً لتفهمكم.',
       'line': 'line-1', 'trip': 'trip-1', 'date': '2026-10-08'}
    ]);
    expect(popped, 4);
  });

  testWidgets('the supervisor notifications page lays out with the app theme', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionUserIdProvider.overrideWithValue('sup'),
        supervisorDashboardProvider.overrideWith(_Dashboard.new),
        myNotificationsProvider.overrideWith((ref) async => [_note('a', 'إجازة رسمية')]),
        notificationsRepoProvider.overrideWithValue(_FakeNotificationsRepo()),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Directionality(
            textDirection: TextDirection.rtl, child: SupervisorNotificationsScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('أرسل إشعاراً لطلابك'), findsOneWidget);
    expect(find.text('إجازة رسمية'), findsOneWidget);
    await tester.tap(find.text('إرسال'));
    await tester.pumpAndSettle();
    expect(find.text('إشعار جديد للطلاب'), findsOneWidget);
  });
}
