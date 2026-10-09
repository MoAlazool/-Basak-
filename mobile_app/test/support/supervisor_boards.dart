// The supervisor's day as the canvas boards draw it (SupHome, SupTrip, …),
// and a way to put Home, Trips or the shell on screen over it: no server, a
// fixed clock, the real screens and providers above the repository.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/core/widgets/floating_glass_nav_bar.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/supervisor/data/supervisor_repository.dart';
import 'package:basak_mobile/features/supervisor/home/presentation/supervisor_home_screen.dart';
import 'package:basak_mobile/features/supervisor/models/supervisor_models.dart';
import 'package:basak_mobile/features/supervisor/trips/presentation/supervisor_trips_screen.dart';

import 'notification_fakes.dart';

/// Sunday 11 October 2026, as on the boards.
const boardToday = '2026-10-11';
const boardTomorrow = '2026-10-12';

/// 6:50 in the morning: the 6:15 trip has gone, 7:00 is next.
final boardMorning = DateTime(2026, 10, 11, 6, 50);

/// 7:30 in the evening: tomorrow's confirmation is open.
final boardEvening = DateTime(2026, 10, 11, 19, 30);

const _going = ['06:15:00', '07:00:00', '07:45:00', '08:30:00', '09:15:00'];
const _returning = ['12:30:00', '13:30:00', '14:30:00', '15:30:00', '16:30:00', '17:30:00'];

String tripIdOf(String direction, String time) => '${direction == 'return' ? 'r' : 'd'}-${time.substring(0, 5)}';

List<Map<String, dynamic>> boardTrips({bool returns = true}) => [
      for (final t in _going)
        {'id': tripIdOf('departure', t), 'direction': 'departure', 'departure_time': t, 'arrival_time': '08:20:00'},
      if (returns)
        for (final t in _returning) {'id': tripIdOf('return', t), 'direction': 'return', 'departure_time': t},
    ];

const _stops = [
  ('s1', 'موقف الزرقا', '07:00:00'),
  ('s2', 'ميت الخولي', '07:07:00'),
  ('s3', 'شرباص', '07:15:00'),
  ('s4', 'كوبري السرو', '07:23:00'),
  ('s5', 'السرو', '07:30:00'),
  ('s6', 'الروضة', '07:40:00'),
  ('s7', 'فارسكور', '07:50:00'),
];

Map<String, dynamic> _riders(String day, String line, String direction, String time, int students,
        {bool breakdown = false}) =>
    {
      'ride_date': day, 'line_id': line, 'line_name': 'الزرقا', 'direction': direction, 'time': time,
      'students': students, 'trip_id': tripIdOf(direction, time),
      if (breakdown) ...{
        'stations': [
          for (final (i, (id, name, stop)) in _stops.indexed)
            {'id': id, 'name': name, 'order_index': i + 1, 'stop_time': stop, 'students': i == 2 ? 2 : 0},
        ],
        'riders': [
          {'id': 'r1', 'full_name': 'ندى إبراهيم خليل', 'phone': '01012345678', 'station_id': 's3', 'station': 'شرباص',
            'university': 'جامعة المنصورة الجديدة', 'time': '07:15:00'},
          {'id': 'r2', 'full_name': 'كريم محمد عبد الله', 'phone': '01098765432', 'station_id': 's3',
            'station': 'شرباص', 'university': 'جامعة المنصورة الجديدة', 'time': '07:15:00'},
        ],
      },
    };

/// get_supervisor_dashboard() as on SupHome: خط الزرقا, 107 going in 5 trips,
/// 105 returning in 6, and tomorrow's 64 and 58.
Map<String, dynamic> boardDashboard({
  int lines = 3,
  bool active = true,
  bool returns = true,
  bool riders = true,
  bool tripsListed = true,
  bool firstLineStopped = false,
  int todaySevenOClock = 38,
}) {
  const today = [12, 38, 27, 21, 9], back = [8, 14, 22, 31, 19, 11];
  const tomorrow = [7, 24, 15, 13, 5], tomorrowBack = [4, 8, 12, 19, 10, 5];
  const all = [
    ('line-a', 'الزرقا', 'جامعة المنصورة الجديدة', 124, true),
    ('line-b', 'دمياط الجديدة', 'جامعة دمياط', 86, true),
    ('line-c', 'السنبلاوين', 'جامعة المنصورة', 52, false),
  ];
  return {
    'today': boardToday,
    'profile': {
      'id': 'supervisor-1', 'full_name': 'محمود السيد', 'phone': '01011223344', 'is_active': active,
      'company_id': 'company-1', 'company_name': 'النورس للنقل', 'company_active': true,
      'assignment': lines == 0 ? 'none' : 'direct',
      'vote': {'opens_at': '16:00', 'closes_at': '06:00'},
    },
    'totals': {'lines': lines, 'registered_students': 124},
    'lines': [
      for (final (i, (id, name, university, students, isActive)) in all.take(lines).indexed)
        {
          'id': id, 'name': name, 'is_active': i == 0 ? !firstLineStopped : isActive, 'directly_assigned': true,
          'registered_students': students, 'destination': university,
          if (tripsListed) 'trips': i == 0 ? boardTrips(returns: returns) : boardTrips().take(2).toList(),
        },
    ],
    'trip_times': [
      if (riders && lines > 0) ...[
        for (final (i, t) in _going.indexed)
          _riders(boardToday, 'line-a', 'departure', t, i == 1 ? todaySevenOClock : today[i]),
        if (returns)
          for (final (i, t) in _returning.indexed) _riders(boardToday, 'line-a', 'return', t, back[i]),
        for (final (i, t) in _going.indexed)
          _riders(boardTomorrow, 'line-a', 'departure', t, tomorrow[i], breakdown: i == 1),
        if (returns)
          for (final (i, t) in _returning.indexed) _riders(boardTomorrow, 'line-a', 'return', t, tomorrowBack[i]),
        if (lines > 1) _riders(boardToday, 'line-b', 'departure', '06:15:00', 4),
      ],
    ],
  };
}

Map<String, dynamic> _student(String id, String name, {String? boarded, String phone = '01098765432'}) => {
      'id': id, 'full_name': name, 'phone': phone, 'university': 'جامعة المنصورة الجديدة', 'confirmed': true,
      'chosen_time': '07:15:00', if (boarded != null) 'checked_in_at': '${boardToday}T$boarded:00',
    };

/// get_supervisor_trip_manifest() as on SupTrip: the 7:00 trip, 14 of 38
/// boarded, seven stops, five subscribers who did not confirm.
Map<String, dynamic> boardManifest({String direction = 'departure', bool trips = true, int unconfirmed = 5}) {
  final expected = [6, 4, 5, 8, 6, 5, 4];
  return {
    'line': {'id': 'line-a', 'name': 'الزرقا', 'origin_name': 'الزرقا', 'destination': 'جامعة المنصورة الجديدة'},
    'direction': direction,
    'trips': [
      if (trips)
        for (final t in direction == 'return' ? _returning : _going)
          {'id': tripIdOf(direction, t), 'label': '', 'start_time': t, 'arrival_time': '08:20:00', 'students': 9},
    ],
    'trip': trips
        ? {
            'id': tripIdOf(direction, direction == 'return' ? '15:30:00' : '07:00:00'), 'label': '',
            'start_time': direction == 'return' ? '15:30:00' : '07:00:00', 'arrival_time': '08:20:00',
          }
        : null,
    'stations': [
      if (trips)
        for (final (i, (id, name, stop)) in _stops.indexed)
          {
            'id': id, 'name': name, 'stop_time': stop,
            'students': i == 2
                ? [
                    _student('k', 'كريم محمد عبد الله'),
                    _student('n', 'ندى إبراهيم خليل', boarded: '07:15'),
                    _student('a', 'أحمد سامي فتحي', boarded: '07:16'),
                    _student('m', 'منة الله عادل حسين', boarded: '07:16'),
                    _student('y', 'يوسف طارق حسن', boarded: '07:17'),
                  ]
                : [
                    for (var n = 0; n < expected[i]; n++)
                      _student('$id-$n', 'راكب ${i + 1}-${n + 1}', boarded: i < 2 ? '07:0${i * 7}' : null),
                  ],
          },
    ],
    'unconfirmed': [
      for (var n = 0; n < unconfirmed; n++)
        {'id': 'u$n', 'full_name': 'مشترك ${n + 1}', 'phone': '0100000000$n', 'station': 'شرباص'},
    ],
  };
}

class _Auth extends AuthNotifier {
  _Auth() : super(AuthRepository()) {
    state = const AuthState(
        user: User(id: 'supervisor-1', appMetadata: {}, userMetadata: {}, aud: '', createdAt: ''),
        role: UserRole.supervisor);
  }
}

class _Dashboard extends SupervisorDashboardNotifier {
  final BoardWorld world;
  _Dashboard(this.world);

  @override
  Future<SupervisorDashboard> build() async {
    world.dashboardReads++;
    if (world.loading) return Completer<SupervisorDashboard>().future;
    if (world.dashboardFails) throw Exception('PostgrestException(message: boom, code: 500)');
    return SupervisorDashboard.fromJson(world.dashboard);
  }
}

/// What the screens are shown over. Change a field and pull to refresh (or
/// invalidate the provider) to see the next state.
class BoardWorld {
  Map<String, dynamic> dashboard;
  Map<String, dynamic> Function(ManifestKey key) manifest;
  Map<String, int> capacities;
  DateTime now;
  int unread;
  bool loading;
  bool dashboardFails;
  bool manifestFails;
  int dashboardReads = 0;
  final manifestKeys = <ManifestKey>[];
  final shared = <String>[];

  BoardWorld({
    Map<String, dynamic>? dashboard,
    Map<String, dynamic> Function(ManifestKey key)? manifest,
    this.capacities = const {},
    DateTime? now,
    this.unread = 2,
    this.loading = false,
    this.dashboardFails = false,
    this.manifestFails = false,
  })  : dashboard = dashboard ?? boardDashboard(),
        manifest = manifest ?? ((key) => boardManifest(direction: key.direction)),
        now = now ?? boardMorning;

  List<Override> get overrides => [
        sessionUserIdProvider.overrideWithValue('supervisor-1'),
        authStateProvider.overrideWith((ref) => _Auth()),
        supervisorDashboardProvider.overrideWith(() => _Dashboard(this)),
        supervisorPhotoUrlProvider.overrideWith((ref) async => null),
        lineCapacitiesProvider.overrideWith((ref) async => capacities),
        tripManifestProvider.overrideWith((ref, key) async {
          manifestKeys.add(key);
          if (manifestFails) throw Exception('PostgrestException(message: relation does not exist, code: 42P01)');
          return TripManifest.fromJson(manifest(key));
        }),
        supervisorClockProvider.overrideWithValue(() => now),
        shareCountsProvider.overrideWithValue((text) async => shared.add(text)),
        notificationsRepoProvider
            .overrideWithValue(FakeNotificationsRepo([for (var i = 0; i < unread; i++) note('n$i', 'تنبيه')])),
      ];
}

/// The bell, by what a screen reader calls it ("التنبيهات، 2 غير مقروءة").
Finder findBell(String label) => find.byWidgetPredicate((w) => w is BasakIconButton && w.label == label);

/// The dot of a pager's page [index]: the tap alternative to the swipe.
Finder findPagerDot(int index) =>
    find.descendant(of: find.byType(PagerDots), matching: find.byType(BasakPressable)).at(index);

/// The app's own fonts instead of the test font (whose every letter is a
/// square): for pictures, and for checking that nothing overflows.
Future<void> loadBoardFonts(WidgetTester tester) => tester.runAsync(() async {
      Future<ByteData> file(String name) async =>
          ByteData.view((await File('assets/fonts/$name').readAsBytes()).buffer);
      final readex = FontLoader('ReadexPro');
      for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        readex.addFont(file('ReadexPro-$f.ttf'));
      }
      await readex.load();
      await (FontLoader('Lucide')..addFont(file('lucide.ttf'))).load();
    });

/// [screen] in the app's frame: Arabic, the theme, and — with [tab] — the
/// floating tab bar over the page's bottom, as the shell draws it.
Future<void> pumpBoard(
  WidgetTester tester,
  BoardWorld world,
  Widget screen, {
  int? tab = 0,
  Size size = const Size(390, 844),
  /// Null: the text scale of the test itself (RENDER_SCALE, see flutter_test_config.dart).
  double? textScale,
  Key? boundaryKey,
  List<Override> more = const [],
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [...world.overrides, ...more],
    child: RepaintBoundary(
      key: boundaryKey,
      child: MaterialApp(
        // A boundary with a global key would carry the last screen's state over.
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: textScale == null
              ? MediaQuery.of(context)
              : MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: tab == null
            ? screen
            : Scaffold(
                extendBody: true,
                body: screen,
                bottomNavigationBar: FloatingGlassNavBar(
                  currentIndex: tab,
                  onTabSelected: (_) {},
                  items: FloatingGlassNavBar.supervisorNavItems,
                ),
              ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}
