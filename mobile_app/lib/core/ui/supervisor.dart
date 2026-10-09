import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'basak_page.dart';
import 'facts.dart';
import 'pass_card.dart';
import 'status_chip.dart';
import 'tokens.dart';

/// The supervisor's set: the pieces of Home (the numbers), Trips (one trip)
/// and the scanner.

/// The two totals a day's buses are planned on. Says its day and how firm the
/// numbers are; swiped as a page, with [PagerDots] below.
class CountsHero extends StatelessWidget {
  /// "اليوم · الأحد 11 أكتوبر".
  final String day;

  /// "نهائي · أُغلق التأكيد 6:00 ص" or "التأكيد مفتوح · حتى 6:00 ص".
  final String firmness;

  /// Confirmation has closed: the numbers will not change.
  final bool isFinal;

  final int going;

  /// "في 5 رحلات".
  final String goingTrips;
  final int returning;
  final String returningTrips;

  /// "سيركب 107 من 124 مشتركاً".
  final String shareSentence;

  /// Riders ÷ subscribers, from 0 to 1.
  final double share;
  final VoidCallback? onShare;

  const CountsHero({
    super.key,
    required this.day,
    required this.firmness,
    required this.isFinal,
    required this.going,
    required this.goingTrips,
    required this.returning,
    required this.returningTrips,
    required this.shareSentence,
    required this.share,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final soft = text.caption.copyWith(color: colors.onInk2);

    Widget total(IconData icon, String label, int count, String trips) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: colors.sky),
                  const SizedBox(width: BasakSpace.s6),
                  Text(label, style: text.label.copyWith(color: colors.sky, fontWeight: FontWeight.w400)),
                ],
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text('$count', style: text.total.copyWith(color: colors.onInk)),
              ),
              Text(trips, style: soft),
            ],
          ),
        );

    final percent = '${(share.clamp(0.0, 1.0) * 100).round()}%';

    return Semantics(
      container: true,
      label: '$day: $going ذهاباً و$returning عودة',
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: colors.ink, borderRadius: BasakRadius.all(BasakRadius.sheet)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.s20, BasakSpace.s20, BasakSpace.s20, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(day,
                                style: text.rowTitle.copyWith(color: colors.onInk, height: 24 / 16)),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: isFinal ? colors.mint : colors.openDot,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: BasakSpace.s6),
                                Flexible(child: Text(firmness, style: soft)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (onShare != null) ...[
                        const SizedBox(width: BasakSpace.s10),
                        BasakPressable(
                          onTap: onShare,
                          semanticLabel: 'مشاركة الأعداد',
                          child: Center(
                            widthFactor: 1,
                            heightFactor: 1,
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 36),
                              padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s12),
                              decoration: BoxDecoration(
                                color: colors.inkRaised,
                                borderRadius: BasakRadius.all(BasakRadius.tile),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.share2, size: 15, color: colors.onInk),
                                  const SizedBox(width: BasakSpace.s6),
                                  ExcludeSemantics(
                                    child: Text('مشاركة', style: text.label.copyWith(color: colors.onInk)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: BasakSpace.s18),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        total(LucideIcons.arrowUp, 'الذهاب', going, goingTrips),
                        Container(
                          width: 1,
                          margin: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s18),
                          color: colors.inkRule,
                        ),
                        total(LucideIcons.arrowDown, 'العودة', returning, returningTrips),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: BasakSpace.s8),
            TicketTear(color: colors.inkRule),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.s20, BasakSpace.s8, BasakSpace.s20, BasakSpace.s20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(shareSentence, style: text.bodySmall.copyWith(color: colors.onInk)),
                      ),
                      Text(percent,
                          textDirection: TextDirection.ltr,
                          style: text.label.copyWith(color: colors.sky, fontWeight: FontWeight.w400)),
                    ],
                  ),
                  const SizedBox(height: BasakSpace.s8),
                  BasakBar(value: share, height: 6, color: colors.mint, track: colors.inkRule),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where a pager stands, and the tap alternative to a swipe.
class PagerDots extends StatelessWidget {
  final int count;
  final int index;
  final ValueChanged<int>? onTap;

  /// What each page is called, for screen readers ("اليوم", "غداً").
  final List<String>? labels;

  const PagerDots({super.key, required this.count, required this.index, this.onTap, this.labels});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          BasakPressable(
            onTap: onTap == null ? null : () => onTap!(i),
            semanticLabel: labels != null && i < labels!.length ? labels![i] : null,
            selected: i == index,
            enforceTapTarget: false,
            child: Padding(
              // A small dot, a comfortable target.
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 3, vertical: BasakSpace.s20),
              child: AnimatedContainer(
                duration: BasakMotion.fade,
                width: i == index ? 24 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == index ? colors.teal : colors.grabber,
                  borderRadius: BasakRadius.all(3),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

enum BarRowState {
  /// Its time has passed, by the clock.
  past,

  /// The next trip: tinted and marked.
  next,
  upcoming,
}

/// One trip in a column of Home: its time, how many ride, and a bar scaled to
/// the busiest trip of the list.
class BarRow extends StatelessWidget {
  /// Already formatted with `BasakUi.time12`.
  final String time;
  final int count;

  /// [count] ÷ the largest count in the list.
  final double share;
  final BarRowState state;
  final VoidCallback? onTap;

  /// One quiet line under the bar: the bus's seats ("45 من 50").
  final String? note;

  /// [note] is something to act on ("يحتاج باصين").
  final bool noteWarns;

  const BarRow({
    super.key,
    required this.time,
    required this.count,
    required this.share,
    this.state = BarRowState.upcoming,
    this.onTap,
    this.note,
    this.noteWarns = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final ink = switch (state) {
      BarRowState.past => colors.ink3,
      BarRowState.next => colors.teal,
      BarRowState.upcoming => colors.ink,
    };
    return BasakPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s8, vertical: 9),
        decoration: BoxDecoration(
          color: state == BarRowState.next ? colors.tealTint : null,
          borderRadius: BasakRadius.all(BasakRadius.tag),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(time,
                    maxLines: 1,
                    style: text.body.copyWith(fontWeight: FontWeight.w600, height: 22 / 15, color: ink)),
                const SizedBox(width: BasakSpace.s6),
                // The mark takes the room between the time and the count.
                Expanded(
                  child: state == BarRowState.next
                      ? Text('القادمة',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: text.tab.copyWith(fontWeight: FontWeight.w500, color: ink))
                      : const SizedBox.shrink(),
                ),
                Text('$count', style: text.headline.copyWith(height: 22 / 17, color: ink)),
              ],
            ),
            const SizedBox(height: BasakSpace.s6),
            BasakBar(
              value: share,
              height: 4,
              color: state == BarRowState.past ? colors.grabber : colors.teal,
            ),
            if (note != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(top: BasakSpace.s4),
                  child: Text(
                    note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.caption.copyWith(
                      color: noteWarns ? colors.warning : colors.ink3,
                      fontWeight: noteWarns ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A column of [BarRow]s under its heading: "الذهاب · 4 رحلات".
class BarList extends StatelessWidget {
  final String title;
  final String? trailing;
  final List<Widget> rows;

  const BarList({super.key, required this.title, this.trailing, required this.rows});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return BasakCard(
      padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.s8, BasakSpace.s14, BasakSpace.s8, BasakSpace.s8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.s8, 0, BasakSpace.s8, BasakSpace.s4),
            child: Row(
              children: [
                Expanded(child: Text(title, style: text.body.copyWith(fontWeight: FontWeight.w600))),
                if (trailing != null) Text(trailing!, style: text.caption.copyWith(color: colors.ink3)),
              ],
            ),
          ),
          ...rows,
        ],
      ),
    );
  }
}

enum StopState { done, current, upcoming }

/// A rider of a stop, as the manifest lists them.
class StopRider {
  final String name;

  /// When they boarded, already formatted; null while they have not.
  final String? boardedAt;
  final VoidCallback? onTap;

  /// A day that has not come: nobody has boarded or missed anything yet, so
  /// the row carries the name alone.
  final bool plain;

  const StopRider({required this.name, this.boardedAt, this.onTap, this.plain = false});
}

/// One stop of a trip on its rail: the stop time, how many boarded of how many
/// are expected, and — opened in place — the riders at that stop.
class StopRow extends StatelessWidget {
  final String name;

  /// Already formatted with `BasakUi.time12`.
  final String time;
  final int boarded;
  final int expected;
  final StopState state;
  final bool isFirst;
  final bool isLast;
  final bool expanded;
  final VoidCallback? onToggle;
  final List<StopRider> riders;

  /// Said in the pill instead of "boarded / expected": how many will ride
  /// from here on a day that has not come ("8"). Neutral.
  final String? countLabel;

  const StopRow({
    super.key,
    required this.name,
    required this.time,
    required this.boarded,
    required this.expected,
    required this.state,
    this.isFirst = false,
    this.isLast = false,
    this.expanded = false,
    this.onToggle,
    this.riders = const [],
    this.countLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final tone = countLabel != null
        ? BasakTone.neutral
        : boarded >= expected && expected > 0
        ? BasakTone.success
        : boarded > 0
            ? BasakTone.warning
            : BasakTone.neutral;

    final node = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: state == StopState.done ? colors.teal : colors.surface,
        shape: BoxShape.circle,
        border: switch (state) {
          StopState.done => null,
          StopState.current => Border.all(color: colors.teal, width: 3),
          StopState.upcoming => Border.all(color: colors.disabled, width: 2),
        },
      ),
    );

    Widget line(bool shown) => Container(width: 2, color: shown ? colors.grabber : Colors.transparent);

    final head = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 14,
            child: Column(
              children: [
                SizedBox(height: 21, child: line(!isFirst)),
                node,
                Expanded(child: line(!isLast || expanded)),
              ],
            ),
          ),
          const SizedBox(width: BasakSpace.s12),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.body.copyWith(fontWeight: expanded ? FontWeight.w600 : FontWeight.w500),
                  ),
                  Text(time, style: text.caption.copyWith(color: colors.ink3)),
                ],
              ),
            ),
          ),
          const SizedBox(width: BasakSpace.s12),
          Center(
            child: Container(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s10, vertical: 3),
              decoration: BoxDecoration(color: tone.tint(colors), borderRadius: BasakRadius.all(BasakRadius.full)),
              child: Text(
                countLabel ?? '$boarded / $expected',
                textDirection: TextDirection.ltr,
                style: text.label.copyWith(color: tone.foreground(colors)),
              ),
            ),
          ),
          const SizedBox(width: BasakSpace.s8),
          Center(
            child: Icon(expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18, color: colors.ink3),
          ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          expanded: expanded,
          label: countLabel != null ? '$name، $time، $countLabel' : '$name، $time، صعد $boarded من $expected',
          child: BasakPressable(onTap: onToggle, child: head),
        ),
        if (expanded && riders.isNotEmpty)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 14, child: Center(child: line(!isLast))),
                const SizedBox(width: BasakSpace.s12),
                Expanded(
                  child: Container(
                    margin: const EdgeInsetsDirectional.only(bottom: BasakSpace.s10),
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s12),
                    decoration: BoxDecoration(color: colors.ground, borderRadius: BasakRadius.all(BasakRadius.small)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < riders.length; i++) ...[
                          if (i > 0) Divider(height: 1, thickness: 1, color: colors.hairline),
                          _rider(context, riders[i]),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _rider(BuildContext context, StopRider rider) {
    final colors = context.colors;
    final text = context.text;
    final boarded = rider.boardedAt != null;
    return BasakPressable(
      onTap: rider.onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              rider.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall
                  .copyWith(fontWeight: boarded || rider.plain ? FontWeight.w400 : FontWeight.w600),
            ),
          ),
          const SizedBox(width: BasakSpace.s10),
          if (rider.plain)
            const SizedBox.shrink()
          else if (boarded) ...[
            Icon(LucideIcons.check, size: 14, color: colors.success),
            const SizedBox(width: BasakSpace.s6),
            Text(rider.boardedAt!, style: text.label.copyWith(color: colors.success)),
          ] else
            Container(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s8, vertical: BasakSpace.s2),
              decoration: BoxDecoration(color: colors.warningTint, borderRadius: BasakRadius.all(8)),
              child: Text('لم يصعد',
                  style: text.caption.copyWith(color: colors.warning, fontWeight: FontWeight.w500)),
            ),
        ],
      ),
    );
  }
}

/// One number and what it counts: "118 · طالباً مختلفاً".
class StatTile extends StatelessWidget {
  final String value;
  final String label;

  const StatTile({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) => BasakCard(
        radius: BasakRadius.control,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, maxLines: 1, style: context.text.sheetTitle),
            Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.label.copyWith(color: context.colors.ink2, fontWeight: FontWeight.w400)),
          ],
        ),
      );
}

/// A labelled bar with its value: scan results, the busiest stops.
class Meter extends StatelessWidget {
  final String label;
  final String value;

  /// From 0 to 1.
  final double share;
  final BasakTone tone;

  const Meter({super.key, required this.label, required this.value, required this.share, this.tone = BasakTone.info});

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall)),
              const SizedBox(width: BasakSpace.s12),
              Text(value, style: text.bodySmall.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: BasakSpace.s6),
          BasakBar(value: share, height: 6, color: tone.foreground(context.colors)),
        ],
      ),
    );
  }
}

/// The glass controls that sit on the live camera, and only there.
abstract final class ScanChrome {
  /// A pill at the top of the camera: the trip being boarded, the live count.
  /// With [onTap] it shows a chevron and opens the trip sheet.
  static Widget pill(
    BuildContext context, {
    required String label,
    IconData? icon,
    VoidCallback? onTap,
    String? semanticLabel,
    bool ltr = false,
  }) {
    final colors = context.colors;
    final body = Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14),
      decoration: BoxDecoration(color: colors.scanGlass, borderRadius: BasakRadius.all(BasakRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16, color: colors.onInk), const SizedBox(width: BasakSpace.s8)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: ltr ? TextDirection.ltr : null,
              style: context.text.body.copyWith(color: colors.onInk, fontWeight: FontWeight.w600),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: BasakSpace.s8),
            Icon(LucideIcons.chevronDown, size: 16, color: colors.onInk),
          ],
        ],
      ),
    );
    return onTap == null
        ? Semantics(label: semanticLabel, child: body)
        : BasakPressable(onTap: onTap, semanticLabel: semanticLabel, child: Center(widthFactor: 1, child: body));
  }

  /// A labelled control at the bottom of the camera. [on] is shown, not guessed:
  /// white when the control is active.
  static Widget toggle(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool on,
    required VoidCallback? onTap,
  }) {
    final colors = context.colors;
    final ink = on ? colors.ink : colors.onInk;
    return BasakPressable(
      onTap: onTap,
      selected: on,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s12),
        decoration: BoxDecoration(
          color: on ? colors.surface : colors.scanGlass,
          borderRadius: BasakRadius.all(BasakRadius.control),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: ink),
            const SizedBox(width: BasakSpace.s8),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall.copyWith(color: ink, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The head of a result: a badge, a title, one line. The tone follows the outcome.
class ResultHeader extends StatelessWidget {
  final BasakTone tone;
  final IconData icon;
  final String title;
  final String? message;

  const ResultHeader({super.key, required this.tone, required this.icon, required this.title, this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: tone.tint(colors), shape: BoxShape.circle),
          child: Icon(icon, size: 26, color: tone.foreground(colors)),
        ),
        const SizedBox(width: BasakSpace.s14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(header: true, child: Text(title, style: text.sheetTitle)),
              if (message != null) Text(message!, style: text.bodySmall.copyWith(color: colors.ink2)),
            ],
          ),
        ),
      ],
    );
  }
}
