import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'basak_page.dart';
import 'facts.dart';
import 'pass_card.dart';
import 'status_chip.dart';
import 'tokens.dart';

/// What the pay screen, the subscription tab and the receipt are composed of
/// (boards Pay, PayUpload, PayDone, Subscription*, Receipt).

/// An amount: the number in [style], its currency after it, small and quiet.
/// [money] is what `formatMoney` returns ("4,500 ج.م").
class MoneyText extends StatelessWidget {
  final String money;
  final TextStyle style;

  /// The currency's size: 16 beside the page's one amount, 13 inside a card.
  final double unitSize;
  final bool onInk;

  const MoneyText(this.money, {super.key, required this.style, this.unitSize = 13, this.onInk = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cut = money.lastIndexOf(' ');
    final number = cut < 0 ? money : money.substring(0, cut);
    final unit = cut < 0 ? '' : money.substring(cut + 1);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: unit.isEmpty ? number : '$number '),
          if (unit.isNotEmpty)
            TextSpan(
              text: unit,
              style: TextStyle(
                  fontSize: unitSize, fontWeight: FontWeight.w400, color: onInk ? colors.onInk2 : colors.ink3),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// How far a period has run: a thin bar over its first and last day.
class ValidityBar {
  /// From 0 to 1.
  final double elapsed;
  final String from;
  final String to;

  const ValidityBar({required this.elapsed, required this.from, required this.to});
}

/// The card a subscription opens its tab with: the status and the year, the
/// period's name with one fact beside it, and under them whichever applies —
/// the validity bar of a running period, or what is due with its button.
/// Ink while the subscription is valid today, light otherwise.
class PeriodCard extends StatelessWidget {
  final BasakStatus status;

  /// Beside the chip: "2026 / 2027", or when the data was last read.
  final String? meta;
  final bool metaLtr;

  /// "الفصل الأول".
  final String title;

  /// Beside the title: "باقي 95 يوماً", "أُرسل اليوم 3:40 م".
  final String? note;
  final ValidityBar? bar;

  /// Under a hairline: an [AmountAction], a renewal.
  final Widget? footer;
  final bool? onInk;

  const PeriodCard({
    super.key,
    required this.status,
    this.meta,
    this.metaLtr = false,
    required this.title,
    this.note,
    this.bar,
    this.footer,
    this.onInk,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final ink = onInk ?? status == BasakStatus.active;
    final quiet = ink ? colors.onInk2 : colors.ink3;

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsetsDirectional.all(BasakSpace.s20),
        decoration: BoxDecoration(
          color: ink ? colors.ink : colors.surface,
          borderRadius: BasakRadius.all(BasakRadius.sheet),
          boxShadow: ink ? null : BasakShadow.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StatusChip(status, onInk: ink),
                const SizedBox(width: BasakSpace.s12),
                if (meta != null)
                  Expanded(
                    child: Text(
                      meta!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      textDirection: metaLtr ? TextDirection.ltr : null,
                      style: text.label.copyWith(color: ink ? colors.sky : colors.ink3, fontWeight: FontWeight.w400),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: BasakSpace.s18),
            // The name keeps its words; a long fact drops under it.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: BasakSpace.s12,
              children: [
                Text(title,
                    style: text.title
                        .copyWith(fontSize: 24, height: 34 / 24, color: ink ? colors.onInk : colors.ink)),
                if (note != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: BasakSpace.s4),
                    child: Text(note!, style: text.bodySmall.copyWith(color: ink ? colors.onInk2 : colors.ink2)),
                  ),
              ],
            ),
            if (bar != null) ...[
              const SizedBox(height: BasakSpace.s18),
              BasakBar(
                value: bar!.elapsed,
                height: 6,
                color: ink ? colors.sky : colors.teal,
                track: ink ? colors.inkRule : colors.track,
              ),
              const SizedBox(height: BasakSpace.s8),
              Row(
                children: [
                  Expanded(child: Text(bar!.from, style: text.caption.copyWith(color: quiet))),
                  Text(bar!.to, style: text.caption.copyWith(color: quiet)),
                ],
              ),
            ],
            if (footer != null) ...[
              const SizedBox(height: BasakSpace.s18),
              Divider(height: 1, thickness: 1, color: ink ? colors.inkRule : colors.hairline),
              const SizedBox(height: BasakSpace.s18),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

/// What is due and the button that pays it: "المبلغ المطلوب · 4,500 ج.م · ادفع الآن".
class AmountAction extends StatelessWidget {
  final String caption;

  /// From `formatMoney`.
  final String money;
  final String actionLabel;
  final VoidCallback? onAction;
  final Key? captionKey;
  final Key? moneyKey;
  final Key? actionKey;

  const AmountAction({
    super.key,
    required this.caption,
    required this.money,
    required this.actionLabel,
    required this.onAction,
    this.captionKey,
    this.moneyKey,
    this.actionKey,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(caption, key: captionKey, style: text.caption.copyWith(color: context.colors.ink3)),
              MoneyText(money, key: moneyKey, style: text.title),
            ],
          ),
        ),
        const SizedBox(width: BasakSpace.s12),
        BasakButton(
          key: actionKey,
          label: actionLabel,
          onPressed: onAction,
          size: BasakButtonSize.medium,
          expand: false,
        ),
      ],
    );
  }
}

/// A renewal offered in place: what would be bought, and its price, on the
/// ground's colour inside a card.
class OfferSummary extends StatelessWidget {
  final String caption;
  final String value;

  /// From `formatMoney`.
  final String money;

  const OfferSummary({super.key, required this.caption, required this.value, required this.money});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s12),
      decoration: BoxDecoration(color: colors.ground, borderRadius: BasakRadius.all(BasakRadius.control)),
      child: Row(
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
          MoneyText(money, style: text.headline, unitSize: 12),
        ],
      ),
    );
  }
}

/// An optional next step, tonal: "الفصل الثاني متاح الآن · اشترك".
class OfferCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onAction;

  const OfferCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return BasakCard(
      color: colors.tealTint,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s18, vertical: BasakSpace.s16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: text.rowTitle.copyWith(height: 24 / 16)),
                Text(subtitle, style: text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400)),
              ],
            ),
          ),
          const SizedBox(width: BasakSpace.s12),
          BasakButton(label: actionLabel, onPressed: onAction, size: BasakButtonSize.small, expand: false),
        ],
      ),
    );
  }
}

/// One value the student copies into the bank's app.
class CopyField {
  final String label;
  final String value;
  final VoidCallback onCopy;

  const CopyField({required this.label, required this.value, required this.onCopy});
}

/// Who is paid, and how: the account's holder and the method, then only the
/// values to copy, each with its own "نسخ".
class PayeeCard extends StatelessWidget {
  final String name;
  final String method;
  final List<CopyField> fields;

  const PayeeCard({super.key, required this.name, required this.method, required this.fields});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final initial = name.trim().isEmpty ? '' : name.trim().characters.first;
    return BasakCard(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration:
                        BoxDecoration(color: colors.avatarTint, borderRadius: BasakRadius.all(BasakRadius.tile)),
                    child: Text(initial,
                        textScaler: TextScaler.noScaling,
                        style: text.rowTitle.copyWith(color: colors.teal, height: 1)),
                  ),
                ),
                const SizedBox(width: BasakSpace.s12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.body.copyWith(fontWeight: FontWeight.w600, height: 22 / 15)),
                        Text(method, style: text.caption.copyWith(color: colors.ink3)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final field in fields) ...[
            Divider(height: 1, thickness: 1, color: colors.hairline),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(field.label, style: text.caption.copyWith(color: colors.ink3)),
                          // A number reads left to right, at the start edge.
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              field.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.ltr,
                              textAlign:
                                  Directionality.of(context) == TextDirection.rtl ? TextAlign.end : TextAlign.start,
                              style: text.rowTitle.copyWith(height: 24 / 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: BasakSpace.s12),
                  BasakButton(
                    label: 'نسخ',
                    icon: LucideIcons.copy,
                    onPressed: field.onCopy,
                    variant: BasakButtonVariant.secondary,
                    size: BasakButtonSize.small,
                    expand: false,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A card that folds: a glyph and a title, and under them what the title
/// promises ("قبل التحويل").
class Disclosure extends StatefulWidget {
  final IconData? icon;
  final String title;
  final Widget child;
  final bool initiallyOpen;

  const Disclosure({super.key, this.icon, required this.title, required this.child, this.initiallyOpen = true});

  @override
  State<Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<Disclosure> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return BasakCard(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BasakPressable(
            onTap: () => setState(() => _open = !_open),
            child: Semantics(
              expanded: _open,
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 17, color: colors.ink2),
                    const SizedBox(width: BasakSpace.s8),
                  ],
                  Expanded(
                    child: Text(widget.title, style: text.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Icon(_open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18, color: colors.ink3),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: BasakMotion.fade,
            curve: BasakMotion.fadeCurve,
            alignment: AlignmentDirectional.topStart,
            child: _open
                ? Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: BasakSpace.s12),
                    child: widget.child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Short instructions in order: a number, a sentence.
class NumberedList extends StatelessWidget {
  final List<String> items;

  const NumberedList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsetsDirectional.only(top: i == 0 ? 0 : BasakSpace.s6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${i + 1}', style: text.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: BasakSpace.s10),
                Expanded(child: Text(items[i], style: text.bodySmall.copyWith(color: colors.ink2))),
              ],
            ),
          ),
      ],
    );
  }
}

/// One group of a [DisclosureGroup]: its heading and its "label · value" lines.
class DisclosureSection {
  final String title;
  final List<(String label, String value, bool ltr)> rows;

  const DisclosureSection({required this.title, required this.rows});
}

/// Several groups in one card, one open at a time: the receipt's الاشتراك,
/// الطالب and الشركة.
class DisclosureGroup extends StatefulWidget {
  final List<DisclosureSection> sections;

  /// The group open at first; null: all closed.
  final int? initiallyOpen;

  const DisclosureGroup({super.key, required this.sections, this.initiallyOpen = 0});

  @override
  State<DisclosureGroup> createState() => _DisclosureGroupState();
}

class _DisclosureGroupState extends State<DisclosureGroup> {
  late int? _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return BasakCard(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.sections.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: colors.hairline),
            BasakPressable(
              onTap: () => setState(() => _open = _open == i ? null : i),
              child: Semantics(
                expanded: _open == i,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(widget.sections[i].title, style: text.rowTitle.copyWith(height: 24 / 16)),
                      ),
                      Icon(_open == i ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                          size: 18, color: colors.ink3),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: BasakMotion.fade,
              curve: BasakMotion.fadeCurve,
              alignment: AlignmentDirectional.topStart,
              child: _open != i
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: BasakSpace.s16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var r = 0; r < widget.sections[i].rows.length; r++)
                            Padding(
                              padding: EdgeInsetsDirectional.only(top: r == 0 ? 0 : BasakSpace.s12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(widget.sections[i].rows[r].$1,
                                      style: text.bodySmall.copyWith(color: colors.ink2)),
                                  const SizedBox(width: BasakSpace.s12),
                                  Expanded(
                                    child: Text(
                                      widget.sections[i].rows[r].$2,
                                      textAlign:
                                          widget.sections[i].rows[r].$3 && rtl ? TextAlign.start : TextAlign.end,
                                      textDirection: widget.sections[i].rows[r].$3 ? TextDirection.ltr : null,
                                      style: text.bodySmall.copyWith(fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
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

/// Where the receipt's picture goes: a dashed frame that states the one
/// requirement, with the two ways to bring a picture. [actions] are two
/// `BasakButton`s, laid side by side.
class UploadZone extends StatelessWidget {
  final IconData icon;

  /// Over the requirement, when the zone is the page's only section.
  final String? title;
  final String requirement;
  final List<Widget> actions;

  const UploadZone({
    super.key,
    this.icon = LucideIcons.receiptText,
    this.title,
    required this.requirement,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return CustomPaint(
      painter: _DashedFrame(color: colors.disabled, radius: BasakRadius.card),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.s16, BasakSpace.s20, BasakSpace.s16, BasakSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title == null) ...[
              ExcludeSemantics(child: Icon(icon, size: 26, color: colors.ink2)),
              const SizedBox(height: BasakSpace.s6),
            ] else ...[
              Text(title!, textAlign: TextAlign.center, style: text.body.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: BasakSpace.s4),
            ],
            Text(requirement, textAlign: TextAlign.center, style: text.bodySmall.copyWith(color: colors.ink2)),
            const SizedBox(height: BasakSpace.s14),
            Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: BasakSpace.s10),
                  Expanded(child: actions[i]),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedFrame extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedFrame({required this.color, required this.radius});

  static const _stroke = 1.5;
  static const _dash = 5.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    final frame = Path()
      ..addRRect(RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(_stroke / 2), Radius.circular(math.max(0, radius - _stroke / 2))));
    for (final metric in frame.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += _dash + _gap) {
        canvas.drawPath(metric.extractPath(at, math.min(at + _dash, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFrame old) => old.color != color || old.radius != radius;
}

/// A fact the student must read before going on, on its tone's tint: the
/// company has no transfer details yet.
class NoticeCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final BasakTone tone;

  const NoticeCard({
    super.key,
    this.icon = LucideIcons.triangleAlert,
    required this.message,
    this.tone = BasakTone.warning,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BasakCard(
      color: tone.tint(colors),
      radius: BasakRadius.control,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(top: BasakSpace.s2),
            child: Icon(icon, size: 18, color: tone.foreground(colors)),
          ),
          const SizedBox(width: BasakSpace.s12),
          Expanded(
            child: Text(message,
                style: context.text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400)),
          ),
        ],
      ),
    );
  }
}

/// Why the company refused the receipt, in its own words, and which attempt
/// that was.
class RejectionCard extends StatelessWidget {
  final String title;

  /// "المحاولة 2 من 5"; shown from the second attempt.
  final String? attempt;
  final String caption;
  final String reason;

  const RejectionCard({
    super.key,
    this.title = 'الإيصال مرفوض',
    this.attempt,
    this.caption = 'سبب الرفض من الشركة',
    required this.reason,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Semantics(
      container: true,
      liveRegion: true,
      child: BasakCard(
        color: colors.dangerTint,
        padding: const EdgeInsetsDirectional.all(BasakSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.circleX, size: 19, color: colors.danger),
                const SizedBox(width: BasakSpace.s8),
                Expanded(
                  child: Text(title, style: text.rowTitle.copyWith(color: colors.danger, height: 24 / 16)),
                ),
                if (attempt != null) ...[
                  const SizedBox(width: BasakSpace.s10),
                  Text(attempt!,
                      style: text.caption.copyWith(color: colors.danger, fontWeight: FontWeight.w500)),
                ],
              ],
            ),
            const SizedBox(height: BasakSpace.s10),
            Text(caption, style: text.caption.copyWith(color: colors.ink2)),
            const SizedBox(height: BasakSpace.s2),
            Text(reason, style: text.body),
          ],
        ),
      ),
    );
  }
}

/// A receipt on its way: what is happening now, how much of it has left the
/// phone, and the three phases on a line.
class SendProgress extends StatelessWidget {
  final String title;

  /// From 0 to 1; null while the part cannot be measured.
  final double? sent;
  final List<String> steps;
  final int current;

  const SendProgress({super.key, required this.title, required this.sent, required this.steps, required this.current});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final percent = sent == null ? null : '${(sent! * 100).round()}%';
    return Semantics(
      container: true,
      liveRegion: true,
      label: percent == null ? title : '$title $percent',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text(title, style: text.body.copyWith(fontWeight: FontWeight.w600))),
                if (percent != null)
                  Text(percent,
                      textDirection: TextDirection.ltr,
                      style: text.bodySmall.copyWith(fontWeight: FontWeight.w600, color: colors.teal)),
              ],
            ),
            const SizedBox(height: BasakSpace.s8),
            BasakBar(value: sent ?? 0, height: 6, color: colors.teal, track: colors.hairline),
            const SizedBox(height: BasakSpace.s16),
            Divider(height: 1, thickness: 1, color: colors.hairline),
            const SizedBox(height: BasakSpace.s14),
            StepLine(steps: steps, current: current),
          ],
        ),
      ),
    );
  }
}

/// A glyph on its tone's tint, 56: what a blocked page opens with.
class ToneGlyph extends StatelessWidget {
  final IconData icon;
  final BasakTone tone;

  /// 56 in a card; 88 and round for the result of a whole page.
  final bool large;

  const ToneGlyph(this.icon, {super.key, this.tone = BasakTone.danger, this.large = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = large ? 88.0 : 56.0;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tone.tint(colors),
          borderRadius: BasakRadius.all(large ? BasakRadius.full : 22),
        ),
        child: Icon(icon, size: large ? 40 : 28, color: tone.foreground(colors)),
      ),
    );
  }
}

/// The end of a flow, alone on its page: a mark, what happened, one sentence
/// about what comes next.
class ResultBody extends StatelessWidget {
  final IconData icon;
  final BasakTone tone;
  final String title;
  final String message;

  const ResultBody({
    super.key,
    this.icon = LucideIcons.check,
    this.tone = BasakTone.success,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToneGlyph(icon, tone: tone, large: true),
        const SizedBox(height: BasakSpace.s24),
        Semantics(
          header: true,
          child: Text(title,
              textAlign: TextAlign.center, style: text.display.copyWith(fontSize: 26, height: 38 / 26)),
        ),
        const SizedBox(height: BasakSpace.s8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(message,
              textAlign: TextAlign.center, style: text.body.copyWith(color: context.colors.ink2)),
        ),
      ],
    );
  }
}

/// A square 54 button holding one icon, beside a dock's primary button:
/// save as a picture, share.
class SquareIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const SquareIconButton({super.key, required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BasakPressable(
      onTap: onPressed,
      semanticLabel: label,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(color: colors.sunken, borderRadius: BasakRadius.all(BasakRadius.control)),
        child: Icon(icon, size: 20, color: onPressed == null ? colors.disabled : colors.ink),
      ),
    );
  }
}

/// The picture the student chose, large enough to recognise.
class ReceiptPreviewFrame extends StatelessWidget {
  final Widget child;
  final double height;

  const ReceiptPreviewFrame({super.key, required this.child, this.height = 150});

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: 'معاينة صورة الإيصال',
        child: ClipRRect(
          borderRadius: BasakRadius.all(BasakRadius.small),
          child: Container(height: height, width: double.infinity, color: context.colors.sunken, child: child),
        ),
      );
}
