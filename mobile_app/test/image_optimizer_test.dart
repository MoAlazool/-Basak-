import 'dart:io';
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

  group('preparing what was picked', prepareTests);

  test('profile photos are stored much smaller than receipts', () {
    expect(ProfilePhoto.outputSize, lessThanOrEqualTo(512));
    expect(ProfilePhoto.outputSize, lessThan(ImageOptimizer.receiptMaxSide));
  });
}

/// What the picker hands over at the stored size is uploaded as it is; only
/// what still needs work goes through the pixels.
void prepareTests() {
  test('a picked JPEG already at the stored size is uploaded untouched', () async {
    final picked = Uint8List.fromList(img.encodeJpg(img.decodeJpg(_photo(1800, 1350))!, quality: ImageOptimizer.pickQuality));
    expect(ImageOptimizer.isReadyReceipt(picked), isTrue);
    expect(identical(await ImageOptimizer.prepareReceiptBytes(picked), picked) ||
        (await ImageOptimizer.prepareReceiptBytes(picked)).length == picked.length, isTrue);
  });

  test('a file is read and prepared off the main isolate from its path', () async {
    final directory = await Directory.systemTemp.createTemp('receipt');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/picked.jpg')..writeAsBytesSync(_photo(1200, 900));
    final prepared = await ImageOptimizer.prepareReceipt(file.path);
    expect(prepared, file.readAsBytesSync());
  });

  test('a PNG screenshot, an oversized photo and a sideways photo still go through the optimiser', () async {
    final png = _photo(900, 1600, png: true);
    expect(ImageOptimizer.isReadyReceipt(png), isFalse);
    expect((await ImageOptimizer.prepareReceiptBytes(png)).sublist(0, 2), [0xFF, 0xD8], reason: 'stored as JPEG');

    final large = _photo(2600, 1950);
    expect(ImageOptimizer.isReadyReceipt(large), isFalse);
    final stored = img.decodeJpg(await ImageOptimizer.prepareReceiptBytes(large))!;
    expect(stored.width, ImageOptimizer.receiptMaxSide);

    // A camera photo saved with "rotate me" in its tags (as Android pickers leave it).
    final sideways = img.decodeJpg(_photo(1600, 1200))!..exif.imageIfd.orientation = 6;
    final tagged = Uint8List.fromList(img.encodeJpg(sideways, quality: 85));
    expect(ImageOptimizer.isReadyReceipt(tagged), isFalse);
    final upright = img.decodeJpg(await ImageOptimizer.prepareReceiptBytes(tagged))!;
    expect([upright.width, upright.height], [1200, 1600], reason: 'turned upright for the reviewer');
  });

  test('too many bytes for its size: compressed again', () async {
    final heavy = Uint8List.fromList(img.encodeJpg(_noise(1800, 1800), quality: 100));
    expect(heavy.length, greaterThan(ImageOptimizer.receiptReadyBytes));
    expect(ImageOptimizer.isReadyReceipt(heavy), isFalse);
    expect((await ImageOptimizer.prepareReceiptBytes(heavy)).length, lessThan(heavy.length));
  });

  test('small print survives the direct path: what was picked at the target is not touched at all', () async {
    final picked = Uint8List.fromList(img.encodeJpg(img.decodeJpg(await ImageOptimizer.receipt(_photo(3600, 2400)))!,
        quality: ImageOptimizer.pickQuality));
    final image = img.decodeJpg(await ImageOptimizer.prepareReceiptBytes(picked))!;
    var darkest = 255;
    for (var y = 0; y < 40; y++) {
      final value = image.getPixel(1, y).r.toInt();
      if (value < darkest) darkest = value;
    }
    expect(darkest, lessThan(120));
  });

  test('something that is not an image is refused when prepared too', () async {
    expect(() => ImageOptimizer.prepareReceiptBytes(Uint8List.fromList([1, 2, 3, 4])), throwsA(isA<FormatException>()));
  });
}

img.Image _noise(int width, int height) {
  final image = img.Image(width: width, height: height);
  var seed = 7;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      image.setPixelRgb(x, y, seed & 255, (seed >> 8) & 255, (seed >> 16) & 255);
    }
  }
  return image;
}
