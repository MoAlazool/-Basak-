import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'status_chip.dart';
import 'tokens.dart';

/// The route as two stacked stops on a rail: a ring where the student boards,
/// a filled dot at the university. Two long Arabic names never share a line.
class RouteRail extends StatelessWidget {
  final String from;
  final String fromCaption;
  final String to;
  final String toCaption;

  /// On the ink pass.
  final bool onInk;

  /// The boarding stop is not chosen yet: a dashed ring and rail, [from] in a
  /// quieter voice ("اختر محطتك").
  final bool fromPending;

  /// 19 / 28 names, as on the Home pass. Off: 17 / 26.
  final bool large;

  const RouteRail({
    super.key,
    required this.from,
    this.fromCaption = 'محطة الصعود',
    required this.to,
    this.toCaption = 'الجامعة',
    this.onInk = false,
    this.fromPending = false,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final stop = onInk ? colors.sky : colors.teal;
    final rule = fromPending ? colors.grabber : (onInk ? colors.inkRule : colors.track);
    final caption = text.caption.copyWith(color: onInk ? colors.onInk2 : colors.ink3);
    final name = (large ? text.headline.copyWith(fontSize: 19, height: 28 / 19) : text.headline)
        .copyWith(color: onInk ? colors.onInk : colors.ink);
    final lead = large ? 9.0 : 8.0;

    Widget names(String title, String sub, {bool pending = false}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: pending ? name.copyWith(color: colors.ink3, fontWeight: FontWeight.w500) : name,
            ),
            Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: caption),
          ],
        );

    return Semantics(
      container: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 10,
                  child: Column(
                    children: [
                      SizedBox(height: lead),
                      CustomPaint(
                        size: const Size.square(10),
                        painter: _RingPainter(fromPending ? colors.disabled : stop, dashed: fromPending),
                      ),
                      Expanded(child: _RailLine(color: rule, dashed: fromPending)),
                    ],
                  ),
                ),
                const SizedBox(width: BasakSpace.s14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: BasakSpace.s12),
                    child: names(from, fromCaption, pending: fromPending),
                  ),
                ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 10,
                child: Column(
                  children: [
                    SizedBox(height: lead, child: _RailLine(color: rule, dashed: fromPending)),
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: stop, shape: BoxShape.circle)),
                  ],
                ),
              ),
              const SizedBox(width: BasakSpace.s14),
              Expanded(child: names(to, toCaption)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RailLine extends StatelessWidget {
  final Color color;
  final bool dashed;

  const _RailLine({required this.color, required this.dashed});

  @override
  Widget build(BuildContext context) => dashed
      ? CustomPaint(painter: _DashPainter(color, Axis.vertical, thickness: 2), child: const SizedBox(width: 2))
      : Container(width: 2, color: color);
}

class _RingPainter extends CustomPainter {
  final Color color;
  final bool dashed;

  const _RingPainter(this.color, {this.dashed = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = (Offset.zero & size).deflate(1);
    if (!dashed) {
      canvas.drawOval(rect, paint);
      return;
    }
    const segments = 6;
    const sweep = 6.283185307179586 / segments;
    for (var i = 0; i < segments; i++) {
      canvas.drawArc(rect, i * sweep, sweep * .55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color || old.dashed != dashed;
}

class _DashPainter extends CustomPainter {
  final Color color;
  final Axis axis;
  final double thickness;

  const _DashPainter(this.color, this.axis, {this.thickness = 1.5});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness;
    const dash = 5.0, gap = 4.0;
    final length = axis == Axis.horizontal ? size.width : size.height;
    for (var at = 0.0; at < length; at += dash + gap) {
      final end = (at + dash).clamp(0.0, length);
      axis == Axis.horizontal
          ? canvas.drawLine(Offset(at, size.height / 2), Offset(end, size.height / 2), paint)
          : canvas.drawLine(Offset(size.width / 2, at), Offset(size.width / 2, end), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color || old.axis != axis || old.thickness != thickness;
}

/// The tear line of a ticket: a dashed rule from edge to edge with a notch in
/// the ground's colour at both ends. Lay it out edge to edge inside a clipped card.
class TicketTear extends StatelessWidget {
  final Color color;

  /// The colour of what the ticket lies on, when that is not the ground: the
  /// ink page behind the student's card.
  final Color? ground;

  const TicketTear({super.key, required this.color, this.ground});

  @override
  Widget build(BuildContext context) {
    final notch = Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(color: ground ?? context.colors.ground, shape: BoxShape.circle),
    );
    return ExcludeSemantics(
      child: SizedBox(
        height: 20,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Center(
                child: CustomPaint(
                  painter: _DashPainter(color, Axis.horizontal),
                  child: const SizedBox(height: 1.5, width: double.infinity),
                ),
              ),
            ),
            PositionedDirectional(start: -10, top: 0, child: notch),
            PositionedDirectional(end: -10, top: 0, child: notch),
          ],
        ),
      ),
    );
  }
}

/// The Home pass, always a ticket. Above the tear: the status and the route.
/// Below it, in [footer]: the one thing to do, or, when there is nothing to
/// do, the line and a shortcut to the card. Ink when the pass is valid today,
/// light otherwise.
class PassCard extends StatelessWidget {
  final BasakStatus status;

  /// "الفصل الأول". With [onPeriodTap] it opens the subscription.
  final String period;
  final VoidCallback? onPeriodTap;

  final String from;
  final String fromCaption;
  final String to;
  final String toCaption;

  /// A [PassStub], a [PassAction] or a [StepLine].
  final Widget? footer;

  /// Defaults to the status: only an active pass is ink.
  final bool? onInk;

  const PassCard({
    super.key,
    required this.status,
    required this.period,
    this.onPeriodTap,
    required this.from,
    this.fromCaption = 'محطة الصعود',
    required this.to,
    this.toCaption = 'الجامعة',
    this.footer,
    this.onInk,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final ink = onInk ?? status == BasakStatus.active;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final accent = ink ? colors.sky : colors.ink3;

    final periodLabel = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            period,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.label.copyWith(color: accent, fontWeight: FontWeight.w400),
          ),
        ),
        if (onPeriodTap != null) ...[
          const SizedBox(width: BasakSpace.s4),
          Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 16, color: accent),
        ],
      ],
    );

    return Semantics(
      container: true,
      label: 'اشتراكي: ${status.label}، $period',
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ink ? colors.ink : colors.surface,
          borderRadius: BasakRadius.all(BasakRadius.sheet),
          boxShadow: ink ? null : BasakShadow.card,
        ),
        child: Stack(
          children: [
            // The soft ring behind the top corner of a valid pass.
            if (ink)
              PositionedDirectional(
                end: -96,
                top: -118,
                child: ExcludeSemantics(
                  child: Container(
                    width: 270,
                    height: 270,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.inkRing, width: 36),
                    ),
                  ),
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.s20, BasakSpace.s20, BasakSpace.s20, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          StatusChip(status, onInk: ink),
                          const SizedBox(width: BasakSpace.s12),
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: onPeriodTap == null
                                  ? periodLabel
                                  : BasakPressable(
                                      onTap: onPeriodTap,
                                      enforceTapTarget: false,
                                      child: Padding(
                                        padding: const EdgeInsetsDirectional.symmetric(vertical: 5),
                                        child: periodLabel,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: BasakSpace.s16),
                      RouteRail(
                        from: from,
                        fromCaption: fromCaption,
                        to: to,
                        toCaption: toCaption,
                        onInk: ink,
                        large: true,
                      ),
                    ],
                  ),
                ),
                if (footer == null)
                  const SizedBox(height: BasakSpace.s20)
                else ...[
                  const SizedBox(height: BasakSpace.s6),
                  TicketTear(color: ink ? colors.inkRule : colors.track),
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(BasakSpace.s20, BasakSpace.s6, BasakSpace.s20, BasakSpace.s20),
                    child: footer,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The stub of a pass with nothing to do: the line, its company, and one
/// button that opens the card.
class PassStub extends StatelessWidget {
  final String line;
  final String company;
  final VoidCallback? onShowCard;
  final bool onInk;

  const PassStub({super.key, required this.line, required this.company, this.onShowCard, this.onInk = true});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: onInk ? colors.inkRaised : colors.sunken,
            borderRadius: BasakRadius.all(BasakRadius.tile),
          ),
          child: Icon(LucideIcons.bus, size: 19, color: onInk ? colors.sky : colors.teal),
        ),
        const SizedBox(width: BasakSpace.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.body.copyWith(fontWeight: FontWeight.w600, color: onInk ? colors.onInk : colors.ink),
              ),
              Text(
                company,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.caption.copyWith(color: onInk ? colors.onInk2 : colors.ink3),
              ),
            ],
          ),
        ),
        const SizedBox(width: BasakSpace.s12),
        BasakPressable(
          onTap: onShowCard,
          semanticLabel: 'عرض بطاقتي',
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: onInk ? colors.mint : colors.teal,
              borderRadius: BasakRadius.all(BasakRadius.control),
            ),
            child: Icon(LucideIcons.qrCode, size: 22, color: onInk ? colors.ink : colors.onTeal),
          ),
        ),
      ],
    );
  }
}

/// The stub of a pass that asks for something: what is due, and the button.
class PassAction extends StatelessWidget {
  final String caption;
  final String value;
  final String actionLabel;
  final VoidCallback? onAction;

  const PassAction({
    super.key,
    required this.caption,
    required this.value,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(caption, style: text.caption.copyWith(color: colors.ink3)),
              Text(value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.body.copyWith(fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const SizedBox(width: BasakSpace.s12),
        BasakButton(
          label: actionLabel,
          onPressed: onAction,
          size: BasakButtonSize.small,
          expand: false,
        ),
      ],
    );
  }
}

/// Where a request stands, as nodes on a line: passed ones are filled with a
/// check, the current one is a ring, the rest are empty.
/// ("أُرسل الإيصال" → "المراجعة" → "التفعيل"; also the upload's phases.)
class StepLine extends StatelessWidget {
  final List<String> steps;

  /// The index of the step in progress; every step before it is done.
  final int current;

  const StepLine({super.key, required this.steps, required this.current});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    Widget node(int i) {
      if (i < current) {
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: colors.teal, shape: BoxShape.circle),
          child: Icon(LucideIcons.check, size: 14, color: colors.onTeal),
        );
      }
      final now = i == current;
      return Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: now ? colors.teal : colors.grabber, width: 2),
        ),
        child: now
            ? Container(width: 8, height: 8, decoration: BoxDecoration(color: colors.teal, shape: BoxShape.circle))
            : null,
      );
    }

    TextStyle label(int i) => i < current
        ? text.caption.copyWith(fontWeight: FontWeight.w500)
        : i == current
            ? text.caption.copyWith(fontWeight: FontWeight.w600, color: colors.teal)
            : text.caption.copyWith(color: colors.ink3);

    return Semantics(
      container: true,
      label: 'حالة الطلب',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsetsDirectional.only(top: 11),
                  color: i <= current ? colors.teal : colors.track,
                ),
              ),
            SizedBox(
              width: 76,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  node(i),
                  const SizedBox(height: BasakSpace.s6),
                  Text(steps[i], textAlign: TextAlign.center, maxLines: 2, style: label(i)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
