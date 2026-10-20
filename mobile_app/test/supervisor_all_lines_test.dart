// «كل الخطوط»: a supervisor of several lines sees their numbers together, and
// a trip's riders by university.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/features/supervisor/home/presentation/line_sheet.dart';
import 'package:basak_mobile/features/supervisor/home/presentation/supervisor_home_screen.dart';
import 'package:basak_mobile/features/supervisor/notifications/supervisor_send_screen.dart';
import 'package:basak_mobile/features/supervisor/selection/supervisor_selection.dart';
import 'package:basak_mobile/features/supervisor/trips/presentation/supervisor_trips_screen.dart';

import 'support/supervisor_boards.dart';

ProviderContainer _container(WidgetTester tester, Type screen) =>
    ProviderScope.containerOf(tester.element(find.byType(screen)));

/// The boards' three lines, and the 1:30 return of today on two of them, by university.
Map<String, dynamic> _dashboard() {
  final json = boardDashboard();
  final times = (json['trip_times'] as List).cast<Map<String, dynamic>>();
  final aReturn = times.firstWhere(
      (t) => t['ride_date'] == boardToday && t['line_id'] == 'line-a' && t['time'] == '13:30:00');
  aReturn['universities'] = [
    {'name': 'جامعة المنصورة الجديدة', 'students': 10},
    {'name': 'جامعة الدلتا', 'students': 4},
  ];
  times.add({
    'ride_date': boardToday, 'line_id': 'line-b', 'line_name': 'دمياط الجديدة', 'direction': 'return',
    'time': '13:30:00', 'students': 7, 'trip_id': 'b-r-13:30',
    'universities': [
      {'name': 'جامعة الدلتا', 'students': 7},
    ],
  });
  return json;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(OfflineCache.markOnline);

  testWidgets('the line sheet offers every line together; Home adds their trips up', (tester) async {
    final world = BoardWorld(dashboard: _dashboard());
    await pumpBoard(tester, world, SupervisorHomeScreen(onOpenTrips: () {}), size: const Size(390, 1100));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('line-row')));
    await tester.pumpAndSettle();
    final all = tester.widget<RadioCard>(find.byKey(const Key('line-all')));
    expect((all.title, all.subtitle), ('كل الخطوط', '3 خطوط · 262 مشتركاً'));
    expect(all.selected, isFalse);

    await tester.tap(find.byKey(const Key('line-all')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('line-confirm')));
    await tester.pumpAndSettle();

    expect(_container(tester, SupervisorHomeScreen).read(supervisorSelectionProvider).isAllLines, isTrue);
    final row = tester.widget<LineSwitchRow>(find.byKey(const Key('line-row')));
    expect((row.name, row.caption, row.tag), ('كل الخطوط', 'النورس للنقل · 3 خطوط', null));
    final hero = tester.widget<CountsHero>(find.byKey(const Key('counts-hero-0')));
    // 107 going on الزرقا and 4 on دمياط الجديدة; 105 + 7 returning.
    expect((hero.going, hero.returning), (111, 112));
    expect(hero.shareSentence, 'سيركب 111 من 262 مشتركاً');
    // Each column lists the lines with their rider totals, not the times.
    expect(tester.widget<BarRow>(find.byKey(const Key('line-departure-line-a'))).count, 107);
    expect(tester.widget<BarRow>(find.byKey(const Key('line-departure-line-b'))).count, 4);
    expect(tester.widget<BarRow>(find.byKey(const Key('line-return-line-a'))).count, 105);
    expect(tester.widget<BarRow>(find.byKey(const Key('line-return-line-b'))).count, 7);
    expect(find.byKey(const Key('trip-departure-06:15:00')), findsNothing, reason: 'every line together lists lines, not times');

    // The sheet opens on the choice.
    await tester.tap(find.byKey(const Key('line-row')));
    await tester.pumpAndSettle();
    expect(tester.widget<RadioCard>(find.byKey(const Key('line-all'))).selected, isTrue);
    expect(find.byType(SupervisorLineSheet), findsOneWidget);
  });

  testWidgets('tapping a line in the every-lines view opens its own trips', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var opened = 0;
    final world = BoardWorld(dashboard: _dashboard());
    await pumpBoard(tester, world, SupervisorHomeScreen(onOpenTrips: () => opened++), size: const Size(390, 1100));
    await tester.pumpAndSettle();
    final c = _container(tester, SupervisorHomeScreen);
    c.read(supervisorSelectionProvider.notifier).selectLine(SupervisorSelection.allLines);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('line-departure-line-b')));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(c.read(supervisorSelectionProvider).lineId, 'line-b');
    expect(c.read(supervisorSelectionProvider).isAllLines, isFalse);
  });

  testWidgets('the chosen line is remembered for the account, through a restart', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final world = BoardWorld();
    await pumpBoard(tester, world, SupervisorHomeScreen(onOpenTrips: () {}), size: const Size(390, 1100));
    await tester.pumpAndSettle();
    final c = _container(tester, SupervisorHomeScreen);

    c.read(supervisorSelectionProvider.notifier).selectLine('line-b');
    await tester.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getString('basak.sup.line.supervisor-1'), 'line-b');

    // A fresh launch restores the line from storage (the trip starts cleared).
    c.read(supervisorSelectionProvider.notifier).selectTrip(direction: TripDirection.departure, time: '07:00:00');
    await c.read(supervisorSelectionProvider.notifier).restore();
    await tester.pumpAndSettle();
    expect(c.read(supervisorSelectionProvider).lineId, 'line-b');
  });

  testWidgets('one line only: no «كل الخطوط» in the sheet', (tester) async {
    final world = BoardWorld(dashboard: boardDashboard(lines: 1, firstLineStopped: true));
    await pumpBoard(tester, world, SupervisorHomeScreen(onOpenTrips: () {}), size: const Size(390, 1100));
    await tester.pumpAndSettle();
    _container(tester, SupervisorHomeScreen).read(supervisorSelectionProvider.notifier)
        .selectLine(SupervisorSelection.allLines);
    await tester.pumpAndSettle();
    expect(tester.widget<LineSwitchRow>(find.byKey(const Key('line-row'))).name, 'خط الزرقا',
        reason: 'a choice of every line means the one line');
  });

  testWidgets('Trips, every line: the 1:30 return by university and by line; a line opens its own trip',
      (tester) async {
    final world = BoardWorld(dashboard: _dashboard(), now: DateTime(2026, 10, 11, 13, 0));
    await pumpBoard(tester, world, const SupervisorTripsScreen(), tab: 1, size: const Size(390, 1400));
    await tester.pumpAndSettle();
    final c = _container(tester, SupervisorTripsScreen);
    world.manifestKeys.clear();
    c.read(supervisorSelectionProvider.notifier).selectLine(SupervisorSelection.allLines);
    c.read(supervisorSelectionProvider.notifier)
        .selectTrip(direction: TripDirection.returning, time: '13:30:00');
    await tester.pumpAndSettle();

    final card = tester.widget<TripCard>(find.byKey(const Key('trip-card')));
    expect((card.time, card.direction, card.detail), ('1:30 م', 'عودة', 'كل الخطوط · خطان'));
    expect(find.text('سيركب 21 طالباً'), findsOneWidget);
    expect(world.manifestKeys, isEmpty, reason: 'every line together is read from the dashboard');

    expect(find.text('حسب الجامعة'), findsOneWidget);
    final delta = tester.widget<Meter>(find.byKey(const Key('university-جامعة الدلتا')));
    final mansoura = tester.widget<Meter>(find.byKey(const Key('university-جامعة المنصورة الجديدة')));
    expect((delta.value, delta.share), ('11', 1.0));
    expect(mansoura.value, '10');
    expect(tester.getTopLeft(find.byWidget(delta)).dy, lessThan(tester.getTopLeft(find.byWidget(mansoura)).dy),
        reason: 'most riders first');

    expect(find.text('حسب الخط'), findsOneWidget);
    final a = tester.widget<PersonRow>(find.byKey(const Key('by-line-line-a')));
    final b = tester.widget<PersonRow>(find.byKey(const Key('by-line-line-b')));
    expect((a.name, a.caption), ('خط الزرقا', '14 طالباً'));
    expect((b.name, b.caption), ('خط دمياط الجديدة', '7 طلاب'));

    await tester.tap(find.byKey(const Key('by-line-line-b')));
    await tester.pumpAndSettle();
    final selection = c.read(supervisorSelectionProvider);
    expect((selection.lineId, selection.tripKey, selection.tripId), ('line-b', 'return|13:30', 'b-r-13:30'));
    expect(world.manifestKeys.last, (lineId: 'line-b', direction: 'return', tripId: 'b-r-13:30'));
  });

  testWidgets('one line, a return trip: its riders by university, from the trip itself', (tester) async {
    final world = BoardWorld(
      now: DateTime(2026, 10, 11, 15, 0),
      manifest: (key) {
        final json = boardManifest(direction: key.direction);
        final stations = (json['stations'] as List).cast<Map<String, dynamic>>();
        for (final s in (stations.first['students'] as List).cast<Map<String, dynamic>>()) {
          s['university'] = 'جامعة الدلتا';
        }
        return json;
      },
    );
    await pumpBoard(tester, world, const SupervisorTripsScreen(), tab: 1, size: const Size(390, 1600));
    await tester.pumpAndSettle();
    _container(tester, SupervisorTripsScreen).read(supervisorSelectionProvider.notifier)
        .selectTrip(direction: TripDirection.returning, time: '15:30:00', tripId: 'r-15:30');
    await tester.pumpAndSettle();

    // 38 riders: 6 at the first stop from الدلتا, the rest from المنصورة الجديدة.
    expect(tester.widget<Meter>(find.byKey(const Key('university-جامعة المنصورة الجديدة'))).value, '32');
    expect(tester.widget<Meter>(find.byKey(const Key('university-جامعة الدلتا'))).value, '6');
  });

  testWidgets('every university the lines serve is listed, nobody confirmed from it said with 0', (tester) async {
    final world = BoardWorld(
      dashboard: _dashboard(),
      now: DateTime(2026, 10, 11, 13, 0),
      universities: {
        'line-a': ['جامعة المنصورة الجديدة', 'جامعة الدلتا'],
        'line-b': ['جامعة الدلتا', 'جامعة حورس'],
      },
    );
    await pumpBoard(tester, world, const SupervisorTripsScreen(), tab: 1, size: const Size(390, 1400));
    await tester.pumpAndSettle();
    final c = _container(tester, SupervisorTripsScreen);
    c.read(supervisorSelectionProvider.notifier).selectLine(SupervisorSelection.allLines);
    c.read(supervisorSelectionProvider.notifier).selectTrip(direction: TripDirection.returning, time: '13:30:00');
    await tester.pumpAndSettle();
    expect(tester.widget<Meter>(find.byKey(const Key('university-جامعة حورس'))).value, '0');
    expect(tester.getTopLeft(find.byKey(const Key('university-جامعة حورس'))).dy,
        greaterThan(tester.getTopLeft(find.byKey(const Key('university-جامعة المنصورة الجديدة'))).dy),
        reason: 'after those riders come from');

    // A trip nobody confirmed still lists them.
    c.read(supervisorSelectionProvider.notifier).selectTrip(direction: TripDirection.returning, time: '17:30:00');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('by-university')), findsOneWidget);
    expect(tester.widget<Meter>(find.byKey(const Key('university-جامعة الدلتا'))).value, '0');
  });

  testWidgets('one line, today, nobody confirmed the return: its universities with 0', (tester) async {
    final world = BoardWorld(
      now: DateTime(2026, 10, 11, 15, 0),
      universities: {'line-a': ['جامعة المنصورة الجديدة', 'جامعة الدلتا']},
      manifest: (key) => boardManifest(direction: key.direction)..['stations'] = <Map<String, dynamic>>[],
    );
    await pumpBoard(tester, world, const SupervisorTripsScreen(), tab: 1, size: const Size(390, 1400));
    await tester.pumpAndSettle();
    _container(tester, SupervisorTripsScreen).read(supervisorSelectionProvider.notifier)
        .selectTrip(direction: TripDirection.returning, time: '15:30:00', tripId: 'r-15:30');
    await tester.pumpAndSettle();
    expect(tester.widget<Meter>(find.byKey(const Key('university-جامعة الدلتا'))).value, '0');
    expect(tester.widget<Meter>(find.byKey(const Key('university-جامعة المنصورة الجديدة'))).value, '0');
  });

  testWidgets('a departure from one university says nothing by university', (tester) async {
    await pumpBoard(tester, BoardWorld(now: DateTime(2026, 10, 11, 7, 18)), const SupervisorTripsScreen(),
        tab: 1, size: const Size(390, 1190));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('by-university')), findsNothing);
  });

  testWidgets('a message while every line is on screen goes to one line, chosen on the page', (tester) async {
    final world = BoardWorld(dashboard: _dashboard());
    await pumpBoard(tester, world, const SupervisorSendScreen(), tab: null, size: const Size(390, 1100));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('send-line')), findsNothing, reason: 'one line chosen: it is that line');

    _container(tester, SupervisorSendScreen).read(supervisorSelectionProvider.notifier)
        .selectLine(SupervisorSelection.allLines);
    await tester.pumpAndSettle();
    expect(tester.widget<PickRow>(find.byKey(const Key('send-line'))).value, 'خط الزرقا');

    await tester.tap(find.byKey(const Key('send-line')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('line-all')), findsNothing, reason: 'a message goes to one line');
    await tester.tap(find.byKey(const Key('line-line-b')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('line-confirm')));
    await tester.pumpAndSettle();

    expect(tester.widget<PickRow>(find.byKey(const Key('send-line'))).value, 'خط دمياط الجديدة');
    expect(_container(tester, SupervisorSendScreen).read(supervisorSelectionProvider).isAllLines, isTrue,
        reason: 'the app keeps showing every line');
  });
}
