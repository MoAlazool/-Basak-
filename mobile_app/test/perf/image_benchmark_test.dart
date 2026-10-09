import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:basak_mobile/core/media/image_optimizer.dart';

/// Time and size of the receipt image path on fixed, generated samples.
///
/// Run: flutter test test/perf/image_benchmark_test.dart
///
/// These are pure-Dart timings on the development machine: a proxy for a
/// phone (which is several times slower), not a device measurement. The
/// numbers are printed and copied into RESULTS.md; the assertions are the
/// regression guards.
Uint8List sample(int width, int height, {bool png = false, int quality = 92}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      // Paper with soft shading, sensor-like noise and rows of small print.
      final text = y % 36 < 3 && (x ~/ 5) % 3 != 0 && x % 400 > 60;
      final shade = 228 + ((x * 13 + y * 7) % 19) - (x * 20 ~/ width);
      final v = text ? 30 + (x * 7 + y * 3) % 25 : shade;
      image.setPixelRgb(x, y, v, v, text ? v + 8 : v - 6);
    }
  }
  return Uint8List.fromList(png ? img.encodePng(image, level: 6) : img.encodeJpg(image, quality: quality));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final samples = <String, Uint8List Function()>{
    'camera photo 4000x3000 JPEG': () => sample(4000, 3000),
    'screenshot 1170x2532 PNG': () => sample(1170, 2532, png: true),
    'picked as before 2600x1950 JPEG q92': () => sample(2600, 1950),
    'picked at target 1800x1350 JPEG q85': () => sample(1800, 1350, quality: 85),
    'already small 900x600 JPEG': () => sample(900, 600, quality: 85),
  };

  Future<({int ms, Uint8List stored})> timed(Future<Uint8List> Function() run) async {
    final times = <int>[];
    late Uint8List stored;
    for (var i = 0; i < 3; i++) {
      final watch = Stopwatch()..start();
      stored = await run();
      times.add(watch.elapsedMicroseconds);
    }
    times.sort();
    return (ms: (times[1] / 1000).round(), stored: stored);
  }

  test('receipt image preparation: time and bytes per sample', () async {
    final lines = <String>[];
    for (final entry in samples.entries) {
      final original = entry.value();
      // Before: every picked image was decoded, resized and encoded again.
      final always = await timed(() => ImageOptimizer.receipt(original));
      // Now: only when the picked file still needs it.
      final now = await timed(() => ImageOptimizer.prepareReceiptBytes(original));
      final image = img.decodeJpg(now.stored)!;
      lines.add('| ${entry.key} | ${original.length ~/ 1024} kB | ${always.ms} ms | ${always.stored.length ~/ 1024} kB | '
          '${now.ms} ms | ${now.stored.length ~/ 1024} kB | ${image.width}x${image.height} | '
          '${ImageOptimizer.isReadyReceipt(original) ? 'as picked' : 'optimised'} |');

      // Regression guards.
      expect(image.width <= ImageOptimizer.receiptMaxSide && image.height <= ImageOptimizer.receiptMaxSide, isTrue,
          reason: entry.key);
      expect(now.stored.length, lessThanOrEqualTo(ImageOptimizer.receiptReadyBytes), reason: entry.key);
      expect(now.stored.sublist(0, 2), [0xFF, 0xD8], reason: '${entry.key}: stored as JPEG');
    }
    // ignore: avoid_print
    print('| sample | input | always optimise: time | stored | now: time | stored | size | path |\n'
        '|---|---|---|---|---|---|---|---|\n${lines.join('\n')}');

    // What the picker now hands over (the stored size and quality) needs no work at all.
    final target = samples['picked at target 1800x1350 JPEG q85']!();
    expect(ImageOptimizer.isReadyReceipt(target), isTrue);
    expect(await ImageOptimizer.prepareReceiptBytes(target), target);
    // The old hand-over size still gets shrunk if it ever arrives.
    expect(ImageOptimizer.isReadyReceipt(samples['picked as before 2600x1950 JPEG q92']!()), isFalse);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
