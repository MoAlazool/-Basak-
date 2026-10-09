// The store rating: when the app may ask by itself (the fifth boarded ride,
// once per installed version, at a calm moment on Home), that nothing about it
// can go wrong loudly, and the sheet (boards RateIOS, RateAndroid).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, User;

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/storage/prompt_store.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/features/app_update/app_store.dart';
import 'package:basak_mobile/features/app_update/app_update_repository.dart';
import 'package:basak_mobile/features/app_update/app_version.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/rating/rating.dart';

import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/profile/presentation/profile_screen.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';

import 'support/notification_fakes.dart';
import 'support/perf_fakes.dart';

class _NoSub extends CurrentSubscriptionNotifier {
  @override
  Future<SubscriptionModel?> build() async => null;
}

class _Auth extends AuthNotifier {
  _Auth(UserRole role) : super(AuthRepository()) {
    state = AuthState(
        user: const User(id: 'u1', appMetadata: {}, userMetadata: {'full_name': 'سارة أحمد'}, aud: '', createdAt: ''),
        role: role,
        isInitialLoading: false);
  }
}

class _Store extends AppStore {
  final List<String> calls = [];
  bool hasDialog = true;
  bool opens = true;

  @override
  Future<bool> requestReview() async {
    calls.add('dialog');
    return hasDialog;
  }

  @override
  Future<bool> open(String? url) async {
    calls.add('page:$url');
    return opens;
  }
}

void main() {
  late RequestLog log;
  late FakeBoardedRides server;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    OfflineCache.offlineSince.value = null;
    log = RequestLog();
    server = FakeBoardedRides(log);
  });

  group('the rule', () {
    test('the fifth boarded ride, not the fourth', () {
      bool due(int rides) => RatingRules.due(boardedRides: rides, installed: '1.0.6', askedVersion: null);
      expect(due(0), isFalse);
      expect(due(4), isFalse);
      expect(due(5), isTrue);
      expect(due(60), isTrue);
    });

    test('once per installed version: never again on it, once more on the next', () {
      bool due(String installed, String? asked) =>
          RatingRules.due(boardedRides: 40, installed: installed, askedVersion: asked);
      expect(due('1.0.6', '1.0.6'), isFalse);
      expect(due('1.0.6+36', '1.0.6'), isFalse, reason: 'a new build of the same version is not a new version');
      expect(due('1.0.7', '1.0.6'), isTrue);
      expect(due('1.0.10', '1.0.6'), isTrue);
      expect(due('1.0.6', ''), isTrue);
      expect(due('dev', 'dev'), isFalse);
    });
  });

  group('whether to ask', () {
    RatingRepository repo() => RatingRepository(gateway: server);

    test('five rides and never asked on this version: yes, with one request', () async {
      server.count = 5;
      expect(await repo().isDue(installed: '1.0.6'), isTrue);
      expect(log.calls, {'rating.boarded_rides': 1});
    });

    test('four rides: no', () async {
      server.count = 4;
      expect(await repo().isDue(installed: '1.0.6'), isFalse);
    });

    test('already asked on this version: no, and the rides are not even counted', () async {
      server.count = 50;
      await repo().markAsked('1.0.6');
      expect(await repo().isDue(installed: '1.0.6'), isFalse);
      expect(log.total, 0);
      expect(await repo().isDue(installed: '1.0.7'), isTrue, reason: 'the next version may ask once');
      expect(log.calls, {'rating.boarded_rides': 1});
    });

    test('a database without the function, a refusal, no connection, an odd answer: no', () async {
      server.count = 50;
      for (final error in [
        const PostgrestException(message: 'Could not find the function', code: 'PGRST202'),
        const PostgrestException(message: 'permission denied', code: '42501'),
        const SocketException('Failed host lookup'),
        AssertionError('not initialised'),
      ]) {
        server.fails = error;
        expect(await repo().isDue(installed: '1.0.6'), isFalse, reason: '$error');
      }
      server.fails = null;
      for (final Object? odd in [null, '12', <dynamic>[], <String, dynamic>{}, true]) {
        server.count = odd;
        expect(await repo().isDue(installed: '1.0.6'), isFalse, reason: '$odd');
      }
      server.count = 5.0;
      expect(await repo().isDue(installed: '1.0.6'), isTrue);
    });

    test('offline, or a version that cannot be read: no, without a request', () async {
      server.count = 50;
      expect(await repo().isDue(installed: null), isFalse);
      OfflineCache.offlineSince.value = DateTime(2026, 10, 9);
      addTearDown(() => OfflineCache.offlineSince.value = null);
      expect(await repo().isDue(installed: '1.0.6'), isFalse);
      expect(log.total, 0);
    });

    test('students only, and read once per run however often it is looked at', () async {
      server.count = 50;
      ProviderContainer open(UserRole role) {
        final c = ProviderContainer(overrides: [
          authStateProvider.overrideWith((ref) => _Auth(role)),
          installedVersionProvider.overrideWith((ref) => '1.0.6'),
          ratingRepoProvider.overrideWithValue(RatingRepository(gateway: server)),
        ]);
        addTearDown(c.dispose);
        return c;
      }

      expect(await open(UserRole.supervisor).read(ratingDueProvider.future), isFalse);
      expect(log.total, 0, reason: 'a supervisor is never asked');

      final c = open(UserRole.student);
      expect(await c.read(ratingDueProvider.future), isTrue);
      expect(await c.read(ratingDueProvider.future), isTrue);
      c.listen(ratingDueProvider, (_, __) {});
      expect(log.calls, {'rating.boarded_rides': 1});
    });
  });

  group('on screen', () {
    late _Store store;
    final ready = ValueNotifier(true);
    final navigator = GlobalKey<NavigatorState>();

    Future<void> open(
      WidgetTester tester, {
      Size size = const Size(390, 844),
      double textScale = 1,
      String? storeUrl,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      store = _Store();
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          authStateProvider.overrideWith((ref) => _Auth(UserRole.student)),
          installedVersionProvider.overrideWith((ref) => '1.0.6'),
          ratingRepoProvider.overrideWithValue(RatingRepository(gateway: server)),
          appUpdateProvider.overrideWith((ref) => AppUpdate(kind: UpdateKind.none, storeUrl: storeUrl)),
          appStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          theme: AppTheme.lightTheme,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
          ),
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: ready,
              builder: (context, ready, _) => RatingMoment(ready: ready, child: const Center(child: Text('الرئيسية'))),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    setUp(() => ready.value = true);

    testWidgets('after the fifth ride: the sheet, at a calm moment, saying where the rating goes', (tester) async {
      server.count = 5;
      await open(tester);
      expect(find.byType(BasakSheetFrame), findsNothing, reason: 'not the moment Home appears');
      await tester.pump(RatingMoment.calm);
      await tester.pumpAndSettle();
      expect(find.text('قيّم باصك'), findsOneWidget);
      expect(find.text('تقييمك على Google Play يساعد طلاباً آخرين على الوصول إلى باصك، ويساعدنا على تحسينه.'),
          findsOneWidget);
      expect(find.text('قيّم على Google Play'), findsOneWidget);
      expect(find.text('ليس الآن'), findsOneWidget);
      // The store asks for the stars; the app asks nothing of its own.
      expect(find.byType(BasakButton), findsOneWidget);
      expect(find.byType(SheetLink), findsOneWidget);
      expect(find.byType(BasakPressable), findsNWidgets(2), reason: 'two things to tap: no stars, no question');
      expect(tester.takeException(), isNull);
      expect(log.calls, {'rating.boarded_rides': 1});
    });

    testWidgets('«ليس الآن» closes it, and this version is not asked again', (tester) async {
      server.count = 9;
      await open(tester);
      await tester.pump(RatingMoment.calm);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rate-later')));
      await tester.pumpAndSettle();
      expect(find.byType(BasakSheetFrame), findsNothing);
      expect(store.calls, isEmpty);
      expect(await const PromptStore().ratingAskedVersion(unreadable: ''), '1.0.6');

      log.reset();
      await open(tester); // the next launch
      await tester.pump(const Duration(seconds: 10));
      expect(find.byType(BasakSheetFrame), findsNothing);
      expect(log.total, 0, reason: 'the rides are not counted once this version has been asked');
    });

    testWidgets('the button hands over to the store\'s own review dialog', (tester) async {
      server.count = 5;
      await open(tester, storeUrl: 'https://play.google.com/basak');
      await tester.pump(RatingMoment.calm);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rate-store')));
      await tester.pumpAndSettle();
      expect(store.calls, ['dialog']);
      expect(find.byType(BasakSheetFrame), findsNothing);
    });

    testWidgets('where the store has no dialog, its page for the app opens instead', (tester) async {
      server.count = 5;
      await open(tester, storeUrl: 'https://play.google.com/basak');
      store.hasDialog = false;
      await tester.pump(RatingMoment.calm);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rate-store')));
      await tester.pumpAndSettle();
      expect(store.calls, ['dialog', 'page:https://play.google.com/basak']);
    });

    testWidgets('four rides, or a server that cannot answer: nothing is shown', (tester) async {
      server.count = 4;
      await open(tester);
      await tester.pump(const Duration(seconds: 10));
      expect(find.byType(BasakSheetFrame), findsNothing);

      server
        ..count = 50
        ..fails = const PostgrestException(message: 'Could not find the function', code: 'PGRST202');
      await open(tester);
      await tester.pump(const Duration(seconds: 10));
      expect(find.byType(BasakSheetFrame), findsNothing);
      expect(tester.takeException(), isNull);
      expect(await const PromptStore().ratingAskedVersion(unreadable: ''), isNull);
    });

    testWidgets('no running subscription on Home: the rides are not even counted', (tester) async {
      server.count = 50;
      ready.value = false; // under review, rejected, expired, or none
      await open(tester);
      await tester.pump(const Duration(seconds: 10));
      expect(find.byType(BasakSheetFrame), findsNothing);
      expect(log.total, 0);

      // Activated while the app is open: from then on.
      ready.value = true;
      await tester.pump();
      await tester.pump();
      await tester.pump(RatingMoment.calm);
      await tester.pumpAndSettle();
      expect(find.text('قيّم باصك'), findsOneWidget);
    });

    testWidgets('never over something else: a pushed page, a lost connection, a subscription that stopped',
        (tester) async {
      server.count = 50;
      await open(tester);
      // A payment (any page) opened over Home before the calm moment.
      navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('الدفع'))));
      await tester.pumpAndSettle();
      await tester.pump(RatingMoment.calm);
      await tester.pumpAndSettle();
      expect(find.byType(BasakSheetFrame), findsNothing);
      expect(await const PromptStore().ratingAskedVersion(unreadable: ''), isNull,
          reason: 'not asked: it may be asked on a later launch');

      await open(tester);
      OfflineCache.offlineSince.value = DateTime(2026, 10, 9);
      addTearDown(() => OfflineCache.offlineSince.value = null);
      await tester.pump(RatingMoment.calm);
      await tester.pumpAndSettle();
      expect(find.byType(BasakSheetFrame), findsNothing);
      OfflineCache.offlineSince.value = null;

      await open(tester);
      ready.value = false; // rejected or expired meanwhile
      await tester.pump();
      await tester.pump(RatingMoment.calm);
      await tester.pumpAndSettle();
      expect(find.byType(BasakSheetFrame), findsNothing);
    });

    testWidgets('on an iPhone the sheet names the App Store', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        server.count = 5;
        await open(tester);
        await tester.pump(RatingMoment.calm);
        await tester.pumpAndSettle();
        expect(find.text('قيّم على App Store'), findsOneWidget);
        expect(find.text('تقييمك على App Store يساعد طلاباً آخرين على الوصول إلى باصك، ويساعدنا على تحسينه.'),
            findsOneWidget);
        await tester.tap(find.byKey(const Key('rate-later')));
        await tester.pumpAndSettle();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('nothing clips on a small phone with large text', (tester) async {
      server.count = 5;
      await open(tester, size: const Size(360, 640), textScale: 1.3);
      await tester.pump(RatingMoment.calm);
      await tester.pumpAndSettle();
      expect(find.text('قيّم على Google Play'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the account page always has «قيّم التطبيق» under التطبيق, for a student', (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      store = _Store();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('u1'),
          authStateProvider.overrideWith((ref) => _Auth(UserRole.student)),
          currentSubscriptionProvider.overrideWith(_NoSub.new),
          studentProfileSummaryProvider.overrideWith((ref, id) => Future.value(const <String, dynamic>{
                'full_name': 'سارة أحمد', 'phone': '01023456789', 'university': 'المنصورة الجديدة', 'college': 'الهندسة',
              })),
          notificationsRepoProvider.overrideWithValue(FakeNotificationsRepo()),
          appUpdateProvider.overrideWith((ref) => AppUpdate.none),
          appStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
          home: const Scaffold(body: ProfileScreen()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('التطبيق'), findsOneWidget);
      expect(find.text('قيّم التطبيق'), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile-rate')));
      await tester.pumpAndSettle();
      expect(store.calls, ['page:null']);
      expect(find.byType(BasakSheetFrame), findsNothing);
    });

    testWidgets('«قيّم التطبيق» in the account page goes straight to the store page', (tester) async {
      await open(tester, storeUrl: 'https://play.google.com/basak');
      late BuildContext context;
      late WidgetRef ref;
      await tester.pumpWidget(ProviderScope(
        overrides: [appStoreProvider.overrideWithValue(store), appUpdateProvider.overrideWith((ref) => AppUpdate.none)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Consumer(builder: (c, r, _) {
              context = c;
              ref = r;
              return const SizedBox();
            }),
          ),
        ),
      ));
      await tester.pump();
      await rateFromSettings(context, ref);
      expect(store.calls, ['page:null'], reason: 'the store listing; no sheet, no dialog that may not appear');

      // A phone where the page cannot be opened: the dialog, then a word about it.
      store
        ..calls.clear()
        ..opens = false
        ..hasDialog = false;
      await rateFromSettings(context, ref);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.calls, ['page:null', 'dialog']);
      expect(find.text('تعذّر فتح Google Play. افتحه وابحث عن «باصك».'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });
}
