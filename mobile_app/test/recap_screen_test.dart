// The term recap around its engine: when the app asks for one (and when it
// does not), the banner on Home, and the story — advance, back, close, the
// short version, pages dropping out, share and save.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, User;

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/student/daily_ride/data/daily_ride_repository.dart';
import 'package:basak_mobile/features/student/daily_ride/models/vote_settings.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/invites/invites.dart';
import 'package:basak_mobile/features/student/recap/recap_engine.dart';
import 'package:basak_mobile/features/student/recap/recap_repository.dart';
import 'package:basak_mobile/features/student/recap/recap_screen.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';

import 'support/notification_fakes.dart';
import 'support/recap_fixtures.dart';

class _Sub extends CurrentSubscriptionNotifier {
  SubscriptionModel? sub;
  _Sub(this.sub);

  @override
  Future<SubscriptionModel?> build() async => sub;

  void change(SubscriptionModel? next) => state = AsyncData(sub = next);
}

SubscriptionModel _sub({String id = 'sub-1', String end = '2027-01-14', String status = 'active', String? line}) =>
    SubscriptionModel(
      id: id,
      studentId: 'student-1',
      lineId: 'l',
      stationId: 'st',
      type: 'termly',
      status: status,
      price: 4500,
      createdAt: '2026-09-01',
      startDate: '2026-09-20',
      endDate: end,
      lineName: line ?? 'الزرقا',
      stationName: 'كوبري السرو',
      periodCode: 'first',
      periodPhase: 'current',
    );

class _Auth extends AuthNotifier {
  _Auth() : super(AuthRepository()) {
    state = const AuthState(
      user: User(id: 'student-1', appMetadata: {}, userMetadata: {'full_name': 'سارة أحمد'}, aud: '', createdAt: ''),
      role: UserRole.student,
    );
  }
}

class _Rides implements DailyRideRepository {
  @override
  Future<VoteSettings> getVoteSettings(String? companyId) async => const VoteSettings(opensAt: 0, closesAt: 0);
  @override
  Future<RideDays> getRides(DateTime start, DateTime end) async => const RideDays({});
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Invites implements InvitesGateway {
  @override
  Future<dynamic> myInvites() async => const [];
  @override
  Future<dynamic> respond(String inviteId, bool accept) async => {'note': null};
}

RecapTerm _term(String id, DateTime end) => (subscriptionId: id, end: end);

Future<void> _phone(WidgetTester tester, [Size size = const Size(390, 844)]) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(Widget home, {bool still = false}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: still),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
      home: home,
    );

Future<void> _next(WidgetTester tester) async {
  // The trailing part of the page: clear of the leading quarter that goes back.
  await tester.tapAt(const Offset(60, 500));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    OfflineCache.debugUserId = 'student-1';
    OfflineCache.resetSession();
  });
  tearDown(() {
    OfflineCache.debugUserId = null;
    RecapExport.debugShare = null;
    RecapExport.debugSave = null;
  });

  group('asking the server', () {
    test('a database without the function: no recap, and no error', () async {
      final repo = TermRecapRepository(
          fetch: (_) async => throw const PostgrestException(
              message: 'Could not find the function public.get_my_term_recap', code: 'PGRST202'));
      expect(await repo.load(subscriptionId: 'sub-1', studentId: 'student-1'), isNull);
    });

    test('an answer that is not a recap, or one with no rides: no recap', () async {
      for (final answer in [null, 'x', <String, dynamic>{}, recapJson(rides: const [])]) {
        OfflineCache.resetSession();
        final repo = TermRecapRepository(fetch: (_) async => answer);
        expect(await repo.load(subscriptionId: 'sub-${answer.hashCode}', studentId: 'student-1'), isNull);
      }
    });

    test('the recap is the subscription\'s, drawn for this student', () async {
      String? asked;
      final repo = TermRecapRepository(fetch: (id) async {
        asked = id;
        return sara();
      });
      final recap = await repo.load(subscriptionId: 'sub-1', studentId: 'student-1');
      expect(asked, 'sub-1');
      expect(recap!.rideDays, 62);
      expect(recap.title, recapOf(sara(), key: 'student-1')!.title);
    });
  });

  group('the gate', () {
    final end = DateTime.utc(2027, 1, 14);

    test('opens two weeks before the term ends and stays four weeks after', () {
      final term = _term('sub-1', end);
      expect(RecapGate.open(DateTime.utc(2026, 10, 10), current: term), isNull);
      expect(RecapGate.open(DateTime.utc(2027, 1, 2), current: term), term);
      expect(RecapGate.open(DateTime.utc(2027, 2, 1), current: term), term);
      expect(RecapGate.open(DateTime.utc(2027, 3, 1), current: term), isNull);
    });

    test('a term that ended is remembered until its window has passed', () {
      final ended = _term('sub-1', end);
      final next = _term('sub-2', DateTime.utc(2027, 6, 10));
      // The subscription expired: Home has none, or the next term's.
      expect(RecapGate.open(DateTime.utc(2027, 1, 20), remembered: ended), ended);
      expect(RecapGate.open(DateTime.utc(2027, 2, 5), current: next, remembered: ended), ended);
      expect(RecapGate.keep(DateTime.utc(2027, 2, 5), current: next, remembered: ended), ended);
      expect(RecapGate.keep(DateTime.utc(2027, 2, 20), current: next, remembered: ended), next);
      expect(RecapGate.open(DateTime.utc(2027, 2, 20), current: next, remembered: next), isNull);
    });

    test('only a paid term or year has one', () {
      expect(RecapGate.of(_sub()), _term('sub-1', end));
      expect(RecapGate.of(_sub(status: 'pending_payment')), isNull);
      expect(RecapGate.of(null), isNull);
    });
  });

  group('the provider behind the banner', () {
    Future<(ProviderContainer, _Sub, List<String>)> open(DateTime today, {Map<String, dynamic>? answer}) async {
      final asked = <String>[];
      final sub = _Sub(_sub());
      final c = ProviderContainer(overrides: [
        sessionUserIdProvider.overrideWithValue('student-1'),
        currentSubscriptionProvider.overrideWith(() => sub),
        recapTodayProvider.overrideWithValue(() => today),
        termRecapRepoProvider.overrideWithValue(TermRecapRepository(fetch: (id) async {
          asked.add(id);
          return answer ?? sara();
        })),
      ]);
      addTearDown(c.dispose);
      c.listen(termRecapProvider, (_, __) {});
      await c.read(currentSubscriptionProvider.future);
      await pumpEventQueue();
      return (c, sub, asked);
    }

    test('outside the window nothing is asked', () async {
      final (c, _, asked) = await open(DateTime.utc(2026, 10, 10));
      expect(await c.read(termRecapProvider.future), isNull);
      expect(asked, isEmpty);
    });

    test('inside it: one request, and not another when the subscription changes otherwise', () async {
      final (c, sub, asked) = await open(DateTime.utc(2027, 1, 10));
      expect((await c.read(termRecapProvider.future))?.rideDays, 62);
      expect(asked, ['sub-1']);
      sub.change(_sub(line: 'خط آخر'));
      await pumpEventQueue();
      expect((await c.read(termRecapProvider.future))?.rideDays, 62);
      expect(asked, ['sub-1'], reason: 'a live change that does not move the term asks nothing');
    });

    test('after the term, with the subscription gone from Home, the recap is still there', () async {
      final (c, sub, asked) = await open(DateTime.utc(2027, 1, 10));
      await c.read(termRecapProvider.future);
      sub.change(null);
      await pumpEventQueue();
      expect(await c.read(termRecapProvider.future), isNotNull);
      expect(asked.toSet(), {'sub-1'});
    });

    test('no rides: no banner', () async {
      final (c, _, asked) = await open(DateTime.utc(2027, 1, 10), answer: recapJson(rides: const []));
      expect(await c.read(termRecapProvider.future), isNull);
      expect(asked, hasLength(1));
    });

    test('the server\'s term decides: an answer about a term still far from its end shows nothing', () async {
      final (c, _, _) = await open(DateTime.utc(2027, 1, 10), answer: ahmed());
      expect(await c.read(termRecapProvider.future), isNull);
    });
  });

  group('Home', () {
    Widget home(TermRecap? recap) => ProviderScope(
          overrides: [
            sessionUserIdProvider.overrideWithValue('student-1'),
            authStateProvider.overrideWith((ref) => _Auth()),
            currentSubscriptionProvider.overrideWith(() => _Sub(_sub(end: '2099-12-31'))),
            voteSettingsProvider.overrideWith((ref) async => const VoteSettings(opensAt: 0, closesAt: 0)),
            dailyRideRepoProvider.overrideWithValue(_Rides()),
            invitesGatewayProvider.overrideWithValue(_Invites()),
            studentProfileSummaryProvider.overrideWith((ref, id) async => {'university': 'جامعة المنصورة الجديدة'}),
            notificationsRepoProvider.overrideWithValue(FakeNotificationsRepo()),
            if (recap != null) termRecapProvider.overrideWith((ref) async => recap),
          ],
          child: _app(Scaffold(body: StudentHomeScreen(onNavigateToSubscription: () {}, onNavigateToQr: () {}))),
        );

    testWidgets('no recap, no banner', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(home(null));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recap-banner')), findsNothing);
      expect(find.byType(RecapBanner), findsNothing);
    });

    testWidgets('a recap: the banner, above the pass, opens the story', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(home(recapOf(sara())));
      await tester.pumpAndSettle();
      expect(find.text('ملخّص ترمك جاهز'), findsOneWidget);
      expect(find.text('109 ساعة في الباص… والباقي جوّه.'), findsOneWidget);
      expect(tester.getTopLeft(find.byType(RecapBanner)).dy, lessThan(tester.getTopLeft(find.byType(PassCard)).dy));

      await tester.tap(find.byKey(const Key('recap-banner')));
      await tester.pumpAndSettle();
      expect(find.byType(RecapScreen), findsOneWidget);
      expect(find.text('باصك · ملخّص الترم'), findsOneWidget);

      await tester.tap(find.byKey(const Key('story-close')));
      await tester.pumpAndSettle();
      expect(find.byType(RecapScreen), findsNothing);
      expect(find.byKey(const Key('recap-banner')), findsOneWidget);
    });
  });

  group('the story', () {
    testWidgets('a tap goes on, page by page, to the poster; nothing moves by itself', (tester) async {
      await _phone(tester);
      final recap = recapOf(sara(), key: keyDrawing('regular', 0, 6))!;
      await tester.pumpWidget(_app(RecapScreen(recap: recap)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recap-page-cover')), findsOneWidget);
      expect(find.text('109 ساعة، 62 يوم، ومعاد واحد ما بتغيّروش.'), findsOneWidget);
      expect(find.bySemanticsLabel('الصفحة 1 من 11'), findsOneWidget);

      // No timer: a minute later it is the same page.
      await tester.pump(const Duration(minutes: 1));
      expect(find.byKey(const Key('recap-page-cover')), findsOneWidget);

      const order = ['hours', 'days', 'shape', 'run', 'time', 'back', 'stop', 'college', 'title'];
      for (final name in order) {
        await _next(tester);
        expect(find.byKey(Key('recap-page-$name')), findsOneWidget, reason: name);
        expect(tester.takeException(), isNull, reason: name);
      }
      expect(find.text('ركبت 62 يوم من 101. أكتر من نص الترم على نفس الرصيف.'), findsOneWidget);

      await _next(tester);
      expect(find.byType(RecapPoster), findsOneWidget);
      expect(find.text('شارك'), findsOneWidget);
      expect(find.text('حفظ الصورة'), findsOneWidget);
      expect(find.bySemanticsLabel('الصفحة 11 من 11'), findsOneWidget);
      // The poster names the student by first name only.
      expect(find.text('سارة · خط الزرقا'), findsOneWidget);
      expect(find.textContaining('أحمد'), findsNothing);
      expect(find.text('Basak.app'), findsOneWidget);

      // The last page: a tap goes nowhere.
      await _next(tester);
      expect(find.byType(RecapPoster), findsOneWidget);
    });

    testWidgets('the leading edge goes back; the first page has nowhere to go back to', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(RecapScreen(recap: recapOf(sara())!)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('story-back')), findsNothing);
      await _next(tester);
      expect(find.byKey(const Key('recap-page-hours')), findsOneWidget);
      await tester.tapAt(const Offset(370, 500)); // the start side, in Arabic
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recap-page-cover')), findsOneWidget);
    });

    testWidgets('close leaves at any page', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
              onPressed: () => RecapScreen.open(context, recapOf(sara())!), child: const Text('open')),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _next(tester);
      await _next(tester);
      await tester.tap(find.byKey(const Key('story-close')));
      await tester.pumpAndSettle();
      expect(find.byType(RecapScreen), findsNothing);
    });

    testWidgets('the short version: cover, one number, the poster', (tester) async {
      await _phone(tester);
      final recap = recapOf(omar())!;
      await tester.pumpWidget(_app(RecapScreen(recap: recap)));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('الصفحة 1 من 3'), findsOneWidget);
      await _next(tester);
      expect(find.byKey(const Key('recap-page-short')), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('مرات ركبت الباص'), findsOneWidget);
      expect(find.text('في الترم كله. إحنا مش زعلانين… إحنا بس مستغربين.'), findsOneWidget);
      expect(find.text('لقبك: ${recap.title}'), findsOneWidget);
      await _next(tester);
      expect(find.byType(RecapPoster), findsOneWidget);
      expect(find.text('ركوب'), findsOneWidget);
      expect(find.text('أكتر يوم'), findsOneWidget);
    });

    testWidgets('pages drop out with their data: no hours, no run, never returned', (tester) async {
      await _phone(tester);
      final json = recapJson(
        rides: pick(studyDays(), 5, {0, 2}),
        returning: (i) => null,
        tripMinutes: null,
        college: null,
      );
      final recap = recapOf(json)!;
      await tester.pumpWidget(_app(RecapScreen(recap: recap)));
      await tester.pumpAndSettle();
      final seen = <String>[];
      for (var i = 0; i < recap.pages.length - 1; i++) {
        seen.add(recap.pages[i].kind.name);
        expect(find.byKey(Key('recap-page-${recap.pages[i].kind.name}')), findsOneWidget);
        expect(find.textContaining('ساعة'), findsNothing, reason: recap.pages[i].kind.name);
        if (recap.pages[i].kind == RecapPageKind.back) {
          expect(find.textContaining('ذهاب بس'), findsOneWidget);
          expect(find.text('0'), findsNothing);
        }
        await _next(tester);
      }
      expect(seen, ['cover', 'days', 'shape', 'time', 'back', 'stop', 'college', 'title']);
      expect(find.byType(RecapPoster), findsOneWidget);
      expect(find.text('ساعة'), findsNothing);
      expect(find.text('ما قلتلناش كليتك، بس الطريق عارفك.'), findsOneWidget);
    });

    testWidgets('less motion: pages fade, and the story still advances', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(RecapScreen(recap: recapOf(sara())!), still: true));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(60, 500));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(SlideTransition).evaluate().where((e) {
        final w = e.widget as SlideTransition;
        return w.position.value.dx != 0;
      }), isEmpty);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recap-page-hours')), findsOneWidget);
    });

    testWidgets('nothing overflows on a small phone at large text, on any page', (tester) async {
      for (final json in [sara(), mariam(), omar(), menna()]) {
        await _phone(tester, const Size(360, 640));
        final recap = recapOf(json)!;
        await tester.pumpWidget(MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3), size: Size(360, 640)),
          child: _app(RecapScreen(key: UniqueKey(), recap: recap)),
        ));
        await tester.pumpAndSettle();
        for (var i = 0; i < recap.pages.length; i++) {
          expect(tester.takeException(), isNull, reason: recap.pages[i].kind.name);
          await _next(tester);
        }
      }
    });

    testWidgets('share and save hand over a 1080-wide picture of the poster', (tester) async {
      await _phone(tester);
      final shared = <Uint8List>[], saved = <Uint8List>[];
      RecapExport.debugShare = (png, _) async => shared.add(png);
      RecapExport.debugSave = (png) async => saved.add(png);
      final recap = recapOf(omar())!;
      await tester.pumpWidget(_app(Scaffold(body: RecapScreen(recap: recap))));
      await tester.pumpAndSettle();
      await _next(tester);
      await _next(tester);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('recap-share')));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();
      expect(shared, hasLength(1));
      // PNG: its width is the four bytes at 16.
      final width = ByteData.sublistView(shared.single, 16, 20).getUint32(0);
      final height = ByteData.sublistView(shared.single, 20, 24).getUint32(0);
      expect(width, 1080);
      expect(height, closeTo(1080 * 566 / 318, 1), reason: '9:16');

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('recap-save')));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();
      expect(saved, hasLength(1));
      expect(find.text('تم حفظ البوستر في الاستوديو.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });
}
