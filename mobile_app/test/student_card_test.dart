// The student's card tab ("بطاقتي"): what a supervisor reads off the phone in
// each state of the subscription, and the read-only details sheet.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/features/student/daily_ride/data/daily_ride_repository.dart';
import 'package:basak_mobile/features/student/qr/data/student_qr_repository.dart';
import 'package:basak_mobile/features/student/qr/presentation/card_facts.dart';
import 'package:basak_mobile/features/student/qr/presentation/student_qr_screen.dart';

StudentPassDetails pass(String? status, {String phase = 'current'}) => StudentPassDetails(
    qrValue: 'QR-1', fullName: 'سارة أحمد محمود', phone: '01023456789',
    university: 'جامعة المنصورة الجديدة', college: 'الهندسة',
    lineName: status == null ? null : 'الزرقا', stationName: status == null ? null : 'كوبري السرو',
    subscriptionId: status == null ? null : 'sub1', subscriptionStatus: status,
    periodPhase: status == null ? null : phase, periodName: status == null ? null : 'الفصل الأول',
    academicYear: status == null ? null : 2026, startDate: status == null ? null : '2026-09-20',
    endDate: status == null ? null : '2027-01-14', companyName: status == null ? null : 'النورس للنقل',
    returnStartTimes: const {'16:10': '15:30'});

const riding = DailyRideDetails(isRiding: true, departureTime: '07:23:00', returnTime: '16:10:00');

Future<void> open(WidgetTester tester, StudentPassDetails? details,
    {Size size = const Size(390, 844), Object? error, double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      studentQrProvider.overrideWith((ref) async => error == null ? details : throw error),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      ),
      // Framed as in the app: the floating tab bar over the page's bottom.
      home: const Scaffold(extendBody: true, body: StudentQrScreen(), bottomNavigationBar: SizedBox(height: 84)),
    ),
  ));
  await tester.pumpAndSettle();
}

String chip(WidgetTester tester) {
  final found = find.descendant(of: find.byType(StatusChip), matching: find.byType(Text));
  return tester.widget<Text>(found.first).data!;
}

const wallet = 'إضافة إلى Google Wallet';

void main() {
  setUp(() {
    KnownRides.clear();
    KnownRides.debugUserId = 'me';
  });
  tearDown(() {
    KnownRides.clear();
    KnownRides.debugUserId = null;
  });

  testWidgets('an active card: who, the code, valid until, the four facts and the wallet', (tester) async {
    await open(tester, pass('active'));
    expect(find.text('بطاقتي'), findsOneWidget);
    expect(find.text('تعمل بدون إنترنت'), findsOneWidget);
    expect(find.text('سارة أحمد محمود'), findsOneWidget);
    expect(find.text('الهندسة · جامعة المنصورة الجديدة'), findsOneWidget);
    expect(find.byKey(const Key('student-qr')), findsOneWidget);
    expect(chip(tester), 'اشتراك نشط');
    expect(find.text('حتى 14 يناير 2027'), findsOneWidget);
    for (final text in ['الخط', 'الزرقا', 'محطة الصعود', 'كوبري السرو', 'الفترة', 'الفصل الأول', 'الشركة', 'النورس للنقل']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text(wallet), findsOneWidget);
    expect(find.text('كل التفاصيل'), findsOneWidget);
    // The phone number stays off the face of the card.
    expect(find.textContaining('010'), findsNothing);
    expect(find.byKey(const Key('card-ride')), findsNothing, reason: 'the ride of today is not known yet');
    expect(find.byKey(const Key('card-receipt')), findsNothing);
  });

  testWidgets('the status bar icons are light on the ink ground', (tester) async {
    await open(tester, pass('active'));
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(find
        .ancestor(of: find.text('بطاقتي'), matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>))
        .first);
    expect(region.value.statusBarIconBrightness, Brightness.light);
    expect(region.value.statusBarBrightness, Brightness.dark);
  });

  testWidgets('the ride of today appears once the phone knows it, and follows the vote', (tester) async {
    await open(tester, pass('active'));
    final today = DateTime.now();

    KnownRides.read('me', today, today, const RideDays({}));
    await tester.pump();
    expect(find.byKey(const Key('card-ride')), findsOneWidget);
    expect(find.text('لم يؤكّد رحلة اليوم'), findsOneWidget);
    expect(find.text(TodayRide(today, null).title), findsOneWidget);

    KnownRides.voted('me', today, riding);
    await tester.pump();
    expect(find.text('ذهاب 7:23 ص · عودة 3:30 م'), findsOneWidget,
        reason: 'the return is shown as the time the bus leaves the university');

    KnownRides.voted('me', today,
        const DailyRideDetails(isRiding: true, departureTime: '07:23:00', returnTime: null, isReturning: false));
    await tester.pump();
    expect(find.text('ذهاب 7:23 ص'), findsOneWidget);

    // Another student's votes are never shown.
    KnownRides.debugUserId = 'someone-else';
    expect(TodayRide.known(), isNull);
  });

  testWidgets('under review: the status colour, not active yet, the receipt, no wallet', (tester) async {
    await open(tester, pass('pending_review'));
    expect(chip(tester), 'قيد المراجعة');
    expect(find.text('غير مفعّل بعد'), findsOneWidget);
    expect(find.textContaining('حتى'), findsNothing);
    expect(find.byKey(const Key('card-receipt')), findsOneWidget);
    expect(find.text('الإيصال'), findsOneWidget);
    expect(find.text(wallet), findsNothing);
    expect(find.text('كل التفاصيل'), findsOneWidget);
    expect(tester.widget<PhotoRing>(find.byType(PhotoRing)).ring, BasakPalette.pendingRing);
    expect(find.byKey(const Key('student-qr')), findsOneWidget, reason: 'the code is who the student is');

    // A vote known for today is not shown on a card that is not valid.
    KnownRides.voted('me', DateTime.now(), riding);
    await tester.pump();
    expect(find.byKey(const Key('card-ride')), findsNothing);
  });

  test('the receipt fact reads when it was sent', () {
    final now = DateTime(2026, 10, 11, 18);
    expect(CardDates.sent(DateTime(2026, 10, 11, 15, 40).toIso8601String(), now), 'أُرسل اليوم 3:40 م');
    expect(CardDates.sent(DateTime(2026, 10, 9, 9, 5).toIso8601String(), now), 'أُرسل 9 أكتوبر 9:05 ص');
  });

  testWidgets('expired: the chip says so and the card never looks valid', (tester) async {
    await open(tester, pass('expired', phase: 'expired'));
    expect(chip(tester), 'منتهٍ');
    expect(find.text('انتهى 14 يناير 2027'), findsOneWidget);
    expect(find.textContaining('حتى'), findsNothing);
    expect(find.text(wallet), findsNothing);
    expect(tester.widget<PhotoRing>(find.byType(PhotoRing)).ring, BasakPalette.grabber);

    // Approved once, but its period is over.
    await open(tester, pass('active', phase: 'expired'));
    expect(chip(tester), 'منتهٍ');
    expect(find.text(wallet), findsNothing);
  });

  testWidgets('no subscription: the student and the code, and nothing that looks valid', (tester) async {
    await open(tester, pass(null));
    expect(chip(tester), 'لا يوجد اشتراك');
    expect(find.text('غير مفعّل بعد'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(4));
    expect(find.text(wallet), findsNothing);
    expect(find.byKey(const Key('student-qr')), findsOneWidget);
  });

  testWidgets('the other waiting states keep their own label', (tester) async {
    await open(tester, pass('pending_payment'));
    expect(chip(tester), 'بانتظار الدفع');
    await open(tester, pass('rejected'));
    expect(chip(tester), 'إيصال مرفوض');
    await open(tester, pass('active', phase: 'upcoming'));
    expect(chip(tester), 'يبدأ قريباً');
    expect(find.text('غير مفعّل بعد'), findsOneWidget);
    expect(find.text(wallet), findsNothing);
  });

  testWidgets('no card to show: why, and a way to try again', (tester) async {
    await open(tester, null);
    expect(find.text('البطاقة غير متاحة حالياً'), findsOneWidget);
    expect(find.text('تعذّر تجهيز بطاقتك. سجّل دخولك مرة أخرى، أو تواصل مع الدعم.'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.byKey(const Key('student-qr')), findsNothing);
    expect(find.text('كل التفاصيل'), findsNothing);
    expect(find.text('تعمل بدون إنترنت'), findsNothing);

    await open(tester, const StudentPassDetails(qrValue: '', fullName: 'سارة'));
    expect(find.text('البطاقة غير متاحة حالياً'), findsOneWidget);

    await open(tester, null, error: Exception('boom'));
    expect(find.text('تعذّر تحميل البطاقة'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.byKey(const Key('student-qr')), findsNothing);
  });

  testWidgets('"كل التفاصيل" opens a read-only sheet with the three groups', (tester) async {
    final today = DateTime.now();
    KnownRides.voted('me', today, riding);
    await open(tester, pass('active'));
    await tester.tap(find.byKey(const Key('card-details-open')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('card-details'));
    expect(sheet, findsOneWidget);
    Finder inSheet(String text) => find.descendant(of: sheet, matching: find.text(text));
    for (final text in [
      'سارة أحمد محمود', 'اشتراك نشط',
      'بيانات الطالب', 'الجامعة', 'جامعة المنصورة الجديدة', 'الكلية', 'الهندسة', 'الهاتف', '010 2345 6789',
      'الاشتراك', 'الخط', 'الزرقا', 'محطة الصعود', 'كوبري السرو', 'الشركة', 'النورس للنقل', 'الفترة',
      'الصلاحية', '20 سبتمبر – 14 يناير 2027',
      TodayRide(today, null).title, 'الذهاب', '7:23 ص', 'العودة', '3:30 م',
    ]) {
      expect(inSheet(text), findsOneWidget, reason: text);
    }
    expect(find.descendant(of: sheet, matching: find.textContaining('2026 / 2027')), findsOneWidget);
    // Read-only: nothing to press but the way out.
    expect(find.descendant(of: sheet, matching: find.byType(BasakButton)), findsNothing);
    expect(find.descendant(of: sheet, matching: find.byType(TextField)), findsNothing);

    await tester.tap(find.byKey(const Key('card-details-close')));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
  });

  testWidgets('the sheet of a student without a subscription has only their own data', (tester) async {
    await open(tester, pass(null));
    await tester.tap(find.byKey(const Key('card-details-open')));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('card-details'));
    expect(find.descendant(of: sheet, matching: find.text('بيانات الطالب')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('لا يوجد اشتراك')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('الاشتراك')), findsNothing);
    expect(find.descendant(of: sheet, matching: find.textContaining('رحلة اليوم')), findsNothing);
  });

  for (final size in const [Size(320, 568), Size(360, 640), Size(375, 667), Size(390, 844), Size(430, 932), Size(820, 1180)]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('nothing overflows at ${size.width.toInt()}x${size.height.toInt()}, text x$scale', (tester) async {
        KnownRides.voted('me', DateTime.now(), riding);
        for (final details in [pass('active'), pass('pending_review'), pass(null), null]) {
          await open(tester, details, size: size, textScale: scale);
          expect(tester.takeException(), isNull);
          if (details == null) continue;
          final qr = tester.getSize(find.byKey(const Key('student-qr')));
          expect(qr.width, greaterThanOrEqualTo(100), reason: 'the code stays large enough to scan');
          expect(qr.width, qr.height);
          await tester.ensureVisible(find.byKey(const Key('card-details-open')));
          await tester.tap(find.byKey(const Key('card-details-open')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('on a 360 x 640 phone the page is fixed and the code is still large', (tester) async {
    await open(tester, pass('active'), size: const Size(360, 640));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scroll.position.maxScrollExtent, 0);
    expect(tester.getSize(find.byKey(const Key('student-qr'))).width, greaterThan(130));
    expect(tester.getSize(find.byKey(const Key('card-details-open'))).height, greaterThanOrEqualTo(48));
  });
}
