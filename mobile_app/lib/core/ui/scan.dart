import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'facts.dart';
import 'status_chip.dart';
import 'tokens.dart';

/// What the supervisor's scanner is made of besides the glass controls of
/// `ScanChrome` (boards `SupScan`, `SupScanOk`, `SupScanStop`, `SupScanStates`,
/// `SupScanOffline`, `SupScanPermission`).

/// The dark surface behind the scanner's controls while there is no camera
/// picture to show: before the camera starts, and where it cannot run.
class ScanBackdrop extends StatelessWidget {
  final Widget? child;

  const ScanBackdrop({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-.4, -.64),
          radius: 1.2,
          colors: [colors.scanGlow, Color.lerp(colors.scanGlow, colors.scanBase, .7)!, colors.scanBase],
          stops: const [0, .55, 1],
        ),
      ),
      child: child,
    );
  }
}

/// The viewfinder: four corners. White while it waits, mint for a boarding,
/// [BasakColors.refusedFrame] for a scan that was not recorded. It takes the
/// room it is given, up to 248.
class ScanFrame extends StatelessWidget {
  /// Defaults to white.
  final Color? color;

  /// A code is being checked: a spinner in the middle.
  final bool busy;

  const ScanFrame({super.key, this.color, this.busy = false});

  static const double size = 248;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = math.max(120.0, math.min(size, math.min(constraints.maxWidth, constraints.maxHeight)));
          return TweenAnimationBuilder<Color?>(
            duration: BasakMotion.fade,
            tween: ColorTween(end: color ?? colors.onInk),
            builder: (context, value, child) => CustomPaint(
              painter: _Corners(value ?? colors.onInk),
              child: SizedBox.square(dimension: side, child: child),
            ),
            child: busy
                ? Center(
                    child: SizedBox.square(
                      dimension: 32,
                      child: CircularProgressIndicator(strokeWidth: 3, color: colors.onInk),
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }
}

class _Corners extends CustomPainter {
  final Color color;

  const _Corners(this.color);

  static const _arm = 46.0;
  static const _radius = 26.0;
  static const _stroke = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    const inset = _stroke / 2;
    final w = size.width, h = size.height;
    // One corner, drawn at the top left, then mirrored into the other three.
    Path corner() => Path()
      ..moveTo(inset, _arm)
      ..lineTo(inset, _radius)
      ..arcToPoint(const Offset(_radius, inset), radius: const Radius.circular(_radius - inset))
      ..lineTo(_arm, inset);
    for (final (sx, sy) in const [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)]) {
      canvas
        ..save()
        ..translate(sx < 0 ? w : 0, sy < 0 ? h : 0)
        ..scale(sx, sy)
        ..drawPath(corner(), paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_Corners old) => old.color != color;
}

/// Said on the camera before anything is scanned: there is no connection, so
/// a scan shows saved details and records nothing. [lead] is set heavier.
class ScanNotice extends StatelessWidget {
  final String lead;
  final String message;

  const ScanNotice({super.key, required this.lead, required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = context.text.label.copyWith(color: colors.warning, fontWeight: FontWeight.w400);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s10),
        decoration: BoxDecoration(color: colors.warningTint, borderRadius: BasakRadius.all(BasakRadius.small)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(top: BasakSpace.s2),
              child: Icon(LucideIcons.wifiOff, size: 16, color: colors.warning),
            ),
            const SizedBox(width: BasakSpace.s10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: lead, style: style.copyWith(fontWeight: FontWeight.w600)),
                  TextSpan(text: ' $message'),
                ]),
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The last boarding, at the bottom of the camera: a tick, who, and when.
/// A tap opens that result again.
class ScanLastRow extends StatelessWidget {
  /// "آخر صعود: يوسف طارق حسن".
  final String label;

  /// Already formatted with `BasakUi.time12`.
  final String time;
  final VoidCallback? onTap;

  const ScanLastRow({super.key, required this.label, required this.time, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return BasakPressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s8),
        decoration: BoxDecoration(color: colors.scanGlass, borderRadius: BasakRadius.all(BasakRadius.control)),
        child: Row(
          children: [
            Icon(LucideIcons.check, size: 16, color: colors.mint),
            const SizedBox(width: BasakSpace.s10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.label.copyWith(color: colors.onInk, fontWeight: FontWeight.w400),
              ),
            ),
            const SizedBox(width: BasakSpace.s10),
            Text(time, style: text.label.copyWith(color: colors.onInk2, fontWeight: FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}

/// The scanner without a camera to show: what is missing, one sentence, the
/// way to fix it and a quieter second way. Fills the scanner's page.
class ScanGate extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Room left free under the actions (the floating tab bar).
  final double bottomInset;

  const ScanGate({
    super.key,
    this.icon = LucideIcons.camera,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.primaryIcon,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.bottomInset = BasakSpace.s24,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return ColoredBox(
      color: colors.scanPanel,
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(BasakSpace.gutter, BasakSpace.s12, BasakSpace.gutter, bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ExcludeSemantics(
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: colors.scanGlass,
                                  borderRadius: BasakRadius.all(BasakSpace.s24),
                                ),
                                child: Icon(icon, size: 30, color: colors.onInk),
                              ),
                            ),
                            const SizedBox(height: BasakSpace.s20),
                            Semantics(
                              header: true,
                              child: Text(title,
                                  textAlign: TextAlign.center, style: text.title.copyWith(color: colors.onInk)),
                            ),
                            const SizedBox(height: BasakSpace.s12),
                            Text(message,
                                textAlign: TextAlign.center, style: text.body.copyWith(color: colors.onInk2)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (primaryLabel != null) BasakButton(label: primaryLabel!, icon: primaryIcon, onPressed: onPrimary),
                  if (secondaryLabel != null) ...[
                    const SizedBox(height: BasakSpace.s8),
                    BasakPressable(
                      onTap: onSecondary,
                      child: Center(
                        child: Text(
                          secondaryLabel!,
                          style: text.body.copyWith(color: colors.onInk, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One fact of a [PersonFacts] block.
class PersonFact {
  final String label;
  final String value;

  /// Phone numbers and times read left to right.
  final bool ltr;

  /// Colours the value: a subscription that is not valid.
  final BasakTone? tone;

  const PersonFact(this.label, this.value, {this.ltr = false, this.tone});
}

/// Who a scan found, inside its result sheet: their photo (or the first letter
/// of the name in a circle when there is none), the name, one line under it,
/// then the facts the supervisor may need to explain the result.
class PersonFacts extends StatelessWidget {
  final String name;
  final String? caption;
  final List<PersonFact> facts;

  /// The person's photo, drawn large enough to compare with a face; without
  /// one, the first letter of the name.
  final ImageProvider? photo;

  const PersonFacts({super.key, required this.name, this.caption, this.facts = const [], this.photo});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16),
      decoration: BoxDecoration(color: colors.ground, borderRadius: BasakRadius.all(BasakRadius.control)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s12),
            child: Row(
              children: [
                PhotoRing(key: const Key('person-photo'), name: name, image: photo, size: photo == null ? 44 : 84),
                const SizedBox(width: BasakSpace.s12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.rowTitle),
                      if (caption != null && caption!.isNotEmpty)
                        Text(
                          caption!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final fact in facts) ...[
            Divider(height: 1, thickness: 1, color: colors.hairline),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 46),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s8),
                child: Row(
                  children: [
                    Text(fact.label, style: text.bodySmall.copyWith(color: colors.ink2)),
                    const SizedBox(width: BasakSpace.s12),
                    Expanded(
                      child: Text(
                        fact.value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textDirection: fact.ltr ? TextDirection.ltr : null,
                        // A left-to-right value still sits at the row's end edge.
                        textAlign: fact.ltr && Directionality.of(context) == TextDirection.rtl
                            ? TextAlign.start
                            : TextAlign.end,
                        style: text.body.copyWith(
                          fontWeight: FontWeight.w500,
                          color: fact.tone?.foreground(colors),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Under the button of a result that closes itself: a thin bar that fills
/// over [duration], and what happens when it is full. [onDone] runs once.
class AutoReturnBar extends StatefulWidget {
  final Duration duration;
  final String label;
  final VoidCallback onDone;

  const AutoReturnBar({
    super.key,
    this.duration = BasakMotion.boardedResult,
    this.label = 'يعود للمسح تلقائياً',
    required this.onDone,
  });

  @override
  State<AutoReturnBar> createState() => _AutoReturnBarState();
}

class _AutoReturnBarState extends State<AutoReturnBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    })
    ..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => BasakBar(value: _controller.value, height: 4, color: colors.success),
          ),
        ),
        const SizedBox(width: BasakSpace.s10),
        Text(widget.label, style: context.text.caption.copyWith(color: colors.ink3)),
      ],
    );
  }
}
