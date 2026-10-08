import 'package:basak_mobile/core/widgets/avatar_image.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:basak_mobile/core/widgets/photo_adjust_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A photo whose four quarters are red, green, blue and yellow.
Future<ui.Image> quartered(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final w = width / 2, h = height / 2;
  canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFFF0000));
  canvas.drawRect(Rect.fromLTWH(w, 0, w, h), Paint()..color = const Color(0xFF00FF00));
  canvas.drawRect(Rect.fromLTWH(0, h, w, h), Paint()..color = const Color(0xFF0000FF));
  canvas.drawRect(Rect.fromLTWH(w, h, w, h), Paint()..color = const Color(0xFFFFFF00));
  return recorder.endRecording().toImage(width, height);
}

void main() {
  test('with no pan or zoom the circle shows the top-left square of a landscape photo', () {
    // 1200x800 photo in a 300px circle: the shorter side fills it, so base scale = 300 / 800.
    final crop = ProfilePhoto.visibleSquare(
        transform: Matrix4.identity(), viewport: 300, baseScale: 300 / 800, imageSize: const Size(1200, 800));
    expect(crop, const Rect.fromLTWH(0, 0, 800, 800));
  });

  test('dragging moves the crop and zooming shrinks it, in the photo\'s own pixels', () {
    const base = 300 / 800;
    // Dragged 75px left: 75 / 0.375 = 200 photo pixels.
    final dragged = ProfilePhoto.visibleSquare(
        transform: Matrix4.identity()..translate(-75.0, 0.0), viewport: 300, baseScale: base, imageSize: const Size(1200, 800));
    expect(dragged, const Rect.fromLTWH(200, 0, 800, 800));
    // Zoomed 2x and centred: half the photo's height, in the middle.
    final zoomed = ProfilePhoto.visibleSquare(
        transform: Matrix4.identity()..translate(-300.0, -150.0)..scale(2.0), viewport: 300, baseScale: base, imageSize: const Size(1200, 800));
    expect(zoomed, const Rect.fromLTWH(400, 200, 400, 400));
  });

  test('the crop can never leave the photo', () {
    final crop = ProfilePhoto.visibleSquare(
        transform: Matrix4.identity()..translate(500.0, 500.0), viewport: 300, baseScale: 300 / 800, imageSize: const Size(800, 1200));
    expect(crop.left, 0);
    expect(crop.top, 0);
    expect(crop.right <= 800 && crop.bottom <= 1200, isTrue);
  });

  testWidgets('the saved photo is exactly the framed square, as one small JPEG', (tester) async {
    await tester.runAsync(() async {
      for (final size in [const Size(1200, 800), const Size(800, 1200), const Size(3000, 2000)]) {
        final photo = await quartered(size.width.toInt(), size.height.toInt());
        // Frame only the bottom-right (yellow) quarter.
        final side = size.shortestSide / 2;
        final framed = await ProfilePhoto.renderSquare(
            photo, Rect.fromLTWH(size.width / 2, size.height / 2, side, side));
        expect(framed.sublist(0, 2), [0xFF, 0xD8], reason: 'JPEG');
        final saved = img.decodeJpg(framed)!;
        expect([saved.width, saved.height], [ProfilePhoto.outputSize, ProfilePhoto.outputSize]);
        const edge = ProfilePhoto.outputSize - 20.0;
        for (final point in [const Offset(20, 20), const Offset(edge / 2, edge / 2), const Offset(edge, edge)]) {
          final pixel = saved.getPixel(point.dx.toInt(), point.dy.toInt());
          expect(pixel.r > 230 && pixel.g > 230 && pixel.b < 40, isTrue,
              reason: 'expected yellow at $point for $size, got ${pixel.r},${pixel.g},${pixel.b}');
        }
        expect(framed.length < 80 * 1024, isTrue, reason: 'a profile photo is a small file');
      }
    });
  });

  testWidgets('cancelling the adjust step returns nothing', (tester) async {
    Object? result = 'unset';
    late ui.Image photo;
    late Uint8List png;
    await tester.runAsync(() async {
      photo = await quartered(400, 300);
      png = (await photo.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    });
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await Navigator.of(context)
              .push<Uint8List>(MaterialPageRoute(builder: (_) => PhotoAdjustScreen(source: png))),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('ضبط الصورة'), findsOneWidget);
    await tester.tap(find.byTooltip('إلغاء'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(result, isNull);
  });

  test('a fresh link to the same photo is tried again, while the saved copy on disk is still shared', () {
    const path = 'https://x.supabase.co/storage/v1/object/sign/student-avatars/u1/avatar-1.jpg';
    final expired = avatarImage('$path?token=old') as CachedNetworkImageProvider;
    final fresh = avatarImage('$path?token=new') as CachedNetworkImageProvider;
    // Different requests to the widget: a failed first attempt does not block the second.
    expect(expired == fresh, isFalse);
    expect(avatarImage('$path?token=new') == fresh, isTrue);
    // One file on disk for both: the photo still shows offline.
    expect(expired.cacheKey, fresh.cacheKey);
    expect(fresh.cacheKey, 'x.supabase.co/storage/v1/object/sign/student-avatars/u1/avatar-1.jpg');
  });
}
