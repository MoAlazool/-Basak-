import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/features/supervisor/data/supervisor_repository.dart';
import 'package:basak_mobile/features/supervisor/models/supervisor_models.dart';
import 'package:basak_mobile/features/supervisor/qr_scanner/models/scanned_student_details.dart';
import 'package:basak_mobile/features/supervisor/qr_scanner/presentation/scan_result_sheet.dart';
import 'package:basak_mobile/features/supervisor/qr_scanner/presentation/scan_session.dart';
import 'package:basak_mobile/features/supervisor/qr_scanner/presentation/scanner_view.dart';

/// The server's answer to a scan, decided by the test. Everything else of the
/// repository is never reached from the scanner.
class _Repo extends SupervisorRepository {
  CheckInResult? answer;
  Object? failure;
  final scans = <({String code, String direction, String? tripId})>[];

  @override
  Future<CheckInResult> checkIn(String qrValue, {required String direction, String? tripId}) async {
    scans.add((code: qrValue, direction: direction, tripId: tripId));
    if (failure != null) throw failure!;
    return answer!;
  }

  @override
  Future<TripManifest> getTripManifest({required String lineId, required String direction, String? tripId}) async =>
      TripManifest.fromJson({
        'line': {'id': lineId, 'name': 'الزرقا'},
        'direction': direction,
        'trip': {'id': tripId, 'label': '', 'start_time': '07:00:00', 'students': 3},
        'stations': [
          {
            'id': 'st-1',
            'name': 'كوبري السرو',
            'students': [
              {'id': 'a', 'full_name': 'سارة', 'checked_in_at': '2026-10-11T07:02:00'},
              {'id': 'b', 'full_name': 'يوسف'},
              {'id': 'c', 'full_name': 'عمر'},
            ],
          },
        ],
      });
}

ScannedStudentDetails _student(String name, {String? status = 'active', bool cached = false}) => ScannedStudentDetails(
      id: 'student-1',
      fullName: name,
      phone: '01023456789',
      university: 'جامعة المنصورة الجديدة',
      subscriptionStatus: status,
      lineName: 'الزرقا',
      stationName: 'كوبري السرو',
      todayRideStatus: true,
      isOfflineCache: cached,
    );

const _vote = RideVote(isRiding: true, isReturning: true, departureTime: '07:00:00', returnTime: '15:30:00');

CheckInResult _result(CheckInOutcome outcome, {ScannedStudentDetails? student, DateTime? at}) => CheckInResult(
      outcome: outcome,
      direction: 'departure',
      checkedInAt: at,
      rideVote: _vote,
      hasRideVote: true,
      student: student,
    );

void main() {
  final haptics = <String>[];
  late _Repo repo;

  setUp(() {
    repo = _Repo();
    haptics.clear();
    OfflineCache.offlineSince.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add('${call.arguments}');
      return null;
    });
  });
  tearDown(() {
    OfflineCache.offlineSince.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  // The camera cannot run in a test: the scanner's own surface stands in for
  // its picture, and a code is handed over as the camera would.
  Widget app(Widget Function() scanner) => ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('sup'),
          supervisorRepoProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: scanner())),
        ),
      );

  Widget tab() => const ScannerView(camera: ScanBackdrop());

  /// A code read by the camera; returns once the result sheet has opened.
  Future<void> scan(WidgetTester tester, [String code = 'QR-1']) async {
    unawaited(tester.state<ScannerViewState>(find.byType(ScannerView)).handleCode(code));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  String countPill(WidgetTester tester) => tester
      .widget<Text>(find.descendant(of: find.byKey(const Key('scan-count')), matching: find.byType(Text)))
      .data!;

  testWidgets('a boarding: said in green, counted, and the sheet closes itself after two seconds', (tester) async {
    repo.answer = _result(CheckInOutcome.checkedIn,
        student: _student('سارة أحمد محمود'), at: DateTime(2026, 10, 11, 7, 23));
    await tester.pumpWidget(app(tab));
    await tester.pump();
    expect(find.text('ضع رمز الطالب داخل الإطار'), findsOneWidget);
    expect(countPill(tester), '0');
    expect(find.byKey(const Key('scan-last')), findsNothing);

    await scan(tester);
    expect(find.text('تم تسجيل الصعود'), findsOneWidget);
    // The student's own trip, from what they confirmed: the tab pins none.
    expect(find.text('ذهاب 7:00 ص · سُجّل 7:23 ص'), findsOneWidget);
    expect(find.text('سارة أحمد محمود'), findsOneWidget);
    expect(find.text('جامعة المنصورة الجديدة'), findsOneWidget);
    expect(find.text('كوبري السرو'), findsOneWidget);
    expect(find.text('ذهاب 7:00 ص · عودة 3:30 م'), findsOneWidget);
    expect(find.text('010 2345 6789'), findsOneWidget);
    expect(find.text('يعود للمسح تلقائياً'), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.mediumImpact']);
    expect(tester.widget<ScanFrame>(find.byType(ScanFrame)).color, BasakPalette.mint);

    // A card held to the camera while the result shows is not scanned twice.
    unawaited(tester.state<ScannerViewState>(find.byType(ScannerView)).handleCode('QR-2'));
    await tester.pump();
    expect(repo.scans, hasLength(1));

    // Still there just before the two seconds are over, gone just after.
    await tester.pump(const Duration(milliseconds: 1400));
    expect(find.text('تم تسجيل الصعود'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('تم تسجيل الصعود'), findsNothing);
    expect(tester.widget<ScanFrame>(find.byType(ScanFrame)).color, isNull);

    // The camera is ready for the next rider; the count and the last boarding stay.
    expect(countPill(tester), '1');
    expect(find.text('آخر صعود: سارة أحمد محمود'), findsOneWidget);
    expect(find.text('7:23 ص'), findsOneWidget);
    expect(repo.scans.single, (code: 'QR-1', direction: repo.scans.single.direction, tripId: null));

    // The last boarding opens again, and this time waits to be closed.
    await tester.tap(find.byKey(const Key('scan-last')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('تم تسجيل الصعود'), findsOneWidget);
    expect(find.text('يعود للمسح تلقائياً'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('تم تسجيل الصعود'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-next')));
    await tester.pumpAndSettle();
    expect(find.text('تم تسجيل الصعود'), findsNothing);
    expect(haptics, hasLength(1), reason: 'looking again is not a scan');
  });

  /// Every outcome but a boarding stays until «مسح التالي».
  Future<void> staysUntilTapped(WidgetTester tester, String title) async {
    expect(find.text(title), findsOneWidget);
    expect(find.text('يعود للمسح تلقائياً'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text(title), findsOneWidget, reason: 'only a boarding closes itself');
    await tester.tap(find.text(ScanResultSheet.next));
    await tester.pumpAndSettle();
    expect(find.text(title), findsNothing);
    expect(countPill(tester), '0', reason: 'nothing was boarded');
    expect(find.byKey(const Key('scan-last')), findsNothing);
  }

  testWidgets('already on board: a notice, not an error', (tester) async {
    repo.answer = _result(CheckInOutcome.alreadyCheckedIn,
        student: _student('يوسف طارق حسن'), at: DateTime(2026, 10, 11, 7, 2));
    await tester.pumpWidget(app(tab));
    await scan(tester);
    expect(find.text('صعد 7:02 ص في رحلة الذهاب.'), findsOneWidget);
    expect(find.text('يوسف طارق حسن'), findsOneWidget);
    expect(tester.widget<ResultHeader>(find.byType(ResultHeader)).tone, BasakTone.info);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    expect(tester.widget<ScanFrame>(find.byType(ScanFrame)).color, isNull, reason: 'the frame is not red');
    await staysUntilTapped(tester, 'سبق تسجيله اليوم');
  });

  testWidgets('no valid subscription: refused, with what the supervisor needs to explain why', (tester) async {
    repo.answer = _result(CheckInOutcome.noActiveSubscription, student: _student('عمر خالد منصور', status: 'expired'));
    await tester.pumpWidget(app(tab));
    await scan(tester);
    expect(find.text('لم يُسجَّل الصعود.'), findsOneWidget);
    expect(find.text('عمر خالد منصور'), findsOneWidget);
    expect(find.text('الزرقا · كوبري السرو'), findsOneWidget);
    expect(find.text('غير مفعّل أو منتهٍ'), findsOneWidget);
    expect(tester.widget<ResultHeader>(find.byType(ResultHeader)).tone, BasakTone.danger);
    expect(haptics, ['HapticFeedbackType.heavyImpact']);
    expect(tester.widget<ScanFrame>(find.byType(ScanFrame)).color, BasakPalette.refusedFrame);
    await staysUntilTapped(tester, 'لا يوجد اشتراك ساري');
  });

  testWidgets('a student of another line: refused, and no details are drawn', (tester) async {
    repo.answer = _result(CheckInOutcome.outsideAssignedLines);
    await tester.pumpWidget(app(tab));
    await scan(tester);
    expect(find.text('غير مشترك في الخطوط المسندة إليك. لم يُسجَّل الصعود.'), findsOneWidget);
    expect(find.byType(PersonFacts), findsNothing);
    expect(haptics, ['HapticFeedbackType.heavyImpact']);
    await staysUntilTapped(tester, 'الطالب ليس على خطك');
  });

  testWidgets('a code that is no card of Basak', (tester) async {
    repo.answer = _result(CheckInOutcome.notFound);
    await tester.pumpWidget(app(tab));
    await scan(tester);
    expect(find.text('هذا الرمز لا يخص أي طالب مسجّل في باصك.'), findsOneWidget);
    expect(find.byType(PersonFacts), findsNothing);
    expect(haptics, ['HapticFeedbackType.heavyImpact']);
    await staysUntilTapped(tester, 'رمز غير معروف');
  });

  testWidgets('offline, a student scanned before: saved details, and plainly nothing recorded', (tester) async {
    repo.answer = _result(CheckInOutcome.offlineLookup, student: _student('سارة أحمد محمود', cached: true));
    await tester.pumpWidget(app(tab));
    await scan(tester);
    expect(find.text('بيانات محفوظة من آخر تحقق. أعد المسح عند عودة الاتصال.'), findsOneWidget);
    expect(find.text('سارة أحمد محمود'), findsOneWidget);
    expect(find.text('الزرقا · كوبري السرو'), findsOneWidget);
    expect(tester.widget<ResultHeader>(find.byType(ResultHeader)).tone, BasakTone.warning);
    expect(haptics, ['HapticFeedbackType.heavyImpact']);
    await staysUntilTapped(tester, 'بدون إنترنت · لم يُسجَّل');
  });

  testWidgets('offline is said on the camera before anything is scanned', (tester) async {
    await tester.pumpWidget(app(tab));
    await tester.pump();
    expect(find.byKey(const Key('scan-offline')), findsNothing);

    OfflineCache.offlineSince.value = DateTime(2026, 10, 11, 6, 48);
    await tester.pump();
    expect(find.byKey(const Key('scan-offline')), findsOneWidget);
    expect(find.textContaining('المسح يعرض بيانات محفوظة ولا يسجّل الصعود.', findRichText: true), findsOneWidget);
    expect(repo.scans, isEmpty);
    // The controls stay: a student scanned before can still be looked up.
    expect(find.text('الإضاءة'), findsOneWidget);

    OfflineCache.offlineSince.value = null;
    await tester.pump();
    expect(find.byKey(const Key('scan-offline')), findsNothing);
  });

  testWidgets('a code that cannot be checked: a toast, and the camera stays live', (tester) async {
    repo.failure = const SocketException('Failed host lookup');
    await tester.pumpWidget(app(tab));
    unawaited(tester.state<ScannerViewState>(find.byType(ScannerView)).handleCode('QR-1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('تعذر التحقق من الرمز. اتصل بالإنترنت أو راجع صحة الرمز.'), findsOneWidget);
    expect(find.byType(ResultHeader), findsNothing);
    expect(haptics, isEmpty);

    // The next card is read as usual.
    repo
      ..failure = null
      ..answer = _result(CheckInOutcome.notFound);
    await scan(tester, 'QR-2');
    expect(find.text('رمز غير معروف'), findsOneWidget);
    await tester.tap(find.text(ScanResultSheet.next));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('the camera is not allowed: what it is for, the settings, and trying again', (tester) async {
    var settings = 0, retries = 0;
    await tester.pumpWidget(app(() => ScannerView(
          camera: const ScanBackdrop(),
          cameraState: ScanCameraState.denied,
          onOpenSettings: () => settings++,
          onRetryCamera: () => retries++,
        )));
    await tester.pump();
    expect(find.text('اسمح باستخدام الكاميرا'), findsOneWidget);
    expect(find.text('المسح يحتاج الكاميرا لقراءة رمز الطالب. فعّل الإذن لتطبيق باصك من إعدادات الهاتف.'),
        findsOneWidget);
    expect(find.text('ضع رمز الطالب داخل الإطار'), findsNothing);
    await tester.tap(find.text('فتح الإعدادات'));
    await tester.tap(find.text('إعادة المحاولة'));
    expect((settings, retries), (1, 1));
  });

  testWidgets('no camera, or one that will not start: the same page with other words', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
        app(() => const ScannerView(camera: ScanBackdrop(), cameraState: ScanCameraState.unsupported)));
    await tester.pump();
    expect(find.text('لا توجد كاميرا متاحة على هذا الجهاز.'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsNothing);

    await tester.pumpWidget(app(() => ScannerView(
        camera: const ScanBackdrop(), cameraState: ScanCameraState.failed, onRetryCamera: () => retries++)));
    await tester.pump();
    expect(find.text('تعذر تشغيل الكاميرا. أغلق أي تطبيق آخر يستخدمها ثم أعد المحاولة.'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    expect(retries, 1);
  });

  testWidgets('the tab boards each student on their own trip; the pill chooses the direction', (tester) async {
    repo.answer = _result(CheckInOutcome.notFound);
    await tester.pumpWidget(app(tab));
    await tester.pump();
    // The direction follows the clock until the supervisor chooses.
    expect(find.textContaining('رحلة كل طالب'), findsOneWidget);

    await tester.tap(find.textContaining('رحلة كل طالب'));
    await tester.pumpAndSettle();
    expect(find.text('يُسجَّل كل طالب في رحلته التي أكّدها.'), findsOneWidget);
    await tester.tap(find.text('العودة'));
    await tester.pumpAndSettle();
    expect(find.text('عودة · رحلة كل طالب'), findsOneWidget);

    await scan(tester);
    expect(repo.scans.single, (code: 'QR-1', direction: 'return', tripId: null));
    await tester.tap(find.text(ScanResultSheet.next));
    await tester.pumpAndSettle();
  });

  testWidgets('opened from Trips it is pinned to that trip, and counts its riders', (tester) async {
    repo.answer = _result(CheckInOutcome.checkedIn,
        student: _student('سارة أحمد محمود'), at: DateTime(2026, 10, 11, 7, 23));
    await tester.pumpWidget(app(() => const ScannerView(
          camera: ScanBackdrop(),
          direction: 'departure',
          tripId: 'trip-1',
          tripLabel: '7:00 ص',
          lineId: 'line-a',
          inTab: false,
        )));
    await tester.pumpAndSettle();
    expect(find.text('ذهاب · 7:00 ص'), findsOneWidget);
    expect(countPill(tester), '1 / 3', reason: 'boarded of expected, from the trip list');

    await scan(tester);
    expect(repo.scans.single, (code: 'QR-1', direction: 'departure', tripId: 'trip-1'));
    expect(find.text('ذهاب 7:00 ص · سُجّل 7:23 ص'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('the count and the last boarding survive leaving the tab', (tester) async {
    repo.answer = _result(CheckInOutcome.checkedIn,
        student: _student('سارة أحمد محمود'), at: DateTime(2026, 10, 11, 7, 23));
    final onScanner = ValueNotifier(true);
    addTearDown(onScanner.dispose);
    await tester.pumpWidget(app(() => ValueListenableBuilder<bool>(
          valueListenable: onScanner,
          builder: (context, scanner, _) => scanner ? tab() : const Center(child: Text('الرئيسية')),
        )));
    await scan(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(countPill(tester), '1');

    // Another tab, then back: the scanner is built anew.
    onScanner.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(ScannerView), findsNothing);
    onScanner.value = true;
    await tester.pumpAndSettle();
    expect(countPill(tester), '1');
    expect(find.text('آخر صعود: سارة أحمد محمود'), findsOneWidget);
  });

  test('a new account starts counting from nothing', () {
    var user = 'sup-1';
    final container = ProviderContainer(overrides: [sessionUserIdProvider.overrideWith((ref) => user)]);
    addTearDown(container.dispose);
    container.read(scanSessionProvider.notifier).recordBoarding(_result(CheckInOutcome.checkedIn));
    expect(container.read(scanSessionProvider).boarded, 1);
    user = 'sup-2';
    container.invalidate(sessionUserIdProvider);
    expect(container.read(scanSessionProvider).boarded, 0);
  });

  test('what the student confirmed, in the scanner\'s words', () {
    CheckInResult voted(RideVote? vote, {bool reported = true, bool? legacy}) => CheckInResult(
        outcome: CheckInOutcome.checkedIn,
        direction: 'departure',
        rideVote: vote,
        hasRideVote: reported,
        confirmedRideToday: legacy);
    expect(ScanResultWords.confirmation(voted(_vote)), 'ذهاب 7:00 ص · عودة 3:30 م');
    expect(
        ScanResultWords.confirmation(
            voted(const RideVote(isRiding: true, isReturning: false, departureTime: '07:45:00'))),
        'ذهاب 7:45 ص · بدون عودة');
    expect(ScanResultWords.confirmation(voted(const RideVote(isRiding: false, isReturning: false))),
        'أكّد أنه لن يركب');
    expect(ScanResultWords.confirmation(voted(null)), 'لم يؤكّد اليوم');
    // An older server says only whether they confirmed.
    expect(ScanResultWords.confirmation(voted(null, reported: false, legacy: true)), 'أكّد الركوب');
    expect(ScanResultWords.confirmation(voted(null, reported: false, legacy: false)), 'لم يؤكّد اليوم');
  });
}
