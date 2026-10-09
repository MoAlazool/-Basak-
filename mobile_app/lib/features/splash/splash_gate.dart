import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:basak_mobile/core/ui/ui.dart';

/// The launch screen, drawn over [child], which builds underneath so the
/// session is restored while it plays: ink, the icon, the name, and a
/// three-stop rail that fills from the first stop to the last. The rail is
/// the only thing that moves; when it arrives the splash fades away (≈1.8 s).
class SplashGate extends StatefulWidget {
  final Widget child;

  const SplashGate({super.key, required this.child});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> with SingleTickerProviderStateMixin {
  static const _logoAsset = AssetImage('assets/images/basak_icon.webp');

  /// The rail travels for the first part, then the splash fades out.
  static const _travel = Interval(0, .78, curve: Curves.easeInOut);
  static const _leave = Interval(.84, 1, curve: Curves.easeOut);

  late final AnimationController _c =
      AnimationController(vsync: this, duration: BasakMotion.splash);
  bool _done = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the system "remove animations" setting.
    if (MediaQuery.of(context).disableAnimations && !_c.isCompleted) {
      _c.duration = BasakMotion.splashReduced;
    }
    // Play once the logo is decoded, so it never appears half-loaded, but
    // never hold the launch more than half a second for it.
    if (!_started) {
      _started = true;
      Future.any([
        precacheImage(_logoAsset, context),
        Future<void>.delayed(const Duration(milliseconds: 500)),
      ]).whenComplete(_play);
    }
  }

  void _play() {
    if (!mounted || _c.isAnimating || _c.isCompleted) return;
    _c.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.rtl,
      children: [
        widget.child,
        if (!_done)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final leaving = _leave.transform(_c.value);
                return IgnorePointer(
                  ignoring: leaving > .6,
                  child: Opacity(
                    opacity: 1 - leaving,
                    child: SplashView(progress: _travel.transform(_c.value)),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// What the splash looks like, apart from how it plays.
class SplashView extends StatelessWidget {
  /// How far the rail has travelled, 0 to 1.
  final double progress;

  const SplashView({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    // Material: gives the name a real text style under a bare Stack. The
    // ground is ink, so the phone's own status icons turn light over it.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: BasakChrome.onDark(),
      child: Material(
        color: colors.ink,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery.withNoTextScaling(
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BrandMark(size: 104),
                      const SizedBox(height: BasakSpace.s20),
                      Text('باصك', style: text.amount.copyWith(height: 46 / 34, color: colors.onInk)),
                      const SizedBox(height: BasakSpace.s4),
                      Text('النقل الجامعي', style: text.bodySmall.copyWith(color: colors.sky)),
                    ],
                  ),
                ),
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  bottom: 84,
                  child: Center(child: SplashRail(progress: progress)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
