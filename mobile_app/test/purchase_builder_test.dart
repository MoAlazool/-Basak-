// The subscribe builder (boards FlowCompany, FlowLines, FlowStation,
// FlowPeriod, FlowDaily, FlowConfirm, FlowEmpty): what each state shows for
// each shape of the catalogue. The whole journey is in subscription_flow_test.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/features/student/subscription/models/sale_catalog.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_draft.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';
import 'package:basak_mobile/features/student/subscription/presentation/purchase_flow.dart';

Map<String, dynamic> option(String code, num price, {String phase = 'current'}) => {
      'option': code, 'academic_year': 2026, 'label': code, 'type': code == 'both' ? 'yearly' : 'termly',
      'start_date': code == 'second' ? '2027-02-07' : code == 'summer' ? '2027-07-01' : '2026-09-20',
      'end_date': code == 'first' ? '2027-01-14' : code == 'summer' ? '2027-08-30' : '2027-05-28',
      'phase': phase, 'price': price,
    };

Map<String, dynamic> station(String id, String name, [List<String> times = const ['06:15:00', '07:00:00']]) => {
      'id': id, 'name': name,
      'departures': [
        for (var i = 0; i < times.length; i++) {'trip_id': 't$i', 'time': times[i], 'label': ''},
      ],
    };

Map<String, dynamic> line(String id, String name,
        {List<Map<String, dynamic>>? stations, List<Map<String, dynamic>>? options, num? daily}) =>
    {
      'id': id, 'name': name, 'origin_name': name, 'university': 'جامعة المنصورة الجديدة',
      'first_departure': '06:15:00', 'last_return': '17:30:00',
      'stations': stations ?? [station('$id-s1', 'موقف $name'), station('$id-s2', 'كوبري السرو')],
      'returns': [
        {'trip_id': 'r1', 'time': '15:00:00', 'label': ''},
      ],
      'options': options ?? [option('first', 4500), option('second', 4500), option('both', 8000)],
      'daily': {'enabled': daily != null, 'price': daily ?? 0},
    };

SaleCatalog catalogOf(List<Map<String, dynamic>> companies) => SaleCatalog.fromJson(jsonDecode(jsonEncode({
      'university': {'id': 'u1', 'name': 'جامعة المنصورة الجديدة'},
      'companies': companies,
    })) as Map<String, dynamic>);

/// Two companies; the second lists a closed line before the one on sale.
SaleCatalog twoCompanies() => catalogOf([
      {
        'id': 'c1', 'name': 'النورس للنقل',
        'lines': [line('l1', 'الزرقا', daily: 60), line('l2', 'فارسكور', options: [option('first', 4200)])],
      },
      {
        'id': 'c2', 'name': 'دلتا باص',
        'lines': [line('l4', 'شربين', options: []), line('l3', 'كفر سعد')],
      },
    ]);

SaleCatalog oneLine({List<Map<String, dynamic>>? options, num? daily, List<Map<String, dynamic>>? stations}) =>
    catalogOf([
      {
        'id': 'c1', 'name': 'النورس للنقل',
        'lines': [line('l1', 'الزرقا', options: options, daily: daily, stations: stations)],
      },
    ]);

SubscriptionModel created(SubscriptionRequest request) => SubscriptionModel.fromJson({
      'id': 'sub1', 'student_id': 'me', 'line_id': request.lineId, 'company_id': 'c1',
      'station_id': request.stationId, 'type': request.type, 'status': 'pending_payment', 'price': request.price,
      'created_at': '2026-10-08',
    });

void main() {
  late List<SubscriptionRequest> requests;
  late int reads;
  Object? failWith;

  /// The builder inside a scrolling parent, as its own page above the tabs
  /// when [page] is set, or as a tab's own page when [tab] is.
  Future<void> open(
    WidgetTester tester,
    SaleCatalog Function() catalog, {
    SubscriptionDraft initial = const SubscriptionDraft(),
    bool allowDaily = true,
    bool page = false,
    bool tab = false,
    Size size = const Size(390, 1400),
    double textScale = 1,
    VoidCallback? onCancel,
  }) async {
    requests = [];
    reads = 0;
    failWith = null;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        saleCatalogProvider.overrideWith((ref) async {
          reads++;
          return catalog();
        }),
        subscriptionCreatorProvider.overrideWithValue((request) async {
          if (failWith != null) throw failWith!;
          requests.add(request);
          return created(request);
        }),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
        home: page
            ? PurchaseFlowPage(initial: initial, allowDaily: allowDaily)
            : tab
                ? Scaffold(body: PurchaseFlow(initial: initial, allowDaily: allowDaily, onCreated: (_) {}))
                : Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: PurchaseFlow(initial: initial, allowDaily: allowDaily, onCancel: onCancel, onCreated: (_) {}),
                ),
              ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  /// Scrolls the page to it first.
  Future<void> tapRevealed(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tap(tester, key);
  }

  Future<void> change(WidgetTester tester, String row) async {
    await tester.tap(find.descendant(of: find.byKey(Key('flow-row-$row')), matching: find.text('تغيير')));
    await tester.pumpAndSettle();
  }

  /// Line and station in one gesture.
  Future<void> pick(WidgetTester tester, String lineId, String stationId) async {
    await tap(tester, 'line-$lineId');
    await tap(tester, 'station-$stationId');
    await tap(tester, 'station-confirm');
  }

  double y(WidgetTester tester, String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
  double x(WidgetTester tester, String key) => tester.getTopLeft(find.byKey(Key(key))).dx;
  double width(WidgetTester tester, String key) => tester.getSize(find.byKey(Key(key))).width;

  group('company', () {
    testWidgets('one company is preselected and collapsed, with nothing to change to', (tester) async {
      await open(tester, oneLine);
      expect(find.byKey(const Key('company-c1')), findsNothing);
      expect(find.byKey(const Key('flow-row-company')), findsOneWidget);
      expect(find.text('النورس للنقل'), findsOneWidget);
      expect(find.text('تغيير'), findsNothing);
      // The next step is already open.
      expect(find.byKey(const Key('line-l1')), findsOneWidget);
    });

    testWidgets('several companies: a list of rows, and the later steps wait, numbered', (tester) async {
      await open(tester, twoCompanies);
      expect(find.byType(BuilderStepHead), findsOneWidget);
      expect(find.text('شركة النقل'), findsOneWidget);
      expect(find.text('خطّان إلى جامعتك'), findsNWidgets(2));
      expect(find.text('الخط والمحطة'), findsOneWidget);
      expect(find.text('الفترة'), findsOneWidget);
      expect(find.byType(LineCard), findsNothing);

      await tap(tester, 'company-c2');
      expect(find.byKey(const Key('company-c1')), findsNothing);
      expect(find.byKey(const Key('flow-row-company')), findsOneWidget);
      expect(find.text('دلتا باص'), findsOneWidget);
      expect(find.byKey(const Key('line-l3')), findsOneWidget);
      // With somewhere else to go, the chosen row offers the change.
      await change(tester, 'company');
      expect(find.byKey(const Key('company-c1')), findsOneWidget);
    });

    testWidgets('changing an earlier choice keeps the later ones that still apply', (tester) async {
      await open(tester, twoCompanies);
      await tap(tester, 'company-c1');
      await pick(tester, 'l1', 'l1-s2');
      await tap(tester, 'option-first');
      expect(find.byKey(const Key('flow-review')), findsOneWidget);

      // The same company again: the line, the station and the period stay.
      await change(tester, 'company');
      expect(find.text('الزرقا · كوبري السرو'), findsOneWidget, reason: 'still chosen while the company is open');
      await tap(tester, 'company-c1');
      expect(find.text('الزرقا · كوبري السرو'), findsOneWidget);
      expect(find.byKey(const Key('flow-review')), findsOneWidget);

      // Another line of the company that also sells the first semester: the
      // period is kept, the station is asked again.
      await change(tester, 'line');
      await tap(tester, 'line-l2');
      expect(find.text('اختيار'), findsOneWidget, reason: 'كوبري السرو of the other line is another stop');
      await tap(tester, 'station-l2-s1');
      await tap(tester, 'station-confirm');
      expect(find.text('فارسكور · موقف فارسكور'), findsOneWidget);
      expect(find.text('4,200'), findsOneWidget);
      expect(find.byKey(const Key('flow-review')), findsOneWidget);

      // Another company: what belonged to the first one is dropped.
      await change(tester, 'company');
      await tap(tester, 'company-c2');
      expect(find.byKey(const Key('flow-row-line')), findsNothing);
      expect(find.byKey(const Key('flow-review')), findsNothing);
      expect(requests, isEmpty);
    });
  });

  group('lines and stations', () {
    testWidgets('a line that is not on sale sinks to the end and cannot be tapped', (tester) async {
      await open(tester, twoCompanies);
      await tap(tester, 'company-c2');
      expect(y(tester, 'line-l3'), lessThan(y(tester, 'line-l4')));
      expect(find.text('غير متاح'), findsOneWidget);
      expect(find.text('محطتان · الاشتراك مغلق حالياً'), findsOneWidget);
      await tester.tap(find.byKey(const Key('line-l4')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('من أين تركب؟'), findsNothing);
    });

    testWidgets('closing the station sheet without a stop chooses nothing', (tester) async {
      await open(tester, oneLine);
      await tap(tester, 'line-l1');
      expect(find.text('من أين تركب؟'), findsOneWidget);
      // Nothing is selected yet, so there is nothing to confirm.
      expect(tester.widget<BasakButton>(find.byKey(const Key('station-confirm'))).onPressed, isNull);
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      expect(find.text('من أين تركب؟'), findsNothing);
      expect(find.byKey(const Key('flow-row-line')), findsNothing);
      expect(find.byKey(const Key('line-l1')), findsOneWidget);
    });

    testWidgets('above six stops the sheet searches; a stop opens to all its times', (tester) async {
      const names = ['موقف الزرقا', 'ميت الخولي', 'شرباص', 'كوبري السرو', 'السرو', 'الروضة', 'فارسكور'];
      await open(
        tester,
        () => oneLine(stations: [
          for (var i = 0; i < names.length; i++)
            station('s${i + 1}', names[i], ['06:${15 + i}:00', '07:${10 + i}:00', '13:${10 + i}:00']),
        ]),
        size: const Size(390, 1000),
      );
      await tap(tester, 'line-l1');
      expect(find.text('خط الزرقا · 7 محطات · 3 رحلات'), findsOneWidget);
      expect(find.byKey(const Key('station-search')), findsOneWidget);
      expect(find.byType(StationRow), findsNWidgets(7));
      // Closed rows: the first pass time only.
      expect(find.text('من 6:18 ص'), findsOneWidget);
      await tap(tester, 'station-s4');
      expect(find.text('6:18 ص · 7:13 ص · 1:13 م'), findsOneWidget);
      expect(find.text('من 6:18 ص'), findsNothing);

      await tester.enterText(find.byType(TextField), 'السرو');
      await tester.pumpAndSettle();
      expect(find.byType(StationRow), findsNWidgets(2));
      await tester.enterText(find.byType(TextField), 'القاهرة');
      await tester.pumpAndSettle();
      expect(find.byType(StationRow), findsNothing);
      expect(find.text('لا توجد محطة بهذا الاسم'), findsOneWidget);
      // The stop chosen before the search is still the one to confirm.
      await tap(tester, 'station-confirm');
      expect(find.text('الزرقا · كوبري السرو'), findsOneWidget);
    });
  });

  group('periods', () {
    Future<void> toPeriods(WidgetTester tester, List<Map<String, dynamic>> options, {num? daily}) async {
      await open(tester, () => oneLine(options: options, daily: daily));
      await pick(tester, 'l1', 'l1-s2');
    }

    testWidgets('one period: a wide tile, already chosen', (tester) async {
      await toPeriods(tester, [option('first', 4500)]);
      expect(find.byType(PeriodTile), findsOneWidget);
      expect(width(tester, 'option-first'), 350);
      expect(tester.widget<PeriodTile>(find.byKey(const Key('option-first'))).selected, isTrue);
      expect(find.text('من 20 سبتمبر 2026 إلى 14 يناير 2027'), findsOneWidget);
      expect(find.byKey(const Key('flow-review')), findsOneWidget);
    });

    testWidgets('one period and the cash day: two things to choose from, nothing chosen for the student',
        (tester) async {
      await toPeriods(tester, [option('first', 4500)], daily: 60);
      expect(tester.widget<PeriodTile>(find.byKey(const Key('option-first'))).selected, isFalse);
      expect(find.text('أو يوم واحد، نقداً في الباص'), findsOneWidget);
      expect(find.text('60 ج.م'), findsOneWidget);
      expect(find.byKey(const Key('flow-review')), findsNothing);
    });

    testWidgets('two periods: two columns', (tester) async {
      await toPeriods(tester, [option('first', 4500), option('second', 4500, phase: 'upcoming')]);
      expect(y(tester, 'option-first'), y(tester, 'option-second'));
      expect(width(tester, 'option-first'), (350 - 8) / 2);
      expect(x(tester, 'option-first'), greaterThan(x(tester, 'option-second')));
      // Without the bundle there is no saving to tag; the period to come says so.
      expect(find.textContaining('وفّر'), findsNothing);
      expect(find.text('الفترة القادمة'), findsOneWidget);
    });

    testWidgets('three periods: one row, the bundle tagged with what it saves', (tester) async {
      await toPeriods(tester, [option('both', 8000), option('second', 4500), option('first', 4500)]);
      expect({y(tester, 'option-first'), y(tester, 'option-second'), y(tester, 'option-both')}, hasLength(1));
      expect(width(tester, 'option-first'), closeTo((350 - 16) / 3, .01));
      expect(find.text('وفّر 1,000'), findsOneWidget);
      await tap(tester, 'option-both');
      expect(find.text('من 20 سبتمبر 2026 إلى 28 مايو 2027'), findsOneWidget);
      await tap(tester, 'option-second');
      expect(find.text('من 7 فبراير إلى 28 مايو 2027'), findsOneWidget);
    });

    testWidgets('four periods: a 2 × 2 grid', (tester) async {
      await toPeriods(
          tester, [option('first', 4500), option('second', 4500), option('both', 8000), option('summer', 1500)]);
      expect(y(tester, 'option-first'), y(tester, 'option-second'));
      expect(y(tester, 'option-both'), y(tester, 'option-summer'));
      expect(y(tester, 'option-both'), greaterThan(y(tester, 'option-first')));
      expect(x(tester, 'option-first'), x(tester, 'option-both'));
      expect(width(tester, 'option-summer'), (350 - 8) / 2);
      expect(find.text('الفصل الصيفي'), findsOneWidget);
    });

    testWidgets('nothing on sale for a line chosen earlier: says so, with a way to read again', (tester) async {
      await open(tester, () => oneLine(options: []),
          initial: const SubscriptionDraft(companyId: 'c1', lineId: 'l1', stationId: 'l1-s2'), allowDaily: false);
      expect(find.text('لا توجد فترة متاحة للاشتراك الآن على هذا الخط.'), findsOneWidget);
      final before = reads;
      await tester.tap(find.text('تحديث'));
      await tester.pumpAndSettle();
      expect(reads, before + 1);
    });
  });

  group('the cash day', () {
    testWidgets('chosen from the quiet row, confirmed in place: no review, no payment', (tester) async {
      await open(tester, () => oneLine(daily: 60));
      await pick(tester, 'l1', 'l1-s2');
      await tap(tester, 'option-daily');
      // What was picked, the periods as a list with the day among them, and what a cash day means.
      expect(find.text('الشركة'), findsOneWidget);
      expect(find.text('الزرقا · كوبري السرو'), findsOneWidget);
      expect(find.byType(PeriodRow), findsNWidgets(4));
      expect(find.text('يوم واحد'), findsOneWidget);
      expect(find.text('نقداً'), findsOneWidget);
      expect(find.text('اليوم فقط · الدفع نقداً في الباص'), findsOneWidget);
      expect(find.text('60 ج.م'), findsOneWidget);
      expect(find.textContaining('تدفع للمشرف عند الصعود'), findsOneWidget);
      expect(find.text('مراجعة الاشتراك'), findsNothing);

      // A period from the list goes back to the builder with it chosen.
      await tap(tester, 'option-both');
      expect(find.byType(PeriodTile), findsNWidgets(3));
      expect(tester.widget<PeriodTile>(find.byKey(const Key('option-both'))).selected, isTrue);
      expect(find.byKey(const Key('flow-review')), findsOneWidget);

      await tap(tester, 'option-daily');
      expect(requests, isEmpty);
      await tap(tester, 'flow-confirm');
      expect(find.text('راجع اشتراكك'), findsNothing);
      expect(requests, hasLength(1));
      expect([requests.single.type, requests.single.periodCode, requests.single.price], ['daily', null, 60]);
    });

    testWidgets('its back button returns to the periods with nothing chosen', (tester) async {
      await open(tester, () => oneLine(daily: 60));
      await pick(tester, 'l1', 'l1-s2');
      await tap(tester, 'option-daily');
      await tap(tester, 'flow-back');
      expect(find.byType(PeriodTile), findsNWidgets(3));
      expect(find.byKey(const Key('flow-review')), findsNothing);
      expect(find.byKey(const Key('option-daily')), findsOneWidget);
    });

    testWidgets('not offered to a student who already holds a subscription', (tester) async {
      await open(tester, () => oneLine(daily: 60), allowDaily: false);
      expect(find.text('يومي متاح'), findsNothing);
      await pick(tester, 'l1', 'l1-s2');
      expect(find.byKey(const Key('option-daily')), findsNothing);
    });
  });

  group('the review sheet', () {
    testWidgets('states the route, the period, how long it is valid, the amount once and what cannot be undone',
        (tester) async {
      await open(tester, oneLine);
      await pick(tester, 'l1', 'l1-s2');
      await tap(tester, 'option-first');
      await tap(tester, 'flow-review');
      expect(find.text('راجع اشتراكك'), findsOneWidget);
      expect(find.text('كوبري السرو'), findsOneWidget);
      expect(find.text('محطة الصعود'), findsOneWidget);
      expect(find.text('المنصورة الجديدة'), findsOneWidget);
      expect(find.text('خط الزرقا · النورس للنقل'), findsOneWidget);
      expect(find.text('صالح حتى'), findsOneWidget);
      expect(find.text('14 يناير 2027'), findsOneWidget);
      expect(find.text('4,500 ج.م'), findsOneWidget);
      expect(find.byKey(const Key('review-amount')), findsOneWidget);
      expect(find.text('بعد التأكيد لا يمكن تغيير الخط أو المحطة.'), findsOneWidget);
      expect(find.text('تأكيد والانتقال للدفع'), findsOneWidget);
      expect(find.text('رجوع للتعديل'), findsOneWidget);
      expect(requests, isEmpty);

      await tap(tester, 'flow-confirm');
      expect(requests, hasLength(1));
      expect([requests.single.lineId, requests.single.stationId, requests.single.periodCode, requests.single.price],
          ['l1', 'l1-s2', 'first', 4500]);
      expect(find.text('راجع اشتراكك'), findsNothing);
    });

    testWidgets('a refused request closes the sheet, says why and reads the offer again', (tester) async {
      await open(tester, oneLine);
      await pick(tester, 'l1', 'l1-s2');
      await tap(tester, 'option-first');
      await tap(tester, 'flow-review');
      failWith = Exception('الفترة لم تعد متاحة');
      final before = reads;
      await tester.tap(find.byKey(const Key('flow-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('راجع اشتراكك'), findsNothing);
      expect(find.byType(BasakToastBody), findsOneWidget);
      expect(reads, before + 1);
      expect(requests, isEmpty);
      // The choices are still there to try again.
      expect(find.text('الزرقا · كوبري السرو'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });

  group('nothing on sale', () {
    testWidgets('an empty catalogue: says so for the university, and reads again on demand', (tester) async {
      await open(tester, () => catalogOf([]));
      expect(find.text('اشتراك جديد'), findsOneWidget);
      expect(find.text('لا توجد خطوط لجامعتك بعد'), findsOneWidget);
      expect(
          find.text('لا توجد حالياً شركات أو خطوط متاحة لجامعة المنصورة الجديدة. تظهر هنا فور إضافتها.'), findsOneWidget);
      expect(find.byType(BuilderRow), findsNothing);
      expect(find.byKey(const Key('flow-back')), findsNothing, reason: 'nowhere to go back to');
      final before = reads;
      await tester.tap(find.text('تحديث'));
      await tester.pumpAndSettle();
      expect(reads, before + 1);
    });
  });

  group('as a page of its own', () {
    for (final (size, scale) in const [(Size(390, 844), 1.0), (Size(360, 640), 1.0), (Size(360, 640), 1.3)]) {
      testWidgets('nothing overflows at ${size.width.toInt()} × ${size.height.toInt()}, text ×$scale', (tester) async {
        await open(tester, twoCompanies, page: true, size: size, textScale: scale);
        expect(tester.takeException(), isNull);
        // The round button at the top leaves; the tab bar is not there.
        expect(find.byKey(const Key('flow-back')), findsOneWidget);
        await tap(tester, 'company-c1');
        expect(tester.takeException(), isNull);
        await tap(tester, 'line-l1');
        expect(tester.takeException(), isNull);
        await tapRevealed(tester, 'station-l1-s2');
        await tap(tester, 'station-confirm');
        expect(tester.takeException(), isNull);
        await tapRevealed(tester, 'option-both');
        expect(tester.takeException(), isNull);
        // The one primary button sits in the dock, under the scrolling content.
        expect(find.descendant(of: find.byType(BasakDock), matching: find.byKey(const Key('flow-review'))),
            findsOneWidget);
        await tap(tester, 'flow-review');
        expect(tester.takeException(), isNull);
        await tap(tester, 'review-back');
        await tapRevealed(tester, 'option-daily');
        expect(tester.takeException(), isNull);
        expect(find.descendant(of: find.byType(BasakDock), matching: find.byKey(const Key('flow-confirm'))),
            findsOneWidget);
      });
    }

    testWidgets('the system back button steps back through the builder, then leaves', (tester) async {
      await open(tester, twoCompanies, page: true, size: const Size(390, 1400));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      // Something under the page to return to.
      navigator.push(MaterialPageRoute<void>(builder: (_) => const PurchaseFlowPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('company-c1')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('line-l1')));
      await tester.pumpAndSettle();
      await tap(tester, 'station-l1-s1');
      await tap(tester, 'station-confirm');
      await tap(tester, 'option-daily');
      expect(find.text('تأكيد اشتراك اليوم'), findsOneWidget);

      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.byType(PeriodTile), findsNWidgets(3), reason: 'from the cash day to the periods');
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('line-l1')), findsOneWidget, reason: 'from the periods to the lines');
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('company-c2')), findsOneWidget, reason: 'from the lines to the companies');
      expect(find.byType(PurchaseFlow), findsOneWidget);
      await navigator.maybePop();
      await tester.pumpAndSettle();
      // The page on top is gone; the one under it shows its first step.
      expect(find.byType(PurchaseFlowPage), findsOneWidget);
      expect(find.byKey(const Key('flow-row-line')), findsNothing);
    });

    testWidgets('hosted as a tab: no way out, and the button follows the content above the tab bar',
        (tester) async {
      await open(tester, oneLine, tab: true, size: const Size(390, 844));
      expect(find.byKey(const Key('flow-back')), findsNothing);
      await pick(tester, 'l1', 'l1-s2');
      await tap(tester, 'option-first');
      expect(find.byType(BasakDock), findsNothing);
      await tapRevealed(tester, 'flow-review');
      expect(find.text('راجع اشتراكك'), findsOneWidget);
      await tap(tester, 'review-back');
      // Scrolled to its end, the button clears the floating tab bar.
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(find.byKey(const Key('flow-review'))).dy,
          lessThanOrEqualTo(844 - BasakPage.tabBarClearance));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the close button leaves at once, whatever was chosen', (tester) async {
      var cancelled = 0;
      await open(tester, oneLine, onCancel: () => cancelled++);
      await pick(tester, 'l1', 'l1-s2');
      await tap(tester, 'flow-back');
      expect(cancelled, 1);
    });
  });
}
