import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'basak_page.dart';
import 'pay.dart';
import 'status_chip.dart';
import 'tokens.dart';

/// The heading of the subscribe builder's open step: its number in a teal
/// ring and what is being picked. The options follow it directly on the ground.
class BuilderStepHead extends StatelessWidget {
  final int step;
  final String title;

  const BuilderStepHead({super.key, required this.step, required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Semantics(
      header: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s4),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: colors.teal, width: 2)),
                child: Text('$step',
                    textScaler: TextScaler.noScaling,
                    style: text.label.copyWith(color: colors.teal, fontWeight: FontWeight.w600, height: 1)),
              ),
              const SizedBox(width: BasakSpace.s12),
              Expanded(child: Text(title, style: text.headline)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A transport company to choose: its initial in a tile, its name and how
/// many lines it runs to the student's university.
class CompanyRow extends StatelessWidget {
  final String name;

  /// "4 خطوط إلى جامعتك".
  final String caption;
  final VoidCallback? onTap;

  const CompanyRow({super.key, required this.name, required this.caption, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // The name's own first letter, not the article's: "النورس" reads "ن".
    final bare = name.trim().replaceFirst(RegExp('^ال(?=.)'), '');
    final initial = bare.isEmpty ? '' : bare.characters.first;
    return BasakPressable(
      onTap: onTap,
      child: BasakCard(
        padding: const EdgeInsetsDirectional.all(BasakSpace.s16),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: colors.avatarTint, borderRadius: BasakRadius.all(BasakRadius.small)),
                child: Text(initial,
                    textScaler: TextScaler.noScaling,
                    style: text.headline.copyWith(fontSize: 18, color: colors.teal)),
              ),
            ),
            const SizedBox(width: BasakSpace.s14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.headline),
                  Text(caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400)),
                ],
              ),
            ),
            const SizedBox(width: BasakSpace.s8),
            Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 20, color: colors.ink3),
          ],
        ),
      ),
    );
  }
}

/// A tag that stands on the top edge of a tile: solid, so it reads over the
/// ground and the tile alike.
class _EdgeTag extends StatelessWidget {
  final String label;
  final BasakTone tone;

  const _EdgeTag(this.label, this.tone);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 9, vertical: 1),
      decoration: BoxDecoration(color: tone.foreground(colors), borderRadius: BasakRadius.all(BasakRadius.tag)),
      child: Text(label,
          maxLines: 1,
          style: context.text.tab.copyWith(color: colors.surface, fontWeight: FontWeight.w500, height: 18 / 11)),
    );
  }
}

/// A period on sale as a tile: its name, its price set large and the currency
/// under it. One tile fills the row; several sit in a [ChoiceGrid].
class PeriodTile extends StatelessWidget {
  final String label;

  /// The number alone ("4,500").
  final String amount;
  final String unit;
  final bool selected;
  final VoidCallback? onTap;

  /// On the tile's top edge: "وفّر 1,000".
  final String? tag;
  final BasakTone tagTone;

  const PeriodTile({
    super.key,
    required this.label,
    required this.amount,
    this.unit = 'ج.م',
    required this.selected,
    required this.onTap,
    this.tag,
    this.tagTone = BasakTone.success,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return BasakPressable(
      onTap: onTap,
      selected: selected,
      selectionHaptic: true,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.passthrough,
        children: [
          AnimatedContainer(
            duration: BasakMotion.fade,
            curve: BasakMotion.fadeCurve,
            padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.s6, BasakSpace.s18, BasakSpace.s6, BasakSpace.s14),
            decoration: BoxDecoration(
              color: selected ? colors.tealTint : colors.surface,
              borderRadius: BasakRadius.all(BasakSpace.s18),
              border: Border.all(color: selected ? colors.teal : Colors.transparent, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.label.copyWith(color: selected ? colors.teal : colors.ink2)),
                const SizedBox(height: BasakSpace.s4),
                // A price is never cut short: it shrinks to the tile instead.
                FittedBox(fit: BoxFit.scaleDown, child: Text(amount, maxLines: 1, style: text.sheetTitle)),
                const SizedBox(height: BasakSpace.s4),
                Text(unit, maxLines: 1, style: text.tab.copyWith(color: colors.ink3)),
              ],
            ),
          ),
          if (tag != null)
            PositionedDirectional(
              top: -10,
              start: 0,
              end: 0,
              child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: _EdgeTag(tag!, tagTone))),
            ),
        ],
      ),
    );
  }
}

/// A period as a row of a list: its name and one tag, a line under it, the
/// price at the end. The list form of [PeriodTile], used where the one-day
/// cash subscription is among the choices.
class PeriodRow extends StatelessWidget {
  final String title;
  final String? caption;

  /// The number alone ("4,500").
  final String amount;
  final String unit;
  final bool selected;
  final VoidCallback? onTap;
  final String? tag;
  final BasakTone tagTone;

  const PeriodRow({
    super.key,
    required this.title,
    this.caption,
    required this.amount,
    this.unit = 'ج.م',
    required this.selected,
    required this.onTap,
    this.tag,
    this.tagTone = BasakTone.success,
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
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s12),
        decoration: BoxDecoration(
          color: selected ? colors.tealTint : colors.surface,
          borderRadius: BasakRadius.all(BasakRadius.card),
          border: Border.all(color: selected ? colors.teal : Colors.transparent, width: 2),
          boxShadow: selected ? null : BasakShadow.card,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: BasakSpace.s8,
                    runSpacing: BasakSpace.s4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(title, style: text.rowTitle),
                      if (tag != null) BasakTag(tag!, tone: tagTone),
                    ],
                  ),
                  if (caption != null)
                    Text(caption!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400)),
                ],
              ),
            ),
            const SizedBox(width: BasakSpace.s12),
            Text.rich(
              TextSpan(
                style: text.headline,
                children: [
                  TextSpan(text: amount),
                  TextSpan(text: ' $unit', style: text.caption.copyWith(color: colors.ink3)),
                ],
              ),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet alternative under a set of tiles: a sentence and its price on a
/// sunken row ("أو يوم واحد، نقداً في الباص · 60 ج.م").
class QuietPriceRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const QuietPriceRow({super.key, required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return BasakPressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s8),
        decoration: BoxDecoration(color: colors.sunken, borderRadius: BasakRadius.all(BasakRadius.control)),
        child: Row(
          children: [
            Expanded(child: Text(label, style: text.bodySmall)),
            const SizedBox(width: BasakSpace.s12),
            Text(value, maxLines: 1, style: text.bodySmall.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// A boarding stop on the route rail of the station sheet. Closed, it shows
/// only when the first bus passes; the selected stop opens in place to list
/// every pass time, so a row's length never depends on how many trips run.
class StationRow extends StatelessWidget {
  final String name;

  /// "من 6:15 ص". Shown while the row is closed.
  final String? firstPass;

  /// "يمرّ الباص صباحاً". Shown over [allPasses] while the row is selected.
  final String passesCaption;

  /// "6:38 · 7:23 · 8:08 ص".
  final String allPasses;
  final bool selected;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onTap;

  const StationRow({
    super.key,
    required this.name,
    this.firstPass,
    this.passesCaption = 'يمرّ الباص',
    this.allPasses = '',
    required this.selected,
    this.isFirst = false,
    this.isLast = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final enabled = onTap != null;
    Widget rail(bool hidden) => Container(width: 2, color: hidden ? Colors.transparent : colors.grabber);

    return BasakPressable(
      onTap: onTap,
      selected: selected,
      selectionHaptic: true,
      child: AnimatedContainer(
        duration: BasakMotion.fade,
        curve: BasakMotion.fadeCurve,
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s12),
        decoration: BoxDecoration(
          color: selected ? colors.tealTint : null,
          borderRadius: BasakRadius.all(BasakRadius.small),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: SizedBox(
                  width: 14,
                  child: Column(
                    children: [
                      SizedBox(height: 19, child: rail(isFirst)),
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: selected ? colors.teal : colors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: selected ? colors.teal : colors.disabled, width: 2),
                        ),
                      ),
                      Expanded(child: rail(isLast)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: BasakSpace.s12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(vertical: 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: text.rowTitle.copyWith(
                                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                    color: enabled ? colors.ink : colors.ink3)),
                          ),
                          if (!selected && firstPass != null) ...[
                            const SizedBox(width: BasakSpace.s12),
                            Padding(
                              padding: const EdgeInsetsDirectional.only(top: 3),
                              child: Text(firstPass!,
                                  maxLines: 1,
                                  style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400)),
                            ),
                          ],
                        ],
                      ),
                      if (selected && allPasses.isNotEmpty) ...[
                        const SizedBox(height: BasakSpace.s6),
                        Text(passesCaption, style: text.caption.copyWith(color: colors.ink2)),
                        Text(allPasses,
                            style: text.bodySmall.copyWith(color: colors.teal, fontWeight: FontWeight.w500)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One fact of a review sheet: its name at the start, its value at the end,
/// on the sheet's own white. Rows are parted by a hairline.
class ReviewRow extends StatelessWidget {
  final String label;
  final String value;

  const ReviewRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Container(
      constraints: const BoxConstraints(minHeight: BasakSpace.tapTarget),
      padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.hairline))),
      child: Row(
        children: [
          Text(label, style: text.bodySmall.copyWith(color: colors.ink2)),
          const SizedBox(width: BasakSpace.s12),
          Expanded(
            child: Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: text.body.copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

/// What a review sheet asks for, said once: "المبلغ" and the amount, 26 / 36.
/// [money] is what `formatMoney` returns.
class ReviewAmount extends StatelessWidget {
  final String label;
  final String money;
  final Key? moneyKey;

  const ReviewAmount({super.key, this.label = 'المبلغ', required this.money, this.moneyKey});

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        children: [
          Text(label, style: text.body.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(width: BasakSpace.s12),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              // An amount is never cut short: it shrinks to the row instead.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: MoneyText(money,
                    key: moneyKey, style: text.title.copyWith(fontSize: 26, height: 36 / 26), unitSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
