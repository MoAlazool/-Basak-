// The supervisor's Home (the numbers) in every state, on the boards' data.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/core/widgets/skeleton.dart';
import 'package:basak_mobile/features/supervisor/home/presentation/line_sheet.dart';
import 'package:basak_mobile/features/supervisor/home/presentation/supervisor_home_screen.dart';
import 'package:basak_mobile/features/supervisor/selection/supervisor_selection.dart';

import 'support/supervisor_boards.dart';

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SupervisorHomeScreen)));

Future<int> _home(WidgetTester tester, BoardWorld world, {Size size = const Size(390, 1100)}) async {
  var opened = 0;
  await pumpBoard(tester, world, SupervisorHomeScreen(onOpenTrips: () => opened++), size: size);
  await tester.pumpAndSettle();
  return opened;
}

BarRow _row(WidgetTester tester, String direction, String time) =>
    tester.widget<BarRow>(find.byKey(Key('trip-$direction-$time')));

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(OfflineCache.markOnline);

  testWidgets('the numbers of today: two totals, how firm, how much of the line, every trip in two columns',
      (tester) async {
    final world = BoardWorld();
    await _home(tester, world);

    expect(find.text('محمود السيد'), findsOneWidget);
    expect(findBell('التنبيهات، 2 غير مقروءة'), findsOneWidget);
    final hero = tester.widget<CountsHero>(find.byKey(const Key('counts-hero-0')));
    expect(hero.day, 'اليوم · الأحد 11 أكتوبر');
    expect(hero.firmness, 'نهائي · أُغلق التأكيد 6:00 ص');
    expect(hero.isFinal, isTrue);
    expect((hero.going, hero.goingTrips), (107, 'في 5 رحلات'));
    expect((hero.returning, hero.returningTrips), (105, 'في 6 رحلات'));
    expect(hero.shareSentence, 'سيركب 107 من 124 مشتركاً');
    expect(find.text('86%'), findsWidgets);

    expect(find.descendant(of: find.byKey(const Key('trips-departure')), matching: find.text('5 رحلات')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('trips-return')), matching: find.text('6 رحلات')),
        findsOneWidget);
    expect(find.byType(BarRow), findsNWidgets(11));
    expect(_row(tester, 'departure', '07:00:00').time, '7:00 ص');
    expect(_row(tester, 'departure', '07:00:00').count, 38);
    expect(_row(tester, 'departure', '07:00:00').share, 1, reason: 'the busiest trip fills its bar');
    expect(_row(tester, 'return', '15:30:00').count, 31);
    expect(find.text('اضغط أي رحلة لعرض ركابها ومحطاتها.'), findsOneWidget);
    expect(find.text('إشعار للطلاب'), findsOneWidget);
    expect(find.text('لكل الخط أو لركاب رحلة واحدة'), findsOneWidget);

    // Nothing of the old Home: no prices, no registered-students tiles, no scan tile.
    expect(find.textContaining('ج.م'), findsNothing);
    expect(find.text('مسح بطاقة طالب'), findsNothing);
    expect(find.textContaining('طالب مشترك'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('by the clock: the next trip is marked, the ones that left are dimmed', (tester) async {
    final world = BoardWorld(); // 6:50
    await _home(tester, world);
    expect(_row(tester, 'departure', '06:15:00').state, BarRowState.past);
    expect(_row(tester, 'departure', '07:00:00').state, BarRowState.next);
    expect(_row(tester, 'departure', '07:45:00').state, BarRowState.upcoming);
    expect(_row(tester, 'return', '12:30:00').state, BarRowState.upcoming);
    expect(find.text('القادمة'), findsOneWidget, reason: 'one next trip, of either direction');

    // In the afternoon the next one is a return.
    world.now = DateTime(2026, 10, 11, 14);
    await _home(tester, world);
    expect(_row(tester, 'departure', '09:15:00').state, BarRowState.past);
    expect(_row(tester, 'return', '13:30:00').state, BarRowState.past);
    expect(_row(tester, 'return', '14:30:00').state, BarRowState.next);
  });

  testWidgets('tomorrow: swiped to, or by the dots; its own firmness and sentence; nothing is past', (tester) async {
    final world = BoardWorld();
    await _home(tester, world);
    expect(_row(tester, 'departure', '07:00:00').count, 38);

    await tester.drag(find.byKey(const Key('counts-hero-0')), const Offset(300, 0)); // RTL: the next card comes from the left
    await tester.pumpAndSettle();
    expect(_row(tester, 'departure', '07:00:00').count, 24, reason: 'the lists follow the card');
    expect(_row(tester, 'departure', '06:15:00').state, BarRowState.upcoming);
    expect(find.text('القادمة'), findsNothing);
    final tomorrow = tester.widget<CountsHero>(find.byKey(const Key('counts-hero-1')));
    expect(tomorrow.day, 'غداً · الاثنين 12 أكتوبر');
    expect((tomorrow.going, tomorrow.returning), (64, 58));
    expect(tomorrow.firmness, 'يفتح التأكيد 4:00 م');
    expect(tester.widget<PagerDots>(find.byType(PagerDots)).index, 1);

    // The dots are the tap alternative.
    await tester.tap(findPagerDot(0));
    await tester.pumpAndSettle();
    expect(_row(tester, 'departure', '07:00:00').count, 38);
    expect(tester.widget<PagerDots>(find.byType(PagerDots)).index, 0);
  });

  testWidgets('opens on tomorrow once tomorrow\'s confirmation has opened', (tester) async {
    final world = BoardWorld(now: boardEvening);
    await _home(tester, world);
    expect(tester.widget<PagerDots>(find.byType(PagerDots)).index, 1);
    final hero = tester.widget<CountsHero>(find.byKey(const Key('counts-hero-1')));
    expect(hero.firmness, 'التأكيد مفتوح حتى 6:00 ص');
    expect(hero.isFinal, isFalse);
    expect(hero.shareSentence, 'أكّد 64 من 124 مشتركاً حتى الآن');
    expect(_row(tester, 'return', '15:30:00').count, 19);
  });

  testWidgets('a trip opens its riders in Trips: it is chosen for every tab, then the tab changes', (tester) async {
    final world = BoardWorld();
    var opened = 0;
    await pumpBoard(tester, world, SupervisorHomeScreen(onOpenTrips: () => opened++), size: const Size(390, 1100));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('trip-return-15:30:00')));
    await tester.pump();
    final c = _container(tester);
    final chosen = c.read(supervisorSelectionProvider);
    expect(opened, 1);
    expect((chosen.direction, chosen.tripTime, chosen.tripId), (TripDirection.returning, '15:30:00', 'r-15:30'));
    expect(chosen.tripKey, 'return|15:30');
    expect(c.read(supervisorTripDayProvider), isNull, reason: 'a trip of today');

    // From tomorrow's card, Trips is told the day too.
    await tester.tap(findPagerDot(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trip-departure-07:00:00')));
    await tester.pump();
    expect(opened, 2);
    expect(c.read(supervisorSelectionProvider).tripKey, 'departure|07:00');
    expect(c.read(supervisorTripDayProvider), DateTime(2026, 10, 12));
  });

  testWidgets('share hands the day\'s counts over as text', (tester) async {
    final world = BoardWorld();
    await _home(tester, world);
    await tester.tap(find.text('مشاركة').first);
    await tester.pump();
    expect(world.shared, hasLength(1));
    expect(world.shared.single, contains('أعداد الركاب · خط الزرقا'));
    expect(world.shared.single, contains('اليوم · الأحد 11 أكتوبر'));
    expect(world.shared.single, contains('الذهاب: 107'));
    expect(world.shared.single, contains('7:00 ص: 38'));
    expect(world.shared.single, contains('العودة: 105'));
    expect(world.shared.single, contains('3:30 م: 31'));
  });

  testWidgets('the line row: only with more than one line; the sheet applies the choice everywhere', (tester) async {
    await _home(tester, BoardWorld(dashboard: boardDashboard(lines: 1)));
    expect(find.byKey(const Key('line-row')), findsNothing);
    expect(find.byType(CountsHero), findsNWidgets(2));

    final world = BoardWorld();
    await _home(tester, world);
    final row = tester.widget<LineSwitchRow>(find.byKey(const Key('line-row')));
    expect(row.name, 'خط الزرقا');
    expect(row.caption, 'النورس للنقل · 1 من 3 خطوط');

    await tester.tap(find.byKey(const Key('line-row')));
    await tester.pumpAndSettle();
    expect(find.byType(SupervisorLineSheet), findsOneWidget);
    expect(find.text('الخط'), findsOneWidget);
    expect(find.text('يُطبَّق اختيارك على الرحلات والمسح والإشعارات.'), findsOneWidget);
    expect(find.text('جامعة المنصورة الجديدة · 124 مشتركاً'), findsOneWidget);
    expect(find.text('جامعة دمياط · 86 مشتركاً'), findsOneWidget);
    expect(find.text('جامعة المنصورة · 52 مشتركاً'), findsOneWidget);
    expect(find.text('متوقف'), findsOneWidget);
    expect(tester.widget<RadioCard>(find.byKey(const Key('line-line-a'))).selected, isTrue);

    // Choosing is not applying: the page behind keeps its line until "تأكيد".
    await tester.tap(find.byKey(const Key('line-line-b')));
    await tester.pump();
    final c = _container(tester);
    expect(c.read(supervisorSelectionProvider).lineId, isNull);
    await tester.tap(find.byKey(const Key('line-confirm')));
    await tester.pumpAndSettle();
    expect(c.read(supervisorSelectionProvider).lineId, 'line-b');
    expect(tester.widget<LineSwitchRow>(find.byKey(const Key('line-row'))).name, 'خط دمياط الجديدة');
    expect(tester.widget<LineSwitchRow>(find.byKey(const Key('line-row'))).caption, 'النورس للنقل · 2 من 3 خطوط');
    final hero = tester.widget<CountsHero>(find.byKey(const Key('counts-hero-0')));
    expect((hero.going, hero.returning), (4, 0));
    expect(hero.shareSentence, 'سيركب 4 من 86 مشتركاً');
  });

  testWidgets('choosing another line drops the trip chosen on the first; the same line keeps it', (tester) async {
    final world = BoardWorld();
    await _home(tester, world);
    final c = _container(tester);
    c.read(supervisorSelectionProvider.notifier).selectLine('line-a');
    c.read(supervisorSelectionProvider.notifier)
        .selectTrip(direction: TripDirection.departure, time: '07:00:00', tripId: 'd-07:00');

    await tester.tap(find.byKey(const Key('line-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('line-confirm')));
    await tester.pumpAndSettle();
    expect(c.read(supervisorSelectionProvider).tripKey, 'departure|07:00');

    await tester.tap(find.byKey(const Key('line-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('line-line-c')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('line-confirm')));
    await tester.pumpAndSettle();
    expect(c.read(supervisorSelectionProvider).lineId, 'line-c');
    expect(c.read(supervisorSelectionProvider).hasTrip, isFalse);
    expect(tester.widget<LineSwitchRow>(find.byKey(const Key('line-row'))).tag, 'خط متوقف');
  });

  testWidgets('a stopped line says so, even when it is the only one', (tester) async {
    await _home(tester, BoardWorld(dashboard: boardDashboard(lines: 1, firstLineStopped: true)));
    final row = tester.widget<LineSwitchRow>(find.byKey(const Key('line-row')));
    expect(row.tag, 'خط متوقف');
    expect(row.onTap, isNull, reason: 'there is no other line to change to');
  });

  testWidgets('bus seats: nothing without a number; nearly full and over are said on the trip\'s row', (tester) async {
    await _home(tester, BoardWorld());
    expect(tester.widgetList<BarRow>(find.byType(BarRow)).every((r) => r.note == null), isTrue);

    await _home(tester, BoardWorld(capacities: {'line-a': 30}));
    expect(_row(tester, 'departure', '06:15:00').note, isNull, reason: '12 of 30: room to spare');
    expect(_row(tester, 'departure', '07:45:00').note, '27 من 30');
    expect(_row(tester, 'departure', '07:45:00').noteWarns, isFalse);
    expect(_row(tester, 'departure', '07:00:00').note, 'يحتاج باصين');
    expect(_row(tester, 'departure', '07:00:00').noteWarns, isTrue);
    expect(_row(tester, 'return', '15:30:00').note, 'يحتاج باصين');
    expect(find.text('يحتاج باصين'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('nobody confirmed yet: the trips are listed with zeros and the page says so', (tester) async {
    await _home(tester, BoardWorld(dashboard: boardDashboard(riders: false)));
    final hero = tester.widget<CountsHero>(find.byKey(const Key('counts-hero-0')));
    expect((hero.going, hero.returning), (0, 0));
    expect(find.byType(BarRow), findsNWidgets(11));
    expect(find.text('لا توجد تأكيدات بعد'), findsOneWidget);
    expect(find.text('اضغط أي رحلة لعرض ركابها ومحطاتها.'), findsNothing);

    // A server that lists no trips and no riders: one plain empty state.
    await _home(tester, BoardWorld(dashboard: boardDashboard(riders: false, tripsListed: false)));
    expect(find.byType(BarRow), findsNothing);
    expect(find.text('لا توجد تأكيدات بعد'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a line without return trips keeps its column, and says it has none', (tester) async {
    await _home(tester, BoardWorld(dashboard: boardDashboard(returns: false)));
    expect(find.descendant(of: find.byKey(const Key('trips-return')), matching: find.text('لا رحلات بعد')),
        findsOneWidget);
    expect(tester.widget<CountsHero>(find.byKey(const Key('counts-hero-0'))).returningTrips, 'لا رحلات');
  });

  testWidgets('loading with nothing saved: a skeleton in the shape of Home', (tester) async {
    await pumpBoard(tester, BoardWorld(loading: true), SupervisorHomeScreen(onOpenTrips: () {}));
    expect(find.byType(SupervisorHomeSkeleton), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'جارٍ تحميل أعداد الركاب'), findsOneWidget);
    expect(find.byType(CountsHero), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing saved and the load failed: the header and the bell stay, a plain message, a retry',
      (tester) async {
    final world = BoardWorld(dashboardFails: true);
    await pumpBoard(tester, world, SupervisorHomeScreen(onOpenTrips: () {}));
    await tester.pumpAndSettle();
    expect(findBell('التنبيهات، 2 غير مقروءة'), findsOneWidget);
    expect(find.text('تعذّر تحميل بيانات الخط'), findsOneWidget);
    expect(find.text('تحقّق من الاتصال بالإنترنت ثم أعد المحاولة.'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing, reason: 'never the raw error');
    expect(find.textContaining('boom'), findsNothing);

    world.dashboardFails = false;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.byType(CountsHero), findsNWidgets(2));
  });

  testWidgets('no line assigned: the header and the bell stay; one sentence and "تحديث"', (tester) async {
    final world = BoardWorld(dashboard: boardDashboard(lines: 0), unread: 0);
    await _home(tester, world);
    expect(find.text('محمود السيد'), findsOneWidget);
    expect(findBell('التنبيهات'), findsOneWidget);
    expect(find.text('لا يوجد خط مسند إليك'), findsOneWidget);
    expect(find.text('ستظهر الرحلات والركاب هنا بمجرد أن تسند الشركة خطاً إلى حسابك.'), findsOneWidget);
    expect(find.text('إشعار للطلاب'), findsNothing);

    final before = world.dashboardReads;
    world.dashboard = boardDashboard();
    await tester.tap(find.text('تحديث'));
    await tester.pumpAndSettle();
    expect(world.dashboardReads, before + 1);
    expect(find.byType(CountsHero), findsNWidgets(2));
  });

  testWidgets('offline with saved numbers: the day as saved, the time of the data, and what it means at the door',
      (tester) async {
    OfflineCache.markOffline(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 6, 48));
    final world = BoardWorld();
    await _home(tester, world);
    final strip = tester.widget<ConnectionStrip>(find.byType(ConnectionStrip));
    expect(strip.state, ConnectionStripState.offline);
    expect(strip.dataTime, '6:48 ص');
    expect(strip.note, 'المسح لا يسجّل الصعود الآن');
    expect(find.textContaining('بدون إنترنت · بيانات 6:48 ص · المسح لا يسجّل الصعود الآن'), findsOneWidget);
    expect(find.byType(CountsHero), findsNWidgets(2), reason: 'the saved day is still shown');

    final before = world.dashboardReads;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(world.dashboardReads, greaterThan(before));
  });

  testWidgets('nothing clips at 360 × 640, nor with large text', (tester) async {
    await loadBoardFonts(tester);
    final world = BoardWorld(capacities: {'line-a': 30});
    await pumpBoard(tester, world, SupervisorHomeScreen(onOpenTrips: () {}),
        size: const Size(360, 640), textScale: 1.3);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('إشعار للطلاب'), findsOneWidget);
  });

  test('the selection: a line clears the trip, a trip keeps the line, and the key is direction and time', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final chosen = c.read(supervisorSelectionProvider.notifier);
    expect(c.read(supervisorSelectionProvider).tripKey, isNull);
    chosen.selectLine('line-a');
    chosen.selectTrip(direction: TripDirection.returning, time: '15:30:00');
    expect(c.read(supervisorSelectionProvider).lineId, 'line-a');
    expect(c.read(supervisorSelectionProvider).tripKey, 'return|15:30');
    expect(c.read(supervisorSelectionProvider).direction?.wire, 'return');
    chosen.clearTrip();
    expect(c.read(supervisorSelectionProvider), const SupervisorSelection(lineId: 'line-a'));
    chosen.selectTrip(direction: TripDirection.departure, time: '07:00', tripId: 't');
    chosen.selectLine('line-b');
    expect(c.read(supervisorSelectionProvider), const SupervisorSelection(lineId: 'line-b'));
    chosen.reset();
    expect(c.read(supervisorSelectionProvider), const SupervisorSelection());
    expect(TripDirection.fromWire('return'), TripDirection.returning);
    expect(TripDirection.fromWire('departure'), TripDirection.departure);
  });
}
