import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';

import '../ui/ui.dart';

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

  /// Asks where the photo comes from ([PhotoSourceSheet]), then picks and
  /// frames it. Null when the student backs out at any step.
  static Future<Uint8List?> choose(BuildContext context) async {
    final source = await PhotoSourceSheet.show(context);
    if (source == null || !context.mounted) return null;
    return pickAndAdjust(context, source);
  }

  /// The part of [image] inside [crop], scaled to a square JPEG.
  static Future<Uint8List> renderSquare(ui.Image image, Rect crop) async {
    final recorder = ui.PictureRecorder();
    final target = Rect.fromLTWH(0, 0, outputSize.toDouble(), outputSize.toDouble());
    Canvas(recorder, target)
      ..drawColor(BasakPalette.surface, BlendMode.src)
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
  double _viewport = 0;
  double _baseScale = 1;

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
        BasakToast.show(context, 'تعذر حفظ الصورة. حاول مرة أخرى.', kind: BasakToastKind.failure);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final image = _image;
    final cancel = _saving ? null : () => Navigator.of(context).pop();

    // A dark page: the phone's own status icons turn light over it.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: BasakChrome.onDark(colors.scanPanel),
      child: Scaffold(
        backgroundColor: colors.scanPanel,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                BasakSpace.gutter, BasakSpace.s12, BasakSpace.gutter, BasakSpace.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: BasakSpace.tapTarget,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Semantics(
                        header: true,
                        child: Text('ضبط الصورة', style: text.headline.copyWith(color: colors.onInk)),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Tooltip(
                          message: 'إلغاء',
                          excludeFromSemantics: true,
                          child: BasakPressable(
                            onTap: cancel,
                            child: Center(
                              widthFactor: 1,
                              child: Text('إلغاء',
                                  style: text.body.copyWith(color: colors.onInk, fontWeight: FontWeight.w500)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _error != null
                      ? Center(
                          child: Text(_error!,
                              textAlign: TextAlign.center, style: text.body.copyWith(color: colors.onInk)),
                        )
                      : image == null
                          ? Center(child: CircularProgressIndicator(color: colors.onInk))
                          : LayoutBuilder(builder: (context, constraints) {
                              // 300 on a 390 phone; smaller where the screen is short.
                              final viewport = (constraints.maxWidth - 50)
                                  .clamp(120.0, (constraints.maxHeight - 110).clamp(120.0, 520.0))
                                  .toDouble();
                              // At zoom 1 the photo's shorter side exactly fills the circle.
                              final baseScale =
                                  viewport / (image.width < image.height ? image.width : image.height);
                              final shown = Size(image.width * baseScale, image.height * baseScale);
                              _place(viewport, shown);
                              _viewport = viewport;
                              _baseScale = baseScale;
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
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
                                      IgnorePointer(
                                        child: CustomPaint(
                                          painter: _CircleMask(
                                              outside: colors.scanPanel, ring: colors.onInk),
                                        ),
                                      ),
                                    ]),
                                  ),
                                  const SizedBox(height: BasakSpace.s24),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 280),
                                    child: Text('حرّك الصورة وكبّرها بإصبعين حتى يظهر وجهك داخل الدائرة.',
                                        textAlign: TextAlign.center,
                                        style: text.bodySmall.copyWith(color: colors.onInk2)),
                                  ),
                                ],
                              );
                            }),
                ),
                if (_error == null)
                  BasakButton(
                    key: const Key('photo-confirm'),
                    label: 'اعتماد الصورة',
                    icon: LucideIcons.check,
                    loading: _saving,
                    onPressed: image == null ? null : () => _confirm(_viewport, _baseScale),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Covers everything outside the circle the photo will be shown in, so the
/// circle is all there is to frame.
class _CircleMask extends CustomPainter {
  final Color outside;
  final Color ring;

  const _CircleMask({required this.outside, required this.ring});

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(circle), Path()..addOval(circle)),
      Paint()..color = outside,
    );
    canvas.drawOval(
      circle.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(covariant _CircleMask old) => old.outside != outside || old.ring != ring;
}

/// Camera or photos: the sheet every profile photo starts from.
abstract final class PhotoSourceSheet {
  static Future<ImageSource?> show(BuildContext context) => BasakSheet.show<ImageSource>(
        context,
        title: 'صورة الحساب',
        largeTitle: true,
        builder: (sheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: BasakSpace.s6),
            SheetActionRow(
              key: const Key('photo-source-camera'),
              icon: LucideIcons.camera,
              label: 'التقاط صورة بالكاميرا',
              onTap: () => Navigator.pop(sheet, ImageSource.camera),
            ),
            const SizedBox(height: BasakSpace.s8),
            SheetActionRow(
              key: const Key('photo-source-gallery'),
              icon: LucideIcons.image,
              label: 'اختيار من الصور',
              onTap: () => Navigator.pop(sheet, ImageSource.gallery),
            ),
            const SizedBox(height: BasakSpace.s20),
            Text('صورة واضحة لوجهك: المشرف يطابقها عند الصعود.',
                style: sheet.text.label.copyWith(color: sheet.colors.ink3, fontWeight: FontWeight.w400)),
            const SizedBox(height: BasakSpace.s6),
          ],
        ),
      );
}
