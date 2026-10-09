import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';
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

import 'support/notification_fakes.dart';

class _FakeDailyRideRepo implements DailyRideRepository {
  @override
  Future<VoteSettings> getVoteSettings(String? companyId) async => _reminding;
  @override
  Future<RideDays> getRides(DateTime from, DateTime to) async => const RideDays({});
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
    note(id, title, read: read, role: role);

Widget _app(Widget home,
        {String? status = 'active',
        List<AppNotification> notes = const [],
        FakeNotificationsRepo? repo}) =>
    ProviderScope(
      overrides: [
        sessionUserIdProvider.overrideWithValue('student-1'),
        currentSubscriptionProvider.overrideWith(() => _Subscription(status)),
        voteSettingsProvider.overrideWith((ref) async => _reminding),
        dailyRideRepoProvider.overrideWithValue(_FakeDailyRideRepo()),
        notificationsRepoProvider.overrideWithValue((repo ?? FakeNotificationsRepo())..inbox.addAll(notes)),
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
    {'id': 'line-1', 'name': 'خط المنصورة', 'is_active': true, 'registered_students': 124}
  ],
  'trip_times': [
    {'ride_date': '2026-10-08', 'line_id': 'line-1', 'line_name': 'خط المنصورة',
     'direction': 'departure', 'time': '07:00:00', 'students': 4, 'trip_id': 'trip-1'},
    {'ride_date': '2026-10-09', 'line_id': 'line-1', 'line_name': 'خط المنصورة',
     'direction': 'departure', 'time': '07:00:00', 'students': 0, 'trip_id': 'trip-1'},
  ],
};

class _Dashboard extends SupervisorDashboardNotifier {
  final Map<String, dynamic>? json;
  _Dashboard([this.json]);

  @override
  Future<SupervisorDashboard> build() async => SupervisorDashboard.fromJson(json ?? _dashboardJson);
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

  testWidgets('the inbox has no reminder-days card: the week strip on Home shows those days', (tester) async {
    await tester.pumpWidget(_app(const NotificationsScreen(), notes: [_note('a', 'إجازة رسمية')]));
    await tester.pumpAndSettle();
    expect(find.text('التنبيهات'), findsOneWidget);
    expect(find.text('إجازة رسمية'), findsOneWidget);
    expect(find.text('تذكير تأكيد الرحلة'), findsNothing);
    expect(find.text('تذكير مفعّل'), findsNothing);
    expect(find.textContaining(NotificationsPage.months[DateTime.now().month - 1]), findsNothing);
  });

  testWidgets('a student has no search; a message opens whole in a sheet that says who sent it', (tester) async {
    final repo = FakeNotificationsRepo();
    await tester.pumpWidget(_app(
      const NotificationsScreen(),
      notes: [_note('a', 'إجازة رسمية'), _note('b', 'تأخير الباص', role: 'supervisor'), _note('c', 'قديم', read: true)],
      repo: repo,
    ));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('غير المقروءة · 2'), findsOneWidget);
    // The row is the title and the text; who sent it is in the sheet.
    expect(find.textContaining('خط المنصورة'), findsNothing);

    await tester.tap(find.text('تأخير الباص'));
    await tester.pumpAndSettle();
    expect(repo.marked, [
      ['b']
    ]);
    expect(find.text('أحمد · مشرف الباص'), findsOneWidget);
    expect(find.textContaining('خط المنصورة'), findsOneWidget);
    expect(find.text('نص تأخير الباص'), findsNWidgets(2));
    expect(find.text('اتصل بالمشرف'), findsNothing, reason: 'this subscription names no supervisor to call');
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    expect(find.text('أحمد · مشرف الباص'), findsNothing);
    expect(find.text('غير المقروءة · 1'), findsOneWidget);
  });

  testWidgets('with search (supervisors): it narrows the list; "read all" marks everything read', (tester) async {
    final repo = FakeNotificationsRepo();
    await tester.pumpWidget(_app(
      const NotificationsPage(),
      notes: [_note('a', 'إجازة رسمية'), _note('b', 'تأخير الباص', role: 'supervisor'), _note('c', 'قديم', read: true)],
      repo: repo,
    ));
    await tester.pumpAndSettle();
    expect(find.text('غير المقروءة · 2'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'تأخير');
    await tester.pumpAndSettle();
    expect(find.text('تأخير الباص'), findsOneWidget);
    expect(find.text('إجازة رسمية'), findsNothing);

    // The sender and the audience are searched too, though the row does not print them.
    await tester.enterText(find.byType(TextField), 'المشرف أحمد');
    await tester.pumpAndSettle();
    expect(find.text('تأخير الباص'), findsOneWidget);
    expect(find.text('إجازة رسمية'), findsNothing);

    await tester.enterText(find.byType(TextField), 'غير موجود');
    await tester.pumpAndSettle();
    expect(find.text('لا توجد نتائج'), findsOneWidget);

    await tester.tap(find.text('قراءة الكل'));
    await tester.pumpAndSettle();
    expect(repo.marked, [null]);
    expect(find.text('غير المقروءة'), findsOneWidget);
  });

  testWidgets('opening one notification marks it read', (tester) async {
    final repo = FakeNotificationsRepo();
    await tester.pumpWidget(_app(const NotificationsScreen(),
        notes: [_note('a', 'إجازة رسمية'), _note('b', 'تأخير الباص')], repo: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إجازة رسمية'));
    await tester.pumpAndSettle();
    expect(repo.marked, [
      ['a']
    ]);
    expect(find.text('غير المقروءة · 1'), findsOneWidget);
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
    expect(find.text('التنبيهات'), findsOneWidget);
    expect(find.text('إجازة'), findsOneWidget);
    expect(find.text('التذكيرات تعمل بعد تفعيل اشتراكك.'), findsNothing, reason: 'the reminder card is not built');
  });

  // The page a supervisor writes to the students from, opened as Home opens
  // it: what was sent is said in a toast on the screen it was opened from.
  Widget sendHost(FakeNotificationsRepo repo, {Map<String, dynamic>? dashboard}) => ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('sup'),
          supervisorDashboardProvider.overrideWith(() => _Dashboard(dashboard ?? _dashboardJson)),
          notificationsRepoProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => SupervisorSendScreen.open(context, ref),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> openSend(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('إشعار للطلاب'), findsOneWidget);
  }

  const delay = QuickNotificationTemplate(
      key: 'delay', title: 'تأخير الباص', body: 'سيتأخر الباص نحو {minutes} دقيقة.', needsMinutes: true);
  const leaving = QuickNotificationTemplate(
      key: 'return_departing', title: 'العودة تتحرك', body: 'يتحرك باص العودة من الجامعة الآن.',
      direction: 'return');

  /// Who the confirm sheet says the message will reach, as one string.
  String reach(WidgetTester tester) => tester
      .widget<Text>(find.descendant(of: find.byType(ReachLine), matching: find.byType(Text)))
      .textSpan!
      .toPlainText();

  testWidgets('a ready message: choose the riders of a trip and the minutes, see who gets it, confirm',
      (tester) async {
    final repo = FakeNotificationsRepo()..templates = const [delay, leaving];
    await tester.pumpWidget(sendHost(repo));
    await openSend(tester);

    // Nothing was picked on Trips: the whole line, with its subscribers counted.
    expect(find.text('124 مشتركاً'), findsOneWidget);
    expect(find.byKey(const Key('send-trip')), findsNothing);
    // The text as the students will read it, with the minutes still open.
    expect(find.text('سيتأخر الباص نحو … دقيقة.'), findsOneWidget);

    // The riders of a trip: only trips somebody rides are offered.
    await tester.tap(find.text('ركاب رحلة'));
    await tester.pumpAndSettle();
    expect(find.text('اليوم · ذهاب 7:00 ص'), findsOneWidget);
    expect(find.text('4 طلاب'), findsOneWidget);
    expect(find.textContaining('غداً'), findsNothing);
    expect(find.text('العودة تتحرك'), findsNothing, reason: 'a return message does not fit a going trip');

    await tester.tap(find.text('تأخير الباص'));
    await tester.pumpAndSettle();
    expect(find.text('باصك · مشرف الباص'), findsOneWidget, reason: 'the notification as the student sees it');
    expect(find.text('سيتأخر الباص نحو 10 دقيقة.'), findsOneWidget);
    expect(find.text('المدة بالدقائق'), findsOneWidget);
    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    expect(find.text('سيتأخر الباص نحو 20 دقيقة.'), findsOneWidget);
    expect(reach(tester), 'سيصل إلى 4 طلاب · ركاب ذهاب 7:00 ص اليوم');

    // The server limits how often: its message is shown as it is, and the
    // retry of this same send carries the same key.
    repo.refusal = 'أرسلت هذا الإشعار قبل قليل. انتظر دقيقة ثم حاول مرة أخرى.';
    await tester.tap(find.byKey(const Key('send-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('أرسلت هذا الإشعار قبل قليل. انتظر دقيقة ثم حاول مرة أخرى.'), findsOneWidget);
    expect(find.text('إشعار للطلاب'), findsOneWidget, reason: 'nothing was sent: the page stays');

    repo.refusal = null;
    await tester.tap(find.byKey(const Key('send-confirm')));
    await tester.pumpAndSettle();
    expect(repo.quickSent.length, 2);
    expect(repo.quickSent[1]['key'], repo.quickSent[0]['key']);
    expect(repo.quickSent[1]..remove('key'),
        {'template': 'delay', 'line': 'line-1', 'trip': 'trip-1', 'date': '2026-10-08', 'minutes': 20});

    // Back where the supervisor came from, with what the server answered:
    // it had seen this key before, so it says nothing was sent twice.
    expect(find.text('إشعار للطلاب'), findsNothing);
    expect(find.text('سبق إرسال هذا الإشعار، ولم يُرسل مرة أخرى.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('a return message is offered for a return trip only, and asks for no minutes', (tester) async {
    final repo = FakeNotificationsRepo()..templates = const [delay, leaving];
    await tester.pumpWidget(sendHost(repo, dashboard: {
      ..._dashboardJson,
      'trip_times': [
        ...(_dashboardJson['trip_times'] as List),
        {'ride_date': '2026-10-08', 'line_id': 'line-1', 'line_name': 'خط المنصورة',
         'direction': 'return', 'time': '15:00:00', 'students': 3, 'trip_id': 'trip-2'},
      ],
    }));
    await openSend(tester);
    // The whole line may be told anything.
    expect(find.text('العودة تتحرك'), findsOneWidget);

    await tester.tap(find.text('ركاب رحلة'));
    await tester.pumpAndSettle();
    expect(find.text('العودة تتحرك'), findsNothing);

    // The trip row opens every trip with riders.
    await tester.tap(find.byKey(const Key('send-trip')));
    await tester.pumpAndSettle();
    expect(find.text('3 طلاب'), findsOneWidget);
    await tester.tap(find.text('اليوم · عودة 3:00 م'));
    await tester.pumpAndSettle();
    expect(find.text('العودة تتحرك'), findsOneWidget);

    await tester.tap(find.text('العودة تتحرك'));
    await tester.pumpAndSettle();
    expect(find.text('المدة بالدقائق'), findsNothing, reason: 'this message needs no minutes');
    expect(reach(tester), 'سيصل إلى 3 طلاب · ركاب عودة 3:00 م اليوم');
    await tester.tap(find.byKey(const Key('send-confirm')));
    await tester.pumpAndSettle();
    expect(repo.quickSent.single..remove('key'),
        {'template': 'return_departing', 'line': 'line-1', 'trip': 'trip-2', 'date': '2026-10-08', 'minutes': null});
    expect(find.text('تم إرسال الإشعار إلى 4 طلاب.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('a text of their own: counted as typed, confirmed before it goes, one key per send',
      (tester) async {
    final keys = <Object?>[];
    final repo = _RecordingRepo(keys);
    await tester.pumpWidget(sendHost(repo));
    await openSend(tester);
    await tester.tap(find.text('رسالة أخرى'));
    await tester.pumpAndSettle();

    // Nothing to send yet.
    expect(find.text('0 / 80'), findsOneWidget);
    expect(find.text('0 / 600'), findsOneWidget);
    await tester.tap(find.byKey(const Key('send-continue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('send-confirm')), findsNothing);

    final titleField = find.descendant(of: find.byKey(const Key('send-title')), matching: find.byType(TextField));
    final bodyField = find.descendant(of: find.byKey(const Key('send-body')), matching: find.byType(TextField));
    await tester.enterText(titleField, 'تغيير مكان الركوب');
    await tester.enterText(bodyField, 'غداً الركوب من أمام البنك بدل الموقف.');
    await tester.pumpAndSettle();
    expect(find.text('17 / 80'), findsOneWidget);
    expect(find.text('37 / 600'), findsOneWidget);
    expect(find.text('كل طلاب خط المنصورة · 124'), findsOneWidget);

    Future<void> confirm() async {
      await tester.tap(find.byKey(const Key('send-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send-confirm')));
      await tester.pumpAndSettle();
    }

    // It is shown as the student will see it before anything is sent; the
    // server refuses (its own words are shown) and the supervisor tries again.
    await tester.tap(find.byKey(const Key('send-continue')));
    await tester.pumpAndSettle();
    expect(find.text('باصك · مشرف الباص'), findsOneWidget);
    expect(reach(tester), 'سيصل إلى 124 طالباً · كل طلاب خط المنصورة');
    expect(keys, isEmpty, reason: 'writing a text sends nothing');
    await tester.tap(find.byKey(const Key('send-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('أرسلت إشعارات كثيرة، انتظر قليلاً ثم حاول مرة أخرى.'), findsOneWidget);
    expect(repo.sent, isEmpty);
    await tester.tap(find.byKey(const Key('send-confirm')));
    await tester.pumpAndSettle();
    expect(keys.length, 2);
    expect(keys[0], keys[1], reason: 'the same send, tried twice, is one send to the server');

    // Closing the sheet and confirming the same text again is still that send.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await confirm();
    expect(keys[2], keys[0]);

    // Another text is another send, and this time the server takes it.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.enterText(bodyField, 'الركوب من أمام البنك.');
    await tester.pumpAndSettle();
    repo.refusal = null;
    await confirm();
    expect(keys[3], isNot(keys[0]));
    expect(repo.sent.single..remove('key'), {
      'title': 'تغيير مكان الركوب', 'body': 'الركوب من أمام البنك.',
      'line': 'line-1', 'trip': null, 'date': null,
    });
    expect(find.text('تم إرسال الإشعار إلى 4 طلاب.'), findsOneWidget);
    expect(find.text('رسالة أخرى'), findsNothing, reason: 'both pages closed');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('without a line there is nobody to write to, and the page says so', (tester) async {
    await tester.pumpWidget(sendHost(FakeNotificationsRepo(), dashboard: {..._dashboardJson, 'lines': <dynamic>[]}));
    await openSend(tester);
    expect(find.text('يتاح بعد أن تسند الشركة خطاً إلى حسابك.'), findsOneWidget);
    expect(find.text('رسالة أخرى'), findsNothing);
  });

  test('what was sent is said with the plural the number asks for', () {
    String said(int n) => SupervisorSendScreen.sentMessage((students: n, duplicate: false));
    expect(said(38), 'تم إرسال الإشعار إلى 38 طالباً.');
    expect(said(9), 'تم إرسال الإشعار إلى 9 طلاب.');
    expect(said(2), 'تم إرسال الإشعار إلى طالبين.');
    expect(said(1), 'تم إرسال الإشعار إلى طالب واحد.');
    expect(SupervisorSendScreen.sentMessage((students: 4, duplicate: true)),
        'سبق إرسال هذا الإشعار، ولم يُرسل مرة أخرى.');
  });

  test('a quick template is read from the server and knows which trips it fits', () {
    final template = QuickNotificationTemplate.fromJson({
      'key': 'delay', 'title': 'تأخير الباص', 'body': 'سيتأخر {minutes} دقيقة', 'needs_minutes': true,
      'direction': null,
    });
    expect(template.preview(15), 'سيتأخر 15 دقيقة');
    expect(template.fits('return'), isTrue);
    final back = QuickNotificationTemplate.fromJson({'key': 'r', 'title': 'ع', 'body': 'ب', 'direction': 'return'});
    expect(back.needsMinutes, isFalse);
    expect(back.fits('departure'), isFalse);
    expect(back.fits(null), isTrue, reason: 'the whole line');
    expect(newUuid(), isNot(newUuid()));
  });

  testWidgets('the supervisor inbox: what they sent sits in the same list, marked as theirs', (tester) async {
    final repo = FakeNotificationsRepo([
      _note('a', 'إجازة رسمية'),
      AppNotification(
        id: 'mine', title: 'تأخير في موعد الحافلة', body: 'ستتأخر الحافلة نحو 15 دقيقة.',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        senderRole: 'supervisor', senderName: 'محمود', audience: 'ركاب ذهاب 7:00 ص', read: true, mine: true,
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionUserIdProvider.overrideWithValue('sup'),
        supervisorDashboardProvider.overrideWith(() => _Dashboard()),
        notificationsRepoProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Directionality(
            textDirection: TextDirection.rtl, child: SupervisorNotificationsScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('إجازة رسمية'), findsOneWidget);
    expect(find.text('تأخير في موعد الحافلة'), findsOneWidget);
    expect(find.text('أرسلته أنت · ركاب ذهاب 7:00 ص'), findsOneWidget);
    expect(find.text('ستتأخر الحافلة نحو 15 دقيقة.'), findsNothing, reason: 'its text is one tap away');
    // Writing to the students is a page of its own, reached from Home.
    expect(find.text('أرسل إشعاراً لطلابك'), findsNothing);
  });
}

/// The server's side, with the key of every free-text attempt recorded (also
/// the refused ones, which never reach the fake's list of sent messages).
class _RecordingRepo extends FakeNotificationsRepo {
  final List<Object?> keys;
  _RecordingRepo(this.keys) {
    refusal = 'أرسلت إشعارات كثيرة، انتظر قليلاً ثم حاول مرة أخرى.';
  }

  @override
  Future<SendResult> send({
    required String title,
    required String body,
    required String lineId,
    String? tripId,
    String? rideDate,
    required String idempotencyKey,
  }) {
    keys.add(idempotencyKey);
    return super.send(
        title: title, body: body, lineId: lineId, tripId: tripId, rideDate: rideDate, idempotencyKey: idempotencyKey);
  }
}
