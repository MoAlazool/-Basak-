import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/main.dart';
import 'package:basak_mobile/features/student/lines/models/line_model.dart';
import 'package:basak_mobile/features/student/daily_ride/data/daily_ride_repository.dart';
import 'package:basak_mobile/features/onboarding/onboarding_controller.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';
import 'package:basak_mobile/features/supervisor/models/supervisor_models.dart';
import 'package:basak_mobile/features/student/lines/models/trip_model.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';

class _FakeDailyRideRepo implements DailyRideRepository {
  @override
  DateTime rideDateForCurrentWindow([DateTime? now]) => DateTime(2026, 10, 4);
  @override
  bool isVotingOpen([DateTime? now]) => true;
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
    final station = StationModel.fromJson({
      'id': 'station-1',
      'line_id': 'line-1',
      'name': 'محطة الجامعة',
      'order_index': 1,
      'departure_times': ['07:00', '07:15'],
      'return_times': '16:00',
    });

    expect(station.departureTime, '07:00، 07:15');
    expect(station.returnTime, '16:00');
  });

  test('ride voting opens at 4 PM and closes at 6 AM for the ride date', () {
    final evening = DateTime(2026, 9, 27, 16);
    final beforeDeadline = DateTime(2026, 9, 28, 5, 59);
    final deadline = DateTime(2026, 9, 28, 6);
    final closed = DateTime(2026, 9, 28, 15, 59);

    expect(DailyRideRepository.isVotingOpenAt(evening), isTrue);
    expect(DailyRideRepository.rideDateFor(evening), DateTime(2026, 9, 28));
    expect(DailyRideRepository.isVotingOpenAt(beforeDeadline), isTrue);
    expect(
        DailyRideRepository.rideDateFor(beforeDeadline), DateTime(2026, 9, 28));
    expect(DailyRideRepository.isVotingOpenAt(deadline), isFalse);
    expect(DailyRideRepository.isVotingOpenAt(closed), isFalse);
  });

  testWidgets('Basak opens the Arabic sign-in screen', (tester) async {
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

    expect(find.text('باصك | Basak'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    await tester.tap(find.text('مشرف'));
    await tester.pump();
    expect(find.text('إنشاء حساب جديد'), findsNothing);
    expect(
        find.text('حسابات المشرفين ينشئها مسؤول النظام فقط.'), findsOneWidget);
    expect(find.text('نسيت كلمة المرور؟'), findsNothing);
    await tester.tap(find.text('طالب'));
    await tester.pump();
    expect(find.text('إنشاء حساب جديد'), findsOneWidget);

    // Forgot password (students only) opens the reset screen and comes back.
    await tester.ensureVisible(find.text('نسيت كلمة المرور؟'));
    await tester.tap(find.text('نسيت كلمة المرور؟'));
    await tester.pumpAndSettle();
    expect(find.text('استعادة كلمة المرور'), findsOneWidget);
    expect(find.text('إرسال طلب الاستعادة'), findsOneWidget);
    await tester.tap(find.text('لديّ رمز بالفعل'));
    await tester.pump();
    expect(find.text('تعيين كلمة المرور'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('إنشاء حساب جديد'));
    await tester.tap(find.text('إنشاء حساب جديد'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('الاسم بالكامل'), findsOneWidget);
    expect(find.text('ثلاثي أو رباعي كما في بطاقتك الجامعية.'), findsOneWidget);
    expect(find.text('الصورة الشخصية'), findsOneWidget);
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
    TripModel trip(String direction, Map<String, String> stops) => TripModel.fromJson({
          'id': 't', 'direction': direction, 'label': '', 'start_time': '14:00:00',
          'line_trip_stops': [
            for (final e in stops.entries) {'station_id': e.key, 'stop_time': e.value},
          ],
        });
    // Saved by the dashboard with every stop at the start time.
    expect(trip('return', {'a': '14:00:00', 'b': '14:00:00'}).stopTimesUnset, isTrue);
    expect(trip('return', {'a': '14:00:00', 'b': '14:00:00'}).timeAt('a'), '14:00');
    // Real station times are shown as before.
    expect(trip('return', {'a': '14:30:00', 'b': '14:50:00'}).stopTimesUnset, isFalse);
    // Departure trips always carry their pickup times.
    expect(trip('departure', {'a': '14:00:00'}).stopTimesUnset, isFalse);

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

    final period = PurchasablePeriod.fromJson({
      'period_code': 'second', 'academic_year': 2026, 'label': 'الفصل الدراسي الثاني 2026/2027',
      'subscription_type': 'termly', 'start_date': '2027-02-01', 'end_date': '2027-06-30', 'phase': 'upcoming',
    });
    expect(period.isUpcoming, isTrue);
    expect(period.key, 'second:2026');
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
