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
  subscriptionId: 'sub1', code: '26-7F3A9C2E', companyName: 'المستقبل', studentName: 'طالب تجريبي محلي',
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
      // The line reads with the student's own university, whatever the admin typed.
      expect(subscription('active').lineLabel, 'منية النصر ← الدلتا');
      expect(SubscriptionModel.routeLabel('الزرقا', 'جامعة المنصورة الجديدة'), 'الزرقا ← المنصورة الجديدة');
      expect(SubscriptionModel.routeLabel('الزرقا', null), 'الزرقا');
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

    /// "تغيير" on a chosen row of the builder.
    Future<void> change(WidgetTester tester, String row) async {
      await tester.tap(find.descendant(of: find.byKey(Key('flow-row-$row')), matching: find.text('تغيير')));
      await tester.pumpAndSettle();
    }

    testWidgets('one builder, forward and back, changing choices: nothing is written until confirm', (tester) async {
      await open(tester);
      // One screen: its title, and the university as context, not a step.
      expect(find.text('اشتراك جديد'), findsOneWidget);
      expect(find.text('إلى جامعة الدلتا'), findsOneWidget);
      expect(find.textContaining('الخطوة'), findsNothing);
      // The only company starts chosen and collapsed, with nothing to change to.
      expect(find.byKey(const Key('company-c1')), findsNothing);
      expect(find.text('المستقبل'), findsOneWidget);
      expect(find.text('تغيير'), findsNothing);

      // Line card: name, stop count, lowest price, first departure and last return. Nothing repeated.
      expect(find.text('منية النصر'), findsOneWidget);
      expect(find.text('محطتان'), findsOneWidget);
      // (The currency is tied to its number by a no-break space.)
      expect(find.text('من 8,000 ج.م'), findsOneWidget);
      expect(find.text('6:30 ص'), findsOneWidget);
      expect(find.text('5:30 م'), findsOneWidget);
      expect(find.text('يومي متاح'), findsOneWidget);
      expect(find.textContaining('يخدم'), findsNothing);

      // Line and station are one gesture: the line card opens the station sheet.
      await tap(tester, 'line-l1');
      expect(find.text('من أين تركب؟'), findsOneWidget);
      expect(find.text('خط منية النصر · محطتان · رحلتان صباحاً'), findsOneWidget);
      // A closed stop shows only its first pass time; two stops need no search.
      expect(find.text('من 7:00 ص'), findsOneWidget);
      expect(find.text('من 7:10 ص'), findsOneWidget);
      expect(find.byKey(const Key('station-search')), findsNothing);
      // The selected stop opens in place to every pass time.
      await tap(tester, 'station-s1');
      expect(find.text('7:00 · 9:00 ص'), findsOneWidget);
      expect(find.text('من 7:00 ص'), findsNothing);
      await tap(tester, 'station-s2');
      expect(find.text('من 7:00 ص'), findsOneWidget);
      expect(find.text('اختيار البجلات'), findsOneWidget);
      await tap(tester, 'station-confirm');
      // Both collapse into one row.
      expect(find.text('من أين تركب؟'), findsNothing);
      expect(find.text('منية النصر · البجلات'), findsOneWidget);

      // Period: exactly what is on sale, in a fixed order, each with its price. No date before a choice.
      expect(find.text('الفصل الأول'), findsOneWidget);
      expect(find.text('الفصل الثاني'), findsOneWidget);
      expect(find.text('الفصلان معاً'), findsOneWidget);
      expect(find.text('الفصل الصيفي'), findsNothing);
      expect(tester.getCenter(find.text('الفصل الأول')).dx, greaterThan(tester.getCenter(find.text('الفصل الثاني')).dx));
      expect(tester.getCenter(find.text('الفصل الثاني')).dx, greaterThan(tester.getCenter(find.text('الفصلان معاً')).dx));
      expect(find.text('8,500'), findsOneWidget);
      expect(find.text('وفّر 1,500'), findsOneWidget);
      expect(find.text('الفترة القادمة'), findsOneWidget);
      expect(find.textContaining('2026'), findsNothing);
      expect(find.textContaining('2027'), findsNothing);
      // The review is offered only once a period is chosen.
      expect(find.byKey(const Key('flow-review')), findsNothing);
      await tap(tester, 'option-second');
      // One caption line with the dates of the chosen tile.
      expect(find.text('من 1 فبراير إلى 30 يونيو 2027'), findsOneWidget);

      // Review is a sheet: every choice, the amount once.
      await tap(tester, 'flow-review');
      expect(find.text('راجع اشتراكك'), findsOneWidget);
      expect(find.text('8,500 ج.م'), findsOneWidget);
      expect(find.text('البجلات'), findsOneWidget);
      expect(find.text('خط منية النصر · المستقبل'), findsOneWidget);
      expect(find.text('30 يونيو 2027'), findsOneWidget);
      expect(find.text('بعد التأكيد لا يمكن تغيير الخط أو المحطة.'), findsOneWidget);
      // Going back is said in words.
      await tester.tap(find.text('رجوع للتعديل'));
      await tester.pumpAndSettle();
      expect(find.text('راجع اشتراكك'), findsNothing);

      // "تغيير" on the line row, another station: the period is kept.
      await change(tester, 'line');
      await tap(tester, 'line-l1');
      expect(find.text('اختيار البجلات'), findsOneWidget, reason: 'the sheet opens on the stop already chosen');
      await tap(tester, 'station-s1');
      await tap(tester, 'station-confirm');
      expect(find.text('منية النصر · ميت تمامة'), findsOneWidget);
      expect(find.text('من 1 فبراير إلى 30 يونيو 2027'), findsOneWidget);
      await tap(tester, 'flow-review');
      expect(find.text('ميت تمامة'), findsOneWidget);
      expect(find.text('8,500 ج.م'), findsOneWidget);
      await tap(tester, 'review-back');

      // Another line: its station is asked again, and its one period is already chosen.
      await change(tester, 'line');
      await tap(tester, 'line-l2');
      expect(find.text('اختيار دكرنس'), findsOneWidget, reason: 'a line with one stop leaves nothing to choose');
      await tap(tester, 'station-confirm');
      expect(find.text('دكرنس · دكرنس'), findsOneWidget);
      expect(find.text('6,000'), findsOneWidget);
      expect(find.text('الفصل الثاني'), findsNothing);
      expect(find.byKey(const Key('option-daily')), findsNothing);
      await tap(tester, 'flow-review');
      expect(find.text('6,000 ج.م'), findsOneWidget);
      await tap(tester, 'review-back');

      // And back to the first line, with another period.
      await change(tester, 'line');
      await tap(tester, 'line-l1');
      await tap(tester, 'station-s2');
      await tap(tester, 'station-confirm');
      await tap(tester, 'option-both');
      await tap(tester, 'flow-review');
      expect(find.text('15,000 ج.م'), findsOneWidget);

      expect(created, isEmpty, reason: 'moving between the steps must not create or change anything');

      await tap(tester, 'flow-confirm');
      expect(created, hasLength(1));
      expect([created.single.lineId, created.single.stationId, created.single.periodCode, created.single.price],
          ['l1', 's2', 'both', 15000]);
      expect(find.text('راجع اشتراكك'), findsNothing, reason: 'the sheet closes with the answer');
    });

    testWidgets('the next period opens on the review with company, line and station filled in', (tester) async {
      await open(tester,
          initial: const SubscriptionDraft(companyId: 'c1', lineId: 'l1', stationId: 's2', optionKey: 'second:2026'),
          allowDaily: false);
      expect(find.text('راجع اشتراكك'), findsOneWidget);
      expect(find.text('8,500 ج.م'), findsOneWidget);
      expect(find.text('منية النصر · البجلات'), findsOneWidget);
      // A student who already holds a subscription is not offered a cash day ride.
      await tap(tester, 'review-back');
      expect(find.byKey(const Key('option-second')), findsOneWidget);
      expect(find.byKey(const Key('option-daily')), findsNothing);
      expect(find.text('يومي متاح'), findsNothing);
      expect(created, isEmpty);
    });
  });

  group('the subscriptions page', () {
    Future<void> open(WidgetTester tester, List<SubscriptionModel> subs,
        {Map<String, SubscriptionReceipt> docs = const {}, List<ReceiptModel> receipts = const []}) async {
      tester.view.physicalSize = const Size(1170, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          allSubscriptionsProvider.overrideWith((ref) async => subs),
          saleCatalogProvider.overrideWith((ref) async => catalog()),
          subscriptionReceiptsProvider.overrideWith((ref, id) async => receipts),
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
          home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: SubscriptionScreen())),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('waiting for payment: one card, the amount once, paying on its own page, no change of selection',
        (tester) async {
      await open(tester, [subscription('pending_payment')]);
      expect(find.text('بانتظار الدفع'), findsOneWidget);
      expect(find.text('الفصل الأول'), findsOneWidget);
      expect(find.text('منية النصر · البجلات'), findsOneWidget);
      expect(find.text('المستقبل'), findsOneWidget);
      expect(find.text('المبلغ المطلوب'), findsOneWidget);
      expect(find.text('8,000 ج.م'), findsOneWidget);
      // The tab states what is due; the transfer details and the upload are a page.
      expect(find.byKey(const Key('payment-notes')), findsNothing);
      expect(find.byKey(const Key('payment-methods')), findsNothing);
      expect(find.byKey(const Key('next-period')), findsNothing);
      await tester.tap(find.text('ادفع الآن'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payment-notes')), findsOneWidget);
      expect(find.textContaining('صورة واضحة'), findsOneWidget);
      // One method: it is shown at once, ready to copy.
      expect(find.text('InstaPay'), findsOneWidget);
      expect(find.text('almostaqbal@instapay'), findsOneWidget);
      // Before transferring: the whole amount at once, then the company's own words.
      expect(find.text('حوّل المبلغ كاملاً في عملية واحدة.'), findsOneWidget);
      expect(find.text('اكتب اسم الطالب في الملاحظات.'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsNothing);
      expect(find.text('8,000 ج.م'), findsOneWidget);
      // The selection is fixed once the request exists.
      expect(find.byKey(const Key('flow-back')), findsNothing);
      expect(find.textContaining('تعديل'), findsNothing);
      expect(find.textContaining('تغيير'), findsNothing);
      // Back on the tab the request is as it was.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payment-notes')), findsNothing);
      expect(find.text('بانتظار الدفع'), findsOneWidget);
    });

    testWidgets('rejected: says so, and offers a new receipt for the same subscription', (tester) async {
      await open(tester, [subscription('rejected')], receipts: [
        ReceiptModel.fromJson({
          'id': 'r1', 'subscription_id': 'sub1', 'image_url': 'me/sub1_a.jpg', 'status': 'rejected',
          'rejection_reason': 'المبلغ غير مطابق', 'attempt_number': 1, 'created_at': '2026-10-08T10:00:00Z',
        }),
      ]);
      expect(find.text('إيصال مرفوض'), findsOneWidget);
      expect(find.text('المبلغ غير مطابق'), findsOneWidget);
      await tester.tap(find.text('إيصال جديد'));
      await tester.pumpAndSettle();
      expect(find.text('الإيصال مرفوض'), findsOneWidget);
      expect(find.text('ارفع إيصالاً جديداً'), findsOneWidget);
      // The method may be changed; the line, station and period may not.
      expect(find.byKey(const Key('flow-back')), findsNothing);
      expect(find.textContaining('تعديل'), findsNothing);
    });

    testWidgets('under review: no payment form', (tester) async {
      await open(tester, [subscription('pending_review')]);
      expect(find.text('قيد المراجعة'), findsOneWidget);
      expect(find.text('المبلغ المطلوب'), findsNothing);
      expect(find.text('المبلغ'), findsOneWidget);
      expect(find.byKey(const Key('payment-methods')), findsNothing);
      expect(find.byKey(const Key('payment-notes')), findsNothing);
      expect(find.text('ادفع الآن'), findsNothing);
    });

    testWidgets('active: the pass and its rows; the receipt opens as its own page', (tester) async {
      await open(tester, [subscription('active')], docs: {'sub1': receipt});
      expect(find.text('نشط'), findsOneWidget);
      // The company is on the tab itself, before the receipt is opened.
      expect(find.text('الشركة'), findsOneWidget);
      expect(find.text('المستقبل'), findsOneWidget);
      expect(find.text('المبلغ المطلوب'), findsNothing);
      expect(find.text('30 يناير 2027'), findsOneWidget);
      // On the tab: the receipt's row, never its content or a payment form.
      expect(find.text('26-7F3A9C2E'), findsOneWidget);
      expect(find.byKey(const Key('receipt-pdf-sub1')), findsNothing);
      expect(find.text('طالب تجريبي محلي'), findsNothing);
      expect(find.byKey(const Key('payment-methods')), findsNothing);
      // The next period, when the company sells it in advance, with its own price.
      expect(find.text('الفصل الثاني متاح الآن'), findsOneWidget);
      expect(find.text('نفس الخط والمحطة · 8,500 ج.م'), findsOneWidget);

      await tester.tap(find.text('الإيصال'));
      await tester.pumpAndSettle();
      expect(find.text('26-7F3A9C2E'), findsOneWidget);
      expect(find.text('8 أكتوبر 2026 · InstaPay'), findsOneWidget);
      expect(find.text('5 سبتمبر – 30 يناير 2027'), findsOneWidget);
      expect(find.byKey(const Key('receipt-pdf-sub1')), findsOneWidget);
      expect(find.byKey(const Key('receipt-image-sub1')), findsOneWidget);
      expect(find.byKey(const Key('payment-methods')), findsNothing);
      await tester.tap(find.text('الطالب'));
      await tester.pumpAndSettle();
      expect(find.text('طالب تجريبي محلي'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receipt-pdf-sub1')), findsNothing);
    });

    testWidgets('several subscriptions over time: the current one first, the older ones as rows', (tester) async {
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
        'old1': const SubscriptionReceipt(subscriptionId: 'old1', code: '25-0B11C4D2', companyName: 'المستقبل', studentName: 'طالب',
            lineName: 'خط قديم', periodLabel: 'الفصل الدراسي الأول 2025/2026', amount: 7000, approvedAt: '2025-09-01T10:00:00Z'),
      });
      expect(find.text('اشتراكات سابقة'), findsOneWidget);
      expect(find.text('نشط'), findsOneWidget);
      expect(find.text('انتهى 1 سبتمبر 2026 · منية النصر'), findsOneWidget);
      expect(find.text('انتهى 30 يناير 2026 · منية النصر'), findsOneWidget);
      // Current first, then the past, newest first.
      double y(String id) => tester.getTopLeft(find.byKey(Key('sub-card-$id'))).dy;
      expect(y('now'), lessThan(y('old2')));
      expect(y('old2'), lessThan(y('old1')));
      // An old one opens its own receipt, as it was issued.
      expect(find.text('25-0B11C4D2'), findsNothing);
      await tester.tap(find.byKey(const Key('sub-card-old1')));
      await tester.pumpAndSettle();
      expect(find.text('25-0B11C4D2'), findsOneWidget);
      expect(find.text('خط قديم'), findsOneWidget);
      expect(find.byKey(const Key('receipt-pdf-old1')), findsOneWidget);
      expect(find.byKey(const Key('receipt-pdf-now')), findsNothing);
    });

    testWidgets('only past subscriptions: they stay, and a new one starts from a button', (tester) async {
      await open(tester, [subscription('expired')]);
      expect(find.text('منتهٍ'), findsOneWidget);
      expect(find.text('انتهى الفصل الأول'), findsOneWidget);
      expect(find.text('اشتراك سابق'), findsOneWidget);
      // The same line and station are offered again; another choice starts the builder empty.
      expect(find.text('جدّد الاشتراك'), findsOneWidget);
      await tester.tap(find.byKey(const Key('subscribe-again')));
      await tester.pumpAndSettle();
      expect(find.byType(PurchaseFlow), findsOneWidget);
      expect(tester.widget<PurchaseFlow>(find.byType(PurchaseFlow)).initial.lineId, isNull);
    });
  });

  testWidgets('the receipt card shows the stored receipt', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SingleChildScrollView(child: ReceiptCard(receipt: receipt))),
      ),
    ));
    expect(find.text('26-7F3A9C2E'), findsOneWidget);
    expect(find.text('8,000 ج.م'), findsOneWidget);
    expect(find.text('منية النصر'), findsOneWidget);
    // The student and the company are groups that open in place.
    await tester.tap(find.text('الطالب'));
    await tester.pumpAndSettle();
    expect(find.text('طالب تجريبي محلي'), findsOneWidget);
    await tester.tap(find.text('الشركة'));
    await tester.pumpAndSettle();
    expect(find.text('المستقبل'), findsOneWidget);
  });
}
