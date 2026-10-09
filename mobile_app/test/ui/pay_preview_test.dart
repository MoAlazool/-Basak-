// Draws the subscription tab, the pay page and the receipt in each of their
// states to PNG files with the app's real fonts, to hold against the canvas
// boards. Skipped unless RENDER_DIR is set:
//   RENDER_DIR=/tmp/basak-pay flutter test test/ui/pay_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/features/student/subscription/models/payment_method_model.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';
import 'package:basak_mobile/features/student/subscription/presentation/pay_screen.dart';
import 'package:basak_mobile/features/student/subscription/presentation/receipt_screen.dart';
import 'package:basak_mobile/features/student/subscription/presentation/subscription_screen.dart';

import '../support/pay_fixtures.dart';

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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

const _sizes = [Size(390, 844), Size(360, 640)];

Future<void> _open(WidgetTester tester, Size size, Widget home, List<Override> overrides, {bool tab = false}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  // The status bar and the home indicator of the boards' phone.
  tester.view.padding = FakeViewPadding(top: size.height > 700 ? 94 : 48, bottom: size.height > 700 ? 68 : 0);
  addTearDown(tester.view.reset);
  // The boundary's key would carry the last screen's state into this one.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: overrides,
    child: RepaintBoundary(
      key: _key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: !tab
            ? home
            : Scaffold(
                extendBody: true,
                body: home,
                // Where the floating tab bar sits.
                bottomNavigationBar: SafeArea(
                  child: Container(
                    height: 64,
                    margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32)),
                  ),
                ),
              ),
      ),
    ),
  ));
  // Not pumpAndSettle: a skeleton never settles.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

String _tag(Size size) => size.height > 700 ? '' : '-640';

void main() {
  final today = DateTime.now();
  // A term that began 21 days ago and has 95 days to run, as on the board.
  SubscriptionModel running() => boardSub('active',
      start: isoDay(today.subtract(const Duration(days: 21))), end: isoDay(today.add(const Duration(days: 95))));
  List<SubscriptionModel> past(int count) => [
        for (var i = 0; i < count; i++)
          boardSub('expired',
              id: 'old$i',
              code: i.isEven ? 'second' : 'first',
              phase: 'expired',
              year: 2025 - (i + 1) ~/ 2,
              start: '${2026 - (i + 1) ~/ 2}-0${i.isEven ? 2 : 9}-10',
              end: i.isEven ? '${2026 - i ~/ 2}-05-28' : '${2026 - i ~/ 2}-01-15'),
      ];

  testWidgets('draw the subscription tab', (tester) async {
    await tester.runAsync(_fonts);
    Directory(_dir!).createSync(recursive: true);
    for (final size in _sizes) {
      final t = _tag(size);
      Future<void> tab(String name, List<Override> overrides) async {
        await _open(tester, size, const SubscriptionScreen(), overrides, tab: true);
        await _shot(tester, 'tab-$name$t');
      }

      await tab('awaiting', payOverrides(subs: [boardSub('pending_payment')]));
      await tab('review', payOverrides(subs: [boardSub('pending_review')], receipts: [boardReceipt(1, 'pending')]));
      await tab('active', payOverrides(subs: [running(), ...past(5)], doc: boardReceiptDoc));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
      await _shot(tester, 'tab-active-end$t');
      await tab(
          'expired',
          payOverrides(
              subs: [boardSub('expired', phase: 'expired'), ...past(1)], catalog: boardCatalog(secondPhase: 'current')));
      await tab('expired-no-offer',
          payOverrides(subs: [boardSub('expired', phase: 'expired')], catalog: boardCatalog(withSecond: false)));
      await tab(
          'rejected',
          payOverrides(
              subs: [boardSub('rejected')], receipts: [boardReceipt(1, 'rejected', reason: 'المبلغ غير مطابق')]));
      await tab(
          'upcoming',
          payOverrides(subs: [
            boardSub('active', code: 'second', phase: 'upcoming', start: '2027-02-07', end: '2027-06-10'),
          ], doc: boardReceiptDoc));
      await tab('partial', payOverrides(subs: [running()], docError: Exception('x'), catalogNever: true));
      OfflineCache.offlineSince.value = DateTime(today.year, today.month, today.day, 8, 15);
      await tab('offline', payOverrides(subs: [running()], doc: boardReceiptDoc));
      OfflineCache.offlineSince.value = null;
      await tab('daily', payOverrides(subs: [boardSub('active', type: 'daily', price: 50)]));
    }
  }, skip: _dir == null);

  testWidgets('draw the pay page', (tester) async {
    await tester.runAsync(_fonts);
    Directory(_dir!).createSync(recursive: true);
    await fakeReceiptPicker(tester);
    for (final size in _sizes) {
      final t = _tag(size);
      Future<void> pay(String status, List<Override> overrides) =>
          _open(tester, size, PayScreen(subscription: boardSub(status)), overrides);

      await pay('pending_payment', payOverrides(subs: [boardSub('pending_payment')]));
      await _shot(tester, 'pay$t');
      await tester.tap(find.text('البنك الأهلي'));
      await _shot(tester, 'pay-bank$t');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await _shot(tester, 'pay-end$t');

      // A picture chosen, then on its way.
      ScriptedSubmitter.reset();
      await tester.ensureVisible(find.byKey(const Key('receipt-gallery')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('receipt-gallery')));
      await realTime(tester);
      await _shot(tester, 'pay-attached$t');
      await tester.tap(find.byKey(const Key('receipt-send')));
      await realTime(tester);
      await _shot(tester, 'pay-upload$t');
      ScriptedSubmitter.finish.complete(boardReceipt(1, 'pending'));
      await realTime(tester);
      await _shot(tester, 'pay-done$t');

      await pay(
          'rejected',
          payOverrides(subs: [
            boardSub('rejected')
          ], receipts: [
            boardReceipt(1, 'rejected',
                reason: 'المبلغ في الإيصال 4,000 ج.م والمطلوب 4,500 ج.م. حوّل الفرق وارفع الإيصالين في صورة واحدة.'),
          ]));
      await _shot(tester, 'pay-rejected$t');

      await pay(
          'pending_payment',
          payOverrides(
              subs: [boardSub('pending_payment')],
              methods: const <PaymentMethodModel>[],
              receipts: [boardReceipt(1, 'rejected', reason: 'الصورة غير واضحة')]));
      await _shot(tester, 'pay-no-methods-rejected$t');
      await pay('pending_payment',
          payOverrides(subs: [boardSub('pending_payment')], methods: const <PaymentMethodModel>[]));
      await _shot(tester, 'pay-no-methods$t');

      await pay(
          'rejected',
          payOverrides(subs: [
            boardSub('rejected')
          ], receipts: [
            for (var i = 5; i >= 1; i--) boardReceipt(i, 'rejected', reason: 'المبلغ غير مطابق'),
          ]));
      await _shot(tester, 'pay-exhausted$t');
      await tester.tap(find.byKey(const Key('pay-rejected-list')));
      await tester.pumpAndSettle();
      await _shot(tester, 'pay-exhausted-list$t');

      await pay('pending_payment', payOverrides(subs: [boardSub('pending_payment')], methodsNever: true));
      await _shot(tester, 'pay-loading$t');

      // Offline with a picture chosen: it stays, sending waits.
      await pay('pending_payment', payOverrides(subs: [boardSub('pending_payment')], methods: [boardMethods().first]));
      // A lazy list: at a larger text size the buttons are built once scrolled to.
      await tester.scrollUntilVisible(find.byKey(const Key('receipt-camera')), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pump();
      await tester.tap(find.byKey(const Key('receipt-camera')));
      await realTime(tester);
      OfflineCache.offlineSince.value = DateTime(today.year, today.month, today.day, 8, 15);
      await tester.pump();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await _shot(tester, 'pay-offline$t');
      OfflineCache.offlineSince.value = null;
    }
  }, skip: _dir == null);

  testWidgets('draw the receipt', (tester) async {
    await tester.runAsync(_fonts);
    Directory(_dir!).createSync(recursive: true);
    for (final size in _sizes) {
      final t = _tag(size);
      await _open(tester, size, const ReceiptScreen(subscriptionId: 'sub1'), payOverrides(doc: boardReceiptDoc));
      await _shot(tester, 'receipt$t');
      await tester.ensureVisible(find.text('الشركة'));
      await tester.pump();
      await tester.tap(find.text('الشركة'));
      await tester.pumpAndSettle();
      await _shot(tester, 'receipt-company$t');
      await _open(tester, size, const ReceiptScreen(subscriptionId: 'sub1'), payOverrides());
      await _shot(tester, 'receipt-none$t');
    }
  }, skip: _dir == null);
}
