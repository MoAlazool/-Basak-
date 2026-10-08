import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/features/student/daily_ride/data/daily_ride_repository.dart';
import 'package:basak_mobile/features/student/daily_ride/data/reminder_days_off.dart';
import 'package:basak_mobile/features/student/daily_ride/models/vote_settings.dart';
import 'package:basak_mobile/features/student/home/presentation/notifications_screen.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';

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

/// Starts empty instead of reading the phone's storage (no plugin in tests).
class _DaysOffInMemory extends ReminderDaysOffNotifier {
  @override
  Future<Set<DateTime>> build() async => {};
}

Widget _app(Widget home, {String? status = 'active'}) => ProviderScope(
      overrides: [
        sessionUserIdProvider.overrideWithValue('student-1'),
        currentSubscriptionProvider.overrideWith(() => _Subscription(status)),
        voteSettingsProvider.overrideWith((ref) async => _reminding),
        dailyRideRepoProvider.overrideWithValue(_FakeDailyRideRepo()),
        reminderDaysOffProvider.overrideWith(_DaysOffInMemory.new),
      ],
      child: MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: home),
      ),
    );

void main() {
  test('good morning until noon, good evening after', () {
    String at(int hour, [int minute = 0]) =>
        StudentHomeScreen.greetingFor(DateTime(2026, 10, 8, hour, minute));
    expect(at(7), 'صباح الخير');
    expect(at(11, 59), 'صباح الخير');
    expect(at(12), 'مساء الخير');
    expect(at(21), 'مساء الخير');
    expect(at(3), 'مساء الخير');
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
      daysOff: {DateTime(2026, 10, 11)},
    );
    expect(days.map((d) => d.day.day), [9, 10, 11, 12, 13, 14, 15]);
    expect(days.map((d) => d.state), [
      ReminderDayState.dayOff, // Friday: the company's weekly day off
      ReminderDayState.voted,
      ReminderDayState.off, // switched off by the student
      ReminderDayState.on,
      ReminderDayState.dayOff, // a holiday
      ReminderDayState.on,
      ReminderDayState.outside, // after the subscription ends
    ]);

    // 5 PM: Friday's vote is open now, so the strip still starts Friday.
    final evening = reminderDays(
      vote: vote,
      now: DateTime(2026, 10, 8, 17),
      validFrom: null,
      validUntil: null,
      voted: const {},
      daysOff: const {},
    );
    expect(evening.first.day, DateTime(2026, 10, 9));

    // Reminders switched off by the company: voted days still show as voted.
    final noReminders = reminderDays(
      vote: const VoteSettings(opensAt: 16 * 60, closesAt: 6 * 60),
      now: DateTime(2026, 10, 8, 17),
      validFrom: null,
      validUntil: null,
      voted: {DateTime(2026, 10, 9): true},
      daysOff: const {},
    );
    expect(noReminders.take(2).map((d) => d.state),
        [ReminderDayState.voted, ReminderDayState.companyOff]);
  });

  testWidgets('a day chip switches its reminders off and back on', (tester) async {
    await tester.pumpWidget(_app(const NotificationsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('فعّل التذكير لأيام محددة'), findsOneWidget);
    expect(find.text('لا توجد إشعارات بعد'), findsOneWidget);
    final reminded = find.text('تذكير مفعّل');
    expect(reminded, findsWidgets);
    final before = tester.widgetList(reminded).length;

    await tester.tap(reminded.first);
    await tester.pumpAndSettle();
    expect(find.text('التذكير متوقف'), findsOneWidget);
    expect(tester.widgetList(find.text('تذكير مفعّل')).length, before - 1);

    await tester.tap(find.text('التذكير متوقف'));
    await tester.pumpAndSettle();
    expect(find.text('التذكير متوقف'), findsNothing);
  });

  testWidgets('without an active subscription there is no day strip', (tester) async {
    await tester.pumpWidget(_app(const NotificationsScreen(), status: null));
    await tester.pumpAndSettle();
    expect(find.text('التذكيرات تعمل بعد تفعيل اشتراكك.'), findsOneWidget);
    expect(find.text('تذكير مفعّل'), findsNothing);
  });

  testWidgets('the bell on the home screen opens the notifications', (tester) async {
    await tester.pumpWidget(_app(
      StudentHomeScreen(onNavigateToSubscription: () {}, onNavigateToQr: () {}),
      status: null,
    ));
    await tester.pump();
    await tester.tap(find.byIcon(LucideIcons.bell));
    await tester.pumpAndSettle();
    expect(find.text('الإشعارات'), findsOneWidget);
    expect(find.text('مسح الكل'), findsOneWidget);
  });
}
