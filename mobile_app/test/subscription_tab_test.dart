// The "اشتراكي" tab in each state of a subscription (boards
// SubscriptionAwaiting, SubscriptionReview, Subscription, SubscriptionExpired,
// StatePartial and the pass states).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';
import 'package:basak_mobile/features/student/subscription/presentation/pay_screen.dart';
import 'package:basak_mobile/features/student/subscription/presentation/purchase_flow.dart';
import 'package:basak_mobile/features/student/subscription/presentation/receipt_screen.dart';
import 'package:basak_mobile/features/student/subscription/presentation/subscription_screen.dart';

import 'support/pay_fixtures.dart';

Future<void> open(WidgetTester tester, List<Override> overrides,
    {Size size = const Size(390, 844), double textScale = 1, bool visible = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SubscriptionScreen(visible: visible)),
      ),
    ),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

SubscriptionModel running() {
  final today = DateTime.now();
  return boardSub('active',
      start: isoDay(today.subtract(const Duration(days: 21))), end: isoDay(today.add(const Duration(days: 95))));
}

List<SubscriptionModel> past(int count) => [
      for (var i = 0; i < count; i++)
        boardSub('expired',
            id: 'old$i', phase: 'expired', year: 2025 - i, start: '${2025 - i}-09-10', end: '${2026 - i}-01-15'),
    ];

void main() {
  tearDown(() => OfflineCache.offlineSince.value = null);

  testWidgets('awaiting payment: one card with the amount once and "ادفع الآن", then the line and the company',
      (tester) async {
    await open(tester, payOverrides(subs: [boardSub('pending_payment')]));
    expect(find.text('اشتراكي'), findsOneWidget);
    expect(find.text('بانتظار الدفع'), findsOneWidget);
    expect(find.text('الفصل الأول'), findsOneWidget);
    expect(find.text('2026 / 2027'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('amount-label'))).data, 'المبلغ المطلوب');
    expect(find.text('4,500 ج.م'), findsOneWidget);
    expect(find.text('الزرقا · كوبري السرو'), findsOneWidget);
    expect(find.text('النورس للنقل'), findsOneWidget);
    // Paying is a page of its own: nothing of it is on the tab.
    expect(find.byKey(const Key('payment-methods')), findsNothing);
    expect(find.byKey(const Key('payment-notes')), findsNothing);
    expect(find.byKey(const Key('next-period')), findsNothing);
    expect(find.byKey(const Key('sub-card-sub1')), findsOneWidget);

    await tester.tap(find.text('ادفع الآن'));
    await tester.pumpAndSettle();
    expect(find.byType(PayScreen), findsOneWidget);
    expect(find.text('1 · حوّل المبلغ'), findsOneWidget);
  });

  testWidgets('under review: when the receipt was sent, the amount and the method — and nothing to do',
      (tester) async {
    await open(tester, payOverrides(subs: [boardSub('pending_review')], receipts: [boardReceipt(1, 'pending')]));
    expect(find.text('قيد المراجعة'), findsOneWidget);
    expect(find.textContaining('أُرسل اليوم'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('amount-label'))).data, 'المبلغ');
    expect(tester.widget<Text>(find.byKey(const Key('amount-value'))).data, '4,500 ج.م');
    expect(find.text('طريقة الدفع'), findsOneWidget);
    expect(find.text('InstaPay'), findsOneWidget);
    expect(find.text('ادفع الآن'), findsNothing);
    expect(find.byType(BasakButton), findsNothing);
  });

  testWidgets('active: the ink pass with the days left, the receipt as a row, the next period as an offer',
      (tester) async {
    await open(tester, payOverrides(subs: [running()], doc: boardReceiptDoc));
    expect(find.text('نشط'), findsOneWidget);
    expect(find.textContaining('باقي 9'), findsOneWidget);
    expect(find.byType(BasakBar), findsOneWidget);
    expect(find.text('المبلغ المطلوب'), findsNothing);
    expect(find.byKey(const Key('payment-methods')), findsNothing);
    // The receipt is one row; its page holds the rest.
    expect(find.text('الإيصال'), findsOneWidget);
    expect(find.text('26-7F3A9C2E'), findsOneWidget);
    expect(find.byKey(const Key('receipt-pdf-sub1')), findsNothing);
    // The next period, when the company sells it in advance, with its own price.
    expect(find.byKey(const Key('next-period')), findsOneWidget);
    expect(find.text('الفصل الثاني متاح الآن'), findsOneWidget);
    expect(find.text('نفس الخط والمحطة · 4,500 ج.م'), findsOneWidget);

    await tester.tap(find.byKey(const Key('receipt-row-sub1')));
    await tester.pumpAndSettle();
    expect(find.byType(ReceiptScreen), findsOneWidget);
    expect(find.byKey(const Key('receipt-pdf-sub1')), findsOneWidget);
    expect(find.byKey(const Key('receipt-image-sub1')), findsOneWidget);
  });

  testWidgets('the next period opens the builder with the same line and station', (tester) async {
    await open(tester, payOverrides(subs: [running()], doc: boardReceiptDoc));
    await tester.tap(find.text('اشترك'));
    await tester.pumpAndSettle();
    final flow = tester.widget<PurchaseFlow>(find.byType(PurchaseFlow));
    expect([flow.initial.companyId, flow.initial.lineId, flow.initial.stationId, flow.initial.optionKey],
        ['c1', 'l1', 's1', 'second:2026']);
    expect(flow.allowDaily, isFalse, reason: 'a student who holds a subscription is not offered a cash day');
  });

  testWidgets('no next period on sale: no offer', (tester) async {
    await open(tester,
        payOverrides(subs: [running()], doc: boardReceiptDoc, catalog: boardCatalog(withSecond: false)));
    expect(find.byKey(const Key('next-period')), findsNothing);
  });

  testWidgets('past subscriptions: the latest two, then all of them on request, newest first', (tester) async {
    await open(tester, payOverrides(subs: [...past(5).reversed, running()], doc: boardReceiptDoc),
        size: const Size(390, 2400));
    expect(find.text('اشتراكات سابقة'), findsOneWidget);
    expect(find.byKey(const Key('sub-card-old0')), findsOneWidget);
    expect(find.byKey(const Key('sub-card-old1')), findsOneWidget);
    expect(find.byKey(const Key('sub-card-old2')), findsNothing);
    expect(find.text('الفصل الأول 2025/2026'), findsOneWidget);
    expect(find.text('انتهى 15 يناير 2026 · الزرقا'), findsOneWidget);

    await tester.tap(find.text('عرض كل الاشتراكات السابقة · 5'));
    await tester.pumpAndSettle();
    expect(find.text('عرض كل الاشتراكات السابقة · 5'), findsNothing);
    double y(String id) => tester.getTopLeft(find.byKey(Key('sub-card-$id'))).dy;
    expect(y('sub1'), lessThan(y('old0')));
    for (var i = 0; i < 4; i++) {
      expect(y('old$i'), lessThan(y('old${i + 1}')));
    }

    // A past one opens its own receipt.
    await tester.tap(find.byKey(const Key('sub-card-old3')));
    await tester.pumpAndSettle();
    expect(tester.widget<ReceiptScreen>(find.byType(ReceiptScreen)).subscriptionId, 'old3');
  });

  testWidgets('one or two past subscriptions: no "show all"', (tester) async {
    await open(tester, payOverrides(subs: [running(), ...past(1)], doc: boardReceiptDoc));
    expect(find.text('اشتراك سابق'), findsOneWidget);
    expect(find.byKey(const Key('history-all')), findsNothing);
  });

  testWidgets('expired: the renewal is filled in — same line and station, the period on sale, its price',
      (tester) async {
    await open(
        tester,
        payOverrides(
            subs: [boardSub('expired', phase: 'expired'), ...past(1)], catalog: boardCatalog(secondPhase: 'current')));
    expect(find.text('منتهٍ'), findsOneWidget);
    expect(find.text('14 يناير 2027'), findsOneWidget);
    expect(find.text('انتهى الفصل الأول'), findsOneWidget);
    expect(find.text('الفصل الثاني · نفس الخط والمحطة'), findsOneWidget);
    expect(find.text('الزرقا · كوبري السرو'), findsOneWidget);
    expect(find.text('4,500 ج.م'), findsOneWidget);
    expect(find.text('اختر خطاً أو محطة أخرى'), findsOneWidget);
    // The ended one is also the first row of the past.
    expect(find.text('انتهى 14 يناير 2027 · الزرقا'), findsOneWidget);
    expect(find.byKey(const Key('next-period')), findsNothing);

    await tester.tap(find.text('جدّد الاشتراك'));
    await tester.pumpAndSettle();
    final flow = tester.widget<PurchaseFlow>(find.byType(PurchaseFlow));
    expect([flow.initial.lineId, flow.initial.stationId, flow.initial.optionKey], ['l1', 's1', 'second:2026']);
  });

  testWidgets('expired, another line or station: the builder opens empty', (tester) async {
    await open(tester,
        payOverrides(subs: [boardSub('expired', phase: 'expired')], catalog: boardCatalog(secondPhase: 'current')));
    await tester.tap(find.byKey(const Key('subscribe-again')));
    await tester.pumpAndSettle();
    final flow = tester.widget<PurchaseFlow>(find.byType(PurchaseFlow));
    expect(flow.initial.lineId, isNull);
    expect(flow.allowDaily, isTrue);
  });

  testWidgets('expired with nothing to renew: a new subscription from one button', (tester) async {
    await open(tester,
        payOverrides(subs: [boardSub('expired', phase: 'expired')], catalog: boardCatalog(withSecond: false)));
    expect(find.text('لا يوجد اشتراك حالي'), findsOneWidget);
    expect(find.text('جدّد الاشتراك'), findsNothing);
    expect(find.text('اشتراك جديد'), findsOneWidget);
    await tester.tap(find.byKey(const Key('subscribe-again')));
    await tester.pumpAndSettle();
    expect(find.byType(PurchaseFlowPage), findsOneWidget);
  });

  testWidgets('a period that ended without a payment says so, and has no receipt to open', (tester) async {
    await open(tester,
        payOverrides(subs: [boardSub('pending_payment', phase: 'expired')], catalog: boardCatalog(withSecond: false)));
    expect(find.text('انتهى دون دفع'), findsOneWidget);
    expect(find.text('انتهى دون دفع · الزرقا'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sub-card-sub1')));
    await tester.pumpAndSettle();
    expect(find.byType(ReceiptScreen), findsNothing);
  });

  testWidgets('rejected: the ticket says why and which attempt, and leads to the pay page', (tester) async {
    await open(
        tester,
        payOverrides(
            subs: [boardSub('rejected')], receipts: [boardReceipt(1, 'rejected', reason: 'المبلغ غير مطابق')]));
    expect(find.text('إيصال مرفوض'), findsOneWidget);
    expect(find.text('المحاولة 2 من 5'), findsOneWidget);
    expect(find.text('المبلغ غير مطابق'), findsOneWidget);
    expect(find.text('كوبري السرو'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('amount-value'))).data, '4,500 ج.م');

    await tester.tap(find.text('إيصال جديد'));
    await tester.pumpAndSettle();
    expect(find.byType(PayScreen), findsOneWidget);
    expect(find.text('الإيصال مرفوض'), findsOneWidget);
  });

  testWidgets('paid and starting later: the light ticket with its first day, and its receipt', (tester) async {
    await open(
        tester,
        payOverrides(subs: [
          boardSub('active', code: 'second', phase: 'upcoming', start: '2027-02-07', end: '2027-06-10'),
        ], doc: boardReceiptDoc));
    expect(find.text('يبدأ قريباً'), findsOneWidget);
    expect(find.text('الفصل الثاني · 7 فبراير'), findsOneWidget);
    expect(find.text('خط الزرقا'), findsOneWidget);
    expect(find.text('26-7F3A9C2E'), findsOneWidget);
    expect(find.textContaining('باقي'), findsNothing);
  });

  testWidgets('a cash day ride: active, paid on the bus, no receipt', (tester) async {
    await open(tester, payOverrides(subs: [boardSub('active', type: 'daily', price: 50)]));
    expect(find.text('اشتراك يومي'), findsOneWidget);
    expect(find.text('نقداً في الباص'), findsOneWidget);
    expect(find.text('50 ج.م'), findsOneWidget);
    expect(find.text('الإيصال'), findsNothing);
    expect(find.byKey(const Key('next-period')), findsNothing);
  });

  testWidgets('a part that failed says so in place and can be read again; the rest stays', (tester) async {
    var fail = true;
    await open(tester, [
      ...payOverrides(subs: [running()], catalogNever: true),
      subscriptionReceiptDocProvider.overrideWith((ref, id) async {
        if (fail) throw Exception('x');
        return boardReceiptDoc;
      }),
    ]);
    expect(find.text('نشط'), findsOneWidget);
    expect(find.text('الزرقا · كوبري السرو'), findsOneWidget);
    expect(find.text('تعذّر تحميل الإيصال'), findsOneWidget);
    // What is on sale is still being read: its place is held, nothing spins.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('next-period')), findsNothing);

    fail = false;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('تعذّر تحميل الإيصال'), findsNothing);
    expect(find.text('26-7F3A9C2E'), findsOneWidget);
  });

  testWidgets('a paid subscription with no receipt on record says so', (tester) async {
    await open(tester, payOverrides(subs: [running()]));
    expect(find.text('لا يوجد إيصال لهذا الاشتراك.'), findsOneWidget);
  });

  testWidgets('offline: the pass says how old what it shows is', (tester) async {
    final now = DateTime.now();
    OfflineCache.offlineSince.value = DateTime(now.year, now.month, now.day, 8, 15);
    await open(tester, payOverrides(subs: [running()], doc: boardReceiptDoc));
    expect(find.text('آخر تحديث 8:15 ص'), findsOneWidget);
    expect(find.text('2026 / 2027'), findsNothing);
    OfflineCache.offlineSince.value = null;
    await tester.pump();
    expect(find.text('2026 / 2027'), findsOneWidget);
  });

  testWidgets('no subscription at all: the tab is the builder', (tester) async {
    await open(tester, payOverrides());
    expect(find.byType(PurchaseFlow), findsOneWidget);
    expect(find.text('اشتراكي'), findsNothing);
  });

  testWidgets('behind another tab nothing more is read: not what is on sale, not the receipt', (tester) async {
    var catalogReads = 0, docReads = 0, receiptReads = 0;
    final overrides = [
      ...payOverrides(subs: [running()]),
      saleCatalogProvider.overrideWith((ref) async {
        catalogReads++;
        return boardCatalog();
      }),
      subscriptionReceiptDocProvider.overrideWith((ref, id) async {
        docReads++;
        return boardReceiptDoc;
      }),
      subscriptionReceiptsProvider.overrideWith((ref, id) async {
        receiptReads++;
        return <ReceiptModel>[];
      }),
    ];
    await open(tester, overrides, visible: false);
    expect(find.text('نشط'), findsOneWidget);
    expect(find.text('الإيصال'), findsOneWidget, reason: 'the row is there; its code comes when the tab is opened');
    expect([catalogReads, docReads, receiptReads], [0, 0, 0]);
  });

  testWidgets('a first load with nothing saved fails as a whole page with a way to try again', (tester) async {
    var fail = true;
    await open(tester, [
      ...payOverrides(),
      allSubscriptionsProvider.overrideWith((ref) async {
        if (fail) throw Exception('تعذر الوصول');
        return [boardSub('pending_payment')];
      }),
    ]);
    expect(find.byType(PageError), findsOneWidget);
    expect(find.text('تعذر الوصول'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('بانتظار الدفع'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('nothing overflows on a 360 × 640 phone at text scale $scale', (tester) async {
      final states = <List<Override>>[
        payOverrides(subs: [boardSub('pending_payment')]),
        payOverrides(subs: [boardSub('pending_review')], receipts: [boardReceipt(1, 'pending')]),
        payOverrides(subs: [running(), ...past(5)], doc: boardReceiptDoc),
        payOverrides(subs: [boardSub('expired', phase: 'expired')], catalog: boardCatalog(secondPhase: 'current')),
        payOverrides(subs: [boardSub('expired', phase: 'expired')], catalog: boardCatalog(withSecond: false)),
        payOverrides(subs: [
          boardSub('rejected')
        ], receipts: [
          boardReceipt(1, 'rejected', reason: 'المبلغ في الإيصال 4,000 ج.م والمطلوب 4,500 ج.م. حوّل الفرق.'),
        ]),
        payOverrides(subs: [
          boardSub('active', code: 'second', phase: 'upcoming', start: '2027-02-07', end: '2027-06-10'),
        ], doc: boardReceiptDoc),
      ];
      for (final overrides in states) {
        await tester.pumpWidget(const SizedBox());
        await open(tester, overrides, size: const Size(360, 640), textScale: scale);
        expect(tester.takeException(), isNull);
        expect(find.byType(SubscriptionScreen), findsOneWidget);
      }
    });
  }

  group('the words of the tab', () {
    final now = DateTime(2026, 10, 11, 9);

    test('days left take the number\'s own plural', () {
      String left(int days) => SubscriptionScreenWords.daysLeft(isoDay(now.add(Duration(days: days))), now);
      expect(left(95), 'باقي 95 يوماً');
      expect(left(11), 'باقي 11 يوماً');
      expect(left(10), 'باقي 10 أيام');
      expect(left(3), 'باقي 3 أيام');
      expect(left(2), 'باقي يومان');
      expect(left(1), 'باقي يوم واحد');
      expect(left(0), 'ينتهي اليوم');
    });

    test('the share of the period that has passed', () {
      expect(SubscriptionScreenWords.elapsed('2026-10-01', '2026-10-21', now), .5);
      expect(SubscriptionScreenWords.elapsed('2026-11-01', '2026-12-01', now), 0);
      expect(SubscriptionScreenWords.elapsed('2026-01-01', '2026-02-01', now), 1);
    });

    test('when a receipt was sent', () {
      expect(SubscriptionScreenWords.sentAt(DateTime(2026, 10, 11, 15, 40).toIso8601String(), now),
          'أُرسل اليوم 3:40 م');
      expect(SubscriptionScreenWords.sentAt(DateTime(2026, 10, 10, 21, 5).toIso8601String(), now),
          'أُرسل أمس 9:05 م');
      expect(SubscriptionScreenWords.sentAt(DateTime(2026, 10, 3, 9).toIso8601String(), now), 'أُرسل 3 أكتوبر');
    });
  });
}
