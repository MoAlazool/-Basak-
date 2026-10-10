import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'status_chip.dart';
import 'tokens.dart';

/// A round photo. With [ring], a ring in the subscription's status colour
/// stands off it by a white gap. Without a photo: the name's first letter.
class PhotoRing extends StatelessWidget {
  final ImageProvider? image;

  /// The person's name; its first letter stands in for a missing photo.
  final String name;
  final double size;
  final Color? ring;

  const PhotoRing({super.key, this.image, required this.name, this.size = 44, this.ring});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final initial = name.trim().isEmpty ? '' : name.trim().characters.first;
    final photo = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colors.avatarTint, shape: BoxShape.circle),
      child: image == null
          ? Text(
              initial,
              textScaler: TextScaler.noScaling,
              style: context.text.rowTitle.copyWith(color: colors.teal, fontSize: size * 16 / 44, height: 1.2),
            )
          : Image(
              image: image!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (context, error, stack) => const SizedBox.shrink(),
            ),
    );
    return Semantics(
      image: true,
      label: 'صورة $name',
      child: ring == null
          ? photo
          : Container(
              padding: const EdgeInsetsDirectional.all(2),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring!, width: 2)),
              child: photo,
            ),
    );
  }
}

/// A card with two sides, turned over about its upright axis. [turn] runs
/// from 0 (the face) to 1 (the back); whoever owns it animates it. The face
/// decides the size and the back is laid out in the same box, so the card
/// does not change shape as it turns.
///
/// Only the side on show can be tapped or read by a screen reader. At rest
/// nothing is transformed, so the face (a QR code) is drawn exactly as it is.
/// With [fade] the sides fade into each other instead of turning: what the
/// phone's "reduce motion" asks for.
class CardFlip extends StatelessWidget {
  final double turn;
  final bool fade;
  final Widget front;
  final Widget back;

  /// A tap anywhere on the card. Not announced: the screen gives a button of
  /// its own for the same thing.
  final VoidCallback? onTap;

  /// The colour of the shadow the card throws while it is off the page.
  final Color? shadow;

  const CardFlip({
    super.key,
    required this.turn,
    required this.front,
    required this.back,
    this.fade = false,
    this.onTap,
    this.shadow,
  });

  /// How strongly the far edge recedes.
  static const double _perspective = .0012;

  @override
  Widget build(BuildContext context) {
    final t = turn.clamp(0.0, 1.0);
    final showBack = t >= .5;
    final turning = !fade && t > 0 && t < 1;
    // 0 flat on the page, 1 edge-on.
    final lift = turning ? math.sin(math.pi * t) : 0.0;

    Widget side(Widget child, {required bool shown, required double opacity}) => IgnorePointer(
          ignoring: !shown,
          child: ExcludeSemantics(excluding: !shown, child: Opacity(opacity: opacity, child: child)),
        );

    Widget card = Stack(
      children: [
        side(front, shown: !showBack, opacity: fade ? (1 - 2 * t).clamp(0.0, 1.0) : (showBack ? 0 : 1)),
        if (t > 0)
          Positioned.fill(
            child: side(
              // Seen from behind while the card turns: turned back to read true.
              turning ? Transform(alignment: Alignment.center, transform: Matrix4.rotationY(math.pi), child: back) : back,
              shown: showBack,
              opacity: fade ? (2 * t - 1).clamp(0.0, 1.0) : (showBack ? 1 : 0),
            ),
          ),
      ],
    );

    if (turning) {
      card = Transform(
        key: const Key('card-turn'),
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, _perspective)
          ..rotateY(math.pi * t)
          ..scaleByDouble(1 - .04 * lift, 1 - .04 * lift, 1, 1),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BasakRadius.all(BasakRadius.sheet),
            boxShadow: [
              BoxShadow(
                color: (shadow ?? context.colors.ink).withValues(alpha: .5 * lift),
                blurRadius: 28 * lift,
                offset: Offset(0, 14 * lift),
              ),
            ],
          ),
          child: card,
        ),
      );
    }

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// A student's college and university under their name. On one line, with a
/// dot between them, when both fit; otherwise each on a line of its own, the
/// college first. Neither is ever cut to make room for the other, and the two
/// never run into each other.
class SchoolLine extends StatelessWidget {
  final String? college;
  final String? university;

  /// Defaults to the quiet label under a name.
  final TextStyle? style;

  const SchoolLine({super.key, this.college, this.university, this.style});

  /// Between the two on one line: a middle dot with air on both sides.
  static const separator = ' · ';

  @override
  Widget build(BuildContext context) {
    final parts = [college, university].map((s) => (s ?? '').trim()).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return const SizedBox.shrink();
    final style =
        this.style ?? context.text.label.copyWith(color: context.colors.ink3, fontWeight: FontWeight.w400);

    Text line(String value, {int maxLines = 1}) =>
        Text(value, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);

    if (parts.length == 1) return line(parts.single, maxLines: 2);
    final joined = parts.join(separator);
    return LayoutBuilder(builder: (context, box) {
      final painter = TextPainter(
        text: TextSpan(text: joined, style: style),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final fits = painter.width <= box.maxWidth;
      painter.dispose();
      if (fits) return line(joined);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final part in parts) line(part)],
      );
    });
  }
}

/// Label over value, two columns: the four facts on the face of the card.
class FactGrid extends StatelessWidget {
  final List<(String label, String value)> facts;

  /// Tighter, one line per value: the card on a short phone.
  final bool dense;

  /// A small picture before a fact's value, by the fact's label (the
  /// company's mark beside its name).
  final Map<String, Widget> marks;

  const FactGrid({super.key, required this.facts, this.dense = false, this.marks = const {}});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    Widget fact((String, String) f) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(f.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.caption.copyWith(color: colors.ink3)),
            if (marks[f.$1] == null)
              Text(f.$2,
                  maxLines: dense ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.body.copyWith(fontWeight: FontWeight.w500))
            else
              Row(
                children: [
                  marks[f.$1]!,
                  const SizedBox(width: BasakSpace.s8),
                  Expanded(
                    child: Text(f.$2,
                        maxLines: dense ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.body.copyWith(fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
          ],
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < facts.length; i += 2) ...[
          if (i > 0) SizedBox(height: dense ? BasakSpace.s4 : BasakSpace.s10),
          // A last fact without a neighbour takes the whole row.
          if (i + 1 == facts.length)
            Align(alignment: AlignmentDirectional.centerStart, child: fact(facts[i]))
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: fact(facts[i])),
                const SizedBox(width: BasakSpace.s16),
                Expanded(child: fact(facts[i + 1])),
              ],
            ),
        ],
      ],
    );
  }
}

/// A strip for the one fact of the day: "رحلة اليوم · ذهاب 7:23 ص · عودة 3:30 م".
class InfoStrip extends StatelessWidget {
  final String label;
  final String value;

  /// A glyph in a small round badge at the end: the tick of a confirmed ride.
  final IconData? icon;

  /// The badge's tone on the neutral strip (success: the tick).
  final BasakTone iconTone;

  /// Tints the whole strip: the receipt fact of a subscription under review.
  final BasakTone? tone;

  /// Tighter, for the card on a short phone.
  final bool dense;

  const InfoStrip({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.iconTone = BasakTone.success,
    this.tone,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final tinted = tone != null;
    final foreground = tinted ? tone!.foreground(colors) : colors.ink;
    return Container(
      width: double.infinity,
      padding: EdgeInsetsDirectional.symmetric(
          horizontal: BasakSpace.s14, vertical: dense ? BasakSpace.s6 : BasakSpace.s10),
      decoration: BoxDecoration(
          color: tinted ? tone!.tint(colors) : colors.ground, borderRadius: BasakRadius.all(BasakRadius.small)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.caption.copyWith(color: tinted ? foreground : colors.ink3)),
                // A time is never cut short: on a narrow phone with large
                // text the line shrinks to fit instead.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(value, maxLines: 1, style: text.body.copyWith(color: foreground, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
          if (icon != null) ...[
            const SizedBox(width: BasakSpace.s12),
            ExcludeSemantics(
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                    color: tinted ? colors.surface : iconTone.tint(colors), shape: BoxShape.circle),
                child: Icon(icon, size: 14, color: tinted ? foreground : iconTone.foreground(colors)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A thin bar: a share of a whole. [value] runs from 0 to 1.
class BasakBar extends StatelessWidget {
  final double value;
  final double height;
  final Color? color;
  final Color? track;

  const BasakBar({super.key, required this.value, this.height = 8, this.color, this.track});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final share = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final radius = BasakRadius.all(height / 2);
    return ExcludeSemantics(
      child: Container(
        height: height,
        decoration: BoxDecoration(color: track ?? colors.sunken, borderRadius: radius),
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: share,
          child: Container(decoration: BoxDecoration(color: color ?? colors.teal, borderRadius: radius)),
        ),
      ),
    );
  }
}

/// A sentence first, the bar second: "صعد 14 من 38 · بقي 24".
class ProgressLine extends StatelessWidget {
  final String sentence;
  final String? trailing;
  final double value;

  const ProgressLine({super.key, required this.sentence, this.trailing, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Text(sentence, style: text.body.copyWith(fontWeight: FontWeight.w600))),
            if (trailing != null)
              Text(trailing!, style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400)),
          ],
        ),
        const SizedBox(height: BasakSpace.s8),
        BasakBar(value: value),
      ],
    );
  }
}
