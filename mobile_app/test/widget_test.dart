import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/main.dart';
import 'package:basak_mobile/features/student/lines/models/line_model.dart';
import 'package:basak_mobile/features/student/daily_ride/data/daily_ride_repository.dart';

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
    await tester.tap(find.text('طالب'));
    await tester.pump();
    expect(find.text('إنشاء حساب جديد'), findsOneWidget);
    await tester.ensureVisible(find.text('إنشاء حساب جديد'));
    await tester.tap(find.text('إنشاء حساب جديد'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('الاسم بالكامل (ثلاثي أو رباعي)'), findsOneWidget);
    expect(find.text('الصورة الشخصية'), findsOneWidget);
    expect(find.text('الكلية'), findsNothing);
  });
}
