import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/features/student/subscription/models/payment_method_model.dart';
import 'package:basak_mobile/features/student/subscription/models/sale_catalog.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_draft.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';
import 'package:basak_mobile/features/student/subscription/presentation/purchase_flow.dart';
import 'package:basak_mobile/features/student/subscription/presentation/receipt_card.dart';
import 'package:basak_mobile/features/student/subscription/presentation/subscription_screen.dart';

/// What get_subscription_catalog() returns for a student of جامعة الدلتا.
SaleCatalog catalog({bool withSecond = true}) => SaleCatalog.fromJson(jsonDecode(jsonEncode({
      'university': {'id': 'u1', 'name': 'جامعة الدلتا'},
      'companies': [
        {
          'id': 'c1',
          'name': 'المستقبل',
          'lines': [
            {
              'id': 'l1', 'name': 'منية النصر', 'origin_name': 'منية النصر', 'university': 'جامعة الدلتا',
              'first_departure': '06:30:00', 'last_return': '17:30:00',
              'stations': [
                {
                  'id': 's1', 'name': 'ميت تمامة',
                  'departures': [
                    {'trip_id': 't1', 'time': '07:00:00', 'label': ''},
                    {'trip_id': 't2', 'time': '09:00:00', 'label': ''},
                  ],
                },
                {
                  'id': 's2', 'name': 'البجلات',
                  'departures': [
                    {'trip_id': 't1', 'time': '07:10:00', 'label': ''},
                  ],
                },
              ],
              'returns': [
                {'trip_id': 'r1', 'time': '15:00:00', 'label': ''},
                {'trip_id': 'r2', 'time': '17:30:00', 'label': ''},
              ],
              'options': [
                {'option': 'first', 'academic_year': 2026, 'name': 'الفصل الدراسي الأول', 'label': 'الفصل الدراسي الأول 2026/2027',
                 'type': 'termly', 'start_date': '2026-09-05', 'end_date': '2027-01-30', 'phase': 'current', 'price': 8000},
                {'option': 'both', 'academic_year': 2026, 'name': 'الفصلان معاً', 'label': 'الفصلان معاً 2026/2027',
                 'type': 'yearly', 'start_date': '2026-09-05', 'end_date': '2027-06-30', 'phase': 'current', 'price': 15000},
                if (withSecond)
                  {'option': 'second', 'academic_year': 2026, 'name': 'الفصل الدراسي الثاني', 'label': 'الفصل الدراسي الثاني 2026/2027',
                   'type': 'termly', 'start_date': '2027-02-01', 'end_date': '2027-06-30', 'phase': 'upcoming', 'price': 8500},
              ],
              'daily': {'enabled': true, 'price': 50},
            },
            {
              'id': 'l2', 'name': 'دكرنس', 'origin_name': 'دكرنس', 'university': 'جامعة الدلتا',
              'first_departure': '07:00:00', 'last_return': null,
              'stations': [
                {'id': 's9', 'name': 'دكرنس', 'departures': [{'trip_id': 't9', 'time': '07:05:00', 'label': ''}]},
              ],
              'options': [
                {'option': 'first', 'academic_year': 2026, 'name': 'الفصل الدراسي الأول', 'label': 'الفصل الدراسي الأول 2026/2027',
                 'type': 'termly', 'start_date': '2026-09-05', 'end_date': '2027-01-30', 'phase': 'current', 'price': 6000},
              ],
              'daily': {'enabled': false, 'price': 40},
            },
          ],
        },
      ],
    })) as Map<String, dynamic>);

SubscriptionModel subscription(String status, {String type = 'termly', String code = 'first'}) =>
    SubscriptionModel.fromJson({
      'id': 'sub1', 'student_id': 'me', 'line_id': 'l1', 'company_id': 'c1', 'station_id': 's2', 'type': type,
      'status': status, 'price': 8000, 'created_at': '2026-10-08',
      'start_date': '2026-09-05', 'end_date': '2027-01-30', 'period_code': type == 'daily' ? null : code,
      'academic_year': 2026, 'period_label': 'الفصل الدراسي الأول 2026/2027', 'period_phase': 'current',
      'lines': {'name': 'منية النصر', 'companies': {'name': 'المستقبل'}},
      'stations': {'name': 'البجلات'},
      'student': {'university': 'جامعة الدلتا'},
    });

const receipt = SubscriptionReceipt(
  subscriptionId: 'sub1', number: 7, companyName: 'المستقبل', studentName: 'طالب تجريبي محلي',
  studentPhone: '01055512301', universityName: 'جامعة الدلتا', lineName: 'منية النصر', stationName: 'البجلات',
  periodLabel: 'الفصل الدراسي الأول 2026/2027', startDate: '2026-09-05', endDate: '2027-01-30',
  amount: 8000, paymentMethod: 'InstaPay', approvedAt: '2026-10-08T10:00:00Z',
);

void main() {
  group('the selection draft', () {
    final c = catalog();

    test('each choice opens the next step, in order', () {
      var d = const SubscriptionDraft();
      expect(d.firstOpenStep, DraftStep.company);
      d = d.pickCompany(c, 'c1');
      expect(d.firstOpenStep, DraftStep.line);
      d = d.pickLine(c, 'l1');
      expect(d.firstOpenStep, DraftStep.station);
      d = d.pickStation('s2');
      expect(d.firstOpenStep, DraftStep.period);
      d = d.pickOption('second:2026');
      expect(d.firstOpenStep, DraftStep.review);
      expect(d.canOpen(DraftStep.company), isTrue);
    });

    test('changing the line clears only what the new line does not have', () {
      final d = const SubscriptionDraft().pickCompany(c, 'c1').pickLine(c, 'l1').pickStation('s2').pickOption('first:2026');
      final other = d.pickLine(c, 'l2');
      expect(other.lineId, 'l2');
      expect(other.stationId, isNull, reason: 'البجلات is not on the new line');
      expect(other.optionKey, 'first:2026', reason: 'the new line sells the first semester too');
      final both = d.pickOption('both:2026').pickLine(c, 'l2');
      expect(both.optionKey, isNull, reason: 'the new line does not sell both');
      // Picking the same line again keeps everything.
      expect(d.pickLine(c, 'l1'), d);
    });

    test('a choice that is no longer on sale is dropped when the catalog refreshes', () {
      final d = const SubscriptionDraft(companyId: 'c1', lineId: 'l1', stationId: 's1', optionKey: 'second:2026');
      final after = d.reconciled(catalog(withSecond: false));
      expect(after.optionKey, isNull);
      expect(after.stationId, 's1');
      expect(after.firstOpenStep, DraftStep.period);
    });

    test('the request carries the chosen option and its own price', () {
      final d = const SubscriptionDraft(companyId: 'c1', lineId: 'l1', stationId: 's1', optionKey: 'second:2026');
      final r = SubscriptionRequest.from(d, c)!;
      expect([r.type, r.periodCode, r.academicYear, r.price], ['termly', 'second', 2026, 8500]);
      // The earliest departure at that station, and the earliest return from the university.
      expect([r.departureTripId, r.departureTime, r.returnTripId, r.returnTime], ['t1', '07:00:00', 'r1', '15:00:00']);
      // The return does not depend on the station.
      final other = SubscriptionRequest.from(d.pickStation('s2'), c)!;
      expect([other.departureTime, other.returnTripId, other.returnTime], ['07:10:00', 'r1', '15:00:00']);
      final both = SubscriptionRequest.from(d.pickOption('both:2026'), c)!;
      expect([both.type, both.periodCode, both.price], ['yearly', 'both', 15000]);
      final daily = SubscriptionRequest.from(d.pickOption(SubscriptionDraft.dailyKey), c)!;
      expect([daily.type, daily.periodCode, daily.price], ['daily', null, 50]);
      expect(SubscriptionRequest.from(const SubscriptionDraft(companyId: 'c1', lineId: 'l1'), c), isNull);
    });
  });

  group('titles', () {
    test('the boarding station is the headline; the university and the line are rows under it', () {
      expect(subscription('active').boardingTitle, 'البجلات');
      expect(subscription('active').destination, 'جامعة الدلتا');
      expect(subscription('active').periodName, 'الفصل الأول');
      expect(subscription('active', type: 'yearly', code: 'both').periodName, 'الفصلان معاً');
      // The older spelling still reads correctly.
      expect(subscription('active', type: 'yearly', code: 'annual').periodName, 'الفصلان معاً');
    });
  });

  group('choosing a subscription', () {
    late List<SubscriptionRequest> created;

    Future<void> open(WidgetTester tester, {SubscriptionDraft initial = const SubscriptionDraft(), bool allowDaily = true}) async {
      created = [];
      tester.view.physicalSize = const Size(1170, 2800);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          saleCatalogProvider.overrideWith((ref) async => catalog()),
          subscriptionCreatorProvider.overrideWithValue((request) async {
            created.add(request);
            return subscription('pending_payment');
          }),
        ],
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: PurchaseFlow(initial: initial, allowDaily: allowDaily, onCreated: (_) {}),
              ),
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

    testWidgets('five steps, forward and back, changing choices: nothing is written until confirm', (tester) async {
      await open(tester);
      expect(find.text('الخطوة 1 من 5'), findsOneWidget);
      await tap(tester, 'company-c1');

      // Line card: name, own university, stations, range of times, lowest price. Nothing repeated.
      expect(find.text('منية النصر'), findsOneWidget);
      expect(find.text('إلى جامعة الدلتا'), findsNWidgets(2));
      expect(find.text('من 8,000 ج.م'), findsOneWidget);
      expect(find.text('أول ذهاب 6:30 ص'), findsOneWidget);
      expect(find.text('آخر عودة 5:30 م'), findsOneWidget);
      expect(find.textContaining('يخدم'), findsNothing);
      await tap(tester, 'line-l1');

      // Station: under each name, one time per trip that stops there.
      expect(find.text('7:00 ص · 9:00 ص'), findsOneWidget);
      expect(find.text('7:10 ص'), findsOneWidget);
      await tap(tester, 'station-s2');

      // Period: exactly what is on sale, in a fixed order, each with its price, and no dates.
      expect(find.text('الخطوة 4 من 5'), findsOneWidget);
      expect(find.text('الفصل الأول'), findsOneWidget);
      expect(find.text('الفصل الثاني'), findsOneWidget);
      expect(find.text('الفصلان معاً'), findsOneWidget);
      expect(find.text('الفصل الصيفي'), findsNothing);
      expect(tester.getCenter(find.text('الفصل الأول')).dx, greaterThan(tester.getCenter(find.text('الفصل الثاني')).dx));
      expect(tester.getCenter(find.text('الفصل الثاني')).dx, greaterThan(tester.getCenter(find.text('الفصلان معاً')).dx));
      expect(find.text('8,500 ج.م'), findsOneWidget);
      expect(find.text('وفّر 1,500 ج.م'), findsOneWidget);
      expect(find.textContaining('2026'), findsNothing);
      expect(find.textContaining('2027'), findsNothing);
      await tap(tester, 'option-second');

      // Review: every choice, the amount once.
      expect(find.text('8,500 ج.م'), findsOneWidget);
      expect(find.text('البجلات'), findsOneWidget);
      expect(find.text('المستقبل'), findsOneWidget);
      // Going back is said in words: one step, and which one.
      expect(find.text('الخطوة السابقة: الفترة'), findsOneWidget);

      // Back to the station, change it: the period is kept.
      await tap(tester, 'review-edit-station');
      await tap(tester, 'station-s1');
      await tap(tester, 'flow-step-review');
      expect(find.text('ميت تمامة'), findsOneWidget);
      expect(find.text('8,500 ج.م'), findsOneWidget);

      // Back step by step to the line, pick another line: its station is asked again.
      await tap(tester, 'flow-back');
      await tap(tester, 'flow-back');
      await tap(tester, 'flow-back');
      await tap(tester, 'line-l2');
      expect(find.text('٣. اختر محطة الصعود'), findsOneWidget);
      await tap(tester, 'station-s9');
      await tap(tester, 'option-first');
      expect(find.text('6,000 ج.م'), findsOneWidget);

      // And jump from the progress bar to change the line and the period.
      await tap(tester, 'flow-step-line');
      await tap(tester, 'line-l1');
      await tap(tester, 'station-s2');
      await tap(tester, 'flow-step-period');
      await tap(tester, 'option-both');
      expect(find.text('15,000 ج.م'), findsOneWidget);

      expect(created, isEmpty, reason: 'moving between the steps must not create or change anything');

      await tap(tester, 'flow-confirm');
      expect(created, hasLength(1));
      expect([created.single.lineId, created.single.stationId, created.single.periodCode, created.single.price],
          ['l1', 's2', 'both', 15000]);
    });

    testWidgets('the next period opens on the review with company, line and station filled in', (tester) async {
      await open(tester,
          initial: const SubscriptionDraft(companyId: 'c1', lineId: 'l1', stationId: 's2', optionKey: 'second:2026'),
          allowDaily: false);
      expect(find.text('٥. راجع اختياراتك'), findsOneWidget);
      expect(find.text('8,500 ج.م'), findsOneWidget);
      // A student who already holds a subscription is not offered a cash day ride.
      await tap(tester, 'review-edit-period');
      expect(find.byKey(const Key('option-daily')), findsNothing);
      expect(created, isEmpty);
    });
  });

  group('the subscriptions page', () {
    Future<void> open(WidgetTester tester, List<SubscriptionModel> subs, {Map<String, SubscriptionReceipt> docs = const {}}) async {
      tester.view.physicalSize = const Size(1170, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          allSubscriptionsProvider.overrideWith((ref) async => subs),
          saleCatalogProvider.overrideWith((ref) async => catalog()),
          subscriptionReceiptsProvider.overrideWith((ref, id) async => <ReceiptModel>[]),
          subscriptionReceiptDocProvider.overrideWith((ref, id) async => docs[id]),
          paymentMethodsProvider.overrideWith((ref, id) async => [
                PaymentMethodModel.fromJson({
                  'id': 'm1', 'company_id': 'c1', 'method_type': 'instapay', 'display_name': 'InstaPay',
                  'instapay_address': 'almostaqbal@instapay', 'instructions': 'اكتب اسم الطالب في الملاحظات.',
                  'is_active': true, 'sort_order': 0,
                }),
              ]),
        ],
        child: const MaterialApp(
          home: Directionality(textDirection: TextDirection.rtl, child: SubscriptionScreen()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> toggle(WidgetTester tester, String id) async {
      await tester.tap(find.byKey(Key('sub-toggle-$id')));
      await tester.pumpAndSettle();
    }

    testWidgets('waiting for payment: the card is open, the amount once, one block of notes, no change of selection', (tester) async {
      await open(tester, [subscription('pending_payment')]);
      expect(find.text('بانتظار الدفع'), findsOneWidget);
      expect(find.text('الفصل الأول'), findsOneWidget);
      expect(find.text('البجلات'), findsOneWidget);
      expect(find.text('منية النصر'), findsOneWidget);
      expect(find.text('المبلغ المطلوب'), findsOneWidget);
      expect(find.text('8,000 ج.م'), findsOneWidget);
      // It needs the student, so it is already open.
      expect(find.byKey(const Key('payment-notes')), findsOneWidget);
      expect(find.textContaining('صورة واضحة'), findsOneWidget);
      expect(find.byKey(const Key('next-period')), findsNothing);
      await tester.tap(find.text('InstaPay').first);
      await tester.pumpAndSettle();
      expect(find.text('اكتب اسم الطالب في الملاحظات.'), findsOneWidget);
      expect(find.text('almostaqbal@instapay'), findsOneWidget);
      expect(find.text('8,000 ج.م'), findsOneWidget);
      // The selection is fixed once the request exists.
      expect(find.byKey(const Key('flow-back')), findsNothing);
      expect(find.textContaining('تعديل'), findsNothing);
      expect(find.textContaining('تغيير'), findsNothing);
      // The student may fold it away.
      await toggle(tester, 'sub1');
      expect(find.byKey(const Key('payment-notes')), findsNothing);
      expect(find.text('بانتظار الدفع'), findsOneWidget);
    });

    testWidgets('rejected: says so, and offers re-upload for the same subscription', (tester) async {
      await open(tester, [subscription('rejected')]);
      expect(find.text('تم الرفض'), findsOneWidget);
      expect(find.text('تم رفض الإيصال'), findsOneWidget);
      expect(find.text('إيصال التحويل'), findsOneWidget);
      expect(find.textContaining('تغيير'), findsNothing);
    });

    testWidgets('under review: compact, with no payment form', (tester) async {
      await open(tester, [subscription('pending_review')]);
      expect(find.text('بانتظار المراجعة'), findsOneWidget);
      expect(find.text('المبلغ المطلوب'), findsNothing);
      expect(find.byKey(const Key('payment-methods')), findsNothing);
      expect(find.byKey(const Key('payment-notes')), findsNothing);
      await toggle(tester, 'sub1');
      expect(find.text('استلمنا إيصالك'), findsOneWidget);
      expect(find.byKey(const Key('payment-methods')), findsNothing);
    });

    testWidgets('active: a compact card; the details and the receipt open in place', (tester) async {
      await open(tester, [subscription('active')], docs: {'sub1': receipt});
      expect(find.text('الاشتراك الحالي'), findsOneWidget);
      expect(find.text('الاشتراك مفعّل'), findsOneWidget);
      expect(find.text('المبلغ المدفوع'), findsOneWidget);
      expect(find.text('المبلغ المطلوب'), findsNothing);
      expect(find.text('30 يناير 2027'), findsOneWidget);
      // Collapsed: no receipt, no payment form, ever.
      expect(find.byKey(const Key('receipt-pdf-sub1')), findsNothing);
      expect(find.text('00007'), findsNothing);
      expect(find.byKey(const Key('payment-methods')), findsNothing);
      expect(find.text('إيصال التحويل'), findsNothing);

      await toggle(tester, 'sub1');
      expect(find.text('إخفاء التفاصيل'), findsOneWidget);
      expect(find.text('00007'), findsOneWidget);
      expect(find.text('طالب تجريبي محلي'), findsOneWidget);
      expect(find.text('InstaPay'), findsOneWidget);
      expect(find.text('من 5 سبتمبر 2026 إلى 30 يناير 2027'), findsOneWidget);
      expect(find.byKey(const Key('receipt-pdf-sub1')), findsOneWidget);
      expect(find.byKey(const Key('receipt-image-sub1')), findsOneWidget);
      expect(find.byKey(const Key('payment-methods')), findsNothing);

      await toggle(tester, 'sub1');
      expect(find.text('00007'), findsNothing);
      // The next period, when the company sells it in advance, with its own price.
      expect(find.text('الفصل الثاني · 8,500 ج.م'), findsOneWidget);
    });

    testWidgets('several subscriptions over time: the current one first, each older one its own card', (tester) async {
      SubscriptionModel sub(String id, String status, String code, String phase, String start, String end) =>
          SubscriptionModel.fromJson({
            'id': id, 'student_id': 'me', 'line_id': 'l1', 'company_id': 'c1', 'station_id': 's2', 'type': 'termly',
            'status': status, 'price': 8000, 'created_at': start, 'start_date': start, 'end_date': end,
            'period_code': code, 'academic_year': 2026, 'period_phase': phase,
            'lines': {'name': 'منية النصر', 'companies': {'name': 'المستقبل'}}, 'stations': {'name': 'البجلات'},
            'student': {'university': 'جامعة الدلتا'},
          });
      await open(tester, [
        sub('old1', 'expired', 'first', 'expired', '2025-09-05', '2026-01-30'),
        sub('now', 'active', 'second', 'current', '2027-02-01', '2027-06-30'),
        sub('old2', 'expired', 'summer', 'expired', '2026-07-01', '2026-09-01'),
      ], docs: {
        'old1': const SubscriptionReceipt(subscriptionId: 'old1', number: 3, companyName: 'المستقبل', studentName: 'طالب',
            lineName: 'خط قديم', periodLabel: 'الفصل الدراسي الأول 2025/2026', amount: 7000, approvedAt: '2025-09-01T10:00:00Z'),
      });
      expect(find.text('الاشتراك الحالي'), findsOneWidget);
      expect(find.text('اشتراكات سابقة'), findsOneWidget);
      expect(find.text('الاشتراك مفعّل'), findsOneWidget);
      expect(find.text('انتهى الاشتراك'), findsNWidgets(2));
      // Current first, then the past, newest first.
      double y(String id) => tester.getTopLeft(find.byKey(Key('sub-card-$id'))).dy;
      expect(y('now'), lessThan(y('old2')));
      expect(y('old2'), lessThan(y('old1')));
      // All compact; an old one opens to its own receipt, as it was issued.
      expect(find.text('إخفاء التفاصيل'), findsNothing);
      await toggle(tester, 'old1');
      expect(find.text('00003'), findsOneWidget);
      expect(find.text('خط قديم'), findsOneWidget);
      expect(find.byKey(const Key('receipt-pdf-old1')), findsOneWidget);
      expect(find.byKey(const Key('receipt-pdf-now')), findsNothing);
    });

    testWidgets('only past subscriptions: they stay, and a new one starts from a button', (tester) async {
      await open(tester, [subscription('expired')]);
      expect(find.text('لا يوجد اشتراك حالي'), findsOneWidget);
      expect(find.text('اشتراك سابق'), findsOneWidget);
      expect(find.text('انتهى الاشتراك'), findsOneWidget);
      await tester.tap(find.byKey(const Key('subscribe-again')));
      await tester.pumpAndSettle();
      expect(find.text('الخطوة 1 من 5'), findsOneWidget);
    });
  });

  testWidgets('the receipt card can be shared as an image', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RepaintBoundary(key: key, child: const ReceiptCard(receipt: receipt)),
        ),
      ),
    ));
    expect(find.text('المستقبل'), findsOneWidget);
    expect(find.text('طالب تجريبي محلي'), findsOneWidget);
    final png = await tester.runAsync(() => ReceiptExport.png(key));
    expect(png!.sublist(1, 4), 'PNG'.codeUnits);
    expect(ReceiptExport.fileName(receipt, 'png'), 'basak-receipt-00007.png');
  });
}
