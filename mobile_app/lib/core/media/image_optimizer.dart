
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Images are shrunk on the phone before they are uploaded: the original never
/// leaves the device and only the optimised file is stored.
///
/// - Profile photos are small on every screen, so they are compressed hard
///   (see `ProfilePhoto`, which crops and encodes them).
/// - Receipts must stay readable: account numbers, amounts and reference codes
///   are small print, so they keep more pixels and a gentler compression.
class ImageOptimizer {
  /// Longest side of a stored receipt. A phone photo of an A5 bank slip or a
  /// full-screen transfer screenshot is still sharp at this size.
  static const receiptMaxSide = 1800;
  static const receiptQuality = 86;

  /// A receipt photo or screenshot as one upright JPEG, at most
  /// [receiptMaxSide] pixels on its longest side. Throws when the bytes are
  /// not an image the app can read.
  static Future<Uint8List> receipt(Uint8List original) =>
      compute(_encodeReceipt, original);

  static Uint8List _encodeReceipt(Uint8List original) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(original);
    } catch (_) {
      decoded = null; // truncated or unknown data
    }
    if (decoded == null) {
      throw const FormatException('تعذر قراءة الصورة. اختر صورة JPG أو PNG واضحة للإيصال.');
    }
    // Phone cameras store "which way is up" as a tag; make it real pixels so
    // the reviewer never sees a sideways receipt.
    var image = img.bakeOrientation(decoded);
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > receiptMaxSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: receiptMaxSide, interpolation: img.Interpolation.cubic)
          : img.copyResize(image, height: receiptMaxSide, interpolation: img.Interpolation.cubic);
    }
    // Screenshots can carry transparency; JPEG cannot, so flatten onto white.
    if (image.numChannels == 4) {
      final flat = img.Image(width: image.width, height: image.height)..clear(img.ColorRgb8(255, 255, 255));
      image = img.compositeImage(flat, image);
    }
    return img.encodeJpg(image, quality: receiptQuality);
  }
}
