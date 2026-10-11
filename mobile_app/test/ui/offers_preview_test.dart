// Draws «عروض باصك» to PNG files with the app's real fonts: Home's strip, the
// page of all offers, one offer in full and the coupon card at the till
// (waiting for the PIN, used, over), with pictures and without, on a
// 390 × 844 phone and on a 360 × 640 one at the largest text. A look at the
// layout without a device. Skipped unless RENDER_DIR is set:
//   RENDER_DIR=/tmp/basak-offers flutter test test/ui/offers_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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

/// A picture painted here, standing in for the ones in the bucket: no network.
class _Painted extends ImageProvider<_Painted> {
  final ui.Image image;
  const _Painted(this.image);

  @override
  Future<_Painted> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_Painted key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: image.clone())));
}

/// A 1600 × 900 picture in the app's own colours: a table, a cup, some light.
Future<ui.Image> _paint() {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(1600, 900);
  canvas.drawRect(Offset.zero & size, Paint()..color = BasakPalette.sky);
  canvas.drawCircle(const Offset(1250, 240), 330, Paint()..color = BasakPalette.tealTint);
  canvas.drawRect(const Rect.fromLTWH(0, 640, 1600, 260), Paint()..color = BasakPalette.teal);
  canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(520, 330, 360, 330), const Radius.circular(48)),
      Paint()..color = BasakPalette.surface);
  canvas.drawCircle(const Offset(930, 470), 80, Paint()
    ..color = BasakPalette.surface
    ..style = PaintingStyle.stroke
    ..strokeWidth = 36);
  canvas.drawCircle(const Offset(330, 520), 120, Paint()..color = BasakPalette.mint);
  return recorder.endRecording().toImage(size.width.toInt(), size.height.toInt());
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
  String picture(int n) => 'offers/${offerUuid(n)}/cover.jpg';

  /// The second offer has no picture: its place holds the merchant's mark.
  List<Map<String, dynamic>> offers() => [
        offerJson(1,
            title: 'خصم على كل المشروبات الساخنة',
            special: true,
            needsPin: true,
            left: 12,
            endsAt: '2026-10-14T18:00:00',
            imagePath: picture(1)),
        offerJson(2,
            title: 'أدوات الرسم الهندسي',
            value: '50 ج.م',
            kind: 'amount',
            category: 'study',
            merchant: 'مكتبة الهندسة',
            used: 1,
            endsAt: '2026-10-11T22:00:00'),
        offerJson(3,
            title: 'مشروب مع كل وجبة',
            value: 'مشروب مجاني',
            kind: 'gift',
            merchant: 'مطعم الطلبة',
            imagePath: picture(3)),
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
      final painted = _Painted((await tester.runAsync(_paint))!);
      debugCompanyLogoImage = (url) => painted;
      addTearDown(() => debugCompanyLogoImage = null);
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
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -520));
      await _shot(tester, 'offers_page_next_$tag');
      debugDisableShadows = true;
    });

    testWidgets('one offer at $tag', skip: skip, (tester) async {
      final gateway = FakeOffersGateway(offersJson(offers()));
      final list = OffersState.tryParse(gateway.answer)!.offers;
      await open(tester, OfferDetailsScreen(offer: list.first), gateway);
      await _shot(tester, 'offer_details_$tag');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await _shot(tester, 'offer_details_end_$tag');
      await tester.tap(find.byKey(const Key('offer-use')));
      await _shot(tester, 'offer_confirm_$tag');

      await tester.pumpWidget(const SizedBox());
      await open(tester, OfferDetailsScreen(offer: list[1]), gateway);
      await _shot(tester, 'offer_details_no_picture_$tag');
      debugDisableShadows = true;
    });

    testWidgets('the coupon card at $tag', skip: skip, (tester) async {
      final gateway = FakeOffersGateway(offersJson(offers()));
      final list = OffersState.tryParse(gateway.answer)!.offers;
      final offer = list.first;
      final coupon =
          OfferCoupon(id: 'c1', code: 'K7M2QP', expiresAt: clock.now.add(const Duration(minutes: 9, seconds: 41)));
      await open(tester, OfferCouponScreen(offer: offer, coupon: coupon), gateway);
      await _shot(tester, 'offer_coupon_$tag');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await _shot(tester, 'offer_coupon_pin_$tag');

      // Used: by the PIN, and at once on an offer without one and without a picture.
      await tester.pumpWidget(const SizedBox());
      await open(tester, OfferCouponScreen(offer: offer, coupon: coupon.asConfirmed()), gateway);
      await _shot(tester, 'offer_coupon_used_$tag');
      await tester.pumpWidget(const SizedBox());
      final plain = Offer.tryParse(offerJson(5, title: 'مشروب مع كل وجبة', value: 'مشروب مجاني', kind: 'gift'))!;
      await open(tester, OfferCouponScreen(offer: plain, coupon: coupon.asConfirmed()), gateway);
      await _shot(tester, 'offer_coupon_used_no_picture_$tag');

      await tester.pumpWidget(const SizedBox());
      final over = OfferCoupon(id: 'c2', code: 'K7M2QP', expiresAt: clock.now.subtract(const Duration(seconds: 1)));
      await open(tester, OfferCouponScreen(offer: offer, coupon: over), gateway);
      await _shot(tester, 'offer_coupon_expired_$tag');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await _shot(tester, 'offer_coupon_expired_end_$tag');
      debugDisableShadows = true;
    });
  }
}
