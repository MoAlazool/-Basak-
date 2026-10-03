import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/basak_ui.dart';

/// Background shared by the native launch window, the splash and the login
/// screen, so the whole launch reads as one continuous surface.
const splashBackground = Color(0xFFF4F9FC);

/// Placed on the login screen's logo; the splash glides its logo onto it.
final GlobalKey basakLogoTargetKey = GlobalKey(debugLabel: 'basak-logo-target');

/// Launch animation (≈3.2 s) drawn over [child], which builds underneath so
/// auth restores while the logo plays:
///   0.0s icon springs in · 0.3s it settles with an impact wave at the pin tip
///   0.8s brake nudge + headlight flash · 1.2s «باصك» reveals right→left
///   1.8s shine sweeps the icon · 2.7s logo glides to the next screen's logo.
class SplashGate extends StatefulWidget {
  final Widget child;

  const SplashGate({super.key, required this.child});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> with SingleTickerProviderStateMixin {
  static const _total = 3200; // ms
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: _total));
  bool _done = false;
  Rect? _target; // login logo rect, measured when the exit starts

  // Logo-relative positions (disc centre = 0,0; edge = ±1) from the artwork.
  static const _headlights = [Offset(0.12, 0.22), Offset(0.54, 0.22)];
  static const _pinTip = Offset(-0.02, 0.85);

  @override
  void initState() {
    super.initState();
    _c.addListener(_measureTarget);
    _c.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the system "remove animations" setting.
    if (MediaQuery.of(context).disableAnimations && !_c.isCompleted) {
      _c.duration = const Duration(milliseconds: 900);
    }
  }

  void _measureTarget() {
    if (_target != null || _c.value < _t(2700)) return;
    final box = basakLogoTargetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.attached) {
      _target = box.localToGlobal(Offset.zero) & box.size;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _t(int ms) => ms / _total;

  /// Progress (0..1, curved) of a phase running from [startMs] to [endMs].
  double _phase(int startMs, int endMs, [Curve curve = Curves.linear]) {
    final v = ((_c.value - _t(startMs)) / (_t(endMs) - _t(startMs))).clamp(0.0, 1.0);
    return curve.transform(v);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.rtl,
      children: [
        widget.child,
        if (!_done)
          Positioned.fill(
            child: AnimatedBuilder(animation: _c, builder: (context, _) => _splash(context)),
          ),
      ],
    );
  }

  Widget _splash(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final logo = math.min(size.width * .42, 180.0);
    final center = Offset(size.width / 2, size.height / 2 - logo * .18);

    // 0.0–0.3 s: spring in from 0.72 scale, slightly raised.
    final appear = _phase(0, 300, Curves.easeOut);
    final spring = _phase(0, 700, Curves.elasticOut);
    // 0.3–0.8 s: settle down with a soft bounce ("pin drop").
    final drop = _phase(300, 800, Curves.bounceOut);
    // 0.8–1.2 s: brake nudge — a decaying horizontal sway.
    final brake = _phase(800, 1200);
    final sway = math.sin(brake * math.pi * 3) * (1 - brake) * logo * .035;
    // 2.7–3.2 s: glide to the next screen's logo and fade the backdrop.
    final exit = _phase(2700, 3200, Curves.easeInOutCubic);

    var scale = (.72 + .28 * spring);
    var pos = center.translate(sway, -logo * .10 * (1 - drop));
    var size0 = logo;
    if (exit > 0) {
      final target = _target;
      if (target != null) {
        pos = Offset.lerp(pos, target.center, exit)!;
        size0 = logo + (target.width - logo) * exit;
        scale = 1;
      } else {
        scale *= 1 + .15 * exit; // no logo on the next screen: gentle zoom-out
      }
    }
    final logoOpacity = _target == null ? appear * (1 - exit) : appear;

    return IgnorePointer(
      ignoring: exit > .6,
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 1 - exit,
              child: const ColoredBox(color: splashBackground),
            ),
          ),
          // Impact wave from the pin tip (0.55–1.35 s).
          _wave(pos + _pinTip * (size0 / 2) * scale, logo, _phase(550, 1350, Curves.easeOut),
              1 - exit),
          // Soft halo that breathes behind the icon.
          Positioned(
            left: pos.dx - size0 * .8,
            top: pos.dy - size0 * .8,
            width: size0 * 1.6,
            height: size0 * 1.6,
            child: Opacity(
              opacity: (appear * .9) * (1 - exit),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFF7EC8E3).withOpacity(.30 + .08 * math.sin(_c.value * math.pi * 4)),
                    const Color(0xFF7EC8E3).withOpacity(0),
                  ]),
                ),
              ),
            ),
          ),
          // The logo itself.
          Positioned(
            left: pos.dx - size0 / 2,
            top: pos.dy - size0 / 2,
            width: size0,
            height: size0,
            child: Opacity(
              opacity: logoOpacity.clamp(0.0, 1.0),
              child: Transform.scale(scale: scale, child: _logo(size0)),
            ),
          ),
          // «باصك» reveals right → left under the logo (1.2–1.8 s).
          Positioned(
            left: 0,
            right: 0,
            top: center.dy + logo * .62,
            child: Opacity(
              opacity: 1 - exit,
              child: Center(child: _name(_phase(1200, 1800, Curves.easeOutCubic))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logo(double size) {
    final flash = _phase(800, 1250);
    final flashOpacity = math.sin(flash * math.pi); // on → off
    final shine = _phase(1800, 2450, Curves.easeInOut);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF1F6F8B).withOpacity(.22),
                    blurRadius: size * .18,
                    offset: Offset(0, size * .08)),
              ],
            ),
            child: ClipOval(
              child: Stack(fit: StackFit.expand, children: [
                Image.asset('assets/images/basak_icon.png', fit: BoxFit.cover),
                // Diagonal shine sweep.
                if (shine > 0 && shine < 1)
                  FractionalTranslation(
                    translation: Offset(-1.2 + 2.4 * shine, 0),
                    child: Transform.rotate(
                      angle: -.45,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Colors.white.withOpacity(0),
                            Colors.white.withOpacity(.55),
                            Colors.white.withOpacity(0),
                          ], stops: const [.35, .5, .65]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        // Headlight flash on the logo's own bus.
        if (flashOpacity > 0)
          for (final light in _headlights)
            Positioned(
              left: size / 2 + light.dx * size / 2 - size * .09,
              top: size / 2 + light.dy * size / 2 - size * .09,
              width: size * .18,
              height: size * .18,
              child: Opacity(
                opacity: flashOpacity,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      Color(0xFFFFFBE6),
                      Color(0x99FFE9A8),
                      Color(0x00FFE9A8),
                    ], stops: [0, .35, 1]),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _wave(Offset at, double logo, double t, double opacity) {
    if (t <= 0 || t >= 1) return const SizedBox.shrink();
    final w = logo * (.25 + 1.1 * t);
    return Positioned(
      left: at.dx - w / 2,
      top: at.dy - w * .18,
      width: w,
      height: w * .36,
      child: Opacity(
        opacity: (1 - t) * .7 * opacity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.all(Radius.elliptical(w / 2, w * .18)),
            border: Border.all(color: const Color(0xFF3E8FBF), width: 2.2 * (1 - t) + .6),
          ),
        ),
      ),
    );
  }

  Widget _name(double t) => ShaderMask(
        blendMode: BlendMode.dstIn,
        // Wipe from the right edge (start of the Arabic word) to the left.
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: const [Colors.white, Colors.white, Colors.transparent, Colors.transparent],
          stops: [0, t, (t + .12).clamp(0.0, 1.0), 1],
        ).createShader(rect),
        child: Transform.translate(
          offset: Offset(-12 * (1 - t), 0),
          child: Text(
            'باصك',
            textDirection: TextDirection.rtl,
            style: AppTextStyles.displayMedium.copyWith(
                fontSize: 38, fontWeight: FontWeight.w800, color: BasakUi.ink, height: 1.1),
          ),
        ),
      );
}
