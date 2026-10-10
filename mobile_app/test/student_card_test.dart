// The student's card tab ("بطاقتي"): what a supervisor reads off the phone in
// each state of the subscription, and its back: everything else it knows,
// one tap away.
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

Finder get front => find.byKey(const Key('card-front'));
Finder get back => find.byKey(const Key('card-back'));
Finder onBack(String text) => find.descendant(of: back, matching: find.text(text));

/// Turns the card over with the button under it and waits for it to land.
Future<void> flip(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('card-flip')));
  await tester.tap(find.byKey(const Key('card-flip')));
  await tester.pumpAndSettle();
}

/// Whether [side] is the one that can be seen, tapped and read aloud.
bool showing(WidgetTester tester, Finder side) {
  final opacity = tester.widget<Opacity>(find.ancestor(of: side, matching: find.byType(Opacity)).first).opacity;
  final ignoring =
      tester.widget<IgnorePointer>(find.ancestor(of: side, matching: find.byType(IgnorePointer)).first).ignoring;
  return opacity == 1 && !ignoring;
}

void main() {
  setUp(() {
    KnownRides.clear();
    KnownRides.debugUserId = 'me';
  });
  tearDown(() {
    KnownRides.clear();
    KnownRides.debugUserId = null;
  });

  testWidgets('an active card: who, the code, valid until and the wallet; the facts are on its back', (tester) async {
    await open(tester, pass('active'));
    expect(find.text('بطاقتي'), findsOneWidget);
    expect(find.text('تعمل بدون إنترنت'), findsOneWidget);
    expect(find.text('سارة أحمد محمود'), findsOneWidget);
    // The college and the university, each whole (see the long-name tests below).
    expect(find.descendant(of: find.byType(SchoolLine), matching: find.textContaining('الهندسة')), findsOneWidget);
    expect(find.descendant(of: find.byType(SchoolLine), matching: find.textContaining('جامعة المنصورة الجديدة')),
        findsOneWidget);
    expect(find.byKey(const Key('student-qr')), findsOneWidget);
    expect(chip(tester), 'اشتراك نشط');
    expect(find.text('حتى 14 يناير 2027'), findsOneWidget);
    // The face is who and the code; the line, the stop and the rest are behind it.
    expect(back, findsNothing);
    for (final text in ['الخط', 'الزرقا', 'محطة الصعود', 'كوبري السرو', 'الفترة', 'الشركة', 'النورس للنقل']) {
      expect(find.text(text), findsNothing, reason: text);
    }
    expect(find.text(wallet), findsOneWidget);
    expect(find.text('التفاصيل'), findsOneWidget);
    expect(find.text('اضغط البطاقة لعرض التفاصيل'), findsOneWidget);
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
    expect(find.text('التفاصيل'), findsOneWidget);
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
    expect(find.byKey(const Key('card-flip')), findsNothing);
    expect(find.text('تعمل بدون إنترنت'), findsNothing);

    await open(tester, const StudentPassDetails(qrValue: '', fullName: 'سارة'));
    expect(find.text('البطاقة غير متاحة حالياً'), findsOneWidget);

    await open(tester, null, error: Exception('boom'));
    expect(find.text('تعذّر تحميل البطاقة'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.byKey(const Key('student-qr')), findsNothing);
  });

  group('the back of the card', () {
    testWidgets('a tap turns the card over to its three groups, and a tap turns it back', (tester) async {
      final today = DateTime.now();
      KnownRides.voted('me', today, riding);
      await open(tester, pass('active'));
      expect(showing(tester, front), isTrue);

      // The card itself is the button.
      await tester.tap(front);
      await tester.pumpAndSettle();
      expect(showing(tester, back), isTrue);
      expect(showing(tester, front), isFalse, reason: 'the face is neither seen nor tapped behind the back');
      for (final text in [
        'تفاصيل البطاقة', 'اشتراك نشط',
        'الاشتراك', 'الخط', 'الزرقا', 'محطة الصعود', 'كوبري السرو', 'الشركة', 'النورس للنقل', 'الفترة',
        'الصلاحية', '20 سبتمبر – 14 يناير 2027',
        'بيانات الطالب', 'الجامعة', 'جامعة المنصورة الجديدة', 'الكلية', 'الهندسة', 'الهاتف',
        TodayRide(today, null).title, 'الذهاب', '7:23 ص', 'العودة', '3:30 م',
      ]) {
        expect(onBack(text), findsOneWidget, reason: text);
      }
      expect(find.descendant(of: back, matching: find.textContaining('2026 / 2027')), findsOneWidget);
      expect(find.descendant(of: back, matching: find.textContaining('010 2345 6789')), findsOneWidget);
      // Read-only: nothing to fill in or press on it.
      expect(find.descendant(of: back, matching: find.byType(BasakButton)), findsNothing);
      expect(find.descendant(of: back, matching: find.byType(TextField)), findsNothing);
      // The button under the card now leads back to the code.
      expect(find.text('الرمز'), findsOneWidget);
      expect(find.text('التفاصيل'), findsNothing);

      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(back, findsNothing);
      expect(showing(tester, front), isTrue);
      expect(find.text('التفاصيل'), findsOneWidget);
    });

    testWidgets('half way round the card is in perspective; at rest the code is drawn untouched', (tester) async {
      await open(tester, pass('active'));
      Finder turned() => find.byKey(const Key('card-turn'));
      expect(turned(), findsNothing, reason: 'nothing stands between the code and the screen');
      final side = tester.getSize(find.byKey(const Key('student-qr')));

      await tester.tap(find.byKey(const Key('card-flip')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final matrix = tester.widget<Transform>(turned().first).transform;
      expect(matrix.entry(3, 2), isNot(0), reason: 'perspective');
      expect(showing(tester, front), isTrue, reason: 'the face until the card is edge-on');
      await tester.pump(const Duration(milliseconds: 200));
      expect(showing(tester, back), isTrue);
      await tester.pumpAndSettle();
      expect(turned(), findsNothing);
      expect(tester.getSize(back), tester.getSize(front), reason: 'both sides are one card');

      await flip(tester);
      expect(turned(), findsNothing);
      expect(tester.getSize(find.byKey(const Key('student-qr'))), side);
    });

    testWidgets('a screen reader gets a button that says what turning shows', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, pass('active'));
      expect(
        tester.getSemantics(find.bySemanticsLabel('اقلب البطاقة لعرض التفاصيل')),
        matchesSemantics(label: 'اقلب البطاقة لعرض التفاصيل', isButton: true, isEnabled: true,
            hasEnabledState: true, hasTapAction: true),
      );
      expect(find.bySemanticsLabel(RegExp('رمز QR للطالب')), findsOneWidget);

      await flip(tester);
      expect(find.bySemanticsLabel('اقلب البطاقة لعرض رمز QR'), findsOneWidget);
      expect(find.bySemanticsLabel('اقلب البطاقة لعرض التفاصيل'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('رمز QR للطالب')), findsNothing, reason: 'the hidden face is not read aloud');
      expect(find.bySemanticsLabel(RegExp('تفاصيل البطاقة')), findsWidgets);
      handle.dispose();
    });

    testWidgets('with reduce motion the sides fade into each other and nothing turns', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await open(tester, pass('active'));

      await tester.tap(find.byKey(const Key('card-flip')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const Key('card-turn')), findsNothing);
      final fading =
          tester.widget<Opacity>(find.ancestor(of: front, matching: find.byType(Opacity)).first).opacity;
      expect(fading, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(showing(tester, back), isTrue);
    });

    testWidgets('left on its back, the card is on its face again when the tab is left or the phone put away',
        (tester) async {
      final onShow = ValueNotifier(true);
      addTearDown(onShow.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [studentQrProvider.overrideWith((ref) async => pass('active'))],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: ValueListenableBuilder<bool>(
              valueListenable: onShow,
              builder: (context, visible, _) => Scaffold(body: StudentQrScreen(visible: visible)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await flip(tester);
      expect(showing(tester, back), isTrue);

      // Another tab is opened: no turn to watch, the code is simply there.
      onShow.value = false;
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(back, findsNothing);
      expect(showing(tester, front), isTrue);
      expect(find.text('التفاصيل'), findsOneWidget);

      onShow.value = true;
      await tester.pump();
      await flip(tester);
      // Nothing is drawn while the app is away; it comes back on the code.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(back, findsNothing);
      expect(showing(tester, front), isTrue);
    });

    testWidgets('a student without a subscription has only their own data on it', (tester) async {
      await open(tester, pass(null));
      await flip(tester);
      expect(onBack('بيانات الطالب'), findsOneWidget);
      expect(onBack('لا يوجد اشتراك'), findsOneWidget);
      expect(onBack('الاشتراك'), findsNothing);
      expect(find.descendant(of: back, matching: find.textContaining('رحلة اليوم')), findsNothing);
    });
  });

  group('the college and the university', () {
    const longCollege = 'كلية الحاسبات والمعلومات والذكاء الاصطناعي وعلوم البيانات';
    const longUniversity = 'جامعة المنصورة الجديدة الأهلية للعلوم والتكنولوجيا';

    Future<void> school(WidgetTester tester, {String? college, String? university, double width = 240, double scale = 1}) =>
        tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: SizedBox(width: width, child: SchoolLine(college: college, university: university)),
                ),
              ),
            ),
          ),
        ));

    testWidgets('short names share a line, with a dot between them', (tester) async {
      await school(tester, college: 'طب', university: 'طنطا', width: 300);
      expect(find.text('طب · طنطا'), findsOneWidget);
    });

    testWidgets('names that do not fit one line each get a line: never glued, never one cut for the other',
        (tester) async {
      for (final scale in [1.0, 1.3]) {
        await school(tester, college: longCollege, university: longUniversity, scale: scale);
        expect(tester.takeException(), isNull);
        expect(find.textContaining(' · '), findsNothing);
        final college = tester.getRect(find.text(longCollege));
        final university = tester.getRect(find.text(longUniversity));
        expect(university.top, greaterThanOrEqualTo(college.bottom), reason: 'the university is under the college');
        // RTL: both start at the right edge, and neither leaves its box.
        expect(college.right, university.right);
        expect(college.width, lessThanOrEqualTo(240));
        expect(university.width, lessThanOrEqualTo(240));
        for (final name in [longCollege, longUniversity]) {
          final line = tester.widget<Text>(find.text(name));
          expect(line.maxLines, 1);
          expect(line.overflow, TextOverflow.ellipsis);
        }
      }
    });

    testWidgets('a short college beside a long university still breaks cleanly', (tester) async {
      await school(tester, college: 'الهندسة', university: longUniversity);
      expect(find.text('الهندسة'), findsOneWidget);
      expect(find.text(longUniversity), findsOneWidget);
    });

    testWidgets('one of the two alone is shown alone, and none takes no room', (tester) async {
      await school(tester, college: '  ', university: longUniversity);
      expect(tester.widget<Text>(find.text(longUniversity)).maxLines, 2);
      await school(tester);
      expect(tester.getSize(find.byType(SchoolLine)).height, 0);
    });

    testWidgets('on the card: long names stay inside it at the largest text, and the code is still large',
        (tester) async {
      final details = StudentPassDetails(
          qrValue: 'QR-1', fullName: 'عبد الرحمن محمد عبد الفتاح السيد', university: longUniversity,
          college: longCollege, lineName: 'الزرقا', stationName: 'كوبري السرو', subscriptionId: 'sub1',
          subscriptionStatus: 'active', periodPhase: 'current', periodName: 'الفصل الأول', endDate: '2027-01-14');
      for (final size in const [Size(320, 568), Size(390, 844)]) {
        await open(tester, details, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);
        final card = tester.getRect(front);
        for (final name in [longCollege, longUniversity]) {
          final rect = tester.getRect(find.descendant(of: front, matching: find.text(name)));
          expect(rect.left, greaterThanOrEqualTo(card.left));
          expect(rect.right, lessThanOrEqualTo(card.right));
        }
        expect(tester.getSize(find.byKey(const Key('student-qr'))).width, greaterThanOrEqualTo(100));
        // And whole, on two lines each, on the back.
        await flip(tester);
        expect(tester.takeException(), isNull);
        expect(onBack(longCollege), findsOneWidget);
        expect(onBack(longUniversity), findsOneWidget);
      }
    });
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
          await flip(tester);
          expect(tester.takeException(), isNull);
          expect(tester.getSize(back), tester.getSize(front));
        }
      });
    }
  }

  testWidgets('on a 360 x 640 phone the page is fixed and the code is still large', (tester) async {
    await open(tester, pass('active'), size: const Size(360, 640));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scroll.position.maxScrollExtent, 0);
    expect(tester.getSize(find.byKey(const Key('student-qr'))).width, greaterThan(130));
    expect(tester.getSize(find.byKey(const Key('card-flip'))).height, greaterThanOrEqualTo(48));
  });
}
