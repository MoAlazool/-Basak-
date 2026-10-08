import 'package:flutter/material.dart';

/// The WhatsApp mark, drawn as a path so it stays sharp at any size and needs
/// no image file. [size] is its width and height.
class WhatsAppIcon extends StatelessWidget {
  final double size;
  final Color color;

  const WhatsAppIcon({super.key, this.size = 20, this.color = Colors.white});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _WhatsAppPainter(color));
}

class _WhatsAppPainter extends CustomPainter {
  final Color color;
  const _WhatsAppPainter(this.color);

  // The mark on a 24 x 24 grid.
  static final Path _mark = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(17.472, 14.382)
      ..relativeCubicTo(-0.297, -0.149, -1.758, -0.867, -2.03, -0.967)
      ..relativeCubicTo(-0.273, -0.099, -0.471, -0.148, -0.67, 0.15)
      ..relativeCubicTo(-0.197, 0.297, -0.767, 0.966, -0.94, 1.164)
      ..relativeCubicTo(-0.173, 0.199, -0.347, 0.223, -0.644, 0.075)
      ..relativeCubicTo(-0.297, -0.15, -1.255, -0.463, -2.39, -1.475)
      ..relativeCubicTo(-0.883, -0.788, -1.48, -1.761, -1.653, -2.059)
      ..relativeCubicTo(-0.173, -0.297, -0.018, -0.458, 0.13, -0.606)
      ..relativeCubicTo(0.134, -0.133, 0.298, -0.347, 0.446, -0.52)
      ..relativeCubicTo(0.149, -0.174, 0.198, -0.298, 0.298, -0.497)
      ..relativeCubicTo(0.099, -0.198, 0.05, -0.371, -0.025, -0.52)
      ..relativeCubicTo(-0.075, -0.149, -0.669, -1.612, -0.916, -2.207)
      ..relativeCubicTo(-0.242, -0.579, -0.487, -0.5, -0.669, -0.51)
      ..relativeCubicTo(-0.173, -0.008, -0.371, -0.01, -0.57, -0.01)
      ..relativeCubicTo(-0.198, 0.0, -0.52, 0.074, -0.792, 0.372)
      ..relativeCubicTo(-0.272, 0.297, -1.04, 1.016, -1.04, 2.479)
      ..relativeCubicTo(0.0, 1.462, 1.065, 2.875, 1.213, 3.074)
      ..relativeCubicTo(0.149, 0.198, 2.096, 3.2, 5.077, 4.487)
      ..relativeCubicTo(0.709, 0.306, 1.262, 0.489, 1.694, 0.625)
      ..relativeCubicTo(0.712, 0.227, 1.36, 0.195, 1.871, 0.118)
      ..relativeCubicTo(0.571, -0.085, 1.758, -0.719, 2.006, -1.413)
      ..relativeCubicTo(0.248, -0.694, 0.248, -1.289, 0.173, -1.413)
      ..relativeCubicTo(-0.074, -0.124, -0.272, -0.198, -0.57, -0.347)
      ..relativeMoveTo(-5.421, 7.403)
      ..relativeLineTo(-0.004, 0)
      ..relativeArcToPoint(const Offset(-5.031, -1.378), radius: const Radius.elliptical(9.87, 9.87), rotation: 0.0, largeArc: false, clockwise: true)
      ..relativeLineTo(-0.361, -0.214)
      ..relativeLineTo(-3.741, 0.982)
      ..relativeLineTo(0.998, -3.648)
      ..relativeLineTo(-0.235, -0.374)
      ..relativeArcToPoint(const Offset(-1.51, -5.26), radius: const Radius.elliptical(9.86, 9.86), rotation: 0.0, largeArc: false, clockwise: true)
      ..relativeCubicTo(0.001, -5.45, 4.436, -9.884, 9.888, -9.884)
      ..relativeCubicTo(2.64, 0.0, 5.122, 1.03, 6.988, 2.898)
      ..relativeArcToPoint(const Offset(2.893, 6.994), radius: const Radius.elliptical(9.825, 9.825), rotation: 0.0, largeArc: false, clockwise: true)
      ..relativeCubicTo(-0.003, 5.45, -4.437, 9.884, -9.885, 9.884)
      ..relativeMoveTo(8.413, -18.297)
      ..arcToPoint(const Offset(12.05, 0.0), radius: const Radius.elliptical(11.815, 11.815), rotation: 0.0, largeArc: false, clockwise: false)
      ..cubicTo(5.495, 0.0, 0.16, 5.335, 0.157, 11.892)
      ..relativeCubicTo(0.0, 2.096, 0.547, 4.142, 1.588, 5.945)
      ..lineTo(0.057, 24.0)
      ..relativeLineTo(6.305, -1.654)
      ..relativeArcToPoint(const Offset(5.683, 1.448), radius: const Radius.elliptical(11.882, 11.882), rotation: 0.0, largeArc: false, clockwise: false)
      ..relativeLineTo(0.005, 0)
      ..relativeCubicTo(6.554, 0.0, 11.89, -5.335, 11.893, -11.893)
      ..relativeArcToPoint(const Offset(-3.48, -8.413), radius: const Radius.elliptical(11.821, 11.821), rotation: 0.0, largeArc: false, clockwise: false)
      ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(_mark, Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_WhatsAppPainter old) => old.color != color;
}
