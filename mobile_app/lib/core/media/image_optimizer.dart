
import 'dart:io';

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

  /// The picker is asked for the stored size and quality directly, so the
  /// phone's own (fast, native) encoder does the work.
  static const pickMaxSide = 1800.0;
  static const pickQuality = 85;

  /// A picked file no larger than this, already an upright JPEG within
  /// [receiptMaxSide], is uploaded as it is.
  static const receiptReadyBytes = 1536 * 1024;

  /// The file at [path], ready to upload. Reading the file and any work on
  /// its pixels happen off the main isolate, so the screen never stutters.
  ///
  /// What the picker hands over is normally ready (see [isReadyReceipt]) and
  /// is returned untouched. Only a file that is still too large, not a JPEG
  /// (a PNG screenshot, a format the picker left alone) or stored sideways
  /// goes through [receipt]'s decode, resize and encode.
  static Future<Uint8List> prepareReceipt(String path) => compute(_prepareFile, path);

  /// [prepareReceipt] for bytes already in memory.
  static Future<Uint8List> prepareReceiptBytes(Uint8List original) => compute(_prepare, original);

  static Uint8List _prepareFile(String path) => _prepare(File(path).readAsBytesSync());

  static Uint8List _prepare(Uint8List original) =>
      isReadyReceipt(original) ? original : _encodeReceipt(original);

  /// Whether [bytes] can be stored as they are: a JPEG, small enough, within
  /// the size limit and with no "rotate me" tag. Reads the header only.
  static bool isReadyReceipt(Uint8List bytes) {
    if (bytes.length > receiptReadyBytes || bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return false;
    try {
      final info = img.JpegDecoder().startDecode(bytes);
      if (info == null || info.width > receiptMaxSide || info.height > receiptMaxSide) return false;
      final exif = img.decodeJpgExif(bytes);
      final orientation = exif != null && exif.imageIfd.hasOrientation ? exif.imageIfd.orientation : 1;
      return orientation == null || orientation == 1;
    } catch (_) {
      return false;
    }
  }

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
