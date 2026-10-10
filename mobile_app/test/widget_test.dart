import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/main.dart';
import 'package:basak_mobile/features/student/lines/models/line_model.dart';
import 'package:basak_mobile/features/student/daily_ride/data/daily_ride_repository.dart';
import 'package:basak_mobile/features/student/daily_ride/models/vote_settings.dart';
import 'package:basak_mobile/features/onboarding/onboarding_controller.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';
import 'package:basak_mobile/features/supervisor/models/supervisor_models.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';

class _FakeDailyRideRepo implements DailyRideRepository {
  @override
  Future<VoteSettings> getVoteSettings(String? companyId) async => VoteSettings.fallback;
  @override
  Future<RideDays> getRides(DateTime from, DateTime to) async => const RideDays({});
  @override
  Future<DailyRideDetails> confirmRide({
    required DateTime rideDate,
    required bool isRiding,
    required String? departureTime,
    required String? returnTime,
    required bool isReturning,
  }) async => DailyRideDetails(
    isRiding: isRiding,
    departureTime: departureTime,
    returnTime: returnTime,
    isReturning: isReturning,
  );
}

void main() {
  test('Egyptian phone numbers share one canonical login format', () {
    expect(AuthRepository.normalizeEgyptianPhone('01012345678'), '01012345678');
    expect(
        AuthRepository.normalizeEgyptianPhone('+20 1012345678'), '01012345678');
    expect(AuthRepository.normalizeEgyptianPhone('1012345678'), '01012345678');
  });

  test('station times accept either text or a list of times', () {
    expect(stationTimes(['07:15:00', '07:00']), ['07:00', '07:15']);
    expect(stationTimes('16:00'), ['16:00']);
    expect(stationTimes(null), isEmpty);
    expect(stationTimesLabel(['07:00', '07:15']), '07:00، 07:15');
    expect(stationTimesLabel('16:00'), '16:00');
  });

  test('the default vote opens at 4 PM and closes at 6 AM on the ride day', () {
    const vote = VoteSettings.fallback;
    final evening = DateTime(2026, 9, 27, 16);
    final beforeDeadline = DateTime(2026, 9, 28, 5, 59);
    final deadline = DateTime(2026, 9, 28, 6);
    final closed = DateTime(2026, 9, 28, 15, 59);

    expect(vote.isOpenAt(evening), isTrue);
    expect(vote.rideDateFor(evening), DateTime(2026, 9, 28));
    expect(vote.isOpenAt(beforeDeadline), isTrue);
    expect(vote.rideDateFor(beforeDeadline), DateTime(2026, 9, 28));
    expect(vote.isOpenAt(deadline), isFalse);
    expect(vote.isOpenAt(closed), isFalse);
    // Closed: today's vote stays on screen until the next one opens.
    expect(vote.rideDateFor(closed), DateTime(2026, 9, 28));
  });

  test('a vote may open and close the same evening', () {
    final vote = VoteSettings.fromJson(
        {'opens_at': '12:00', 'closes_at': '22:30', 'reminder_minutes': 0});
    expect(vote.closesOnRideDay, isFalse);
    expect(vote.isOpenAt(DateTime(2026, 10, 7, 11, 59)), isFalse);
    expect(vote.isOpenAt(DateTime(2026, 10, 7, 12)), isTrue);
    expect(vote.rideDateFor(DateTime(2026, 10, 7, 12)), DateTime(2026, 10, 8));
    expect(vote.isOpenAt(DateTime(2026, 10, 7, 22, 29)), isTrue);
    expect(vote.isOpenAt(DateTime(2026, 10, 7, 22, 30)), isFalse);
    // After it closes, the closed vote's ride day (tomorrow) is shown.
    expect(vote.rideDateFor(DateTime(2026, 10, 7, 23)), DateTime(2026, 10, 8));
    final window = vote.windowFor(DateTime(2026, 10, 8));
    expect(window.opens, DateTime(2026, 10, 7, 12));
    expect(window.closes, DateTime(2026, 10, 7, 22, 30));
  });

  test('reminders run from the opening every interval until the close', () {
    final vote = VoteSettings.fromJson(
        {'opens_at': '16:00', 'closes_at': '06:00', 'reminder_minutes': 180});
    expect(vote.reminderTimesFor(DateTime(2026, 10, 8)), [
      DateTime(2026, 10, 7, 16),
      DateTime(2026, 10, 7, 19),
      DateTime(2026, 10, 7, 22),
      DateTime(2026, 10, 8, 1),
      DateTime(2026, 10, 8, 4),
    ]);
    final once = VoteSettings.fromJson(
        {'opens_at': '18:00', 'closes_at': '23:00', 'reminder_minutes': 1440});
    expect(once.reminderTimesFor(DateTime(2026, 10, 8)), [DateTime(2026, 10, 7, 18)]);
    expect(VoteSettings.fallback.reminderTimesFor(DateTime(2026, 10, 8)), isEmpty);
  });

  test('no reminders on days off: a weekday (Friday) or a holiday', () {
    final vote = VoteSettings.fromJson({
      'opens_at': '16:00',
      'closes_at': '06:00',
      'reminder_minutes': 360,
      'off_weekdays': [5],
      'off_dates': ['2026-10-06'],
    });
    // 9 Oct 2026 is a Friday: its reminders would start on Thursday evening.
    expect(vote.remindsFor(DateTime(2026, 10, 9)), isFalse);
    expect(vote.reminderTimesFor(DateTime(2026, 10, 9)), isEmpty);
    expect(vote.reminderTimesFor(DateTime(2026, 10, 6)), isEmpty);
    expect(vote.reminderTimesFor(DateTime(2026, 10, 8)), [
      DateTime(2026, 10, 7, 16),
      DateTime(2026, 10, 7, 22),
      DateTime(2026, 10, 8, 4),
    ]);
    // Voting itself is not affected.
    expect(vote.isOpenAt(DateTime(2026, 10, 8, 20)), isTrue);
    expect(vote, VoteSettings.fromJson({
      'opens_at': '16:00',
      'closes_at': '06:00',
      'reminder_minutes': 360,
      'off_weekdays': [5],
      'off_dates': ['2026-10-06'],
    }));
  });

  test('vote times read in Arabic', () {
    expect(VoteSettings.fallback.opensLabel, '٤ م');
    expect(VoteSettings.fallback.closesLabel, '٦ ص');
    expect(VoteSettings.clock(6 * 60 + 30, long: true), '٦:٣٠ صباحاً');
    expect(VoteSettings.clock(12 * 60, long: true), '١٢ ظهراً');
    expect(VoteSettings.fallback.windowSentence,
        'التصويت من ٤ مساءً في اليوم السابق حتى ٦ صباحاً يوم الرحلة.');
  });

  testWidgets('Basak opens the Arabic sign-in screen', (tester) async {
    PackageInfo.setMockInitialValues(appName: 'باصك', packageName: 'com.basak.basak_mobile',
        version: '1.0.2', buildNumber: '14', buildSignature: '');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => AuthNotifier(ref.watch(authRepositoryProvider)),
          ),
          // First-launch onboarding is covered separately; start at sign-in.
          onboardingProvider.overrideWith((ref) => OnboardingController.completed()),
        ],
        child: const BasakApp(),
      ),
    );
    // The splash waits up to 0.5 s for its logo (test assets never decode in
    // fake time), then plays for ~3.2 s; it covers the screen until then.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 3200));

    // A phone nobody is signed in on opens on the welcome screen.
    expect(find.text('باصك'), findsOneWidget);
    expect(find.text('اشتراك الباص الجامعي، بكل بساطة.'), findsOneWidget);
    expect(find.text('إنشاء حساب طالب'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    // The installed version, under the ways in.
    expect(find.text('الإصدار 1.0.2'), findsOneWidget);

    // Supervisors have a sign-in of their own: no sign-up, no recovery.
    await tester.tap(find.text('دخول المشرفين'));
    await tester.pumpAndSettle();
    expect(find.text('دخول المشرف'), findsOneWidget);
    expect(find.text('إنشاء حساب'), findsNothing);
    expect(
        find.text('حسابات المشرفين ينشئها مسؤول النظام فقط. لتغيير كلمة المرور تواصل مع إدارة شركتك.'),
        findsOneWidget);
    expect(find.text('نسيت كلمة المرور؟'), findsNothing);
    await tester.tap(find.text('دخول الطلاب'));
    await tester.pumpAndSettle();
    expect(find.text('أهلاً بعودتك'), findsOneWidget);
    expect(find.text('إنشاء حساب'), findsOneWidget);

    // Forgot password (students only) opens the reset screen and comes back.
    await tester.ensureVisible(find.text('نسيت كلمة المرور؟'));
    await tester.tap(find.text('نسيت كلمة المرور؟'));
    await tester.pumpAndSettle();
    expect(find.text('استعادة كلمة المرور'), findsOneWidget);
    expect(find.text('إرسال طلب الاستعادة'), findsOneWidget);
    // A code in hand still needs the phone number it was issued for.
    await tester.enterText(find.byType(TextField), '01012345678');
    await tester.tap(find.text('لديّ رمز بالفعل'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد الرمز'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('إنشاء حساب'));
    await tester.tap(find.text('إنشاء حساب'));
    await tester.pumpAndSettle();
    // Sign-up opens on its first step; the photo and the college have steps of their own.
    expect(find.text('الاسم بالكامل'), findsOneWidget);
    expect(find.text('اسمك كما في بطاقتك الجامعية، ورقم هاتفك هو اسم دخولك.'), findsOneWidget);
    expect(find.text('صورتك'), findsOneWidget);
    expect(find.text('الكلية'), findsNothing);
  });

  test('supervisor dashboard parses students per trip time', () {
    final dashboard = SupervisorDashboard.fromJson({
      'today': '2026-10-03',
      'profile': {'id': 's1', 'full_name': 'مشرف', 'assignment': 'direct'},
      'totals': {'lines': 1},
      'lines': [],
      'trip_times': [
        {'ride_date': '2026-10-03', 'line_id': 'l1', 'line_name': 'خط', 'direction': 'return', 'time': '17:00:00', 'students': 5},
        {'ride_date': '2026-10-03', 'line_id': 'l1', 'line_name': 'خط', 'direction': 'return', 'time': '18:00:00', 'students': 12},
      ],
    });
    expect(dashboard.tripTimes, hasLength(2));
    expect(dashboard.tripTimes.first.isReturn, isTrue);
    expect(dashboard.tripTimes.last.students, 12);
    expect(dashboard.profile.isDirectlyAssigned, isTrue);
  });

  test('a second scan the same day is not a success and carries the message', () {
    final result = CheckInResult.fromJson({
      'result': 'already_checked_in',
      'message': 'This student has already been checked in today.',
      'direction': 'departure',
    });
    expect(result.outcome, CheckInOutcome.alreadyCheckedIn);
    expect(result.outcome.isSuccess, isFalse);
    expect(result.message, contains('already been checked in today'));
  });

  test('return times are shown as the trip start at the university, saved as the stop time', () {
    final sub = SubscriptionModel.fromJson({
      'id': 'x', 'student_id': 's', 'line_id': 'l', 'station_id': 'st', 'type': 'termly',
      'status': 'active', 'price': 3500, 'created_at': '2026-10-01',
      'departure_time': '07:15:00', 'return_time': '13:50:00',
      'return_trip': {'start_time': '12:00:00'},
      'stations': {
        'name': 'ميت تمامه',
        'line_trip_stops': [
          {'stop_time': '07:15:00', 'line_trips': {'direction': 'departure', 'is_active': true, 'start_time': '06:30:00'}},
          {'stop_time': '13:50:00', 'line_trips': {'direction': 'return', 'is_active': true, 'start_time': '12:00:00'}},
          {'stop_time': '16:40:00', 'line_trips': {'direction': 'return', 'is_active': true, 'start_time': '15:00:00'}},
          {'stop_time': '18:00:00', 'line_trips': {'direction': 'return', 'is_active': false, 'start_time': '17:00:00'}},
        ],
      },
    });
    // The choices sent to the server stay the station stop times.
    expect(sub.returnTimes, ['13:50', '16:40']);
    // What the student reads is when the bus leaves the university.
    expect(sub.returnShown('13:50'), '12:00');
    expect(sub.returnShown('16:40'), '15:00');
    expect(sub.returnTimeShown, '12:00');
    // Departure keeps the pickup time at the student's station.
    expect(sub.departureTimes, ['07:15']);
    // A time with no known trip (legacy lines) is shown as it is.
    expect(sub.returnShown('14:30'), '14:30');
  });

  test('a return trip saved without station times serves every station with no times shown', () {
    TripManifest manifest(String stopTime) => TripManifest.fromJson({
          'line': {'id': 'l', 'name': 'خط', 'origin_name': 'المنصورة'},
          'direction': 'return',
          'trips': [],
          'trip': {'id': 't', 'label': '', 'start_time': '14:00:00', 'students': 0},
          'stations': [
            {'id': 's1', 'name': 'المنصورة', 'stop_time': stopTime, 'students': []},
            {'id': 's2', 'name': 'ميت تمامة', 'stop_time': null, 'students': []},
          ],
        });
    expect(manifest('14:00:00').stopTimesUnset, isTrue);
    expect(manifest('16:00:00').stopTimesUnset, isFalse);
  });

  test('subscriptions distinguish current, upcoming and expired periods', () {
    SubscriptionModel sub(String status, String phase) => SubscriptionModel.fromJson({
          'id': 'x', 'student_id': 's', 'line_id': 'l', 'station_id': 'st', 'type': 'termly',
          'status': status, 'price': 3500, 'created_at': '2026-10-01',
          'start_date': '2027-02-01', 'end_date': '2027-06-30',
          'period_code': 'second', 'academic_year': 2026,
          'period_label': 'الفصل الدراسي الثاني 2026/2027', 'period_phase': phase,
        });
    expect(sub('active', 'upcoming').isUpcoming, isTrue);
    expect(sub('active', 'current').isCurrent, isTrue);
    expect(sub('expired', 'expired').isExpired, isTrue);
    expect(sub('pending_payment', 'expired').isExpired, isTrue);
    expect(sub('active', 'upcoming').academicYear, 2026);
  });

  testWidgets('StudentHomeScreen has RefreshIndicator for pull to refresh', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSubscriptionProvider.overrideWith(_NoSubscription.new),
          dailyRideRepoProvider.overrideWithValue(_FakeDailyRideRepo()),
        ],
        child: MaterialApp(
          home: StudentHomeScreen(
            onNavigateToSubscription: () {},
            onNavigateToQr: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });
}

/// No current subscription, without touching the server or the saved copy.
class _NoSubscription extends CurrentSubscriptionNotifier {
  @override
  Future<SubscriptionModel?> build() async => null;
}
