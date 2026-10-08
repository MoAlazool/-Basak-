import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';

import '../theme/app_text_styles.dart';

/// The one way a profile photo enters the app:
///
///   pick or take a photo -> drag and zoom it inside a circle -> confirm
///
/// What comes back is the photo exactly as the student framed it: a square
/// JPEG of [outputSize] pixels. That file is the profile photo. Every place
/// that shows it (profile, home, transport card, wallet card) draws that same
/// square in a circle, so the framing chosen here is the framing everywhere
/// and nothing crops it again.
class ProfilePhoto {
  // Shown as a small circle in the app, on the dashboard and on the wallet card
  // (at most ~270 px there), so 512 px at this quality is ample and a fraction of the size.
  static const outputSize = 512;
  static const _jpegQuality = 80;

  /// Returns the framed photo, or null when the student cancels at any step
  /// (the photo they already had, if any, is then left untouched).
  static Future<Uint8List?> pickAndAdjust(
      BuildContext context, ImageSource source) async {
    // The picker bakes the camera's rotation into the pixels and caps the
    // size, so very large photos never reach memory at full resolution.
    final picked = await ImagePicker().pickImage(
        source: source, imageQuality: 90, maxWidth: 1600, maxHeight: 1600);
    if (picked == null || !context.mounted) return null;
    final bytes = await picked.readAsBytes();
    if (!context.mounted) return null;
    return Navigator.of(context).push<Uint8List>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PhotoAdjustScreen(source: bytes),
    ));
  }

  /// The part of [image] inside [crop], scaled to a square JPEG.
  static Future<Uint8List> renderSquare(ui.Image image, Rect crop) async {
    final recorder = ui.PictureRecorder();
    final target = Rect.fromLTWH(0, 0, outputSize.toDouble(), outputSize.toDouble());
    Canvas(recorder, target)
      ..drawColor(Colors.white, BlendMode.src)
      ..drawImageRect(image, crop, target, Paint()..filterQuality = FilterQuality.high);
    final square = await recorder.endRecording().toImage(outputSize, outputSize);
    final rgba = await square.toByteData(format: ui.ImageByteFormat.rawRgba);
    square.dispose();
    if (rgba == null) throw Exception('تعذر تجهيز الصورة.');
    return compute(_encodeJpeg, rgba.buffer.asUint8List());
  }

  static Uint8List _encodeJpeg(Uint8List rgba) => img.encodeJpg(
        img.Image.fromBytes(
            width: outputSize, height: outputSize, bytes: rgba.buffer, numChannels: 4),
        quality: _jpegQuality,
      );

  /// The square of the photo that is visible in a viewport of [viewport]
  /// pixels, given the pan/zoom [transform] applied to a photo that is drawn
  /// at [baseScale] times its real size. In the photo's own pixels.
  static Rect visibleSquare({
    required Matrix4 transform,
    required double viewport,
    required double baseScale,
    required Size imageSize,
  }) {
    final zoom = transform.getMaxScaleOnAxis();
    final offset = transform.getTranslation();
    final side = (viewport / zoom / baseScale).clamp(1.0, imageSize.shortestSide);
    final left = (-offset.x / zoom / baseScale).clamp(0.0, imageSize.width - side);
    final top = (-offset.y / zoom / baseScale).clamp(0.0, imageSize.height - side);
    return Rect.fromLTWH(left, top, side, side);
  }
}

class PhotoAdjustScreen extends StatefulWidget {
  final Uint8List source;

  const PhotoAdjustScreen({super.key, required this.source});

  @override
  State<PhotoAdjustScreen> createState() => _PhotoAdjustScreenState();
}

class _PhotoAdjustScreenState extends State<PhotoAdjustScreen> {
  final _controller = TransformationController();
  ui.Image? _image;
  String? _error;
  bool _saving = false;
  double _placedFor = 0;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      // Flutter applies the photo's EXIF rotation while decoding.
      final codec = await ui.instantiateImageCodec(widget.source);
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر فتح هذه الصورة. اختر صورة أخرى.');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _image?.dispose();
    super.dispose();
  }

  /// Starts centred; a tall photo starts a little above centre, where faces usually are.
  void _place(double viewport, Size shown) {
    if (_placedFor == viewport) return;
    final first = _placedFor == 0;
    _placedFor = viewport;
    final dx = (shown.width - viewport) / 2;
    final dy = (shown.height - viewport) * (shown.height > shown.width ? 0.3 : 0.5);
    final start = Matrix4.identity()..translate(-dx, -dy);
    if (first) {
      _controller.value = start;
    } else {
      // The screen was resized or rotated: reset after this frame, not during it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.value = start;
      });
    }
  }

  Future<void> _confirm(double viewport, double baseScale) async {
    final image = _image;
    if (image == null || _saving) return;
    setState(() => _saving = true);
    try {
      final crop = ProfilePhoto.visibleSquare(
        transform: _controller.value,
        viewport: viewport,
        baseScale: baseScale,
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
      );
      final framed = await ProfilePhoto.renderSquare(image, crop);
      if (mounted) Navigator.of(context).pop(framed);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر حفظ الصورة. حاول مرة أخرى.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      backgroundColor: const Color(0xFF0E1C26),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text('ضبط الصورة',
            style: AppTextStyles.titleLarge.copyWith(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          tooltip: 'إلغاء',
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(color: Colors.white)),
                ),
              )
            : image == null
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : LayoutBuilder(builder: (context, constraints) {
                    final viewport = (constraints.maxWidth - 32)
                        .clamp(120.0, (constraints.maxHeight - 190).clamp(120.0, 520.0))
                        .toDouble();
                    // At zoom 1 the photo's shorter side exactly fills the circle.
                    final baseScale = viewport / (image.width < image.height ? image.width : image.height);
                    final shown = Size(image.width * baseScale, image.height * baseScale);
                    _place(viewport, shown);
                    return Column(children: [
                      const SizedBox(height: 8),
                      Text('حرّك الصورة وكبّرها حتى يظهر وجهك داخل الدائرة',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: const Color(0xFFB9CCD8))),
                      const Spacer(),
                      SizedBox(
                        width: viewport,
                        height: viewport,
                        child: Stack(fit: StackFit.expand, children: [
                          ClipRect(
                            child: InteractiveViewer(
                              transformationController: _controller,
                              constrained: false,
                              minScale: 1,
                              maxScale: 5,
                              child: SizedBox(
                                width: shown.width,
                                height: shown.height,
                                child: RawImage(image: image, fit: BoxFit.fill),
                              ),
                            ),
                          ),
                          const IgnorePointer(child: CustomPaint(painter: _CircleMask())),
                        ]),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving ? null : () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Color(0xFF4A6272)),
                                minimumSize: const Size.fromHeight(50),
                              ),
                              child: const Text('إلغاء'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _saving ? null : () => _confirm(viewport, baseScale),
                              style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50)),
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(LucideIcons.check, size: 18),
                              label: const Text('اعتماد الصورة'),
                            ),
                          ),
                        ]),
                      ),
                    ]);
                  }),
      ),
    );
  }
}

/// Dims everything outside the circle the photo will be shown in.
class _CircleMask extends CustomPainter {
  const _CircleMask();

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(circle), Path()..addOval(circle)),
      Paint()..color = const Color(0xB30E1C26),
    );
    canvas.drawOval(
      circle.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
