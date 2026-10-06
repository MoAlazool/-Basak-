import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:basak_mobile/core/media/image_optimizer.dart';
import 'package:basak_mobile/core/widgets/photo_adjust_screen.dart';

/// A noisy "photo" with thin dark lines, like small print on a bank slip.
Uint8List _photo(int width, int height, {bool png = false}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final line = y % 40 < 2 && x % 7 < 4;
      final noise = (x * 31 + y * 17) % 23;
      image.setPixelRgb(x, y, line ? 20 : 225 + noise, line ? 20 : 225 + noise, line ? 30 : 220 + noise);
    }
  }
  return Uint8List.fromList(png ? img.encodePng(image) : img.encodeJpg(image, quality: 98));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a large receipt photo is stored smaller, as a JPEG no bigger than the limit', () async {
    final original = _photo(4000, 3000);
    final stored = await ImageOptimizer.receipt(original);
    final image = img.decodeJpg(stored)!;
    expect(image.width, ImageOptimizer.receiptMaxSide);
    expect(image.height, 1350);
    expect(stored.length, lessThan(original.length ~/ 3));
  });

  test('a tall screenshot keeps its shape and is limited by its height', () async {
    final stored = await ImageOptimizer.receipt(_photo(1290, 2796, png: true));
    final image = img.decodeJpg(stored)!;
    expect(image.height, ImageOptimizer.receiptMaxSide);
    expect((image.width / image.height - 1290 / 2796).abs(), lessThan(0.005));
  });

  test('a receipt that is already small is not enlarged', () async {
    final stored = await ImageOptimizer.receipt(_photo(900, 600));
    final image = img.decodeJpg(stored)!;
    expect([image.width, image.height], [900, 600]);
  });

  test('small print survives: thin dark lines are still dark after optimising', () async {
    final stored = await ImageOptimizer.receipt(_photo(3600, 2400));
    final image = img.decodeJpg(stored)!;
    // Lines sit every 40 source pixels = every 20 stored pixels, 1 px thick.
    var darkest = 255;
    for (var y = 0; y < 40; y++) {
      final value = image.getPixel(1, y).r.toInt();
      if (value < darkest) darkest = value;
    }
    expect(darkest, lessThan(120), reason: 'a line must stay clearly darker than the paper');
  });

  test('something that is not an image is refused with a clear message', () async {
    expect(() => ImageOptimizer.receipt(Uint8List.fromList([1, 2, 3, 4])), throwsA(isA<FormatException>()));
  });

  test('profile photos are stored much smaller than receipts', () {
    expect(ProfilePhoto.outputSize, lessThanOrEqualTo(512));
    expect(ProfilePhoto.outputSize, lessThan(ImageOptimizer.receiptMaxSide));
  });
}
