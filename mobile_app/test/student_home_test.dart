import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/core/widgets/connection_strip_host.dart';
import 'package:basak_mobile/core/widgets/skeleton.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/student/daily_ride/data/daily_ride_repository.dart';
import 'package:basak_mobile/features/student/daily_ride/models/vote_settings.dart';
import 'package:basak_mobile/features/student/home/data/line_supervisors.dart';
import 'package:basak_mobile/features/student/home/presentation/ride_card.dart';
import 'package:basak_mobile/features/student/home/presentation/ride_sheet.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/invites/invites.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';

import 'support/notification_fakes.dart';

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
  final Object? error;
  _Sub(this.sub, {this.error});

  @override
  Future<SubscriptionModel?> build() async {
    if (error != null) throw error!;
    return sub;
  }
}

/// Open all day, whatever the hour the test runs at.
const _open = VoteSettings(opensAt: 0, closesAt: 0);

class _Rides implements DailyRideRepository {
  final List<({bool riding, String? departure, String? returnTime, bool returning})> saved = [];

  @override
  Future<VoteSettings> getVoteSettings(String? companyId) async => _open;

  @override
  Future<RideDays> getRides(DateTime start, DateTime end) async => const RideDays({});

  @override
  Future<DailyRideDetails> confirmRide({
    required DateTime rideDate,
    required bool isRiding,
    required String? departureTime,
    required String? returnTime,
    required bool isReturning,
  }) async {
    saved.add((riding: isRiding, departure: departureTime, returnTime: returnTime, returning: isReturning));
    return DailyRideDetails(
        isRiding: isRiding, departureTime: departureTime, returnTime: returnTime, isReturning: isReturning);
  }
}

class _Invites implements InvitesGateway {
  final List<Map<String, dynamic>> waiting;
  final List<({String id, bool accept})> answers = [];
  _Invites(this.waiting);

  @override
  Future<dynamic> myInvites() async => waiting;

  @override
  Future<dynamic> respond(String inviteId, bool accept) async {
    answers.add((id: inviteId, accept: accept));
    return {'note': null};
  }
}

SubscriptionModel _sub(String status,
        {List<String> departures = const ['06:38', '07:23', '08:08'],
        List<String> returns = const ['12:30', '15:30']}) =>
    SubscriptionModel(
      id: 'sub',
      studentId: 'student-1',
      lineId: 'l',
      stationId: 'st',
      type: 'termly',
      status: status,
      price: 4500,
      createdAt: '2026-09-01',
      startDate: '2020-01-01',
      endDate: '2099-12-31',
      lineName: 'الزرقا',
      stationName: 'كوبري السرو',
      departureTimes: departures,
      returnTimes: returns,
      supervisorName: 'محمود السيد',
      supervisorPhone: '01011223344',
      studentUniversity: 'جامعة المنصورة الجديدة',
      companyName: 'النورس للنقل',
      periodCode: 'first',
      periodPhase: 'current',
    );

Widget _home({
  SubscriptionModel? sub,
  Object? error,
  _Rides? rides,
  _Invites? invites,
  VoidCallback? toSubscription,
  VoidCallback? toCard,
  double textScale = 1,
  List<LineSupervisor> supervisors = const [],
}) =>
    ProviderScope(
      overrides: [
        sessionUserIdProvider.overrideWithValue('student-1'),
        authStateProvider.overrideWith((ref) => _Auth()),
        currentSubscriptionProvider.overrideWith(() => _Sub(sub, error: error)),
        voteSettingsProvider.overrideWith((ref) async => _open),
        dailyRideRepoProvider.overrideWithValue(rides ?? _Rides()),
        invitesGatewayProvider.overrideWithValue(invites ?? _Invites(const [])),
        studentProfileSummaryProvider.overrideWith((ref, id) async => {'university': 'جامعة المنصورة الجديدة'}),
        notificationsRepoProvider.overrideWithValue(FakeNotificationsRepo()),
        lineSupervisorsProvider.overrideWith((ref) async => supervisors),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
        home: Scaffold(
          body: StudentHomeScreen(
            onNavigateToSubscription: toSubscription ?? () {},
            onNavigateToQr: toCard ?? () {},
          ),
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    OfflineCache.markOnline();
  });
  tearDown(OfflineCache.markOnline);

  group('the ride sheet', () {
    Future<RideChoice? Function()> open(WidgetTester tester,
        {required List<String> departures,
        required List<String> returns,
        String? departure,
        String? returnTime,
        bool returning = true}) async {
      RideChoice? result;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: SizedBox(
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await RideSheet.show(
                  context,
                  title: 'رحلة الغد',
                  subtitle: 'الاثنين 12 أكتوبر · من كوبري السرو',
                  declineLabel: 'لن أركب غداً',
                  departures: departures,
                  returns: returns,
                  departureLabel: (t) => 'ذ $t',
                  returnLabel: (t) => 'ع $t',
                  departure: departure,
                  returnTime: returnTime,
                  returning: returning,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () => result;
    }

    testWidgets('five return times: a grid of three, "لن أعود بالباص" last and full width', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final result = await open(tester,
          departures: ['06:38', '07:23', '08:08', '08:53', '09:38'],
          returns: ['12:30', '13:30', '14:30', '15:30', '16:30']);
      expect(find.text('رحلة الغد'), findsOneWidget);
      expect(find.text('موعد مرور الباص على محطتك'), findsOneWidget);
      expect(find.text('موعد تحرّك الباص من الجامعة'), findsOneWidget);
      expect(find.byType(TimeTile), findsNWidgets(11));

      // Three to a row, the earliest at the start edge (the right, in Arabic).
      final first = tester.getRect(find.byKey(const Key('ride-return-12:30')));
      final third = tester.getRect(find.byKey(const Key('ride-return-14:30')));
      final fourth = tester.getRect(find.byKey(const Key('ride-return-15:30')));
      expect(first.top, third.top);
      expect(first.left, greaterThan(third.left));
      expect(fourth.top, greaterThan(first.top));
      expect(fourth.left, first.left);
      final none = tester.getRect(find.byKey(const Key('ride-return-none')));
      expect(none.top, greaterThan(fourth.top));
      expect(none.width, closeTo(first.right - third.left, 1));

      // The first times are chosen until the student picks others.
      expect(tester.widget<TimeTile>(find.byKey(const Key('ride-departure-06:38'))).selected, isTrue);
      expect(tester.widget<TimeTile>(find.byKey(const Key('ride-return-12:30'))).selected, isTrue);
      await tester.tap(find.byKey(const Key('ride-departure-08:53')));
      await tester.tap(find.byKey(const Key('ride-return-16:30')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ride-confirm')));
      await tester.pumpAndSettle();
      final choice = result()!;
      expect((choice.riding, choice.departure, choice.returnTime, choice.returning), (true, '08:53', '16:30', true));
    });

    testWidgets('one return time keeps its third of the grid; the saved ride is what is chosen', (tester) async {
      final result = await open(tester,
          departures: ['07:00'], returns: ['15:00'], departure: '07:00', returnTime: '15:00', returning: false);
      final only = tester.getRect(find.byKey(const Key('ride-return-15:00')));
      final none = tester.getRect(find.byKey(const Key('ride-return-none')));
      expect(only.width, lessThan(none.width / 2));
      expect(only.right, none.right, reason: 'at the start edge');
      expect(tester.widget<TimeTile>(find.byKey(const Key('ride-return-none'))).selected, isTrue,
          reason: 'the saved ride had no return');
      await tester.tap(find.byKey(const Key('ride-return-15:00')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ride-confirm')));
      await tester.pumpAndSettle();
      expect(result()!.returnTime, '15:00');
    });

    testWidgets('no return trips: only "لن أعود بالباص", already chosen', (tester) async {
      final result = await open(tester, departures: ['07:00', '08:00'], returns: const []);
      expect(find.text('العودة'), findsOneWidget);
      expect(find.byType(TimeTile), findsNWidgets(3));
      expect(tester.widget<TimeTile>(find.byKey(const Key('ride-return-none'))).selected, isTrue);
      await tester.tap(find.byKey(const Key('ride-confirm')));
      await tester.pumpAndSettle();
      final choice = result()!;
      expect((choice.riding, choice.departure, choice.returning), (true, '07:00', false));
    });

    testWidgets('many times on a small phone: the times scroll, "تأكيد الركوب" stays in reach', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String at(int i) => '${(6 + i ~/ 4).toString().padLeft(2, '0')}:${(i % 4 * 15).toString().padLeft(2, '0')}';
      final result = await open(tester,
          departures: [for (var i = 0; i < 20; i++) at(i)], returns: [for (var i = 20; i < 40; i++) at(i)]);
      expect(tester.takeException(), isNull);
      final confirm = tester.getRect(find.byKey(const Key('ride-confirm')));
      expect(confirm.bottom, lessThan(640));
      expect(tester.getRect(find.byKey(const Key('ride-decline'))).bottom, lessThanOrEqualTo(640));
      await tester.ensureVisible(find.byKey(const Key('ride-return-none')));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const Key('ride-confirm'))), confirm, reason: 'pinned, not scrolled away');

      await tester.tap(find.byKey(const Key('ride-decline')));
      await tester.pumpAndSettle();
      expect(result()!.riding, isFalse);
    });
  });

  group('where the vote stands', () {
    const vote = VoteSettings.fallback; // 4 PM the day before → 6 AM
    RideMoment at(DateTime now, {bool known = true, bool riding = false, bool voted = false, bool times = true}) =>
        RideMoment.resolve(
            vote: vote, now: now, known: known, riding: riding, voted: voted || riding, hasDepartures: times);

    test('open: the question, or the confirmed ride, or no times to choose', () {
      final evening = DateTime(2026, 10, 11, 18);
      expect(at(evening).kind, RideCardKind.ask);
      expect(at(evening).day, DateTime(2026, 10, 12));
      expect(at(evening).closes, DateTime(2026, 10, 12, 6));
      expect(at(evening, riding: true).kind, RideCardKind.confirmed);
      expect(at(evening, times: false).kind, RideCardKind.noTimes);
      expect(at(DateTime(2026, 10, 12, 5, 59)).kind, RideCardKind.ask, reason: 'until the minute it closes');
    });

    test('closed with no answer: says so, and when the next one opens', () {
      final m = at(DateTime(2026, 10, 12, 9));
      expect(m.kind, RideCardKind.closed);
      expect(m.day, DateTime(2026, 10, 12));
      expect(m.nextDay, DateTime(2026, 10, 13));
      expect(m.nextOpens, DateTime(2026, 10, 12, 16));
    });

    test('closed after an answer: the next ride, not open yet', () {
      final m = at(DateTime(2026, 10, 12, 9), voted: true);
      expect(m.kind, RideCardKind.notOpen);
      expect(m.day, DateTime(2026, 10, 13));
      expect(m.opens, DateTime(2026, 10, 12, 16));
      expect(m.closes, DateTime(2026, 10, 13, 6));
      expect(at(DateTime(2026, 10, 12, 9), known: false).kind, RideCardKind.notOpen,
          reason: 'votes not read: nothing is said to be missed');
    });

    test('closed with a ride confirmed: the ride stays, locked', () {
      final m = at(DateTime(2026, 10, 12, 9), riding: true);
      expect(m.kind, RideCardKind.confirmedLocked);
      expect(m.day, DateTime(2026, 10, 12));
    });

    test('a vote that closes the same evening', () {
      const evening = VoteSettings(opensAt: 12 * 60, closesAt: 22 * 60, reminderMinutes: 30);
      final late = RideMoment.resolve(
          vote: evening, now: DateTime(2026, 10, 11, 23), known: true, riding: false, voted: false, hasDepartures: true);
      expect(late.kind, RideCardKind.closed);
      expect(late.day, DateTime(2026, 10, 12));
      expect(late.nextOpens, DateTime(2026, 10, 12, 12));
      expect(RideWords.rideOf(late.day, DateTime(2026, 10, 11, 23)), 'رحلة الغد');
      expect(RideWords.when(late.nextOpens!, DateTime(2026, 10, 11, 23)), 'غداً');
    });

    test('the words', () {
      final now = DateTime(2026, 10, 11, 18);
      expect(RideWords.date(DateTime(2026, 10, 12)), 'الاثنين 12 أكتوبر');
      expect(RideWords.clock(DateTime(2026, 10, 12, 6)), '6:00 ص');
      expect(RideWords.question(DateTime(2026, 10, 12), now), 'هل ستركب غداً؟');
      expect(RideWords.question(DateTime(2026, 10, 11), now), 'هل ستركب اليوم؟');
      expect(RideWords.rideOf(DateTime(2026, 10, 14), now), 'رحلة يوم الأربعاء');
    });

    testWidgets('the blocked cards: their sentence, and two buttons that do nothing', (tester) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var taps = 0;
      RideCard card(RideMoment m, DateTime now, {bool offline = false}) => RideCard(
          moment: m, now: now, offline: offline, onYes: () => taps++, onNo: () => taps++, onEdit: () => taps++);
      final asked = RideMoment(
          kind: RideCardKind.ask,
          day: DateTime(2026, 10, 12),
          opens: DateTime(2026, 10, 11, 16),
          closes: DateTime(2026, 10, 12, 6));
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: Column(children: [
                card(at(DateTime(2026, 10, 12, 9), voted: true), DateTime(2026, 10, 12, 9)),
                card(at(DateTime(2026, 10, 12, 9)), DateTime(2026, 10, 12, 9)),
                card(at(DateTime(2026, 10, 11, 18), times: false), DateTime(2026, 10, 11, 18)),
                card(asked, DateTime(2026, 10, 11, 18), offline: true),
                const RideLockedCard(),
              ]),
            ),
          ),
        ),
      ));
      expect(find.text('يفتح 4:00 م'), findsOneWidget);
      expect(find.text('يفتح التأكيد اليوم 4:00 م ويبقى حتى 6:00 ص.'), findsOneWidget);
      expect(find.text('مغلق'), findsOneWidget);
      expect(find.text('انتهى وقت تأكيد رحلة اليوم'), findsOneWidget);
      expect(find.text('أُغلق التأكيد 6:00 ص ولم تسجّل رحلة. يفتح تأكيد يوم الثلاثاء اليوم 4:00 م.'), findsOneWidget);
      expect(find.text('لم يضف المشرف مواعيد ذهاب لهذا الخط بعد.'), findsOneWidget);
      expect(find.text('التأكيد يحتاج اتصالاً بالإنترنت، ومتاح حتى 6:00 ص.'), findsOneWidget);
      expect(find.text('تأكيد الرحلات يبدأ بعد تفعيل الاشتراك.'), findsOneWidget);

      expect(find.byKey(const Key('ride-yes')), findsNWidgets(4));
      for (final key in ['ride-yes', 'ride-no']) {
        for (final button in tester.widgetList<BasakButton>(find.byKey(Key(key)))) {
          expect(button.onPressed, isNull);
        }
        for (var i = 0; i < 4; i++) {
          await tester.tap(find.byKey(Key(key)).at(i), warnIfMissed: false);
        }
      }
      expect(taps, 0);
    });

    testWidgets('the vote reminds: the "not open" card says it will', (tester) async {
      const reminding = VoteSettings(opensAt: 16 * 60, closesAt: 6 * 60, reminderMinutes: 30);
      final now = DateTime(2026, 10, 12, 9);
      final m = RideMoment.resolve(
          vote: reminding, now: now, known: true, riding: false, voted: true, hasDepartures: true);
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: RideCard(moment: m, now: now, onYes: () {}, onNo: () {}, onEdit: () {})),
        ),
      ));
      expect(find.text('يفتح التأكيد اليوم 4:00 م ويبقى حتى 6:00 ص. نذكّرك عند فتحه.'), findsOneWidget);
    });
  });

  group('Home', () {
    testWidgets("every supervisor of the student's line is shown, the primary contact first", (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_home(sub: _sub('active'), supervisors: const [
        LineSupervisor(lineId: 'l', name: 'محمود السيد', phone: '01011223344'),
        LineSupervisor(lineId: 'l', name: 'أحمد علي', phone: '01055667788'),
        LineSupervisor(lineId: 'another line', name: 'سامي حسن', phone: '01099887766'),
      ]));
      await _settle(tester);

      expect(find.text('محمود السيد'), findsOneWidget);
      expect(find.text('أحمد علي'), findsOneWidget);
      expect(find.text('سامي حسن'), findsNothing, reason: 'a supervisor of another line');
      expect(find.byKey(const Key('supervisor-card')), findsOneWidget);
      expect(find.byKey(const Key('supervisor-card-1')), findsOneWidget);
      expect(tester.getTopLeft(find.text('محمود السيد')).dy, lessThan(tester.getTopLeft(find.text('أحمد علي')).dy));
    });

    testWidgets('an active subscription: the pass, the question, the supervisor; yes goes through the sheet',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rides = _Rides();
      var toCard = 0, toSubscription = 0;
      await tester.pumpWidget(_home(
          sub: _sub('active'), rides: rides, toCard: () => toCard++, toSubscription: () => toSubscription++));
      await _settle(tester);

      expect(find.byType(PassCard), findsOneWidget);
      expect(find.text('نشط'), findsOneWidget);
      expect(find.text('كوبري السرو'), findsOneWidget);
      expect(find.text('المنصورة الجديدة'), findsOneWidget);
      expect(find.text('خط الزرقا'), findsOneWidget);
      expect(find.text('النورس للنقل'), findsOneWidget);
      expect(find.text('هل ستركب غداً؟'), findsOneWidget);
      expect(find.text('هذا الأسبوع'), findsOneWidget);
      expect(find.text('محمود السيد'), findsOneWidget);
      expect(find.byKey(const Key('supervisor-card')), findsOneWidget);

      await tester.tap(find.text('الفصل الأول'));
      await tester.tap(find.bySemanticsLabel('عرض بطاقتي'));
      expect((toSubscription, toCard), (1, 1));

      await tester.tap(find.byKey(const Key('ride-yes')));
      await tester.pumpAndSettle();
      expect(find.text('رحلة الغد'), findsOneWidget);
      expect(find.textContaining('من كوبري السرو'), findsOneWidget);
      expect(rides.saved, isEmpty, reason: 'nothing is sent until the sheet is confirmed');
      await tester.tap(find.byKey(const Key('ride-departure-07:23')));
      await tester.tap(find.byKey(const Key('ride-return-15:30')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ride-confirm')));
      await tester.pumpAndSettle();

      expect(rides.saved, [(riding: true, departure: '07:23', returnTime: '15:30', returning: true)]);
      expect(find.text('مؤكدة'), findsOneWidget);
      expect(find.text('7:23 ص'), findsOneWidget);
      expect(find.text('3:30 م'), findsOneWidget);
      expect(find.textContaining('تم تأكيد حضورك ومواعيد رحلتك ليوم'), findsOneWidget);
      expect(find.byKey(const Key('ride-yes')), findsNothing);

      // "تعديل" opens the same sheet on the saved ride; from it the ride is cancelled.
      await tester.tap(find.byKey(const Key('ride-edit')));
      await tester.pumpAndSettle();
      expect(tester.widget<TimeTile>(find.byKey(const Key('ride-departure-07:23'))).selected, isTrue);
      await tester.tap(find.byKey(const Key('ride-decline')));
      await tester.pumpAndSettle();
      expect(rides.saved.last.riding, isFalse);
      expect(find.text('تم إلغاء تأكيد الحضور.'), findsOneWidget);
      expect(find.byKey(const Key('ride-yes')), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('"لن أركب" answers at once, without a sheet', (tester) async {
      final rides = _Rides();
      await tester.pumpWidget(_home(sub: _sub('active'), rides: rides));
      await _settle(tester);
      await tester.ensureVisible(find.byKey(const Key('ride-no')));
      await tester.tap(find.byKey(const Key('ride-no')));
      await tester.pumpAndSettle();
      expect(rides.saved.single.riding, isFalse);
      expect(find.byType(TimeTile), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('offline: the strip with the time of the saved data, the ride buttons off with one line why',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      OfflineCache.markOffline(DateTime(now.year, now.month, now.day, 8, 15));
      final rides = _Rides();
      await tester.pumpWidget(_home(sub: _sub('active'), rides: rides));
      await _settle(tester);
      expect(find.text('بدون إنترنت · بيانات 8:15 ص'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(find.byType(PassCard), findsOneWidget, reason: 'the pass still shows');
      expect(find.textContaining('التأكيد يحتاج اتصالاً بالإنترنت، ومتاح حتى'), findsOneWidget);
      expect(tester.widget<BasakButton>(find.byKey(const Key('ride-yes'))).onPressed, isNull);
      expect(tester.widget<BasakButton>(find.byKey(const Key('ride-no'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('ride-yes')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(TimeTile), findsNothing);
      expect(rides.saved, isEmpty);

      // Back online: said in green for two seconds, and the question can be answered again.
      OfflineCache.markOnline();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('عاد الاتصال · البيانات محدّثة'), findsOneWidget);
      expect(tester.widget<BasakButton>(find.byKey(const Key('ride-yes'))).onPressed, isNotNull);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ConnectionStrip), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('under review: the three steps, and the ride locked', (tester) async {
      await tester.pumpWidget(_home(sub: _sub('pending_review')));
      await _settle(tester);
      expect(find.text('قيد المراجعة'), findsOneWidget);
      expect(find.byType(StepLine), findsOneWidget);
      expect(find.text('خط الزرقا · النورس للنقل'), findsOneWidget);
      expect(find.text('تأكيد الرحلات يبدأ بعد تفعيل الاشتراك.'), findsOneWidget);
      expect(find.byKey(const Key('ride-yes')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('awaiting payment and a refused receipt: the stub carries the one thing to do', (tester) async {
      var toSubscription = 0;
      await tester.pumpWidget(_home(sub: _sub('pending_payment'), toSubscription: () => toSubscription++));
      await _settle(tester);
      expect(find.text('بانتظار الدفع'), findsOneWidget);
      expect(find.text('4,500 ج.م'), findsOneWidget);
      await tester.tap(find.text('ادفع الآن'));
      expect(toSubscription, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_home(sub: _sub('rejected')));
      await _settle(tester);
      expect(find.text('إيصال مرفوض'), findsOneWidget);
      expect(find.text('إيصال جديد'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no subscription: the route with the university known and the stop still to choose',
        (tester) async {
      var toSubscription = 0;
      await tester.pumpWidget(_home(toSubscription: () => toSubscription++));
      await _settle(tester);
      expect(find.text('ابدأ اشتراكك'), findsOneWidget);
      expect(find.text('اختر محطتك'), findsOneWidget);
      expect(find.text('المنصورة الجديدة'), findsOneWidget);
      expect(find.text('جامعتك'), findsOneWidget);
      expect(find.byType(PassCard), findsNothing);
      expect(find.byType(RideCard), findsNothing);
      await tester.tap(find.text('اشترك الآن'));
      expect(toSubscription, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an invitation: the card, its sheet with what is shared, and the other way in', (tester) async {
      final invites = _Invites([
        {
          'id': 'i1', 'company_name': 'النورس للنقل', 'line_name': 'الزرقا', 'station_name': 'كوبري السرو',
          'subscription_type': 'termly', 'price': 4500,
        },
        {
          'id': 'i2', 'company_name': 'المستقبل', 'line_name': 'منية النصر', 'station_name': 'البجلات',
          'subscription_type': 'yearly',
        },
      ]);
      var toSubscription = 0;
      await tester.pumpWidget(_home(invites: invites, toSubscription: () => toSubscription++));
      await _settle(tester);
      expect(find.text('دعوة للاشتراك من'), findsOneWidget, reason: 'one invitation at a time');
      expect(find.text('النورس للنقل'), findsOneWidget);
      expect(find.text('1 من 2'), findsOneWidget);
      expect(find.text('الزرقا · كوبري السرو'), findsOneWidget);
      expect(find.text('اشتراك فصلي'), findsOneWidget);
      expect(find.text('4,500 ج.م'), findsOneWidget);
      expect(find.text('ابدأ اشتراكك'), findsNothing);
      await tester.tap(find.text('أو اختر اشتراكك بنفسك'));
      expect(toSubscription, 1);

      // Swiped to the next one and back.
      await tester.fling(find.byType(InviteCard), const Offset(200, 0), 800);
      await tester.pumpAndSettle();
      expect(find.text('2 من 2'), findsOneWidget);
      expect(find.text('المستقبل'), findsOneWidget);
      expect(find.text('اشتراك سنوي'), findsOneWidget);
      await tester.fling(find.byType(InviteCard), const Offset(-200, 0), 800);
      await tester.pumpAndSettle();
      expect(find.text('1 من 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('invite-accept')));
      await tester.pumpAndSettle();
      expect(find.text('الانضمام إلى النورس للنقل؟'), findsOneWidget);
      expect(find.text('ترى الشركة اسمك وهاتفك وجامعتك وصورتك.'), findsOneWidget);
      expect(find.text('يُفتح لك اشتراك فصلي على خط الزرقا بانتظار الدفع.'), findsOneWidget);
      expect(find.text('لا يتغيّر حسابك ولا اشتراكاتك لدى شركات أخرى.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('ليس الآن'));
      await tester.pumpAndSettle();
      expect(invites.answers, isEmpty, reason: '"not now" answers nothing');

      await tester.tap(find.byKey(const Key('invite-accept')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('invite-join')));
      await tester.pumpAndSettle();
      expect(invites.answers, [(id: 'i1', accept: true)]);
      expect(find.text('انضممت إلى النورس للنقل. أكمل الدفع من صفحة الاشتراك.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('nothing saved and no connection: the whole page says so, with a retry', (tester) async {
      await tester.pumpWidget(_home(error: Exception('SocketException: Failed host lookup')));
      await _settle(tester);
      expect(find.text('لا يوجد اتصال'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(find.byType(HomeSkeleton), findsNothing);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('nothing clips on a small phone at the largest text', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      for (final offline in [false, true]) {
        if (offline) OfflineCache.markOffline(DateTime(now.year, now.month, now.day, 8, 15));
        for (final status in ['active', 'pending_review', 'pending_payment', 'rejected']) {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_home(sub: _sub(status), textScale: 1.3));
          await _settle(tester);
          expect(tester.takeException(), isNull, reason: '$status, offline: $offline');
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_home(textScale: 1.3));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the connection strip host', () {
    test('the time of the saved data: alone for today, with the day otherwise', () {
      final now = DateTime(2026, 10, 4, 12);
      expect(ConnectionStripHost.dataTime(DateTime(2026, 10, 4, 8, 15), now), '8:15 ص');
      expect(ConnectionStripHost.dataTime(DateTime(2026, 10, 3, 21, 40), now), '3 أكتوبر 9:40 م');
    });

    testWidgets('over a page: amber while offline with a retry, green for two seconds, then gone', (tester) async {
      var retries = 0;
      final page = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ConnectionStripHost(onRetry: () => retries++, child: Text('content', key: page)),
          ),
        ),
      ));
      expect(find.byType(ConnectionStrip), findsNothing);
      final element = tester.element(find.byKey(page));

      final now = DateTime.now();
      OfflineCache.markOffline(DateTime(now.year, now.month, now.day, 8, 15));
      await tester.pumpAndSettle();
      expect(find.text('بدون إنترنت · بيانات 8:15 ص'), findsOneWidget);
      expect(tester.widget<ConnectionStrip>(find.byType(ConnectionStrip)).state, ConnectionStripState.offline);
      expect(tester.element(find.byKey(page)), same(element), reason: 'the page under it keeps its state');
      await tester.tap(find.text('إعادة المحاولة'));
      expect(retries, 1);

      OfflineCache.markOnline();
      await tester.pumpAndSettle();
      expect(tester.widget<ConnectionStrip>(find.byType(ConnectionStrip)).state, ConnectionStripState.backOnline);
      expect(find.text('إعادة المحاولة'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1400));
      expect(find.byType(ConnectionStrip), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionStrip), findsNothing);
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('switched off (the tab that places its own strip): nothing is shown', (tester) async {
      OfflineCache.markOffline(DateTime.now());
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ConnectionStripHost(enabled: false, child: Text('content'))),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionStrip), findsNothing);
      expect(find.text('content'), findsOneWidget);
    });
  });
}
