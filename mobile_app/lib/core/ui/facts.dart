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

/// Label over value, two columns: the four facts on the face of the card.
class FactGrid extends StatelessWidget {
  final List<(String label, String value)> facts;

  /// Tighter, one line per value: the card on a short phone.
  final bool dense;

  const FactGrid({super.key, required this.facts, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    Widget fact((String, String) f) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(f.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.caption.copyWith(color: colors.ink3)),
            Text(f.$2,
                maxLines: dense ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: text.body.copyWith(fontWeight: FontWeight.w500)),
          ],
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < facts.length; i += 2) ...[
          if (i > 0) SizedBox(height: dense ? BasakSpace.s4 : BasakSpace.s10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: fact(facts[i])),
              const SizedBox(width: BasakSpace.s16),
              Expanded(child: i + 1 < facts.length ? fact(facts[i + 1]) : const SizedBox.shrink()),
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
