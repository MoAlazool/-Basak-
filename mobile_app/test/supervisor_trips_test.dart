// The supervisor's Trips (one trip) in every state, on the boards' data, and
// the shell around the tabs.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/core/widgets/floating_glass_nav_bar.dart';
import 'package:basak_mobile/core/widgets/skeleton.dart';
import 'package:basak_mobile/features/supervisor/home/presentation/supervisor_home_screen.dart';
import 'package:basak_mobile/features/supervisor/selection/supervisor_selection.dart';
import 'package:basak_mobile/features/supervisor/supervisor_main_screen.dart';
import 'package:basak_mobile/features/supervisor/trips/presentation/rider_sheet.dart';
import 'package:basak_mobile/features/supervisor/trips/presentation/supervisor_trips_screen.dart';
import 'package:basak_mobile/features/supervisor/trips/presentation/trip_sheet.dart';

import 'support/supervisor_boards.dart';

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SupervisorTripsScreen)));

Future<void> _trips(WidgetTester tester, BoardWorld world,
    {Size size = const Size(390, 1190), List<Override> more = const []}) async {
  await pumpBoard(tester, world, const SupervisorTripsScreen(), tab: 1, size: size, more: more);
  await tester.pumpAndSettle();
}

StopRow _stop(WidgetTester tester, String id) => tester.widget<StopRow>(find.byKey(Key('stop-$id')));

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(OfflineCache.markOnline);

  testWidgets('one trip: its time and direction, where it arrives, who boarded of who is expected', (tester) async {
    final world = BoardWorld(now: DateTime(2026, 10, 11, 7, 18));
    await _trips(tester, world);

    expect(find.text('الرحلات'), findsWidgets);
    expect(find.text('الأحد 11 أكتوبر'), findsOneWidget);
    final card = tester.widget<TripCard>(find.byKey(const Key('trip-card')));
    expect((card.time, card.direction), ('7:00 ص', 'ذهاب'));
    expect(card.detail, 'خط الزرقا · الوصول إلى الجامعة 8:20 ص');
    expect(card.note, isNull, reason: 'the company set no seats');
    final progress = tester.widget<ProgressLine>(find.byType(ProgressLine));
    expect((progress.sentence, progress.trailing), ('صعد 14 من 38', 'بقي 24'));
    expect(progress.value, closeTo(14 / 38, .001));
    expect(world.manifestKeys.single, (lineId: 'line-a', direction: 'departure', tripId: null),
        reason: 'no trip chosen: the next one to leave, as the server picks it');

    // Nothing of the old screen: no scan button, no stat tiles, no route chips.
    expect(find.textContaining('مسح QR'), findsNothing);
    expect(find.textContaining('تم تسجيلهم'), findsNothing);
    expect(find.textContaining('لم يُسجَّل'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the stops on a rail: stop time, boarded of expected, and where the bus is', (tester) async {
    await _trips(tester, BoardWorld(now: DateTime(2026, 10, 11, 7, 18)));
    expect(find.text('المحطات'), findsOneWidget);
    expect(find.text('7 محطات'), findsOneWidget);
    expect(find.byType(StopRow), findsNWidgets(7));

    final first = _stop(tester, 's1');
    expect((first.name, first.time, first.boarded, first.expected), ('موقف الزرقا', '7:00 ص', 6, 6));
    expect((first.state, first.isFirst, first.isLast), (StopState.done, true, false));
    expect(find.text('6 / 6'), findsOneWidget);
    expect((_stop(tester, 's3').boarded, _stop(tester, 's3').expected), (4, 5));
    expect(_stop(tester, 's2').state, StopState.done);
    expect(_stop(tester, 's3').state, StopState.current);
    expect(_stop(tester, 's4').state, StopState.upcoming);
    expect(_stop(tester, 's7').isLast, isTrue);
    expect(find.text('0 / 8'), findsOneWidget);
  });

  testWidgets('a stop opens in place to its riders: when each boarded, or «لم يصعد»', (tester) async {
    await _trips(tester, BoardWorld(now: DateTime(2026, 10, 11, 7, 18)));
    expect(find.text('كريم محمد عبد الله'), findsNothing);

    await tester.tap(find.text('شرباص'));
    await tester.pumpAndSettle();
    final stop = _stop(tester, 's3');
    expect(stop.expanded, isTrue);
    expect(stop.riders.map((r) => (r.name, r.boardedAt)), [
      ('ندى إبراهيم خليل', '7:15 ص'),
      ('أحمد سامي فتحي', '7:16 ص'),
      ('منة الله عادل حسين', '7:16 ص'),
      ('يوسف طارق حسن', '7:17 ص'),
      ('كريم محمد عبد الله', null),
    ], reason: 'who boarded, in the order they did; then who is still awaited');
    expect(find.text('لم يصعد'), findsOneWidget);

    await tester.tap(find.text('شرباص'));
    await tester.pumpAndSettle();
    expect(find.text('كريم محمد عبد الله'), findsNothing);
  });

  testWidgets('the rider sheet: state, stop, today\'s confirmation, university, phone — call, WhatsApp, copy',
      (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await _trips(tester, BoardWorld(now: DateTime(2026, 10, 11, 7, 18)));
    await tester.tap(find.text('شرباص'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('كريم محمد عبد الله'));
    await tester.pumpAndSettle();

    final sheet = find.byType(RiderSheet);
    expect(sheet, findsOneWidget);
    Finder inSheet(String text) => find.descendant(of: sheet, matching: find.text(text));
    expect(inSheet('كريم محمد عبد الله'), findsOneWidget);
    expect(tester.widget<BasakTag>(find.byKey(const Key('rider-state'))).label, 'لم يصعد');
    expect(tester.widget<BasakTag>(find.byKey(const Key('rider-state'))).tone, BasakTone.warning);
    expect(inSheet('المحطة'), findsOneWidget);
    expect(inSheet('شرباص · 7:15 ص'), findsOneWidget);
    expect(inSheet('تأكيد اليوم'), findsOneWidget);
    expect(inSheet('ذهاب 7:00 ص'), findsOneWidget);
    expect(inSheet('جامعة المنصورة الجديدة'), findsOneWidget);
    expect(inSheet('010 9876 5432'), findsOneWidget);
    expect(inSheet('اتصال'), findsOneWidget);
    expect(inSheet('واتساب'), findsOneWidget);
    expect(inSheet('نسخ الرقم'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rider-copy')));
    await tester.pumpAndSettle();
    final copied = calls.where((c) => c.method == 'Clipboard.setData').single;
    expect((copied.arguments as Map)['text'], '01098765432');
    expect(find.byType(RiderSheet), findsNothing);
    expect(find.text('تم نسخ الرقم'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));

    // Someone who boarded says when.
    await tester.tap(find.text('ندى إبراهيم خليل'));
    await tester.pumpAndSettle();
    expect(tester.widget<BasakTag>(find.byKey(const Key('rider-state'))).label, 'صعد 7:15 ص');
    expect(tester.widget<BasakTag>(find.byKey(const Key('rider-state'))).tone, BasakTone.success);
  });

  testWidgets('«لم يؤكّدوا اليوم · n» closes the list, collapsed', (tester) async {
    await _trips(tester, BoardWorld(now: DateTime(2026, 10, 11, 7, 18)));
    expect(find.text('لم يؤكّدوا اليوم · 5'), findsOneWidget);
    expect(find.text('مشتركون على الخط لم يحدّدوا موعدهم'), findsOneWidget);
    expect(find.text('مشترك 1'), findsNothing);

    await tester.scrollUntilVisible(find.byKey(const Key('unconfirmed')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('لم يؤكّدوا اليوم · 5'));
    await tester.pumpAndSettle();
    expect(find.text('مشترك 1'), findsOneWidget);
    expect(find.byType(PersonRow), findsNWidgets(5));

    await tester.tap(find.text('مشترك 1'));
    await tester.pumpAndSettle();
    expect(tester.widget<BasakTag>(find.byKey(const Key('rider-state'))).label, 'لم يؤكّد اليوم');
    expect(find.descendant(of: find.byType(RiderSheet), matching: find.text('لم يؤكّد')), findsOneWidget);

    await _trips(tester, BoardWorld(manifest: (key) => boardManifest(unconfirmed: 0)));
    expect(find.byKey(const Key('unconfirmed')), findsNothing);
  });

  testWidgets('«تغيير» opens the trip sheet: both directions with counts, every trip with how far it is',
      (tester) async {
    final world = BoardWorld(now: DateTime(2026, 10, 11, 7, 18));
    await _trips(tester, world);
    await tester.tap(find.text('تغيير'));
    await tester.pumpAndSettle();

    final sheet = find.byType(TripSheet);
    expect(sheet, findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('الرحلة')), findsOneWidget);
    expect(find.text('الذهاب · 5'), findsOneWidget);
    expect(find.text('العودة · 6'), findsOneWidget);
    final rows = tester.widgetList<TripChoiceRow>(find.byType(TripChoiceRow)).toList();
    expect(rows.map((r) => (r.time, r.note, r.riders, r.selected, r.past)), [
      ('6:15 ص', 'مضى موعدها', '12 طالباً', false, true),
      ('7:00 ص', 'الآن', '38 طالباً', true, false),
      ('7:45 ص', 'بعد 27 دقيقة', '27 طالباً', false, false),
      ('8:30 ص', null, '21 طالباً', false, false),
      ('9:15 ص', null, '9 طلاب', false, false),
    ]);

    // Another direction, another trip, then "عرض الرحلة".
    await tester.tap(find.text('العودة · 6'));
    await tester.pumpAndSettle();
    expect(find.byType(TripChoiceRow), findsNWidgets(6));
    await tester.tap(find.byKey(const Key('trip-choice-return-15:30:00')));
    await tester.pump();
    expect(_container(tester).read(supervisorSelectionProvider).hasTrip, isFalse, reason: 'not before "عرض الرحلة"');
    await tester.tap(find.byKey(const Key('trip-show')));
    await tester.pumpAndSettle();

    final chosen = _container(tester).read(supervisorSelectionProvider);
    expect((chosen.direction, chosen.tripTime, chosen.tripId), (TripDirection.returning, '15:30:00', 'r-15:30'));
    expect(world.manifestKeys.last, (lineId: 'line-a', direction: 'return', tripId: 'r-15:30'));
    final card = tester.widget<TripCard>(find.byKey(const Key('trip-card')));
    expect((card.time, card.direction), ('3:30 م', 'عودة'));
  });

  testWidgets('the trip chosen on Home is the trip shown here', (tester) async {
    final world = BoardWorld();
    await pumpBoard(tester, world, const SupervisorTripsScreen(), tab: 1);
    final c = _container(tester);
    c.read(supervisorSelectionProvider.notifier)
        .selectTrip(direction: TripDirection.departure, time: '07:45:00', tripId: 'd-07:45');
    await tester.pumpAndSettle();
    expect(world.manifestKeys.last, (lineId: 'line-a', direction: 'departure', tripId: 'd-07:45'));
  });

  testWidgets('a direction without trips: the two directions, and one sentence — no admin dashboard', (tester) async {
    final world = BoardWorld(
      now: DateTime(2026, 10, 11, 14),
      dashboard: boardDashboard(returns: false),
      manifest: (key) => boardManifest(direction: key.direction, trips: key.direction == 'departure'),
    );
    await _trips(tester, world, size: const Size(390, 844));
    expect(find.text('الذهاب · 5'), findsOneWidget);
    expect(find.text('العودة · 0'), findsOneWidget);
    expect(find.text('لا توجد رحلات عودة'), findsOneWidget);
    expect(find.text('لم تُضف الشركة رحلات عودة لخط الزرقا بعد. تظهر هنا فور إضافتها.'), findsOneWidget);
    expect(find.textContaining('لوحة التحكم'), findsNothing);
    expect(find.byType(TripCard), findsNothing);

    await tester.tap(find.text('الذهاب · 5'));
    await tester.pumpAndSettle();
    expect(find.byType(TripCard), findsOneWidget);
    expect(find.text('لا توجد رحلات عودة'), findsNothing);
  });

  testWidgets('the trip could not be loaded: a plain message and a retry, never the raw exception', (tester) async {
    final world = BoardWorld(manifestFails: true);
    await _trips(tester, world, size: const Size(390, 844));
    expect(find.text('تعذّر تحميل الرحلة'), findsOneWidget);
    expect(find.text('تحقّق من الاتصال بالإنترنت ثم أعد المحاولة.'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('42P01'), findsNothing);

    world.manifestFails = false;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.byType(TripCard), findsOneWidget);
  });

  testWidgets('loading, a failed start and no line each keep the page\'s title', (tester) async {
    await pumpBoard(tester, BoardWorld(loading: true), const SupervisorTripsScreen(), tab: 1);
    expect(find.byType(StationRowsSkeleton), findsOneWidget);
    expect(find.text('الرحلات'), findsWidgets);

    await _trips(tester, BoardWorld(dashboardFails: true), size: const Size(390, 844));
    expect(find.text('تعذّر تحميل الرحلات'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);

    await _trips(tester, BoardWorld(dashboard: boardDashboard(lines: 0)), size: const Size(390, 844));
    expect(find.text('لا يوجد خط مسند إليك'), findsOneWidget);
    expect(find.text('تحديث'), findsOneWidget);
  });

  testWidgets('bus seats on the trip card: how many of the seats, or how many buses', (tester) async {
    await _trips(tester, BoardWorld(capacities: {'line-a': 50}));
    final card = tester.widget<TripCard>(find.byKey(const Key('trip-card')));
    expect((card.note, card.noteWarns), ('مقاعد الباص: 38 من 50', false));

    await _trips(tester, BoardWorld(capacities: {'line-a': 30}));
    final over = tester.widget<TripCard>(find.byKey(const Key('trip-card')));
    expect((over.note, over.noteWarns), ('يحتاج باصين · الباص 30 مقعداً', true));
  });

  testWidgets('a trip of tomorrow, opened from Home: who confirmed, stop by stop, and the way back to today',
      (tester) async {
    final world = BoardWorld(now: boardEvening);
    await pumpBoard(tester, world, const SupervisorTripsScreen(),
        tab: 1,
        size: const Size(390, 1190),
        more: [supervisorTripDayProvider.overrideWith((ref) => DateTime(2026, 10, 12))]);
    final c = _container(tester);
    c.read(supervisorSelectionProvider.notifier)
        .selectTrip(direction: TripDirection.departure, time: '07:00:00', tripId: 'd-07:00');
    await tester.pumpAndSettle();

    expect(find.text('غداً · الاثنين 12 أكتوبر'), findsOneWidget);
    expect(find.text('أكّد 24 طالباً'), findsOneWidget);
    expect(find.text('التأكيد مفتوح حتى 6:00 ص'), findsOneWidget);
    expect(find.byType(ProgressLine), findsNothing, reason: 'nobody has boarded a trip that has not come');
    expect(_stop(tester, 's3').countLabel, '2');
    await tester.tap(find.text('شرباص'));
    await tester.pumpAndSettle();
    expect(_stop(tester, 's3').riders.map((r) => (r.name, r.plain)),
        [('ندى إبراهيم خليل', true), ('كريم محمد عبد الله', true)]);
    expect(find.text('لم يصعد'), findsNothing);
    expect(world.manifestKeys, isEmpty, reason: 'drawn from the dashboard: no request');

    await tester.tap(find.text('كريم محمد عبد الله'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rider-state')), findsNothing);
    expect(find.descendant(of: find.byType(RiderSheet), matching: find.text('تأكيد الغد')), findsOneWidget);
    expect(find.descendant(of: find.byType(RiderSheet), matching: find.text('ذهاب 7:00 ص')), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    // A trip of tomorrow whose riders the server did not break down.
    c.read(supervisorSelectionProvider.notifier)
        .selectTrip(direction: TripDirection.departure, time: '07:45:00', tripId: 'd-07:45');
    await tester.pumpAndSettle();
    expect(find.text('أكّد 15 طالباً'), findsOneWidget);
    expect(find.text('التفاصيل غير متاحة'), findsOneWidget);

    await tester.tap(find.byKey(const Key('back-to-today')));
    await tester.pumpAndSettle();
    expect(find.text('الأحد 11 أكتوبر'), findsOneWidget);
    expect(find.byType(ProgressLine), findsOneWidget);
  });

  testWidgets('nothing clips at 360 × 640, nor with large text', (tester) async {
    await loadBoardFonts(tester);
    final world = BoardWorld(capacities: {'line-a': 30}, now: DateTime(2026, 10, 11, 7, 18));
    await pumpBoard(tester, world, const SupervisorTripsScreen(),
        tab: 1, size: const Size(360, 640), textScale: 1.3);
    await tester.pumpAndSettle();
    await tester.tap(find.text('شرباص'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('تغيير'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('the shell', () {
    test('four tabs: الرئيسية · الرحلات · مسح (filled) · حسابي — الملخص is a page under حسابي', () {
      final items = FloatingGlassNavBar.supervisorNavItems;
      expect(items.map((i) => i.label), ['الرئيسية', 'الرحلات', 'مسح', 'حسابي']);
      expect(items.map((i) => i.filled), [false, false, true, false]);
      expect(SupervisorMainScreen.scanTab, 2);
    });

    testWidgets('a suspended account: one blocking screen for the whole app, with a retry and sign out',
        (tester) async {
      final world = BoardWorld(dashboard: boardDashboard(active: false));
      await pumpBoard(tester, world, const SupervisorMainScreen(), tab: null);
      await tester.pumpAndSettle();
      expect(find.byType(SupervisorSuspendedScreen), findsOneWidget);
      expect(find.text('الحساب موقوف'), findsOneWidget);
      expect(find.text('أوقفت إدارة الشركة حساب المشرف. تواصل مع شركتك لإعادة تفعيله.'), findsOneWidget);
      expect(find.text('تسجيل الخروج'), findsOneWidget);
      expect(find.byType(FloatingGlassNavBar), findsNothing, reason: 'no tab leads around it');
      expect(find.byType(SupervisorHomeScreen), findsNothing);

      // The company activates the account again.
      world.dashboard = boardDashboard();
      await tester.tap(find.byKey(const Key('suspended-retry')));
      await tester.pumpAndSettle();
      expect(find.byType(SupervisorSuspendedScreen), findsNothing);
      expect(find.byType(SupervisorHomeScreen), findsOneWidget);
      expect(find.byType(FloatingGlassNavBar), findsOneWidget);
      // The push offer waits three seconds after the start.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('a trip tapped on Home opens the Trips tab on that trip; the tab itself is always today',
        (tester) async {
      final world = BoardWorld();
      await pumpBoard(tester, world, const SupervisorMainScreen(), tab: null, size: const Size(390, 1100));
      await tester.pumpAndSettle();

      await tester.tap(findPagerDot(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('trip-departure-07:00:00')));
      await tester.pumpAndSettle();
      expect(find.byType(SupervisorTripsScreen), findsOneWidget);
      expect(find.text('غداً · الاثنين 12 أكتوبر'), findsOneWidget);
      expect(tester.widget<FloatingGlassNavBar>(find.byType(FloatingGlassNavBar)).currentIndex, 1);

      // Home, then Trips from the bar: today, the same trip.
      await tester.tap(find.text('الرئيسية'));
      await tester.pumpAndSettle();
      expect(find.byType(SupervisorHomeScreen), findsOneWidget);
      await tester.tap(find.text('الرحلات').last);
      await tester.pumpAndSettle();
      expect(find.text('الأحد 11 أكتوبر'), findsOneWidget);
      expect(world.manifestKeys.last, (lineId: 'line-a', direction: 'departure', tripId: 'd-07:00'));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });
}
