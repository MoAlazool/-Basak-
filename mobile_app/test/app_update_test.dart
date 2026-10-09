// The update check: how versions compare, what the server's answer means, that
// nothing about it can stand in the app's way, the sheet for an optional
// update and the screen for a required one (boards UpdateAvailable,
// UpdateRequired).
import 'dart:async';
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
import 'package:basak_mobile/features/app_update/update_gate.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/presentation/force_password_change_screen.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/onboarding/onboarding_controller.dart';
import 'package:basak_mobile/features/student/qr/data/student_qr_repository.dart';
import 'package:basak_mobile/features/student/qr/presentation/student_qr_screen.dart';

import 'support/perf_fakes.dart';

class _Auth extends AuthNotifier {
  _Auth(UserRole? role) : super(AuthRepository()) {
    state = role == null
        ? const AuthState(isInitialLoading: false)
        : AuthState(
            user: const User(id: 'u1', appMetadata: {}, userMetadata: {'full_name': 'سارة أحمد'}, aud: '', createdAt: ''),
            role: role,
            isInitialLoading: false);
  }
}

class _Store extends AppStore {
  final List<String?> opened = [];
  bool opens = true;

  @override
  Future<bool> open(String? url) async {
    opened.add(url);
    return opens;
  }
}

const _pass = StudentPassDetails(
    qrValue: 'QR-1', fullName: 'سارة أحمد محمود', phone: '01023456789', university: 'جامعة المنصورة الجديدة',
    college: 'الهندسة', lineName: 'الزرقا', stationName: 'كوبري السرو', subscriptionId: 'sub1',
    subscriptionStatus: 'active', periodPhase: 'current', periodName: 'الفصل الأول', academicYear: 2026,
    startDate: '2026-09-20', endDate: '2027-01-14', companyName: 'النورس للنقل');

AppUpdate _update(String installed, {String min = '0.0.0', String latest = '0.0.0', List<String>? lines, String? url}) =>
    AppUpdate.resolve(installed: installed, answer: {
      'platform': 'android', 'min_version': min, 'latest_version': latest,
      'whats_new': lines ?? const ['بطاقة أوضح للمشرف عند الصعود', 'ملخّص الترم ومشاركته', 'تحسينات في السرعة وإصلاحات'],
      'store_url': url ?? 'https://play.google.com/store/apps/details?id=basak',
    });

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    OfflineCache.offlineSince.value = null;
  });

  group('versions compare number by number', () {
    AppVersion v(String text) => AppVersion.tryParse(text)!;

    test('1.0.6 is before 1.0.10, which text order gets wrong', () {
      expect(v('1.0.6') < v('1.0.10'), isTrue);
      expect(v('1.0.10') < v('1.0.6'), isFalse);
      expect(v('1.9.9') < v('1.10.0'), isTrue);
      expect(v('2.0.0') < v('10.0.0'), isTrue);
      expect(v('1.0.6').compareTo(v('1.0.6')), 0);
    });

    test('a missing part is zero', () {
      expect(v('2.5'), v('2.5.0'));
      expect(v('2'), v('2.0.0'));
      expect(v('2') < v('2.0.1'), isTrue);
      expect(v('2.5') < v('2.5.0'), isFalse);
    });

    test('a build number or a tag is not part of the version', () {
      expect(v('1.0.6+35'), v('1.0.6'));
      expect(v('1.0.6+35') < v('1.0.6+36'), isFalse);
      expect(v('1.0.6+999') < v('1.0.7'), isTrue);
      expect(v('2.5.0-beta.1'), v('2.5.0'));
      expect(v(' v1.2.3 '), v('1.2.3'));
      expect(v('1.0.6+35').toString(), '1.0.6');
    });

    test('what is not a version is nothing, never a guess', () {
      for (final text in [null, '', '  ', 'abc', '1.x.3', '1..3', '1.2.3.4', '-1.0', '+35', '1.0.']) {
        expect(AppVersion.tryParse(text), isNull, reason: '$text');
      }
    });
  });

  group('what the answer means for this installation', () {
    test('below the floor: required; below the newest: optional; otherwise nothing', () {
      expect(_update('2.3.1', min: '2.5.0', latest: '2.5.0').kind, UpdateKind.required);
      expect(_update('2.4.9', min: '2.5', latest: '2.6').kind, UpdateKind.required);
      expect(_update('2.5.0', min: '2.5.0', latest: '2.6.0').kind, UpdateKind.optional);
      expect(_update('1.0.6+35', min: '1.0.0', latest: '1.0.10').kind, UpdateKind.optional);
      expect(_update('1.0.10', min: '1.0.0', latest: '1.0.6').kind, UpdateKind.none, reason: 'ahead of the store');
      expect(_update('2.6.0', min: '2.5.0', latest: '2.6.0').kind, UpdateKind.none);
      expect(_update('1.0.6').kind, UpdateKind.none, reason: 'the table starts at 0.0.0, which asks nobody');
    });

    test('the versions as shown, three lines at most, and only a safe store link', () {
      final update = _update('2.3.1+7', min: '2.5', latest: '2.6', lines: ['أ', ' ', 'ب', 'ج', 'د'], url: ' https://x.y/z ');
      expect(update.installed, '2.3.1');
      expect(update.minVersion, '2.5.0');
      expect(update.latestVersion, '2.6.0');
      expect(update.whatsNew, ['أ', 'ب', 'ج']);
      expect(update.storeUrl, 'https://x.y/z');
      expect(_update('1.0.0', latest: '2.0.0', url: 'http://x.y').storeUrl, isNull);
      expect(_update('1.0.0', latest: '2.0.0', url: 'javascript:alert(1)').storeUrl, isNull);
    });

    test('an answer that cannot be read asks for nothing', () {
      for (final Object? answer in [
        null, 'ok', 7, <dynamic>[], <String, dynamic>{},
        {'min_version': 'soon', 'latest_version': null},
        {'min_version': 9, 'latest_version': <dynamic>[], 'whats_new': 'x', 'store_url': 5},
      ]) {
        expect(AppUpdate.resolve(installed: '1.0.6', answer: answer).kind, UpdateKind.none, reason: '$answer');
      }
      expect(AppUpdate.resolve(installed: null, answer: {'min_version': '9.0.0'}).kind, UpdateKind.none);
      expect(AppUpdate.resolve(installed: 'dev', answer: {'min_version': '9.0.0'}).kind, UpdateKind.none);
    });
  });

  group('the check never stands in the way', () {
    late RequestLog log;
    late FakeAppVersions server;
    setUp(() {
      log = RequestLog();
      server = FakeAppVersions(log)..answer = {'min_version': '2.0.0', 'latest_version': '2.1.0'};
    });

    test('one request, for this platform, and its answer', () async {
      final update = await AppUpdateRepository(gateway: server).check(installed: '1.0.6');
      expect(update.kind, UpdateKind.required);
      expect(log.calls, {'app_version': 1});
    });

    test('a database without the function, a refusal, no connection: no update', () async {
      for (final error in [
        const PostgrestException(message: 'Could not find the function public.get_app_version', code: 'PGRST202'),
        const PostgrestException(message: 'permission denied', code: '42501'),
        const SocketException('Failed host lookup'),
        StateError('anything'),
        AssertionError('not initialised'),
      ]) {
        server.fails = error;
        expect((await AppUpdateRepository(gateway: server).check(installed: '1.0.6')).kind, UpdateKind.none,
            reason: '$error');
      }
    });

    test('an answer that never comes is not waited for', () async {
      final never = _Never();
      final update =
          await AppUpdateRepository(gateway: never, timeout: const Duration(milliseconds: 20)).check(installed: '1.0.6');
      expect(update.kind, UpdateKind.none);
    });

    test('an installation that does not know its own version asks nothing', () async {
      expect((await AppUpdateRepository(gateway: server).check(installed: null)).kind, UpdateKind.none);
      expect((await AppUpdateRepository(gateway: server).check(installed: '')).kind, UpdateKind.none);
      expect(log.total, 0);
    });

    test('where there is no store there is no check', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        expect((await AppUpdateRepository(gateway: server).check(installed: '1.0.6')).kind, UpdateKind.none);
        expect(log.total, 0);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('the provider asks once per run, whoever watches', () async {
      final c = ProviderContainer(overrides: [
        installedVersionProvider.overrideWith((ref) => '1.0.6'),
        appUpdateRepoProvider.overrideWithValue(AppUpdateRepository(gateway: server)),
      ]);
      addTearDown(c.dispose);
      expect((await c.read(appUpdateProvider.future)).isRequired, isTrue);
      await c.read(appUpdateProvider.future);
      c.listen(appUpdateProvider, (_, __) {});
      expect(log.calls, {'app_version': 1});
    });
  });

  group('on screen', () {
    late _Store store;

    Future<void> open(
      WidgetTester tester, {
      required AppUpdate update,
      UserRole? role = UserRole.student,
      Size size = const Size(390, 844),
      double textScale = 1,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      store = _Store();
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          authStateProvider.overrideWith((ref) => _Auth(role)),
          onboardingProvider.overrideWith((ref) => OnboardingController.completed()),
          mustChangePasswordProvider.overrideWith((ref) => false),
          appUpdateProvider.overrideWith((ref) => update),
          appStoreProvider.overrideWithValue(store),
          studentQrProvider.overrideWith((ref) async => _pass),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
          ),
          home: const UpdateGate(child: Scaffold(body: Center(child: Text('التطبيق')))),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('nothing to say: the app, and no sheet however long it waits', (tester) async {
      await open(tester, update: AppUpdate.none);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('التطبيق'), findsOneWidget);
      expect(find.byType(BasakSheetFrame), findsNothing);
      expect(find.byType(UpdateRequiredScreen), findsNothing);
    });

    testWidgets('an optional update: the sheet over Home, its version and lines, and «لاحقاً»', (tester) async {
      await open(tester, update: _update('2.3.1', min: '2.0.0', latest: '2.5.0'));
      expect(find.byType(BasakSheetFrame), findsNothing, reason: 'not before Home has settled');
      await tester.pump(UpdateGate.calm);
      await tester.pumpAndSettle();
      expect(find.text('التطبيق'), findsOneWidget, reason: 'the app stays under it');
      expect(find.text('تحديث جديد متاح'), findsOneWidget);
      expect(find.text('2.5.0'), findsOneWidget);
      expect(find.text('بطاقة أوضح للمشرف عند الصعود'), findsOneWidget);
      expect(find.text('ملخّص الترم ومشاركته'), findsOneWidget);
      expect(find.text('تحسينات في السرعة وإصلاحات'), findsOneWidget);
      expect(find.text('تحديث الآن'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('لاحقاً'));
      await tester.pumpAndSettle();
      expect(find.byType(BasakSheetFrame), findsNothing);
      expect(store.opened, isEmpty);
    });

    testWidgets('«تحديث الآن» opens the store page the dashboard gave', (tester) async {
      await open(tester, update: _update('2.3.1', latest: '2.5.0', url: 'https://play.google.com/basak'));
      await tester.pump(UpdateGate.calm);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('update-now')));
      await tester.pumpAndSettle();
      expect(store.opened, ['https://play.google.com/basak']);
      expect(find.byType(BasakSheetFrame), findsNothing);
    });

    testWidgets('shown once per store version: not on the next launch, again for a newer one', (tester) async {
      final update = _update('2.3.1', latest: '2.5.0');
      await open(tester, update: update);
      await tester.pump(UpdateGate.calm);
      await tester.pumpAndSettle();
      expect(find.text('تحديث جديد متاح'), findsOneWidget);
      await tester.tap(find.text('لاحقاً'));
      await tester.pumpAndSettle();
      expect(await const PromptStore().updateOfferedVersion(unreadable: ''), '2.5.0');

      await open(tester, update: update); // the next launch
      await tester.pump(UpdateGate.calm);
      await tester.pumpAndSettle();
      expect(find.byType(BasakSheetFrame), findsNothing);

      await open(tester, update: _update('2.3.1', latest: '2.6.0'));
      await tester.pump(UpdateGate.calm);
      await tester.pumpAndSettle();
      expect(find.text('2.6.0'), findsOneWidget);
    });

    testWidgets('no lines written in the dashboard: the sheet without the list', (tester) async {
      await open(tester, update: _update('2.3.1', latest: '2.5.0', lines: const []));
      await tester.pump(UpdateGate.calm);
      await tester.pumpAndSettle();
      expect(find.text('تحديث جديد متاح'), findsOneWidget);
      expect(find.byType(CheckLines), findsNothing);
    });

    testWidgets('an optional update waits for a signed-in home, and for a connection', (tester) async {
      await open(tester, update: _update('2.3.1', latest: '2.5.0'), role: null);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(BasakSheetFrame), findsNothing, reason: 'nobody is signed in');

      await open(tester, update: _update('2.3.1', latest: '2.5.0'));
      OfflineCache.offlineSince.value = DateTime(2026, 10, 9);
      addTearDown(() => OfflineCache.offlineSince.value = null);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(BasakSheetFrame), findsNothing, reason: 'offline');
      expect(await const PromptStore().updateOfferedVersion(unreadable: ''), isNull, reason: 'still to be offered');
    });

    testWidgets('a supervisor is offered the same sheet', (tester) async {
      await open(tester, update: _update('2.3.1', latest: '2.5.0'), role: UserRole.supervisor);
      await tester.pump(UpdateGate.calm);
      await tester.pumpAndSettle();
      expect(find.text('تحديث جديد متاح'), findsOneWidget);
    });

    testWidgets('a required update: the screen instead of the app, the two versions, the store', (tester) async {
      await open(tester, update: _update('2.3.1', min: '2.5.0', latest: '2.5.0', url: 'https://play.google.com/basak'));
      expect(find.text('التطبيق'), findsNothing);
      expect(find.text('حدّث التطبيق للمتابعة'), findsOneWidget);
      expect(find.text('هذا الإصدار لم يعد مدعوماً. التحديث يأخذ دقيقة، ولا يغيّر حسابك أو اشتراكك.'), findsOneWidget);
      expect(find.text('إصدارك \u20662.3.1\u2069 · المطلوب \u20662.5.0\u2069'), findsOneWidget);
      expect(find.text('تحديث من Google Play'), findsOneWidget);
      expect(find.text('عرض بطاقتي'), findsOneWidget);
      expect(find.text('بطاقتك تعمل عند الصعود حتى قبل التحديث.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('update-required-store')));
      await tester.pump();
      expect(store.opened, ['https://play.google.com/basak']);
      expect(find.text('حدّث التطبيق للمتابعة'), findsOneWidget, reason: 'it stays until the app is updated');
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(BasakSheetFrame), findsNothing, reason: 'no optional sheet on top of it');
    });

    testWidgets('a store that cannot be opened says so', (tester) async {
      await open(tester, update: _update('2.3.1', min: '2.5.0'));
      store.opens = false;
      await tester.tap(find.byKey(const Key('update-required-store')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('تعذّر فتح Google Play. افتحه وابحث عن «باصك».'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('«عرض بطاقتي» opens the card by itself, and back returns to the update', (tester) async {
      await open(tester, update: _update('2.3.1', min: '2.5.0'));
      await tester.tap(find.byKey(const Key('update-required-card')));
      await tester.pumpAndSettle();
      expect(find.byType(StudentQrScreen), findsOneWidget);
      expect(find.text('بطاقتي'), findsOneWidget);
      expect(find.text('سارة أحمد محمود'), findsOneWidget);
      expect(find.text('التطبيق'), findsNothing, reason: 'the rest of the app stays closed');
      expect(tester.takeException(), isNull);

      await tester.tap(find.descendant(of: find.byKey(const Key('update-card-back')), matching: find.byType(BasakIconButton)));
      await tester.pumpAndSettle();
      expect(find.byType(StudentQrScreen), findsNothing);
      expect(find.text('حدّث التطبيق للمتابعة'), findsOneWidget);
    });

    testWidgets('a supervisor, and nobody signed in: the same screen without a card', (tester) async {
      for (final role in [UserRole.supervisor, null]) {
        await open(tester, update: _update('2.3.1', min: '2.5.0'), role: role);
        expect(find.text('حدّث التطبيق للمتابعة'), findsOneWidget);
        expect(find.text('تحديث من Google Play'), findsOneWidget);
        expect(find.text('عرض بطاقتي'), findsNothing);
        expect(find.text('بطاقتك تعمل عند الصعود حتى قبل التحديث.'), findsNothing);
      }
    });

    testWidgets('on an iPhone both are named for the App Store', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await open(tester, update: _update('2.3.1', min: '2.5.0'));
        expect(find.text('تحديث من App Store'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('nothing clips on a small phone with large text', (tester) async {
      await open(tester, update: _update('2.3.1', min: '2.5.0'), size: const Size(360, 640), textScale: 1.3);
      expect(tester.takeException(), isNull);
      expect(find.text('عرض بطاقتي'), findsOneWidget);
      await tester.tap(find.byKey(const Key('update-required-card')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await open(tester, update: _update('2.3.1', latest: '2.5.0'), size: const Size(360, 640), textScale: 1.3);
      await tester.pump(UpdateGate.calm);
      await tester.pumpAndSettle();
      expect(find.text('تحديث الآن'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _Never implements AppVersionGateway {
  @override
  Future<Object?> appVersion(String platform) => Completer<Object?>().future;
}
