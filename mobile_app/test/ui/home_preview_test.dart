// Draws the student's Home in each of its states, and the sheets it opens, to
// PNG files with the app's real fonts: a look at the layout without a device,
// to hold against the canvas boards. Skipped unless RENDER_DIR is set:
//   RENDER_DIR=/tmp/basak-home flutter test test/ui/home_preview_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/core/widgets/floating_glass_nav_bar.dart';
import 'package:basak_mobile/core/widgets/skeleton.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/notifications/presentation/notifications_host.dart';
import 'package:basak_mobile/features/notifications/presentation/push_permission_sheet.dart';
import 'package:basak_mobile/features/notifications/push/push_messaging.dart';
import 'package:basak_mobile/features/notifications/push/push_providers.dart';
import 'package:basak_mobile/features/student/daily_ride/data/daily_ride_repository.dart';
import 'package:basak_mobile/features/student/daily_ride/models/vote_settings.dart';
import 'package:basak_mobile/features/student/home/presentation/ride_card.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/home/presentation/supervisor_contact_sheet.dart';
import 'package:basak_mobile/features/student/invites/invites.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';

import '../support/notification_fakes.dart';

final _dir = Platform.environment['RENDER_DIR'];
final _key = GlobalKey();

Future<void> _fonts() async {
  Future<ByteData> file(String name) async =>
      ByteData.view((await File('assets/fonts/$name').readAsBytes()).buffer);
  final readex = FontLoader('ReadexPro');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    readex.addFont(file('ReadexPro-$f.ttf'));
  }
  await readex.load();
  await (FontLoader('Lucide')..addFont(file('lucide.ttf'))).load();
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

class _Auth extends AuthNotifier {
  _Auth() : super(AuthRepository()) {
    state = const AuthState(
      user: User(id: 'student-1', appMetadata: {}, userMetadata: {'full_name': 'سارة أحمد محمود'}, aud: '', createdAt: ''),
      role: UserRole.student,
    );
  }
}

class _Sub extends CurrentSubscriptionNotifier {
  final SubscriptionModel? sub;
  final bool never;
  _Sub(this.sub, {this.never = false});

  @override
  Future<SubscriptionModel?> build() => never ? Completer<SubscriptionModel?>().future : Future.value(sub);
}

/// The vote is open all day: the ride question can be drawn at any hour.
const _vote = VoteSettings(opensAt: 0, closesAt: 0, reminderMinutes: 30, offWeekdays: {DateTime.friday});

class _Rides implements DailyRideRepository {
  final bool confirmed;
  _Rides({this.confirmed = false});

  static String _day(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  Future<VoteSettings> getVoteSettings(String? companyId) async => _vote;

  @override
  Future<RideDays> getRides(DateTime start, DateTime end) async {
    final ride = _vote.rideDateFor(DateTime.now());
    return RideDays({
      _day(DateTime(ride.year, ride.month, ride.day - 1)): const DailyRideDetails(isRiding: true),
      if (confirmed)
        _day(ride): const DailyRideDetails(isRiding: true, departureTime: '07:23', returnTime: '15:30'),
    });
  }

  @override
  Future<DailyRideDetails> confirmRide({
    required DateTime rideDate,
    required bool isRiding,
    required String? departureTime,
    required String? returnTime,
    required bool isReturning,
  }) async =>
      DailyRideDetails(
          isRiding: isRiding, departureTime: departureTime, returnTime: returnTime, isReturning: isReturning);
}

class _Invites implements InvitesGateway {
  final List<Map<String, dynamic>> waiting;
  const _Invites(this.waiting);

  @override
  Future<dynamic> myInvites() async => waiting;

  @override
  Future<dynamic> respond(String inviteId, bool accept) async => {'note': null};
}

SubscriptionModel _sub(String status, {String phase = 'current'}) => SubscriptionModel(
      id: 'sub',
      studentId: 'student-1',
      lineId: 'l',
      stationId: 'st',
      type: 'termly',
      status: status,
      price: 4500,
      createdAt: '2026-09-01',
      startDate: '2026-09-20',
      endDate: '2027-01-14',
      lineName: 'الزرقا',
      stationName: 'كوبري السرو',
      departureTimes: const ['06:38', '07:23', '08:08', '08:53', '09:38'],
      returnTimes: const ['12:30', '13:30', '14:30', '15:30', '16:30', '17:30'],
      supervisorName: 'محمود السيد',
      supervisorPhone: '01011223344',
      studentUniversity: 'جامعة المنصورة الجديدة',
      companyName: 'النورس للنقل',
      periodCode: 'first',
      periodPhase: phase,
    );

const _invite = {
  'id': 'i1', 'company_name': 'النورس للنقل', 'line_name': 'الزرقا', 'station_name': 'كوبري السرو',
  'subscription_type': 'termly', 'price': 4500,
};

Future<void> _home(
  WidgetTester tester, {
  SubscriptionModel? sub,
  bool loading = false,
  bool confirmed = false,
  List<Map<String, dynamic>> invites = const [],
  int unread = 2,
  double height = 844,
  PushMessaging? push,
}) async {
  tester.view.physicalSize = Size(390 * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      sessionUserIdProvider.overrideWithValue('student-1'),
      authStateProvider.overrideWith((ref) => _Auth()),
      currentSubscriptionProvider.overrideWith(() => _Sub(sub, never: loading)),
      voteSettingsProvider.overrideWith((ref) async => _vote),
      dailyRideRepoProvider.overrideWithValue(_Rides(confirmed: confirmed)),
      invitesGatewayProvider.overrideWithValue(_Invites(invites)),
      studentProfileSummaryProvider
          .overrideWith((ref, id) async => {'full_name': 'سارة أحمد محمود', 'university': 'جامعة المنصورة الجديدة'}),
      notificationsRepoProvider
          .overrideWithValue(FakeNotificationsRepo([for (var i = 0; i < unread; i++) note('n$i', 'تنبيه')])),
      if (push != null) pushMessagingProvider.overrideWithValue(push),
    ],
    child: RepaintBoundary(
      key: _key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => NotificationsHost(child: child!),
        // Framed as in the app: the floating tab bar over the page's bottom.
        home: Scaffold(
          extendBody: true,
          body: StudentHomeScreen(onNavigateToSubscription: () {}, onNavigateToQr: () {}),
          bottomNavigationBar: FloatingGlassNavBar(
            currentIndex: 0,
            onTabSelected: (_) {},
            items: FloatingGlassNavBar.studentNavItems,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('draw Home in each state', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(_fonts);
    Directory(_dir!).createSync(recursive: true);

    await _home(tester, sub: _sub('active'), height: 920);
    await _shot(tester, 'home-1-active');

    await tester.tap(find.byKey(const Key('ride-yes')));
    await _shot(tester, 'home-2-ride-sheet');
    await tester.tap(find.byKey(const Key('ride-return-none')));
    await _shot(tester, 'home-2b-ride-sheet-no-return');
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('supervisor-card')));
    await _shot(tester, 'home-3-contact-sheet');
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await _home(tester, sub: _sub('active'), confirmed: true, height: 920);
    await _shot(tester, 'home-4-confirmed');

    await _home(tester, unread: 0);
    await _shot(tester, 'home-5-new');

    await _home(tester, invites: [_invite, {..._invite, 'id': 'i2', 'company_name': 'المستقبل'}], unread: 1);
    await _shot(tester, 'home-6-invite');
    await tester.tap(find.byKey(const Key('invite-accept')));
    await _shot(tester, 'home-7-invite-sheet');
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await _home(tester, sub: _sub('pending_review'));
    await _shot(tester, 'home-8-pending');

    await _home(tester, sub: _sub('pending_payment'));
    await _shot(tester, 'home-8b-awaiting-payment');

    final now = DateTime.now();
    OfflineCache.markOffline(DateTime(now.year, now.month, now.day, 8, 15));
    addTearDown(OfflineCache.markOnline);
    await _home(tester, sub: _sub('active'), height: 920);
    await _shot(tester, 'home-9-offline');
    OfflineCache.markOnline();
    await _shot(tester, 'home-9b-back-online');
    await tester.pump(const Duration(seconds: 3));

    await _home(tester, loading: true);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$_dir/home-10-loading.png').writeAsBytes(bytes!.buffer.asUint8List());
    });

    // The banner of a push that arrives while the app is open.
    await _home(tester, sub: _sub('active'), push: FakePushMessaging());
    final container = ProviderScope.containerOf(tester.element(find.byType(StudentHomeScreen)));
    container.read(foregroundBannerProvider.notifier).show(const PushMessage(
          title: 'الباص تحرّك من موقف الزرقا',
          body: 'مشرف الباص · الآن',
          data: {'notification_id': 'n9', 'type': 'transport.departed', 'category': 'transport', 'route': 'home'},
        ));
    await _shot(tester, 'home-11-push-banner');
    container.read(foregroundBannerProvider.notifier).dismiss();
    await tester.pumpAndSettle();
    debugDisableShadows = true;
  }, skip: _dir == null);

  testWidgets('draw the ride card where there is nothing to answer, and the push explainer', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(_fonts);
    Directory(_dir!).createSync(recursive: true);
    tester.view.physicalSize = const Size(390 * 2, 1500 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    const vote = VoteSettings.fallback;
    final monday = DateTime(2026, 10, 12);
    final tuesday = DateTime(2026, 10, 13);
    RideCard card(RideMoment moment, DateTime now, {bool offline = false}) =>
        RideCard(moment: moment, now: now, offline: offline, onYes: () {}, onNo: () {}, onEdit: () {});
    final push = FakePushMessaging(granted: PushPermission.notAsked);
    late WidgetRef ref;
    late BuildContext sheetContext;

    await tester.pumpWidget(ProviderScope(
      overrides: [pushMessagingProvider.overrideWithValue(push)],
      child: RepaintBoundary(
        key: _key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: Consumer(builder: (context, r, _) {
              ref = r;
              sheetContext = context;
              return BasakPage(children: [
                // Sunday afternoon, before Monday's vote opens.
                card(
                    RideMoment.resolve(
                        vote: vote,
                        now: DateTime(2026, 10, 11, 14),
                        known: true,
                        riding: false,
                        voted: true,
                        hasDepartures: true),
                    DateTime(2026, 10, 11, 14)),
                // Monday morning, after its vote closed unanswered.
                card(
                    RideMoment.resolve(
                        vote: vote,
                        now: DateTime(2026, 10, 12, 9),
                        known: true,
                        riding: false,
                        voted: false,
                        hasDepartures: true),
                    DateTime(2026, 10, 12, 9)),
                card(
                    RideMoment(
                        kind: RideCardKind.noTimes,
                        day: monday,
                        opens: DateTime(2026, 10, 11, 16),
                        closes: DateTime(2026, 10, 12, 6)),
                    DateTime(2026, 10, 11, 18)),
                card(
                    RideMoment(
                        kind: RideCardKind.ask,
                        day: monday,
                        opens: DateTime(2026, 10, 11, 16),
                        closes: DateTime(2026, 10, 12, 6)),
                    DateTime(2026, 10, 11, 18),
                    offline: true),
                RideCard(
                  moment: RideMoment(
                      kind: RideCardKind.confirmedLocked,
                      day: tuesday,
                      opens: DateTime(2026, 10, 12, 16),
                      closes: DateTime(2026, 10, 13, 6)),
                  now: DateTime(2026, 10, 13, 9),
                  departureLabel: '7:23 ص',
                  onYes: () {},
                  onNo: () {},
                  onEdit: () {},
                ),
                const RideLockedCard(),
                const HomeSkeleton(),
              ]);
            }),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$_dir/ride-states.png').writeAsBytes(bytes!.buffer.asUint8List());
    });

    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    await tester.pump();
    late Future<void> offer;
    await tester.runAsync(() async {
      offer = offerPushNotifications(sheetContext, ref);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() async {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$_dir/push-explain.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await tester.tap(find.text('ليس الآن'));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => offer);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(RepaintBoundary(
      key: _key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => SupervisorContactSheet.show(context,
                    name: 'محمود السيد', phone: '01011223344', lineName: 'الزرقا'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await _shot(tester, 'contact-sheet');
    debugDisableShadows = true;
  }, skip: _dir == null);
}
