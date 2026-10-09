import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'basak_page.dart';
import 'status_chip.dart';
import 'tokens.dart';

BoxDecoration _choice(BasakColors colors, {required bool selected, required Color idle, double radius = BasakRadius.control}) =>
    BoxDecoration(
      color: selected ? colors.tealTint : idle,
      borderRadius: BasakRadius.all(radius),
      border: Border.all(color: selected ? colors.teal : Colors.transparent, width: 2),
    );

/// One option of a small set, with a headline value: a period and its price,
/// a departure time.
class ChoiceTile extends StatelessWidget {
  final String label;
  final String? value;
  final bool selected;
  final VoidCallback? onTap;

  /// Under the value: "وفّر 1,000 ج.م".
  final String? tag;

  /// Sits on the ground (white) or inside a sheet or card (ground-coloured).
  final bool onCard;

  const ChoiceTile({
    super.key,
    required this.label,
    this.value,
    required this.selected,
    required this.onTap,
    this.tag,
    this.onCard = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final enabled = onTap != null;
    return BasakPressable(
      onTap: onTap,
      selected: selected,
      selectionHaptic: true,
      child: AnimatedContainer(
        duration: BasakMotion.fade,
        curve: BasakMotion.fadeCurve,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s4, vertical: BasakSpace.s12),
        decoration: _choice(colors, selected: selected, idle: onCard ? colors.ground : colors.surface),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: value == null
                  ? text.body.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: !enabled ? colors.disabled : (selected ? colors.teal : colors.ink))
                  : text.label.copyWith(color: !enabled ? colors.disabled : (selected ? colors.teal : colors.ink2)),
            ),
            if (value != null) ...[
              const SizedBox(height: BasakSpace.s4),
              Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.headline.copyWith(color: enabled ? colors.ink : colors.disabled),
              ),
            ],
            if (tag != null) ...[
              const SizedBox(height: BasakSpace.s6),
              BasakTag(tag!, tone: BasakTone.success),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lays out any number of [ChoiceTile]s: one fills the row, two sit side by
/// side, three fill one row, four or more wrap three to a row.
class ChoiceGrid extends StatelessWidget {
  final List<Widget> children;

  /// Tiles per row. Defaults to the rule above.
  final int? columns;

  const ChoiceGrid({super.key, required this.children, this.columns});

  @override
  Widget build(BuildContext context) {
    final perRow = columns ?? (children.length < 3 ? children.length.clamp(1, 2) : 3);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += perRow) {
      final slice = children.skip(i).take(perRow).toList();
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = 0; j < perRow; j++) ...[
              if (j > 0) const SizedBox(width: BasakSpace.s8),
              Expanded(child: j < slice.length ? slice[j] : const SizedBox.shrink()),
            ],
          ],
        ),
      ));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: BasakSpace.s8),
          rows[i],
        ],
      ],
    );
  }
}

/// A single-choice card with a title, a line under it and a radio at the end:
/// lines, trips, audiences. The whole card is the target.
class RadioCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  /// Beside the title: "متوقف".
  final Widget? tag;

  const RadioCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
    this.tag,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return BasakPressable(
      onTap: onTap,
      selected: selected,
      selectionHaptic: true,
      child: AnimatedContainer(
        duration: BasakMotion.fade,
        curve: BasakMotion.fadeCurve,
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s12, vertical: BasakSpace.s8),
        decoration: _choice(colors, selected: selected, idle: colors.ground),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.rowTitle.copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
                        ),
                      ),
                      if (tag != null) ...[const SizedBox(width: BasakSpace.s8), tag!],
                    ],
                  ),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400)),
                ],
              ),
            ),
            const SizedBox(width: BasakSpace.s12),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: selected ? colors.teal : null,
                shape: BoxShape.circle,
                border: selected ? null : Border.all(color: colors.disabled, width: 2),
              ),
              child: selected ? Icon(LucideIcons.check, size: 14, color: colors.onTeal) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of equal steps to pick one from: the minutes of a delay.
class ChipChoice<T> extends StatelessWidget {
  final List<T> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String Function(T) label;

  const ChipChoice({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: BasakSpace.s6),
          Expanded(
            child: BasakPressable(
              onTap: () => onChanged(options[i]),
              selected: options[i] == value,
              selectionHaptic: true,
              child: AnimatedContainer(
                duration: BasakMotion.fade,
                constraints: const BoxConstraints(minHeight: 44),
                alignment: Alignment.center,
                decoration:
                    _choice(colors, selected: options[i] == value, idle: colors.ground, radius: BasakRadius.tile),
                child: Text(
                  label(options[i]),
                  maxLines: 1,
                  style: options[i] == value
                      ? text.body.copyWith(fontWeight: FontWeight.w600, color: colors.teal)
                      : text.body.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Pill chips for a single choice among short names of any number: payment
/// methods. They wrap onto as many rows as they need.
class BasakChips<T> extends StatelessWidget {
  final List<T> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String Function(T) label;

  const BasakChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Wrap(
      spacing: BasakSpace.s8,
      runSpacing: BasakSpace.s8,
      children: [
        for (final option in options)
          BasakPressable(
            onTap: () => onChanged(option),
            selected: option == value,
            selectionHaptic: true,
            enforceTapTarget: false,
            child: AnimatedContainer(
              duration: BasakMotion.fade,
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s10),
              decoration: BoxDecoration(
                color: option == value ? colors.teal : colors.surface,
                borderRadius: BasakRadius.all(BasakRadius.full),
                border: Border.all(color: option == value ? colors.teal : colors.hairline),
              ),
              child: Text(
                label(option),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall.copyWith(
                  fontWeight: FontWeight.w500,
                  color: option == value ? colors.onTeal : colors.ink,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Two or three views of one list.
class BasakSegmented<T> extends StatelessWidget {
  final List<T> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String Function(T) label;

  const BasakSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Container(
      padding: const EdgeInsetsDirectional.all(BasakSpace.s4),
      decoration: BoxDecoration(color: colors.sunken, borderRadius: BasakRadius.all(BasakRadius.small)),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: BasakSpace.s4),
            Expanded(
              child: BasakPressable(
                onTap: () => onChanged(options[i]),
                selected: options[i] == value,
                selectionHaptic: true,
                enforceTapTarget: false,
                child: AnimatedContainer(
                  duration: BasakMotion.fade,
                  constraints: const BoxConstraints(minHeight: 40),
                  alignment: Alignment.center,
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s8),
                  decoration: BoxDecoration(
                    color: options[i] == value ? colors.surface : null,
                    borderRadius: BasakRadius.all(BasakRadius.tag),
                    boxShadow: options[i] == value ? BasakShadow.card : null,
                  ),
                  child: Text(
                    label(options[i]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: options[i] == value
                        ? text.bodySmall.copyWith(fontWeight: FontWeight.w600)
                        : text.bodySmall.copyWith(fontWeight: FontWeight.w500, color: colors.ink2),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A line on sale, with four facts in fixed places so cards compare by eye:
/// its name, how many stops, the lowest price, the first departure and the
/// last return. At most one tag.
class LineCard extends StatelessWidget {
  final String name;

  /// "7 محطات".
  final String stops;

  /// The lowest price, already formatted with `formatMoney` ("4,500").
  final String fromPrice;
  final String firstDeparture;
  final String lastReturn;
  final String? tag;
  final VoidCallback? onTap;

  /// Why the line cannot be bought ("الاشتراك مغلق حالياً"). Set by [LineCard.unavailable].
  final String? unavailableReason;

  const LineCard({
    super.key,
    required this.name,
    required this.stops,
    required this.fromPrice,
    required this.firstDeparture,
    required this.lastReturn,
    this.tag,
    required this.onTap,
  }) : unavailableReason = null;

  /// A line that is not on sale: shorter, muted, not tappable.
  const LineCard.unavailable({super.key, required this.name, required this.stops, required String reason})
      : unavailableReason = reason,
        fromPrice = '',
        firstDeparture = '',
        lastReturn = '',
        tag = null,
        onTap = null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final meta = text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400);
    const padding = EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s18, vertical: BasakSpace.s16);

    if (unavailableReason != null) {
      return Semantics(
        enabled: false,
        child: BasakCard(
          padding: padding,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.headline.copyWith(color: colors.ink3)),
                    Text('$stops · $unavailableReason', maxLines: 2, overflow: TextOverflow.ellipsis, style: meta),
                  ],
                ),
              ),
              const SizedBox(width: BasakSpace.s12),
              const BasakTag('غير متاح'),
            ],
          ),
        ),
      );
    }

    Widget fact(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s12, vertical: BasakSpace.s8),
            decoration: BoxDecoration(color: colors.ground, borderRadius: BasakRadius.all(BasakRadius.tile)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: text.tab.copyWith(color: colors.ink3)),
                Text(value, maxLines: 1, style: text.bodySmall.copyWith(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        );

    return BasakPressable(
      onTap: onTap,
      child: BasakCard(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.headline),
                      // The tag drops under the stop count when the two do not fit one line.
                      Wrap(
                        spacing: BasakSpace.s8,
                        runSpacing: BasakSpace.s4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(stops, style: meta),
                          if (tag != null) BasakTag(tag!),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: BasakSpace.s12),
                Text.rich(
                  TextSpan(
                    style: text.headline,
                    children: [
                      TextSpan(text: 'من ', style: text.caption.copyWith(color: colors.ink3)),
                      TextSpan(text: fromPrice),
                      // A no-break space: the unit never leaves its number.
                      TextSpan(text: ' ج.م', style: text.caption.copyWith(color: colors.ink3)),
                    ],
                  ),
                  maxLines: 1,
                ),
              ],
            ),
            const SizedBox(height: BasakSpace.s12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  fact('أول ذهاب', firstDeparture),
                  const SizedBox(width: BasakSpace.s8),
                  fact('آخر عودة', lastReturn),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum BuilderRowState { chosen, open, locked }

/// One step of the subscribe builder: a chosen step collapses to a line with
/// "تغيير", the open one names what is being picked, a future one is sunken.
class BuilderRow extends StatelessWidget {
  final BuilderRowState state;

  /// The step's number, shown while it is open or locked.
  final int step;

  /// What the step picks ("الخط والمحطة").
  final String title;

  /// What was picked ("الزرقا · كوبري السرو"). Chosen only.
  final String? value;

  /// Chosen only.
  final VoidCallback? onChange;

  const BuilderRow({
    super.key,
    required this.state,
    required this.step,
    required this.title,
    this.value,
    this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final badgeStyle = text.caption.copyWith(fontWeight: FontWeight.w600);

    Widget badge(Color ring, Color ink) => Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 2)),
          child: Text('$step', textScaler: TextScaler.noScaling, style: badgeStyle.copyWith(color: ink, height: 1)),
        );

    final (Widget leading, Widget body, BoxDecoration decoration, double minHeight) = switch (state) {
      BuilderRowState.chosen => (
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: colors.teal, shape: BoxShape.circle),
            child: Icon(LucideIcons.check, size: 14, color: colors.onTeal),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: text.tab.copyWith(color: colors.ink3)),
              Text(value ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.body.copyWith(fontWeight: FontWeight.w500, height: 22 / 15)),
            ],
          ),
          BoxDecoration(
            color: colors.surface,
            borderRadius: BasakRadius.all(BasakRadius.control),
            boxShadow: BasakShadow.card,
          ),
          60.0,
        ),
      BuilderRowState.open => (
          badge(colors.teal, colors.teal),
          Text(title, style: text.body.copyWith(fontWeight: FontWeight.w600, height: 22 / 15)),
          BoxDecoration(
            color: colors.surface,
            borderRadius: BasakRadius.all(BasakRadius.control),
            border: Border.all(color: colors.teal, width: 1.5),
          ),
          56.0,
        ),
      BuilderRowState.locked => (
          badge(colors.disabled, colors.ink3),
          Text(title, style: text.body.copyWith(color: colors.ink3, height: 22 / 15)),
          BoxDecoration(color: colors.sunken, borderRadius: BasakRadius.all(BasakRadius.control)),
          56.0,
        ),
    };

    return Semantics(
      enabled: state != BuilderRowState.locked,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: EdgeInsetsDirectional.only(
            start: BasakSpace.s16, end: state == BuilderRowState.chosen && onChange != null ? 0 : BasakSpace.s16),
        decoration: decoration,
        child: Row(
          children: [
            leading,
            const SizedBox(width: BasakSpace.s12),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s8),
                child: body,
              ),
            ),
            if (state == BuilderRowState.chosen && onChange != null)
              BasakButton(
                label: 'تغيير',
                onPressed: onChange,
                variant: BasakButtonVariant.quiet,
                size: BasakButtonSize.small,
                expand: false,
              ),
          ],
        ),
      ),
    );
  }
}
