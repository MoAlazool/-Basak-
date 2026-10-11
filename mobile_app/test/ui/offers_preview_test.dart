// Draws «عروض باصك» to PNG files with the app's real fonts: the page of all
// offers, one offer in full and the coupon at the till, on a 390 × 844 phone
// and on a 360 × 640 one at the largest text. A look at the layout without a
// device. Skipped unless RENDER_DIR is set:
//   RENDER_DIR=/tmp/basak-offers flutter test test/ui/offers_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/features/student/offers/offer_coupon_screen.dart';
import 'package:basak_mobile/features/student/offers/offer_details_screen.dart';
import 'package:basak_mobile/features/student/offers/offers_repository.dart';
import 'package:basak_mobile/features/student/offers/offers_screen.dart';
import 'package:basak_mobile/features/student/offers/offers_strip.dart';

import '../support/offer_fakes.dart';

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

/// A coupon's bar never stops: a few frames instead of settling.
Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  expect(tester.takeException(), isNull, reason: name);
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Widget _app(Widget home, List<Override> overrides, {required double scale, required double top}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale), padding: EdgeInsets.only(top: top, bottom: top > 30 ? 34 : 0)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: RepaintBoundary(key: _key, child: page!),
          ),
        ),
        home: home,
      ),
    );

void main() {
  setUpAll(_fonts);
  final skip = _dir == null;
  final clock = TestClock();

  List<Map<String, dynamic>> offers() => [
        offerJson(1,
            title: 'خصم على كل المشروبات الساخنة',
            special: true,
            needsPin: true,
            left: 12,
            endsAt: '2026-10-14T18:00:00'),
        offerJson(2,
            title: 'أدوات الرسم الهندسي',
            value: '50 ج.م',
            kind: 'amount',
            category: 'study',
            merchant: 'مكتبة الهندسة',
            used: 1,
            endsAt: '2026-10-11T22:00:00'),
        offerJson(3,
            title: 'مشروب مع كل وجبة', value: 'مشروب مجاني', kind: 'gift', merchant: 'مطعم الطلبة'),
        offerJson(4,
            title: 'افتتاح فرع جديد بجوار الجامعة',
            value: '',
            kind: 'info',
            category: 'shopping',
            merchant: 'سوبر ماركت الحي'),
      ];

  for (final (size, scale) in const [(Size(390, 844), 1.0), (Size(360, 640), 1.3)]) {
    final tag = '${size.width.toInt()}_${(scale * 100).toInt()}';
    final top = size.height > 700 ? 47.0 : 24.0;

    Future<void> open(WidgetTester tester, Widget home, FakeOffersGateway gateway) async {
      debugDisableShadows = false;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(home, offerOverrides(gateway, clock), scale: scale, top: top));
    }

    testWidgets('the strip, as Home shows it, at $tag', skip: skip, (tester) async {
      final gateway = FakeOffersGateway(offersJson(offers()));
      final list = OffersState.tryParse(gateway.answer)!.offers;
      await open(
          tester,
          Scaffold(
            backgroundColor: BasakPalette.ground,
            body: BasakPage(children: [OffersStrip(offers: list), OffersStrip(offers: list.take(1).toList())]),
          ),
          gateway);
      await _shot(tester, 'offers_strip_$tag');
      debugDisableShadows = true;
    });

    testWidgets('the page of all offers at $tag', skip: skip, (tester) async {
      final gateway = FakeOffersGateway(offersJson(offers()));
      await open(tester, const OffersScreen(), gateway);
      await _shot(tester, 'offers_page_$tag');
      debugDisableShadows = true;
    });

    testWidgets('one offer at $tag', skip: skip, (tester) async {
      final gateway = FakeOffersGateway(offersJson(offers()));
      final offer = OffersState.tryParse(gateway.answer)!.offers.first;
      await open(tester, OfferDetailsScreen(offer: offer), gateway);
      await _shot(tester, 'offer_details_$tag');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await _shot(tester, 'offer_details_end_$tag');
      await tester.tap(find.byKey(const Key('offer-use')));
      await _shot(tester, 'offer_confirm_$tag');
      debugDisableShadows = true;
    });

    testWidgets('the coupon at $tag', skip: skip, (tester) async {
      final gateway = FakeOffersGateway(offersJson(offers()));
      final offer = OffersState.tryParse(gateway.answer)!.offers.first;
      final coupon =
          OfferCoupon(id: 'c1', code: 'K7M2QP', expiresAt: clock.now.add(const Duration(minutes: 9, seconds: 41)));
      await open(tester, OfferCouponScreen(offer: offer, coupon: coupon), gateway);
      await _shot(tester, 'offer_coupon_$tag');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await _shot(tester, 'offer_coupon_pin_$tag');

      await tester.pumpWidget(const SizedBox());
      await open(tester, OfferCouponScreen(offer: offer, coupon: coupon.asConfirmed()), gateway);
      await _shot(tester, 'offer_coupon_used_$tag');

      await tester.pumpWidget(const SizedBox());
      final over = OfferCoupon(id: 'c2', code: 'K7M2QP', expiresAt: clock.now.subtract(const Duration(seconds: 1)));
      await open(tester, OfferCouponScreen(offer: offer, coupon: over), gateway);
      await _shot(tester, 'offer_coupon_expired_$tag');
      debugDisableShadows = true;
    });
  }
}
