// The pay page and the receipt page (boards Pay, PayNoMethods, PayUpload,
// PayDone, PayExhausted, StateRejected, Receipt).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/core/widgets/skeleton.dart';
import 'package:basak_mobile/features/student/subscription/data/subscription_repository.dart';
import 'package:basak_mobile/features/student/subscription/models/payment_method_model.dart';
import 'package:basak_mobile/features/student/subscription/presentation/pay_screen.dart';
import 'package:basak_mobile/features/student/subscription/presentation/receipt_card.dart';
import 'package:basak_mobile/features/student/subscription/presentation/receipt_screen.dart';
import 'package:basak_mobile/features/student/subscription/presentation/subscription_screen.dart';

import 'support/pay_fixtures.dart';

int wentHome = 0;

/// The pay page pushed over a first page, as the tab pushes it.
Future<void> openPay(WidgetTester tester, String status, List<Override> overrides,
    {Size size = const Size(390, 2000), double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  wentHome = 0;
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => PayScreen.open(context, boardSub(status), onGoHome: () => wentHome++),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await frames(tester);
}

/// Not pumpAndSettle: a spinner or a skeleton never settles.
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A toast leaves by itself; the test waits for it.
Future<void> toastGone(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await frames(tester);
}

Future<void> attach(WidgetTester tester, {String key = 'receipt-gallery'}) async {
  await tester.tap(find.byKey(Key(key)));
  await realTime(tester);
}

bool enabled(WidgetTester tester, String key) => tester.widget<BasakButton>(find.byKey(Key(key))).onPressed != null;

void main() {
  final copied = <String>[];

  setUp(() {
    ScriptedSubmitter.reset();
    copied.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
  });

  tearDown(() {
    OfflineCache.offlineSince.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  final awaiting = payOverrides(subs: [boardSub('pending_payment')]);

  group('pay', () {
    testWidgets('the amount once with its copy, a chip per method, one details card', (tester) async {
      await openPay(tester, 'pending_payment', awaiting);
      expect(tester.widget<Text>(find.byKey(const Key('amount-label'))).data, 'المبلغ المطلوب · الفصل الأول');
      expect(find.text('4,500 ج.م'), findsOneWidget);
      expect(find.text('1 · حوّل المبلغ'), findsOneWidget);
      expect(find.text('2 · ارفع الإيصال'), findsOneWidget);
      // Five methods, five chips; the first is the one shown.
      for (final name in ['فودافون كاش', 'اتصالات كاش', 'البنك الأهلي', 'بنك مصر']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.byKey(const Key('payment-methods')), findsOneWidget);
      expect(find.text('شركة النورس للنقل'), findsOneWidget);
      expect(find.text('عنوان InstaPay'), findsOneWidget);
      expect(find.text('elnawras@instapay'), findsOneWidget);
      expect(find.text('نسخ'), findsOneWidget);

      // The amount is copied as the bank's app takes it: digits alone.
      await tester.tap(find.text('نسخ المبلغ'));
      await tester.pump();
      expect(copied, ['4500']);
      // The button itself says so, and no toast comes up for a copy.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.descendant(of: find.byKey(const Key('amount-copy')), matching: find.text('تم النسخ')),
          findsOneWidget);
      expect(find.text('نسخ المبلغ'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pump(BasakMotion.copied);
      await frames(tester);
      expect(find.text('نسخ المبلغ'), findsOneWidget);
      expect(find.text('تم النسخ'), findsNothing);

      // A bank: its account and its IBAN, each with its own copy.
      await tester.tap(find.text('البنك الأهلي'));
      await frames(tester);
      expect(find.text('تحويل بنكي · البنك الأهلي المصري'), findsOneWidget);
      expect(find.text('رقم الحساب'), findsOneWidget);
      expect(find.text('IBAN'), findsOneWidget);
      expect(find.text('elnawras@instapay'), findsNothing);
      expect(find.text('نسخ'), findsNWidgets(2));
      await tester.tap(find.text('نسخ').last);
      await tester.pump();
      expect(copied.last, 'EG00 0003 0000 0000 0000 0000 000');
      // The IBAN's own row turns green; the account's row above it does not.
      await tester.pump(const Duration(milliseconds: 300));
      final rows = tester.widgetList<CopyRow>(find.byType(CopyRow)).toList();
      expect(rows.map((row) => row.label), ['رقم الحساب', 'IBAN']);
      expect(find.descendant(of: find.byType(CopyRow).last, matching: find.text('تم النسخ')), findsOneWidget);
      expect(find.descendant(of: find.byType(CopyRow).first, matching: find.text('تم النسخ')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pump(BasakMotion.copied);
      await frames(tester);
      expect(find.text('نسخ'), findsNWidgets(2));

      await tester.tap(find.text('فودافون كاش'));
      await frames(tester);
      expect(find.text('محفظة فودافون كاش'), findsOneWidget);
      expect(find.text('رقم المحفظة'), findsOneWidget);
      expect(find.text('010 1234 5678'), findsOneWidget);
    });

    testWidgets('"قبل التحويل" carries the company\'s own instructions and folds away', (tester) async {
      await openPay(tester, 'pending_payment', awaiting);
      expect(find.byKey(const Key('payment-notes')), findsOneWidget);
      expect(find.text('قبل التحويل'), findsOneWidget);
      expect(find.text('حوّل المبلغ كاملاً في عملية واحدة.'), findsOneWidget);
      expect(find.text('اكتب اسمك الثلاثي في ملاحظات التحويل.'), findsOneWidget);
      // Nothing about review or notifications here: that is said once, after sending.
      expect(find.textContaining('إشعار'), findsNothing);
      // Another method has no instructions of its own.
      await tester.tap(find.text('بنك مصر'));
      await frames(tester);
      expect(find.text('اكتب اسمك الثلاثي في ملاحظات التحويل.'), findsNothing);
      expect(find.text('حوّل المبلغ كاملاً في عملية واحدة.'), findsOneWidget);
      await tester.tap(find.text('قبل التحويل'));
      await frames(tester);
      expect(find.text('حوّل المبلغ كاملاً في عملية واحدة.'), findsNothing);
    });

    testWidgets('one method: no chips to pick from, its details at once', (tester) async {
      await openPay(tester, 'pending_payment',
          payOverrides(subs: [boardSub('pending_payment')], methods: [boardMethods().first]));
      expect(find.byType(BasakChips<PaymentMethodModel>), findsNothing);
      expect(find.text('elnawras@instapay'), findsOneWidget);
    });

    testWidgets('sending is off until a picture is attached; the picture can be taken back', (tester) async {
      await fakeReceiptPicker(tester);
      await openPay(tester, 'pending_payment', awaiting);
      expect(find.text('صورة واضحة فيها رقم العملية والتاريخ'), findsOneWidget);
      expect(find.text('الكاميرا'), findsOneWidget);
      expect(find.text('من الصور'), findsOneWidget);
      expect(enabled(tester, 'receipt-send'), isFalse);
      await tester.tap(find.byKey(const Key('receipt-send')));
      await tester.pump();
      expect(ScriptedSubmitter.calls, 0);

      await attach(tester, key: 'receipt-camera');
      expect(find.byKey(const Key('receipt-preview')), findsOneWidget);
      expect(find.text('الكاميرا'), findsNothing);
      expect(enabled(tester, 'receipt-send'), isTrue);

      await tester.tap(find.byKey(const Key('receipt-remove')));
      await frames(tester);
      expect(find.byKey(const Key('receipt-preview')), findsNothing);
      expect(find.text('الكاميرا'), findsOneWidget);
      expect(enabled(tester, 'receipt-send'), isFalse);
    });

    testWidgets('while sending: the three phases with the real percentage, and back does not lose it',
        (tester) async {
      await fakeReceiptPicker(tester);
      await openPay(tester, 'pending_payment', awaiting);
      await tester.tap(find.text('اتصالات كاش'));
      await frames(tester);
      await attach(tester);
      await tester.tap(find.byKey(const Key('receipt-send')));
      await realTime(tester);

      expect(ScriptedSubmitter.calls, 1);
      expect(ScriptedSubmitter.lastMethodId, 'm3', reason: 'the method the student picked goes with the receipt');
      expect(find.byKey(const Key('receipt-phase-uploading')), findsOneWidget);
      expect(find.text('جارٍ رفع الصورة'), findsOneWidget);
      expect(find.text('62%'), findsOneWidget);
      for (final step in ['التجهيز', 'الرفع', 'الإرسال']) {
        expect(find.text(step), findsOneWidget);
      }
      expect(find.text('ابقَ في هذه الصفحة حتى يكتمل الإرسال.'), findsOneWidget);
      expect(find.text('جارٍ الإرسال…'), findsOneWidget);
      // Step one is a single row now, and the picture stays in view.
      expect(find.text('طريقة الدفع'), findsOneWidget);
      expect(find.text('اتصالات كاش'), findsOneWidget);
      expect(find.byType(BasakChips<PaymentMethodModel>), findsNothing);
      expect(find.byKey(const Key('receipt-preview')), findsOneWidget);
      expect(find.text('نسخ المبلغ'), findsNothing);

      // The system's back, and the page's own, leave the upload alone.
      await tester.binding.handlePopRoute();
      await frames(tester);
      expect(find.byType(PayScreen), findsOneWidget);
      await toastGone(tester);
      await tester.tap(find.byType(BasakIconButton));
      await frames(tester);
      expect(find.byType(PayScreen), findsOneWidget);
      await toastGone(tester);
      // A second tap sends nothing twice.
      await tester.tap(find.byKey(const Key('receipt-send')));
      await tester.pump();
      expect(ScriptedSubmitter.calls, 1);

      ScriptedSubmitter.tellProgress!(900, 1000);
      await tester.pump();
      expect(find.text('90%'), findsOneWidget);
      ScriptedSubmitter.tellPhase!(ReceiptPhase.saving);
      await tester.pump();
      expect(find.byKey(const Key('receipt-phase-saving')), findsOneWidget);
      expect(find.text('جارٍ إرسال الإيصال'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('sent: "استلمنا إيصالك", the one sentence about review, and two ways out', (tester) async {
      await fakeReceiptPicker(tester);
      await openPay(tester, 'pending_payment', awaiting);
      await attach(tester);
      await tester.tap(find.byKey(const Key('receipt-send')));
      await realTime(tester);
      ScriptedSubmitter.finish.complete(boardReceipt(1, 'pending'));
      await realTime(tester);

      expect(find.byKey(const Key('receipt-phase-done')), findsOneWidget);
      expect(find.text('استلمنا إيصالك'), findsOneWidget);
      expect(find.text('تراجعه النورس للنقل، وسيصلك إشعار عند تفعيل اشتراكك.'), findsOneWidget);
      expect(find.byKey(const Key('receipt-send')), findsNothing);
      expect(find.text('1 · حوّل المبلغ'), findsNothing);

      await tester.tap(find.text('العودة للرئيسية'));
      await tester.pumpAndSettle();
      expect(find.byType(PayScreen), findsNothing);
      expect(wentHome, 1);
    });

    testWidgets('"عرض الطلب" goes back to the subscription', (tester) async {
      // Opened on a subscription already under review: the page only says so.
      await openPay(tester, 'pending_review',
          payOverrides(subs: [boardSub('pending_review')], receipts: [boardReceipt(1, 'pending')]));
      expect(find.text('استلمنا إيصالك'), findsOneWidget);
      expect(find.byKey(const Key('receipt-send')), findsNothing);
      await tester.tap(find.text('عرض الطلب'));
      await tester.pumpAndSettle();
      expect(find.byType(PayScreen), findsNothing);
      expect(wentHome, 0);
    });

    testWidgets('a failed send says why and keeps the picture, ready to be sent again', (tester) async {
      await fakeReceiptPicker(tester);
      await openPay(tester, 'pending_payment', awaiting);
      await attach(tester);
      await tester.tap(find.byKey(const Key('receipt-send')));
      await realTime(tester);
      ScriptedSubmitter.finish.complete(Exception('تعذر رفع صورة الإيصال. حاول مرة أخرى.'));
      await realTime(tester);

      expect(find.text('تعذر رفع صورة الإيصال. حاول مرة أخرى.'), findsWidgets);
      expect(find.byKey(const Key('receipt-preview')), findsOneWidget);
      expect(find.text('استلمنا إيصالك'), findsNothing);
      expect(enabled(tester, 'receipt-send'), isTrue);
      await toastGone(tester);
    });

    testWidgets('offline: sending is off, the picture is kept, and it comes back with the connection',
        (tester) async {
      await fakeReceiptPicker(tester);
      await openPay(tester, 'pending_payment', awaiting);
      await attach(tester);
      OfflineCache.offlineSince.value = DateTime.now();
      await frames(tester);
      expect(enabled(tester, 'receipt-send'), isFalse);
      expect(find.byKey(const Key('receipt-preview')), findsOneWidget);
      expect(find.textContaining('يحتاج اتصالاً بالإنترنت'), findsOneWidget);
      await tester.tap(find.byKey(const Key('receipt-send')));
      await tester.pump();
      expect(ScriptedSubmitter.calls, 0);

      OfflineCache.offlineSince.value = null;
      await toastGone(tester);
      expect(enabled(tester, 'receipt-send'), isTrue);
      expect(find.byKey(const Key('receipt-preview')), findsOneWidget);
    });

    testWidgets('while the methods are read for the first time: their shape, never a spinner', (tester) async {
      await openPay(tester, 'pending_payment', payOverrides(subs: [boardSub('pending_payment')], methodsNever: true));
      expect(find.byType(Skeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('4,500 ج.م'), findsOneWidget);
      expect(find.byKey(const Key('payment-methods')), findsNothing);
    });

    testWidgets('methods that could not be read: said in place, with a way to read them again', (tester) async {
      var fail = true;
      await openPay(tester, 'pending_payment', [
        ...payOverrides(subs: [boardSub('pending_payment')]),
        paymentMethodsProvider.overrideWith((ref, id) async {
          if (fail) throw Exception('x');
          return boardMethods();
        }),
      ]);
      expect(find.byType(InlineError), findsOneWidget);
      expect(find.text('تعذّر تحميل بيانات التحويل'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('إعادة المحاولة'));
      await frames(tester);
      expect(find.byType(InlineError), findsNothing);
      expect(find.text('elnawras@instapay'), findsOneWidget);
    });
  });

  group('rejected', () {
    final rejected = payOverrides(subs: [
      boardSub('rejected')
    ], receipts: [
      boardReceipt(1, 'rejected', reason: 'المبلغ في الإيصال 4,000 ج.م والمطلوب 4,500 ج.م.', method: 'm2'),
    ]);

    testWidgets('the company\'s reason on top, the attempt from the second, the method as one row',
        (tester) async {
      await openPay(tester, 'rejected', rejected);
      expect(find.text('الإيصال مرفوض'), findsOneWidget);
      expect(find.text('المحاولة 2 من 5'), findsOneWidget);
      expect(find.text('سبب الرفض من الشركة'), findsOneWidget);
      expect(find.text('المبلغ في الإيصال 4,000 ج.م والمطلوب 4,500 ج.م.'), findsOneWidget);
      expect(find.text('ارفع إيصالاً جديداً'), findsOneWidget);
      expect(find.text('صورة واضحة برقم العملية والتاريخ'), findsOneWidget);
      expect(find.text('نسخ المبلغ'), findsOneWidget);
      // The method the last receipt was paid with, collapsed.
      expect(find.text('فودافون كاش · 010 1234 5678'), findsOneWidget);
      expect(find.byType(BasakChips<PaymentMethodModel>), findsNothing);
      expect(enabled(tester, 'receipt-send'), isFalse);

      await tester.tap(find.text('تغيير'));
      await frames(tester);
      expect(find.byType(BasakChips<PaymentMethodModel>), findsOneWidget);
      expect(find.byKey(const Key('payment-methods')), findsOneWidget);
      expect(find.text('رقم المحفظة'), findsOneWidget);
    });

    testWidgets('a new receipt goes with the method of the last one unless it is changed', (tester) async {
      await fakeReceiptPicker(tester);
      await openPay(tester, 'rejected', rejected);
      await attach(tester);
      await tester.tap(find.byKey(const Key('receipt-send')));
      await realTime(tester);
      expect(ScriptedSubmitter.lastMethodId, 'm2');
      // The reason makes way for the sending.
      expect(find.text('الإيصال مرفوض'), findsNothing);
      expect(find.byKey(const Key('receipt-phase-uploading')), findsOneWidget);
    });

    testWidgets('a refusal without a written reason still says what to do', (tester) async {
      await openPay(tester, 'rejected',
          payOverrides(subs: [boardSub('rejected')], receipts: [boardReceipt(1, 'rejected')]));
      expect(find.text('راجع سبب الرفض مع إدارة الشركة ثم ارفع إيصالاً جديداً.'), findsOneWidget);
    });
  });

  group('no transfer details', () {
    testWidgets('says so, still takes the receipt, and offers the company', (tester) async {
      await fakeReceiptPicker(tester);
      await openPay(tester, 'pending_payment',
          payOverrides(subs: [boardSub('pending_payment')], methods: const <PaymentMethodModel>[]));
      expect(find.text('الدفع'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('amount-label'))).data, 'المبلغ المطلوب');
      expect(find.text('4,500 ج.م'), findsOneWidget);
      expect(find.textContaining('لم تضف الشركة بيانات التحويل بعد.'), findsOneWidget);
      expect(find.byKey(const Key('payment-methods')), findsNothing);
      expect(find.text('ارفع الإيصال'), findsOneWidget);
      expect(find.text('تواصل مع الشركة'), findsOneWidget);
      expect(find.textContaining('المتبقي'), findsNothing, reason: 'the first attempt needs no count');

      // With a picture the page's one button is the sending.
      await attach(tester);
      expect(find.text('تواصل مع الشركة'), findsNothing);
      await tester.tap(find.byKey(const Key('receipt-send')));
      await realTime(tester);
      expect(ScriptedSubmitter.calls, 1);
      expect(ScriptedSubmitter.lastMethodId, isNull);
    });

    testWidgets('from the second attempt the zone says how many are left', (tester) async {
      await openPay(
          tester,
          'pending_payment',
          payOverrides(
              subs: [boardSub('pending_payment')],
              methods: const <PaymentMethodModel>[],
              receipts: [boardReceipt(1, 'approved')]));
      expect(find.text('المتبقي 4 من 5 محاولات'), findsOneWidget);
    });

    testWidgets('no one to call: no contact button', (tester) async {
      await tester.pumpWidget(const SizedBox());
      tester.view.physicalSize = const Size(390, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: payOverrides(methods: const <PaymentMethodModel>[]),
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: PayScreen(subscription: boardSub('pending_payment', supervisorPhone: null)),
          ),
        ),
      ));
      await frames(tester);
      expect(find.textContaining('لم تضف الشركة'), findsOneWidget);
      expect(find.text('تواصل مع الشركة'), findsNothing);
    });
  });

  group('five attempts used', () {
    final exhausted = payOverrides(subs: [
      boardSub('rejected')
    ], receipts: [
      for (var i = 5; i >= 1; i--) boardReceipt(i, 'rejected', reason: i == 5 ? 'المبلغ غير مطابق' : 'الصورة غير واضحة'),
    ]);

    testWidgets('nothing more can be sent: the last reason, the amount, and the company', (tester) async {
      await openPay(tester, 'rejected', exhausted);
      expect(find.text('اكتملت المحاولات الخمس'), findsOneWidget);
      expect(find.textContaining('رُفضت الإيصالات الخمسة لهذا الاشتراك'), findsOneWidget);
      expect(find.text('آخر سبب للرفض'), findsOneWidget);
      expect(find.text('المبلغ غير مطابق'), findsOneWidget);
      expect(find.text('4,500 ج.م'), findsOneWidget);
      expect(find.text('تواصل مع الشركة'), findsOneWidget);
      expect(find.byKey(const Key('receipt-send')), findsNothing);
      expect(find.byKey(const Key('receipt-camera')), findsNothing);
      expect(find.byKey(const Key('payment-methods')), findsNothing);
    });

    testWidgets('the refused receipts can be read, each with its reason', (tester) async {
      await openPay(tester, 'rejected', exhausted);
      await tester.tap(find.text('عرض الإيصالات المرفوضة'));
      await tester.pumpAndSettle();
      expect(find.text('الإيصالات المرفوضة'), findsOneWidget);
      for (var i = 1; i <= 5; i++) {
        expect(find.text('المحاولة $i'), findsOneWidget);
      }
      expect(find.text('الصورة غير واضحة'), findsNWidgets(4));
    });
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('nothing overflows on a 360 × 640 phone at text scale $scale', (tester) async {
      final states = <(String, List<Override>)>[
        ('pending_payment', awaiting),
        (
          'rejected',
          payOverrides(
              subs: [boardSub('rejected')],
              receipts: [boardReceipt(1, 'rejected', reason: 'المبلغ في الإيصال 4,000 ج.م والمطلوب 4,500 ج.م.')])
        ),
        ('pending_payment', payOverrides(subs: [boardSub('pending_payment')], methods: const <PaymentMethodModel>[])),
        (
          'rejected',
          payOverrides(
              subs: [boardSub('rejected')],
              receipts: [for (var i = 5; i >= 1; i--) boardReceipt(i, 'rejected', reason: 'المبلغ غير مطابق')])
        ),
        ('pending_review', payOverrides(subs: [boardSub('pending_review')])),
      ];
      for (final (status, overrides) in states) {
        await openPay(tester, status, overrides, size: const Size(360, 640), textScale: scale);
        expect(tester.takeException(), isNull);
        expect(find.byType(PayScreen), findsOneWidget);
      }
    });
  }

  group('the receipt', () {
    Future<void> openReceipt(WidgetTester tester, List<Override> overrides,
        {Size size = const Size(390, 844), double textScale = 1}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
          ),
          home: const ReceiptScreen(subscriptionId: 'sub1'),
        ),
      ));
      await frames(tester);
    }

    testWidgets('paid chip and code, amount, date and method; three groups, the subscription open',
        (tester) async {
      await openReceipt(tester, payOverrides(doc: boardReceiptDoc));
      expect(find.text('الإيصال'), findsOneWidget);
      expect(find.text('مدفوع ومعتمد'), findsOneWidget);
      expect(find.text('26-7F3A9C2E'), findsOneWidget);
      expect(find.text('4,500 ج.م'), findsOneWidget);
      expect(find.text('22 سبتمبر 2026 · InstaPay'), findsOneWidget);
      expect(find.text('الفصل الأول 2026/2027'), findsOneWidget);
      expect(find.text('20 سبتمبر – 14 يناير 2027'), findsOneWidget);
      expect(find.text('كوبري السرو'), findsOneWidget);
      // Closed until asked for.
      expect(find.text('سارة أحمد محمود'), findsNothing);
      expect(find.text('057 240 1122'), findsNothing);

      await tester.tap(find.text('الطالب'));
      await tester.pumpAndSettle();
      expect(find.text('سارة أحمد محمود'), findsOneWidget);
      expect(find.text('010 2345 6789'), findsOneWidget);
      expect(find.text('كوبري السرو'), findsNothing, reason: 'one group open at a time');

      await tester.tap(find.text('الشركة'));
      await tester.pumpAndSettle();
      expect(find.text('النورس للنقل'), findsOneWidget);
      expect(find.text('057 240 1122'), findsOneWidget);
      expect(find.text('الزرقا، دمياط'), findsOneWidget);
      // Neither on the page nor in the document.
      expect(find.textContaining('سجل تجاري'), findsNothing);
      expect(find.textContaining('الضريبي'), findsNothing);

      // The three ways out: the PDF, a picture, the share sheet.
      expect(find.text('تنزيل PDF'), findsOneWidget);
      expect(find.byKey(const Key('receipt-pdf-sub1')), findsOneWidget);
      expect(find.byKey(const Key('receipt-image-sub1')), findsOneWidget);
      expect(find.byKey(const Key('receipt-share-sub1')), findsOneWidget);
    });

    testWidgets('no receipt on record: says so, with nothing to download', (tester) async {
      await openReceipt(tester, payOverrides());
      expect(find.text('لا يوجد إيصال لهذا الاشتراك.'), findsOneWidget);
      expect(find.text('تنزيل PDF'), findsNothing);
    });

    testWidgets('a receipt that could not be read can be read again', (tester) async {
      var fail = true;
      await openReceipt(tester, [
        ...payOverrides(),
        subscriptionReceiptDocProvider.overrideWith((ref, id) async {
          if (fail) throw Exception('x');
          return boardReceiptDoc;
        }),
      ]);
      expect(find.text('تعذّر تحميل الإيصال'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('إعادة المحاولة'));
      await frames(tester);
      expect(find.text('26-7F3A9C2E'), findsOneWidget);
    });

    testWidgets('fits a 360 × 640 phone at the largest text', (tester) async {
      await openReceipt(tester, payOverrides(doc: boardReceiptDoc), size: const Size(360, 640), textScale: 1.3);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('receipt-pdf-sub1')), findsOneWidget);
    });

    test('the receipt\'s own words for a period and its dates', () {
      expect(ReceiptCard.period('الفصل الدراسي الثاني 2026/2027'), 'الفصل الثاني 2026/2027');
      expect(ReceiptCard.span('2026-09-20', '2027-01-14'), '20 سبتمبر – 14 يناير 2027');
      expect(ReceiptCard.money(4500), '4,500 ج.م');
    });
  });
}
