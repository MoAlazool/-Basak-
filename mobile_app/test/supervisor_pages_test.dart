import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/core/widgets/basak_ui.dart' show BasakUi;
import 'package:basak_mobile/core/widgets/skeleton.dart';
import 'package:basak_mobile/features/notifications/presentation/notification_preferences_screen.dart';
import 'package:basak_mobile/features/notifications/push/push_messaging.dart';
import 'package:basak_mobile/features/notifications/push/push_providers.dart';
import 'package:basak_mobile/features/supervisor/data/supervisor_repository.dart';
import 'package:basak_mobile/features/supervisor/home/presentation/line_sheet.dart';
import 'package:basak_mobile/features/supervisor/models/supervisor_models.dart';
import 'package:basak_mobile/features/supervisor/monthly/presentation/supervisor_monthly_screen.dart';
import 'package:basak_mobile/features/supervisor/profile/presentation/supervisor_profile_screen.dart';
import 'package:basak_mobile/features/supervisor/supervisor_copy.dart';

import 'support/notification_fakes.dart';
import 'support/perf_fakes.dart' show onePixel;
import 'support/supervisor_boards.dart';
import 'support/supervisor_pages.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'باصك', packageName: 'basak', version: '2.4.0', buildNumber: '40', buildSignature: '');
  });

  group('the month', () {
    Future<void> month(WidgetTester tester, Map<DateTime, Map<String, dynamic>> months,
        {Size size = const Size(390, 1500), bool fails = false, List<DateTime>? asked}) =>
        pumpBoard(tester, BoardWorld(), SupervisorMonthlyScreen(month: DateTime(2026, 10)),
            tab: null,
            size: size,
            more: [
              supervisorMonthlySummaryProvider.overrideWith((ref, month) async {
                asked?.add(month);
                if (fails) throw Exception('PostgrestException(message: boom, code: 500)');
                return SupervisorMonthlySummary.fromJson(months[month] ?? emptyMonth('2026-01-01'));
              }),
            ]);

    testWidgets('the total, the rate, the split, the four counters, the chart and the bars', (tester) async {
      await month(tester, {DateTime(2026, 10): boardMonth()});
      await tester.pumpAndSettle();

      expect(find.text('ملخص الشهر'), findsOneWidget);
      expect(find.text('أكتوبر 2026'), findsOneWidget);
      // The ink hero.
      expect(find.text('تسجيلات الصعود'), findsOneWidget);
      expect(find.text('1,284'), findsNWidgets(2), reason: 'the hero, and the scan results');
      expect(find.text('91%'), findsOneWidget);
      expect(find.text('من الركوب المؤكَّد'), findsOneWidget);
      expect(find.text('702'), findsOneWidget);
      expect(find.text('582'), findsOneWidget);
      // The counters, each with the plural its number asks for.
      expect(find.text('طالباً مختلفاً'), findsOneWidget);
      expect(find.text('أيام عمل'), findsOneWidget);
      expect(find.text('عملية مسح'), findsOneWidget);
      expect(find.text('ركوباً مؤكَّداً'), findsOneWidget);
      expect(find.byType(StatTile), findsNWidgets(4));
      // The value is printed over every bar: nine working days, nine numbers.
      final chart = tester.widget<DayBars>(find.byType(DayBars));
      expect(chart.days, hasLength(9));
      for (final day in chart.days) {
        expect(
            find.descendant(of: find.byType(DayBars), matching: find.text('${day.total}')), findsWidgets);
        expect(find.descendant(of: find.byType(DayBars), matching: find.text(day.label)), findsOneWidget);
      }
      expect(chart.days.first.total, 152);
      // Scan results, then the six busiest stops of seven.
      expect(find.text('صعود مسجَّل'), findsOneWidget);
      expect(find.text('مسح مكرَّر'), findsOneWidget);
      expect(find.text('مسح مرفوض'), findsOneWidget);
      expect(find.byType(Meter), findsNWidgets(9));
      expect(find.text('كوبري السرو'), findsOneWidget);
      expect(find.text('فارسكور'), findsOneWidget);
      expect(find.text('كفر سعد'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a month with nothing in it says so, and the switcher still works', (tester) async {
      final asked = <DateTime>[];
      await month(tester, {DateTime(2026, 9): boardMonth()}, size: const Size(360, 640), asked: asked);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('monthly-empty')), findsOneWidget);
      expect(find.text('لا يوجد نشاط في هذا الشهر'), findsOneWidget);
      expect(find.byType(MonthHero), findsNothing);
      expect(find.byType(MonthSwitcher), findsOneWidget);

      // Back a month: that one has numbers.
      await tester.tap(find.bySemanticsLabel('الشهر السابق'));
      await tester.pumpAndSettle();
      expect(find.text('سبتمبر 2026'), findsOneWidget);
      expect(find.byType(MonthHero), findsOneWidget);
      // And forward again: kept for the session, not read twice.
      await tester.tap(find.bySemanticsLabel('الشهر التالي'));
      await tester.pumpAndSettle();
      expect(find.text('أكتوبر 2026'), findsOneWidget);
      expect(find.text('لا يوجد نشاط في هذا الشهر'), findsOneWidget);
      expect(asked, [DateTime(2026, 10), DateTime(2026, 9)]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the current month has no next one', (tester) async {
      final now = DateTime.now();
      await pumpBoard(tester, BoardWorld(), const SupervisorMonthlyScreen(), tab: null, more: [
        supervisorMonthlySummaryProvider
            .overrideWith((ref, month) async => SupervisorMonthlySummary.fromJson(emptyMonth('2026-01-01'))),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('${BasakUi.arabicMonths[now.month - 1]} ${now.year}'), findsOneWidget);
      expect(tester.widget<MonthSwitcher>(find.byType(MonthSwitcher)).onNext, isNull);
      expect(find.text('ابدأ بمسح رموز الطلاب من تبويب «مسح» وستظهر الأرقام هنا.'), findsOneWidget);
    });

    testWidgets('while it loads, its skeleton; when it cannot be read, plain words and a retry', (tester) async {
      await pumpBoard(tester, BoardWorld(), SupervisorMonthlyScreen(month: DateTime(2026, 10)), tab: null, more: [
        supervisorMonthlySummaryProvider.overrideWith((ref, month) => Completer<SupervisorMonthlySummary>().future),
      ]);
      expect(find.byType(MonthlySkeleton), findsOneWidget);
      expect(find.byType(MonthSwitcher), findsOneWidget);

      await month(tester, const {}, fails: true);
      await tester.pumpAndSettle();
      expect(find.text('تعذّر تحميل الملخص'), findsOneWidget);
      expect(find.textContaining('Postgrest'), findsNothing, reason: 'never the raw exception');
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });

    test('numbers are grouped by thousands, and nouns follow their number', () {
      expect(SupervisorCopy.grouped(1284), '1,284');
      expect(SupervisorCopy.grouped(52), '52');
      expect(SupervisorCopy.grouped(1000000), '1,000,000');
      String students(int n) => SupervisorCopy.noun(n,
          one: 'طالب مختلف', two: 'طالبان مختلفان', few: 'طلاب مختلفين', many: 'طالباً مختلفاً', hundred: 'طالب مختلف');
      expect(students(1), 'طالب مختلف');
      expect(students(2), 'طالبان مختلفان');
      expect(students(9), 'طلاب مختلفين');
      expect(students(118), 'طالباً مختلفاً');
      expect(students(100), 'طالب مختلف');
      expect(students(105), 'طلاب مختلفين');
    });
  });

  group('the account', () {
    Future<void> account(WidgetTester tester, BoardWorld world, {PushPermission push = PushPermission.granted}) async {
      await pumpBoard(tester, world, const SupervisorProfileScreen(),
          tab: 3,
          size: const Size(390, 950),
          more: [pushMessagingProvider.overrideWithValue(FakePushMessaging(granted: push))]);
      await tester.pumpAndSettle();
    }

    testWidgets('the company\'s mark sits beside its name once it has one, and not before', (tester) async {
      await account(tester, BoardWorld());
      expect(find.text('النورس للنقل'), findsOneWidget);
      expect(find.byKey(const Key('supervisor-company-logo')), findsNothing);

      debugCompanyLogoImage = (url) => MemoryImage(onePixel);
      addTearDown(() => debugCompanyLogoImage = null);
      await pumpBoard(tester, BoardWorld(), const SupervisorProfileScreen(), tab: 3, size: const Size(390, 950), more: [
        pushMessagingProvider.overrideWithValue(FakePushMessaging(granted: PushPermission.granted)),
        supervisorCompanyBrandProvider.overrideWith((ref, companyId) async {
          expect(companyId, 'company-1');
          return const CompanyBrand(emblemPath: '0b6f3c1e-8a2d-4e5f-9c7b-1d2e3f4a5b6c/emblem/2');
        }),
      ]);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('supervisor-company-logo')), findsOneWidget);
      expect(find.text('النورس للنقل'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('who they are, where they work, the app, and what the company manages', (tester) async {
      await account(tester, BoardWorld());

      expect(find.text('حسابي'), findsWidgets);
      expect(find.text('محمود السيد'), findsOneWidget);
      expect(find.text('010 1122 3344'), findsOneWidget);
      expect(tester.widget<StatusChip>(find.byType(StatusChip)).status, BasakStatus.active);
      expect(find.text('نشط'), findsOneWidget);

      expect(find.text('العمل'), findsOneWidget);
      expect(find.text('النورس للنقل'), findsOneWidget);
      expect(find.text('3 خطوط'), findsOneWidget);
      final now = DateTime.now();
      expect(find.text('${BasakUi.arabicMonths[now.month - 1]} ${now.year}'), findsOneWidget);

      expect(find.text('التطبيق'), findsOneWidget);
      expect(find.text('إشعارات الهاتف'), findsOneWidget);
      expect(find.text('مفعّلة'), findsOneWidget);
      expect(find.text('اللغة'), findsNothing, reason: 'Arabic only');

      expect(find.text('بياناتك وكلمة المرور تديرها شركتك. لتغييرها تواصل مع إدارة الشركة.'), findsOneWidget);
      expect(find.text('تسجيل الخروج'), findsOneWidget);
      expect(find.text('باصك 2.4.0'), findsOneWidget);
      // What the old page listed and the new one leaves to Home and Trips.
      expect(find.text('المحطات المسندة'), findsNothing);
      expect(find.text('تاريخ الإنشاء'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the lines row opens the line sheet; the summary and the switches open their pages', (tester) async {
      await account(tester, BoardWorld());

      await tester.tap(find.byKey(const Key('supervisor-lines')));
      await tester.pumpAndSettle();
      expect(find.byType(SupervisorLineSheet), findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('supervisor-phone-notifications')));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationPreferencesScreen), findsOneWidget, reason: 'the switches stay for supervisors');
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('supervisor-monthly')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SupervisorMonthlyScreen), findsOneWidget);
      expect(find.text('ملخص الشهر'), findsWidgets);
    });

    testWidgets('signing out asks first', (tester) async {
      await account(tester, BoardWorld());
      await tester.ensureVisible(find.byKey(const Key('supervisor-sign-out')));
      await tester.tap(find.byKey(const Key('supervisor-sign-out')));
      await tester.pumpAndSettle();
      expect(find.text('هل تريد تسجيل الخروج من حساب المشرف على هذا الجهاز؟'), findsOneWidget);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(find.text('هل تريد تسجيل الخروج من حساب المشرف على هذا الجهاز؟'), findsNothing);
      expect(find.byType(SupervisorProfileScreen), findsOneWidget);
    });

    testWidgets('a stopped account says so; a phone with pushes off says so', (tester) async {
      await account(tester, BoardWorld(dashboard: boardDashboard(active: false, lines: 1)),
          push: PushPermission.blocked);
      expect(find.text('موقوف'), findsOneWidget);
      expect(find.text('نشط'), findsNothing);
      expect(find.text('خط واحد'), findsOneWidget);
      expect(find.text('متوقفة'), findsOneWidget);
    });

    testWidgets('without the account read: its skeleton, then plain words; the app rows stay', (tester) async {
      await account(tester, BoardWorld(dashboardFails: true));
      expect(find.textContaining('تعذّر تحميل بيانات الحساب'), findsOneWidget);
      expect(find.textContaining('Postgrest'), findsNothing);
      expect(find.text('إشعارات الهاتف'), findsOneWidget);
      expect(find.text('تسجيل الخروج'), findsOneWidget);
    });
  });
}
