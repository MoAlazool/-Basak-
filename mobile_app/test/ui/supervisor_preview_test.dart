// Draws the supervisor's Home and Trips in each of their states, and the
// sheets they open, to PNG files with the app's real fonts: a look at the
// layout without a device, to hold against the canvas boards (SupHome,
// SupHomeTomorrow, SupLineSheet, SupTrip, SupTripSheet, SupRider,
// SupTripEmpty, SupState*). Skipped unless RENDER_DIR is set:
//   RENDER_DIR=/tmp/basak-sup flutter test test/ui/supervisor_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/features/supervisor/home/presentation/supervisor_home_screen.dart';
import 'package:basak_mobile/features/supervisor/selection/supervisor_selection.dart';
import 'package:basak_mobile/features/supervisor/supervisor_main_screen.dart';
import 'package:basak_mobile/features/supervisor/trips/presentation/supervisor_trips_screen.dart';

import '../support/supervisor_boards.dart';

final _dir = Platform.environment['RENDER_DIR'];
final _key = GlobalKey();

Future<void> _shot(WidgetTester tester, String name, {bool settle = true}) async {
  if (settle) await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> _home(WidgetTester tester, BoardWorld world, {Size size = const Size(390, 1100), double scale = 1}) =>
    pumpBoard(tester, world, SupervisorHomeScreen(onOpenTrips: () {}),
        size: size, textScale: scale, boundaryKey: _key);

Future<void> _trips(WidgetTester tester, BoardWorld world, {Size size = const Size(390, 1190), double scale = 1}) =>
    pumpBoard(tester, world, const SupervisorTripsScreen(),
        tab: 1, size: size, textScale: scale, boundaryKey: _key);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('draw the supervisor\'s Home in each state', (tester) async {
    debugDisableShadows = false;
    await loadBoardFonts(tester);
    Directory(_dir!).createSync(recursive: true);

    await _home(tester, BoardWorld());
    await _shot(tester, 'sup-home-1-today');

    await tester.tap(find.byKey(const Key('line-row')));
    await _shot(tester, 'sup-home-2-line-sheet');
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await _home(tester, BoardWorld(now: boardEvening));
    await _shot(tester, 'sup-home-3-tomorrow');

    await _home(tester, BoardWorld(capacities: {'line-a': 30}, dashboard: boardDashboard(lines: 1)));
    await _shot(tester, 'sup-home-4-capacity-one-line');

    await _home(tester, BoardWorld(), size: const Size(360, 640));
    await _shot(tester, 'sup-home-5-360x640');
    await _home(tester, BoardWorld(capacities: {'line-a': 30}), size: const Size(360, 1500), scale: 1.3);
    await _shot(tester, 'sup-home-6-360-large-text');

    await _home(tester, BoardWorld(dashboard: boardDashboard(riders: false)));
    await _shot(tester, 'sup-home-7-no-confirmations');

    await _home(tester, BoardWorld(dashboardFails: true), size: const Size(390, 844));
    await _shot(tester, 'sup-state-error');
    await _home(tester, BoardWorld(dashboard: boardDashboard(lines: 0), unread: 0), size: const Size(390, 844));
    await _shot(tester, 'sup-state-no-line');
    await _home(tester, BoardWorld(loading: true), size: const Size(390, 844));
    await _shot(tester, 'sup-state-loading', settle: false);

    final now = DateTime.now();
    OfflineCache.markOffline(DateTime(now.year, now.month, now.day, 6, 48));
    addTearDown(OfflineCache.markOnline);
    await _home(tester, BoardWorld(), size: const Size(390, 844));
    await _shot(tester, 'sup-state-offline');
    OfflineCache.markOnline();
    await tester.pump(const Duration(seconds: 3));

    await pumpBoard(tester, BoardWorld(dashboard: boardDashboard(active: false)), const SupervisorMainScreen(),
        tab: null, boundaryKey: _key);
    await _shot(tester, 'sup-state-suspended');
    await tester.pump(const Duration(seconds: 4));
    debugDisableShadows = true;
  }, skip: _dir == null);

  testWidgets('draw the supervisor\'s Trips in each state', (tester) async {
    debugDisableShadows = false;
    await loadBoardFonts(tester);
    Directory(_dir!).createSync(recursive: true);
    final morning = DateTime(2026, 10, 11, 7, 18);

    await _trips(tester, BoardWorld(now: morning));
    await tester.tap(find.text('شرباص'));
    await _shot(tester, 'sup-trip-1');

    await tester.tap(find.text('كريم محمد عبد الله'));
    await _shot(tester, 'sup-trip-2-rider');
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تغيير'));
    await _shot(tester, 'sup-trip-3-trip-sheet');
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const Key('unconfirmed')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('لم يؤكّدوا اليوم · 5'));
    await _shot(tester, 'sup-trip-4-unconfirmed-open');

    await _trips(
        tester,
        BoardWorld(
          now: DateTime(2026, 10, 11, 14),
          dashboard: boardDashboard(returns: false),
          manifest: (key) => boardManifest(direction: key.direction, trips: key.direction == 'departure'),
        ),
        size: const Size(390, 844));
    await _shot(tester, 'sup-trip-5-empty');

    await _trips(tester, BoardWorld(manifestFails: true), size: const Size(390, 844));
    await _shot(tester, 'sup-trip-6-error');

    await _trips(tester, BoardWorld(now: morning, capacities: {'line-a': 30}), size: const Size(360, 640));
    await tester.tap(find.text('شرباص'));
    await _shot(tester, 'sup-trip-7-360x640');
    await tester.tap(find.text('تغيير'));
    await _shot(tester, 'sup-trip-8-sheet-360x640');
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await pumpBoard(tester, BoardWorld(now: boardEvening), const SupervisorTripsScreen(),
        tab: 1,
        size: const Size(390, 1000),
        boundaryKey: _key,
        more: [supervisorTripDayProvider.overrideWith((ref) => DateTime(2026, 10, 12))]);
    ProviderScope.containerOf(tester.element(find.byType(SupervisorTripsScreen)))
        .read(supervisorSelectionProvider.notifier)
        .selectTrip(direction: TripDirection.departure, time: '07:00:00', tripId: 'd-07:00');
    await tester.pumpAndSettle();
    await tester.tap(find.text('شرباص'));
    await _shot(tester, 'sup-trip-9-tomorrow');

    await _trips(tester, BoardWorld(loading: true), size: const Size(390, 844));
    await _shot(tester, 'sup-trip-10-loading', settle: false);
    debugDisableShadows = true;
  }, skip: _dir == null);
}
