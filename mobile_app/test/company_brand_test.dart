// The company's logo and emblem where the app names a company: the fields as
// they arrive (present, null, absent, in copies saved before they existed),
// and the mark in its places.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/notifications/presentation/notifications_page.dart';
import 'package:basak_mobile/features/student/daily_ride/data/daily_ride_repository.dart';
import 'package:basak_mobile/features/student/qr/data/student_qr_repository.dart';
import 'package:basak_mobile/features/student/qr/presentation/student_qr_screen.dart';
import 'package:basak_mobile/features/student/subscription/data/subscription_gateway.dart';
import 'package:basak_mobile/features/student/subscription/models/sale_catalog.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';
import 'package:basak_mobile/features/student/subscription/presentation/receipt_card.dart';

import 'support/pay_fixtures.dart';
import 'support/perf_fakes.dart' show onePixel;

const company = '0b6f3c1e-8a2d-4e5f-9c7b-1d2e3f4a5b6c';
const logo = '$company/logo/1';
const emblem = '$company/emblem/2';
const brand = CompanyBrand(logoPath: logo, emblemPath: emblem);

Map<String, dynamic> subscriptionRow(Object? companies) => {
      'id': 'x', 'student_id': 's', 'line_id': 'l', 'station_id': 'st', 'type': 'termly',
      'status': 'active', 'price': 3500, 'created_at': '2026-10-01',
      'lines': {'name': 'الزرقا', 'companies': companies},
    };

Map<String, dynamic> alert({String type = 'announcement.admin', String role = 'admin', Object? withCompany}) => {
      'id': 'n1', 'type': type, 'title': 'تنبيه', 'body': 'نص التنبيه', 'created_at': '2026-10-10T08:00:00Z',
      'sender_role': role, 'sender_name': 'أحمد', 'audience': '', 'read': false,
      if (withCompany != null) 'company': withCompany,
    };

Widget app(Widget child) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: child)),
      ),
    );

void main() {
  final asked = <String>[];
  setUp(() {
    asked.clear();
    debugCompanyLogoImage = (url) {
      asked.add(url);
      return MemoryImage(onePixel);
    };
  });
  tearDown(() => debugCompanyLogoImage = null);

  group('the fields as they arrive', () {
    test('the catalog: a company with both, with one, and from a server that sends neither', () {
      SaleCompany of(Map<String, dynamic> more) => SaleCompany.fromJson({'id': 'c1', 'name': 'النورس', ...more});
      expect(of({'logo_path': logo, 'emblem_path': emblem}).brand, brand);
      expect(of({'logo_path': logo}).brand, const CompanyBrand(logoPath: logo), reason: 'emblem_path absent');
      expect(of({'logo_path': null, 'emblem_path': null}).brand, CompanyBrand.none);
      expect(of({}).brand, CompanyBrand.none);
    });

    test('a subscription: the new shape, the shape of a copy saved before it, and a suspended company', () {
      final fresh = SubscriptionModel.fromJson(
          subscriptionRow({'id': 'c1', 'name': 'النورس', 'logo_path': logo, 'emblem_path': emblem}));
      expect(fresh.companyName, 'النورس');
      expect(fresh.companyBrand, brand);

      final saved = SubscriptionModel.fromJson(subscriptionRow({'name': 'النورس'}));
      expect(saved.companyName, 'النورس', reason: 'a saved copy still reads');
      expect(saved.companyBrand, CompanyBrand.none);

      final suspended = SubscriptionModel.fromJson(subscriptionRow(null));
      expect(suspended.companyName, isNull);
      expect(suspended.companyBrand, CompanyBrand.none);
      expect(SubscriptionModel.fromJson({...subscriptionRow(null), 'lines': null}).companyBrand, CompanyBrand.none);
    });

    test('a database without the columns is recognised, so the read is made again without them', () {
      expect(SupabaseSubscriptionGateway.isUnknownColumn('42703', 'column companies_1.emblem_path does not exist'),
          isTrue);
      expect(SupabaseSubscriptionGateway.isUnknownColumn(null, 'column "emblem_path" does not exist'), isTrue);
      expect(SupabaseSubscriptionGateway.isUnknownColumn('42501', 'permission denied for table companies'), isFalse);
      expect(SupabaseSubscriptionGateway.isUnknownColumn('PGRST301', 'JWT expired'), isFalse);
    });

    test('the saved pass: written with the paths, and one saved before them still opens', () {
      const pass = StudentPassDetails(qrValue: 'QR', companyName: 'النورس', companyBrand: brand);
      final again = StudentPassDetails.fromCache(pass.toCacheJson());
      expect(again.companyBrand, brand);
      expect(again.companyName, 'النورس');

      final old = StudentPassDetails.fromCache({'qr_value': 'QR', 'company_name': 'النورس'});
      expect(old.qrValue, 'QR');
      expect(old.companyBrand, CompanyBrand.none);
    });

    test('an alert: its company when the server names one, none in an older page', () {
      final sent = AppNotification.fromJson(
          alert(withCompany: {'id': 'c1', 'name': 'النورس', 'logo_path': logo, 'emblem_path': emblem}));
      expect(sent.companyName, 'النورس');
      expect(sent.companyBrand, brand);
      expect(sent.fromCompany, isTrue);
      expect(sent.markedRead().companyBrand, brand, reason: 'kept when it is marked read');

      final older = AppNotification.fromJson(alert());
      expect(older.companyBrand, CompanyBrand.none);
      expect(older.fromCompany, isFalse);
      expect(AppNotification.fromJson(alert(withCompany: {'id': 'c1', 'name': 'النورس'})).companyBrand,
          CompanyBrand.none);
    });

    test('the platform\'s announcement and the system\'s alerts keep their own identity', () {
      final withBrand = {'id': 'c1', 'name': 'النورس', 'logo_path': logo, 'emblem_path': emblem};
      final platform = AppNotification.fromJson(alert(type: 'announcement.platform', withCompany: withBrand));
      expect(platform.fromCompany, isFalse);
      expect(platform.senderLabel, 'منصة باصك');
      final system = AppNotification.fromJson(alert(type: 'subscription.approved', role: 'system', withCompany: withBrand));
      expect(system.fromCompany, isFalse);
      expect(system.senderLabel, 'باصك');
      expect(AppNotification.fromJson(alert(role: 'supervisor', withCompany: withBrand)).fromCompany, isTrue);
    });
  });

  group('the mark in its places', () {
    testWidgets('choosing a company: its emblem in the tile; without one, its initial as before', (tester) async {
      await tester.pumpWidget(app(Column(children: [
        CompanyRow(name: 'النورس للنقل', caption: '4 خطوط إلى جامعتك', brand: brand, onTap: () {}),
        CompanyRow(key: const Key('plain'), name: 'المستقبل', caption: 'خط واحد', onTap: () {}),
      ])));
      await tester.pumpAndSettle();
      expect(asked, hasLength(1));
      expect(asked.single, endsWith('/$emblem/small.png'));
      expect(find.byKey(const Key('company-logo-image')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('plain')), matching: find.text('م')), findsOneWidget);
      // Both tiles are the same box: the list does not move when a picture arrives.
      final tiles = tester.widgetList<CompanyLogo>(find.byType(CompanyLogo)).toList();
      expect(tiles.map((t) => t.size), [48, 48]);
      expect(tester.getSize(find.byType(CompanyLogo).first), tester.getSize(find.byType(CompanyLogo).last));
    });

    testWidgets('the pass stub: the company\'s mark in the bus tile; the bus where it has none', (tester) async {
      await tester.pumpWidget(app(Container(
        color: BasakPalette.ink,
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const PassStub(line: 'خط الزرقا', company: 'النورس للنقل', brand: CompanyBrand(logoPath: logo)),
          const SizedBox(height: 12),
          const PassStub(key: Key('plain'), line: 'خط الزرقا', company: 'النورس للنقل'),
        ]),
      )));
      await tester.pumpAndSettle();
      expect(asked.single, endsWith('/$logo/google.png'), reason: 'no emblem: the logo on its square');
      expect(find.byKey(const Key('company-logo-image')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('plain')), matching: find.byIcon(LucideIcons.bus)),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('plain')), matching: find.byType(CompanyLogo)), findsNothing);
      expect(tester.getSize(find.byType(CompanyLogo)), const Size(40, 40));
    });

    testWidgets('the receipt: the logo it was issued under beside the amount; none, and nothing is added',
        (tester) async {
      await tester.pumpWidget(app(const ReceiptCard(receipt: boardReceiptDoc)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receipt-company-logo')), findsNothing);
      expect(asked, isEmpty);

      const branded = SubscriptionReceipt(
        subscriptionId: 'sub1', code: '26-7F3A9C2E', companyName: 'النورس للنقل', studentName: 'سارة أحمد محمود',
        lineName: 'الزرقا', periodLabel: 'الفصل الدراسي الأول 2026/2027', amount: 4500,
        approvedAt: '2026-09-22T10:00:00Z', companyLogoPath: logo,
      );
      await tester.pumpWidget(app(const ReceiptCard(receipt: branded)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receipt-company-logo')), findsOneWidget);
      expect(asked.single, endsWith('/$logo/google.png'));
      expect(find.text('4,500 ج.م'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the back of the card: the mark beside the company\'s name; the face is left to the code',
        (tester) async {
      KnownRides.clear();
      StudentPassDetails pass(CompanyBrand brand) => StudentPassDetails(
          qrValue: 'QR-1', fullName: 'سارة أحمد', lineName: 'الزرقا', stationName: 'كوبري السرو',
          subscriptionId: 'sub1', subscriptionStatus: 'active', periodPhase: 'current', periodName: 'الفصل الأول',
          endDate: '2027-01-14', companyName: 'النورس للنقل', companyBrand: brand);
      Future<void> open(CompanyBrand brand) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ProviderScope(
          key: UniqueKey(),
          overrides: [studentQrProvider.overrideWith((ref) async => pass(brand))],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: StudentQrScreen())),
          ),
        ));
        await tester.pumpAndSettle();
      }

      await open(brand);
      expect(find.byType(CompanyLogo), findsNothing, reason: 'nothing competes with the code');
      expect(asked, isEmpty);
      await tester.tap(find.byKey(const Key('card-flip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('card-company-logo')), findsOneWidget);
      expect(find.text('النورس للنقل'), findsOneWidget);
      expect(asked.toSet().single, endsWith('/$emblem/small.png'), reason: 'one picture, however often it is drawn');

      await open(CompanyBrand.none);
      await tester.tap(find.byKey(const Key('card-flip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('card-company-logo')), findsNothing);
      expect(find.text('النورس للنقل'), findsOneWidget);
    });

    testWidgets('an alert\'s sheet: the company\'s mark for what the company sent, the kind\'s glyph otherwise',
        (tester) async {
      final withBrand = {'id': 'c1', 'name': 'النورس', 'logo_path': logo, 'emblem_path': emblem};
      Future<void> show(AppNotification n) async {
        await tester.pumpWidget(MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.lightTheme,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => NotificationsPage.showDetail(context, n), child: const Text('افتح')),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('افتح'));
        await tester.pumpAndSettle();
      }

      await show(AppNotification.fromJson(alert(withCompany: withBrand)));
      expect(find.byKey(const Key('alert-company-logo')), findsOneWidget);
      expect(asked.single, endsWith('/$emblem/small.png'));

      asked.clear();
      await show(AppNotification.fromJson(alert(type: 'announcement.platform', withCompany: withBrand)));
      expect(find.byKey(const Key('alert-company-logo')), findsNothing, reason: '«منصة باصك», not the company');
      expect(find.byType(ToneTile), findsWidgets);
      expect(asked, isEmpty);

      await show(AppNotification.fromJson(alert()));
      expect(find.byKey(const Key('alert-company-logo')), findsNothing, reason: 'an older page');
    });
  });
}
