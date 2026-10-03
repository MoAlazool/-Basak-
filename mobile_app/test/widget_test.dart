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
    await tester.pump(const Duration(milliseconds: 250));

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
    expect(find.text('الاسم بالكامل (ثلاثي أو رباعي)'), findsOneWidget);
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
}
