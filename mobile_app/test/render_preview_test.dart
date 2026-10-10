// Draws the subscription screens to PNG files with the app's real fonts, for a
// look at the layout without a device. Skipped unless RENDER_DIR is set:
//   RENDER_DIR=/tmp/basak-preview flutter test test/render_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/features/student/daily_ride/data/daily_ride_repository.dart';
import 'package:basak_mobile/features/student/qr/data/student_qr_repository.dart';
import 'package:basak_mobile/features/student/qr/presentation/student_qr_screen.dart';
import 'package:basak_mobile/features/student/home/presentation/supervisor_contact_sheet.dart';
import 'package:basak_mobile/features/student/subscription/models/payment_method_model.dart';
import 'package:basak_mobile/features/student/subscription/models/sale_catalog.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';
import 'package:basak_mobile/features/student/subscription/presentation/purchase_flow.dart';
import 'package:basak_mobile/features/student/subscription/presentation/subscription_screen.dart';

import 'subscription_flow_test.dart' as fixtures;

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

Future<void> _open(WidgetTester tester, List<SubscriptionModel> subs, {SubscriptionReceipt? doc, double height = 874}) async {
  tester.view.physicalSize = Size(402 * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      allSubscriptionsProvider.overrideWith((ref) async => subs),
      saleCatalogProvider.overrideWith((ref) async => fixtures.catalog()),
      subscriptionReceiptsProvider.overrideWith((ref, id) async => <ReceiptModel>[]),
      subscriptionReceiptDocProvider.overrideWith((ref, id) async => doc),
      paymentMethodsProvider.overrideWith((ref, id) async => [
            PaymentMethodModel.fromJson({
              'id': 'm1', 'company_id': 'c1', 'method_type': 'instapay', 'display_name': 'InstaPay',
              'instapay_address': 'almostaqbal@instapay', 'account_holder': 'شركة المستقبل',
              'instructions': 'اكتب اسم الطالب في خانة الملاحظات عند التحويل.', 'is_active': true, 'sort_order': 0,
            }),
            PaymentMethodModel.fromJson({
              'id': 'm2', 'company_id': 'c1', 'method_type': 'vodafone_cash', 'display_name': 'فودافون كاش',
              'wallet_phone': '01012345678', 'is_active': true, 'sort_order': 1,
            }),
          ]),
    ],
    child: RepaintBoundary(
      key: _key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const SubscriptionScreen(),
      ),
    ),
  ));
}

void main() {
  testWidgets('draw the subscription screens', (tester) async {
    await tester.runAsync(_fonts);
    Directory(_dir!).createSync(recursive: true);
    Future<void> tap(String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    // The builder: the only company starts chosen, so it opens on the lines.
    await _open(tester, []);
    await _shot(tester, '1-lines');
    await tap('line-l1');
    await tap('station-s2');
    await _shot(tester, '2-station');
    await tap('station-confirm');
    await _shot(tester, '3-period');
    await tap('option-both');
    await _shot(tester, '4-period-chosen');
    await tester.ensureVisible(find.byKey(const Key('flow-review')));
    await tap('flow-review');
    await _shot(tester, '5-review');
    await tap('review-back');

    // Awaiting payment on the tab, then the pay page it opens.
    await _open(tester, [fixtures.subscription('pending_payment')]);
    await _shot(tester, '6-awaiting');
    await tester.tap(find.text('ادفع الآن'));
    tester.view.physicalSize = const Size(402 * 2, 1150 * 2);
    await _shot(tester, '6-payment');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    SubscriptionModel sub(String id, String status, String code, String phase, String start, String end) =>
        SubscriptionModel.fromJson({
          'id': id, 'student_id': 'me', 'line_id': 'l1', 'company_id': 'c1', 'station_id': 's2', 'type': 'termly',
          'status': status, 'price': 8000, 'created_at': start, 'start_date': start, 'end_date': end,
          'period_code': code, 'academic_year': 2026, 'period_phase': phase,
          'lines': {'name': 'منيه النصر', 'companies': {'name': 'المستقبل'}}, 'stations': {'name': 'البجلات'},
          'student': {'university': 'جامعة الدلتا'},
        });
    final history = [
      sub('sub1', 'active', 'second', 'current', '2027-02-01', '2027-06-30'),
      sub('old1', 'expired', 'first', 'expired', '2026-09-05', '2027-01-30'),
    ];
    await _open(tester, history, doc: fixtures.receipt, height: 874);
    await _shot(tester, '7-history');
    // The receipt is a row of the tab and a page of its own.
    await tester.tap(find.byKey(const Key('receipt-row-sub1')));
    await _shot(tester, '8-receipt');
  }, skip: _dir == null);

  // The card tab, framed as in the app: the floating tab bar over the page's bottom.
  Future<void> card(WidgetTester tester, Size size, StudentPassDetails? pass, {double textScale = 1}) async {
    await tester.runAsync(_fonts);
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [studentQrProvider.overrideWith((ref) async => pass)],
      child: RepaintBoundary(
        key: _key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
          home: Scaffold(
            extendBody: true,
            body: const StudentQrScreen(),
            bottomNavigationBar: Container(
              height: 64,
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32)),
            ),
          ),
        ),
      ),
    ));
  }

  StudentPassDetails pass(String? status, {String phase = 'current'}) => StudentPassDetails(
      qrValue: '11111111-2222-3333-4444-555555555555', fullName: 'محمد عادل إبراهيم', phone: '01055512301',
      university: 'جامعة الدلتا للعلوم والتكنولوجيا', college: 'الهندسة',
      lineName: status == null ? null : 'منيه النصر', stationName: status == null ? null : 'البجلات',
      subscriptionId: status == null ? null : 'sub1', subscriptionType: status == null ? null : 'termly',
      subscriptionStatus: status, periodPhase: status == null ? null : phase,
      periodName: status == null ? null : 'الفصل الأول', academicYear: status == null ? null : 2026,
      startDate: status == null ? null : '2026-09-20', endDate: status == null ? null : '2027-01-14',
      companyName: status == null ? null : 'المستقبل للنقل');

  void rideToday() {
    final today = DateTime.now();
    KnownRides.debugUserId = 'me';
    KnownRides.voted('me', today,
        const DailyRideDetails(isRiding: true, departureTime: '07:23:00', returnTime: '15:30:00'));
    addTearDown(() {
      KnownRides.clear();
      KnownRides.debugUserId = null;
    });
  }

  /// The page is fixed: it can be pulled to refresh, but there is nothing to scroll to.
  void expectFixed(WidgetTester tester) {
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scroll.position.maxScrollExtent, 0, reason: 'the card page is fixed');
  }

  for (final size in const [Size(402, 874), Size(390, 844), Size(375, 667), Size(360, 640), Size(430, 932)]) {
    final name = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets('draw the student card at $name', (tester) async {
      rideToday();
      await card(tester, size, pass('active'));
      await _shot(tester, 'card-${size.height.toInt()}');
      expectFixed(tester);
      expect(find.byKey(const Key('card-ride')), findsOneWidget);
      // The code is the last thing to give way: still large on the smallest phone.
      expect(tester.getSize(find.byKey(const Key('student-qr'))).width, greaterThan(size.height < 650 ? 130 : size.height < 700 ? 150 : 180));
      expect(find.text('الكلية'), findsNothing);
    }, skip: _dir == null);

    testWidgets('draw the card that is not active at $name', (tester) async {
      await card(tester, size, pass('pending_review'));
      await _shot(tester, 'card-inactive-${size.height.toInt()}');
      expectFixed(tester);
      expect(find.text('إضافة إلى Google Wallet'), findsNothing);
    }, skip: _dir == null);
  }

  testWidgets('draw the card in its other states', (tester) async {
    const phone = Size(390, 844);
    for (final (name, details) in [
      ('expired', pass('expired', phase: 'expired')),
      ('rejected', pass('rejected')),
      ('awaiting-payment', pass('pending_payment')),
      ('none', pass(null)),
    ]) {
      await card(tester, phone, details);
      await _shot(tester, 'card-$name');
      expectFixed(tester);
    }
    await card(tester, phone, null);
    await _shot(tester, 'card-unavailable');
    await card(tester, const Size(360, 640), null);
    await _shot(tester, 'card-unavailable-640');

    rideToday();
    await card(tester, const Size(360, 640), pass('active'), textScale: 1.3);
    await _shot(tester, 'card-640-large-text');
    expect(tester.getSize(find.byKey(const Key('student-qr'))).width, greaterThan(100));

    for (final size in const [phone, Size(360, 640)]) {
      await card(tester, size, pass('active'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card-details-open')));
      await _shot(tester, 'card-details-${size.height.toInt()}');
      expect(find.byKey(const Key('card-details')), findsOneWidget);
      await tester.tap(find.byKey(const Key('card-details-close')));
      await tester.pumpAndSettle();
    }
  }, skip: _dir == null);

  testWidgets('draw the supervisor sheet', (tester) async {
    await tester.runAsync(_fonts);
    tester.view.physicalSize = const Size(402 * 2, 874 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: _key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          backgroundColor: const Color(0xFFEAF5FA),
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => SupervisorContactSheet.show(context,
                    name: 'أحمد علي محمود', phone: '01012345678', lineName: 'منيه النصر'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await _shot(tester, '9-supervisor');
  }, skip: _dir == null);
}
