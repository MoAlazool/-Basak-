import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'status_chip.dart';
import 'tokens.dart';

/// A small fact with a glyph, in a tone: the ride question's deadline
/// ("حتى 6:00 ص"), "مؤكدة", "مغلق". Not a status: that is a [StatusChip].
class IconPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final BasakTone tone;

  const IconPill({super.key, required this.icon, required this.label, this.tone = BasakTone.neutral});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = tone.foreground(colors);
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s10, vertical: 3),
      decoration: BoxDecoration(color: tone.tint(colors), borderRadius: BasakRadius.all(BasakRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.caption.copyWith(color: foreground, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// One time of a grid, or the full-width option under it ("لن أعود بالباص"):
/// 50 high, the ground's colour inside a sheet, teal-ringed when chosen.
class TimeTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// A sentence, not a time: one size down.
  final bool wide;

  const TimeTile({super.key, required this.label, required this.selected, required this.onTap, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final style = (wide ? text.body : text.rowTitle).copyWith(
      color: onTap == null ? colors.disabled : (selected ? colors.teal : colors.ink),
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    );
    return BasakPressable(
      onTap: onTap,
      selected: selected,
      selectionHaptic: true,
      child: AnimatedContainer(
        duration: BasakMotion.fade,
        curve: BasakMotion.fadeCurve,
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s4, vertical: BasakSpace.s8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.tealTint : colors.ground,
          borderRadius: BasakRadius.all(BasakRadius.small),
          border: Border.all(color: selected ? colors.teal : Colors.transparent, width: 2),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: style),
      ),
    );
  }
}

/// Any number of [TimeTile]s, three to a row, the first at the start edge.
/// One or two times still keep their third of the row.
class TimeGrid extends StatelessWidget {
  final List<Widget> children;

  const TimeGrid({super.key, required this.children});

  static const _perRow = 3;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i += _perRow) ...[
            if (i > 0) const SizedBox(height: BasakSpace.s8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < _perRow; j++) ...[
                  if (j > 0) const SizedBox(width: BasakSpace.s8),
                  Expanded(child: i + j < children.length ? children[i + j] : const SizedBox.shrink()),
                ],
              ],
            ),
          ],
        ],
      );
}

/// A caption over one value, on the ground's colour inside a card: the two
/// times of a confirmed ride.
class ValueTile extends StatelessWidget {
  final String label;
  final String value;

  const ValueTile({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s12),
      decoration: BoxDecoration(color: colors.ground, borderRadius: BasakRadius.all(BasakRadius.control)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: text.caption.copyWith(color: colors.ink3)),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.sheetTitle),
        ],
      ),
    );
  }
}

enum WeekDayMark {
  /// A ride is confirmed: filled.
  confirmed,

  /// The day being asked about: a ring.
  asked,

  /// An ordinary day.
  open,

  /// No rides that day.
  off,
}

/// The seven days of the week as letters over numbers: what is confirmed,
/// and the day the question is about.
class WeekStrip extends StatelessWidget {
  final String title;
  final List<({String letter, int day, WeekDayMark mark})> days;

  const WeekStrip({super.key, this.title = 'هذا الأسبوع', required this.days});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Semantics(
      container: true,
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: Text(title, style: text.caption.copyWith(color: colors.ink3))),
          const SizedBox(height: BasakSpace.s10),
          Row(
            children: [
              for (final day in days)
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(day.letter, style: text.tab.copyWith(color: colors.ink3)),
                      const SizedBox(height: BasakSpace.s6),
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: switch (day.mark) {
                            WeekDayMark.confirmed => colors.tealTint,
                            WeekDayMark.asked => colors.surface,
                            _ => null,
                          },
                          border: day.mark == WeekDayMark.asked ? Border.all(color: colors.teal, width: 1.5) : null,
                        ),
                        child: Text(
                          '${day.day}',
                          textScaler: TextScaler.noScaling,
                          style: text.caption.copyWith(
                            fontWeight: FontWeight.w500,
                            color: switch (day.mark) {
                              WeekDayMark.confirmed || WeekDayMark.asked => colors.teal,
                              WeekDayMark.open => colors.ink2,
                              WeekDayMark.off => colors.disabled,
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One thing a sheet states before it asks: a glyph in a small tile and a
/// sentence ("ترى الشركة اسمك وهاتفك وجامعتك وصورتك.").
class SheetPoint extends StatelessWidget {
  final IconData icon;
  final String text;

  const SheetPoint({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: colors.ground, borderRadius: BasakRadius.all(BasakRadius.tile)),
            child: Icon(icon, size: 18, color: colors.ink2),
          ),
        ),
        const SizedBox(width: BasakSpace.s12),
        Expanded(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(top: BasakSpace.s6),
            child: Text(text, style: context.text.body),
          ),
        ),
      ],
    );
  }
}

/// A secondary action of a sheet, one of a row: a teal glyph over a word
/// ("واتساب", "حفظ الرقم", "نسخ الرقم").
class ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const ActionTile({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BasakPressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s4, vertical: BasakSpace.s10),
        decoration: BoxDecoration(color: colors.ground, borderRadius: BasakRadius.all(BasakRadius.control)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: colors.teal),
            const SizedBox(height: BasakSpace.s6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: context.text.label,
            ),
          ],
        ),
      ),
    );
  }
}

/// The glyph a sheet opens with when it explains something: 64, teal on tint
/// (amber when what it says cannot wait: a required update).
class SheetGlyph extends StatelessWidget {
  final IconData icon;
  final BasakTone tone;

  const SheetGlyph(this.icon, {super.key, this.tone = BasakTone.info});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: tone.tint(context.colors), borderRadius: BasakRadius.all(22)),
          child: Icon(icon, size: 28, color: tone.foreground(context.colors)),
        ),
      );
}

/// A whole page that could not be shown: one neutral glyph, what happened,
/// one line of help and the way out. Centred; the tab bar stays.
class PageError extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  const PageError({
    super.key,
    this.icon = LucideIcons.wifiOff,
    required this.title,
    required this.message,
    this.actionLabel = 'إعادة المحاولة',
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: colors.sunken, borderRadius: BasakRadius.all(BasakSpace.s24)),
              child: Icon(icon, size: 30, color: colors.ink2),
            ),
          ),
          const SizedBox(height: 22),
          Text(title, textAlign: TextAlign.center, style: text.title),
          const SizedBox(height: BasakSpace.s8),
          Text(message, textAlign: TextAlign.center, style: text.body.copyWith(color: colors.ink2)),
          const SizedBox(height: BasakSpace.s28),
          BasakButton(label: actionLabel, icon: LucideIcons.refreshCw, onPressed: onAction, expand: false),
        ],
      ),
    );
  }
}

/// A notification that arrived while the app is open: an ink card that drops
/// from the top, over whatever is on screen. Tapping it opens what it is about.
class InkBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final VoidCallback? onTap;

  const InkBanner({super.key, required this.icon, required this.title, this.message, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return BasakPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s12),
        decoration: BoxDecoration(
          color: colors.ink,
          borderRadius: BasakRadius.all(BasakRadius.card),
          boxShadow: BasakShadow.floating,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: colors.inkRaised, borderRadius: BasakRadius.all(BasakRadius.tile)),
              child: Icon(icon, size: 19, color: colors.mint),
            ),
            const SizedBox(width: BasakSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title.isNotEmpty)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.body.copyWith(color: colors.onInk, fontWeight: FontWeight.w600),
                    ),
                  if (message != null && message!.isNotEmpty)
                    Text(
                      message!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.caption.copyWith(color: colors.onInk2),
                    ),
                ],
              ),
            ),
            const SizedBox(width: BasakSpace.s8),
            Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 18, color: colors.onInk2),
          ],
        ),
      ),
    );
  }
}

/// The quiet way out under a sheet's primary button: "ليس الآن",
/// "لن أركب غداً". 48 high, no fill.
class SheetLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  /// Teal: the link leads somewhere of its own («عرض بطاقتي») instead of
  /// only closing what asks.
  final bool accent;

  const SheetLink({super.key, required this.label, required this.onTap, this.accent = false});

  @override
  Widget build(BuildContext context) => BasakPressable(
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.body.copyWith(
                color: accent ? context.colors.teal : context.colors.ink2, fontWeight: FontWeight.w500),
          ),
        ),
      );
}
