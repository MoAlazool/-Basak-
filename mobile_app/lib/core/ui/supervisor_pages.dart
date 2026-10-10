import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'basak_page.dart';
import 'tokens.dart';

/// The supervisor's pages off the tabs: a message to the students (boards
/// `SupSend`, `SupSendConfirm`, `SupSendCustom`) and the month (`SupMonthly`).

/// One of the two audiences of a message, side by side: who, and one line
/// about them. The chosen one is tinted and ringed.
class AudienceTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;

  /// Null: this audience cannot be chosen now (no trip has riders).
  final VoidCallback? onTap;

  const AudienceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final enabled = onTap != null;
    final ink = !enabled ? colors.disabled : (selected ? colors.teal : colors.ink);
    return BasakPressable(
      onTap: onTap,
      selected: selected,
      selectionHaptic: true,
      child: AnimatedContainer(
        duration: BasakMotion.fade,
        curve: BasakMotion.fadeCurve,
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s10),
        decoration: BoxDecoration(
          color: selected ? colors.tealTint : (enabled ? colors.surface : colors.sunken),
          borderRadius: BasakRadius.all(BasakRadius.control),
          border: Border.all(color: selected ? colors.teal : Colors.transparent, width: 2),
          boxShadow: selected || !enabled ? null : BasakShadow.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.body.copyWith(fontWeight: FontWeight.w600, color: ink)),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.label.copyWith(
                fontWeight: FontWeight.w400,
                color: !enabled ? colors.disabled : (selected ? colors.teal : colors.ink2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A white row that shows a choice and opens the way to change it: the trip
/// a message goes to («اليوم · ذهاب 7:00 ص» · «38 طالباً»), or, with [label],
/// a named value («يصل إلى» · «كل طلاب خط الزرقا · 124»).
class PickRow extends StatelessWidget {
  final String? label;
  final String value;

  /// After the value, quieter: «38 طالباً».
  final String? note;
  final VoidCallback? onTap;

  /// The row opens a sheet under it (a chevron pointing down) or leads back
  /// to another page (a chevron pointing onward).
  final bool opensSheet;

  const PickRow({super.key, this.label, required this.value, this.note, required this.onTap, this.opensSheet = true});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final quiet = text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400);
    return BasakPressable(
      onTap: onTap,
      child: BasakCard(
        radius: BasakRadius.control,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              if (label != null) ...[
                Text(label!, style: text.bodySmall.copyWith(color: colors.ink2)),
                const SizedBox(width: BasakSpace.s12),
              ],
              Expanded(
                child: Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: label == null ? TextAlign.start : TextAlign.end,
                  style: text.body.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              if (note != null) ...[const SizedBox(width: BasakSpace.s12), Text(note!, style: quiet)],
              if (onTap != null) ...[
                const SizedBox(width: BasakSpace.s12),
                Icon(
                  opensSheet
                      ? LucideIcons.chevronDown
                      : (rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight),
                  size: 18,
                  color: colors.ink3,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One ready message of a [MessageRows] card.
class MessageRow {
  final String title;

  /// The text as the students will read it, on one line.
  final String preview;
  final VoidCallback? onTap;
  final Key? key;

  const MessageRow({required this.title, required this.preview, this.onTap, this.key});
}

/// The ready messages in one white card: a title, its text on one line and a
/// chevron, a hairline between rows. Any number of rows.
class MessageRows extends StatelessWidget {
  final List<MessageRow> rows;

  const MessageRows({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return BasakCard(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: colors.hairline),
            BasakPressable(
              key: rows[i].key,
              onTap: rows[i].onTap,
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(rows[i].title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.body.copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            rows[i].preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: BasakSpace.s12),
                    Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 18, color: colors.ink3),
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

/// A white card that leads somewhere: a glyph in a sunken tile, a title, one
/// line under it and a chevron («رسالة أخرى», «إشعار للطلاب»).
class LinkCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  /// Null: drawn muted, and not tappable.
  final VoidCallback? onTap;

  const LinkCard({super.key, required this.icon, required this.title, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final enabled = onTap != null;
    return BasakPressable(
      onTap: onTap,
      child: BasakCard(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s14),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: colors.sunken, borderRadius: BasakRadius.all(BasakRadius.small)),
                child: Icon(icon, size: 20, color: enabled ? colors.ink : colors.disabled),
              ),
            ),
            const SizedBox(width: BasakSpace.s12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: text.body
                          .copyWith(fontWeight: FontWeight.w600, color: enabled ? colors.ink : colors.disabled)),
                  if (subtitle != null)
                    Text(subtitle!, style: text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400)),
                ],
              ),
            ),
            if (enabled) ...[
              const SizedBox(width: BasakSpace.s12),
              Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 18, color: colors.ink3),
            ],
          ],
        ),
      ),
    );
  }
}

/// A notification as the student's phone will show it: the app's mark, who
/// it is from, «الآن», the title and the text.
class NotificationPreview extends StatelessWidget {
  /// "باصك · مشرف الباص".
  final String sender;
  final String title;
  final String body;

  const NotificationPreview({super.key, required this.sender, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final quiet = text.caption.copyWith(color: colors.ink3);
    return Semantics(
      container: true,
      label: 'معاينة الإشعار كما يصل للطالب',
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s14),
        decoration: BoxDecoration(color: colors.ground, borderRadius: BasakRadius.all(BasakRadius.control)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: colors.ink, borderRadius: BasakRadius.all(BasakRadius.tag)),
                child: Icon(LucideIcons.bell, size: 18, color: colors.onInk),
              ),
            ),
            const SizedBox(width: BasakSpace.s12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(sender, maxLines: 1, overflow: TextOverflow.ellipsis, style: quiet)),
                      const SizedBox(width: BasakSpace.s8),
                      Text('الآن', style: quiet),
                    ],
                  ),
                  Text(title, style: text.body.copyWith(fontWeight: FontWeight.w600)),
                  Text(body, style: text.bodySmall.copyWith(color: colors.ink2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Who a message will reach, in one line: «سيصل إلى 38 طالباً · ركاب ذهاب
/// 7:00 ص اليوم», the count set heavier.
class ReachLine extends StatelessWidget {
  /// "سيصل إلى".
  final String lead;

  /// "38 طالباً".
  final String count;

  /// "ركاب ذهاب 7:00 ص اليوم".
  final String audience;

  const ReachLine({super.key, this.lead = 'سيصل إلى', required this.count, required this.audience});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = context.text.bodySmall.copyWith(color: colors.ink2);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: BasakSpace.s2),
          child: Icon(LucideIcons.users, size: 18, color: colors.ink2),
        ),
        const SizedBox(width: BasakSpace.s10),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$lead '),
              TextSpan(text: count, style: style.copyWith(color: colors.ink, fontWeight: FontWeight.w600)),
              TextSpan(text: ' · $audience'),
            ]),
            style: style,
          ),
        ),
      ],
    );
  }
}

/// A typed field of a page with its limit counted as it is typed: the label
/// and «17 / 80» over a box that is sunken at rest and white with a teal ring
/// while typed in. With [lines] above one it is a text area of that height.
class CountedField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final int maxLength;
  final String? hint;
  final int lines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;

  const CountedField({
    super.key,
    required this.label,
    required this.controller,
    required this.maxLength,
    this.hint,
    this.lines = 1,
    this.textInputAction,
    this.onChanged,
  });

  @override
  State<CountedField> createState() => _CountedFieldState();
}

class _CountedFieldState extends State<CountedField> {
  final _node = FocusNode();

  @override
  void initState() {
    super.initState();
    _node.addListener(_redraw);
    widget.controller.addListener(_redraw);
  }

  @override
  void didUpdateWidget(CountedField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_redraw);
      widget.controller.addListener(_redraw);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_redraw);
    _node
      ..removeListener(_redraw)
      ..dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final focused = _node.hasFocus;
    final area = widget.lines > 1;
    final value = text.rowTitle.copyWith(fontWeight: FontWeight.w400);
    // Counted as the server counts it: by code point.
    final typed = widget.controller.text.runes.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(widget.label, style: text.label.copyWith(color: colors.ink2))),
            Semantics(
              label: '$typed من ${widget.maxLength}',
              excludeSemantics: true,
              child: Text(
                '$typed / ${widget.maxLength}',
                textDirection: TextDirection.ltr,
                style: text.caption.copyWith(color: colors.ink3),
              ),
            ),
          ],
        ),
        const SizedBox(height: BasakSpace.s6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _node.requestFocus,
          child: AnimatedContainer(
            duration: BasakMotion.fade,
            constraints: BoxConstraints(minHeight: area ? 26.0 * widget.lines + 2 * BasakSpace.s12 : 54),
            alignment: area ? AlignmentDirectional.topStart : AlignmentDirectional.centerStart,
            padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16),
            decoration: BoxDecoration(
              color: focused ? colors.surface : colors.sunken,
              borderRadius: BasakRadius.all(BasakRadius.control),
              border: Border.all(color: focused ? colors.teal : Colors.transparent, width: 2),
            ),
            child: TextField(
              controller: widget.controller,
              focusNode: _node,
              minLines: area ? widget.lines : 1,
              maxLines: area ? widget.lines + 3 : 1,
              keyboardType: area ? TextInputType.multiline : TextInputType.text,
              textInputAction: widget.textInputAction,
              inputFormatters: [_CodePointLimit(widget.maxLength)],
              onChanged: widget.onChanged,
              style: value,
              cursorColor: colors.teal,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s12),
                hintText: widget.hint,
                hintStyle: value.copyWith(color: colors.ink3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Keeps a text within [max] code points: what would pass it is not typed.
class _CodePointLimit extends TextInputFormatter {
  final int max;

  const _CodePointLimit(this.max);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final runes = newValue.text.runes;
    if (runes.length <= max) return newValue;
    // A paste: as much of it as fits.
    if (oldValue.text.runes.length >= max) return oldValue;
    final kept = String.fromCharCodes(runes.take(max));
    return TextEditingValue(text: kept, selection: TextSelection.collapsed(offset: kept.length));
  }
}

/// The month being looked at, between the way back and the way forward.
/// [onNext] is null on the current month.
class MonthSwitcher extends StatelessWidget {
  /// "أكتوبر 2026".
  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const MonthSwitcher({super.key, required this.label, required this.onPrevious, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Row(
      children: [
        // Earlier is where reading starts: the start side.
        BasakIconButton(
          icon: rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft,
          label: 'الشهر السابق',
          onPressed: onPrevious,
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(label, textAlign: TextAlign.center, style: context.text.headline),
          ),
        ),
        BasakIconButton(
          icon: rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight,
          label: 'الشهر التالي',
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// The month in one ink card: its one total, the rate beside it, and the
/// total split in two.
class MonthHero extends StatelessWidget {
  /// "تسجيلات الصعود".
  final String label;

  /// "1,284".
  final String total;

  /// "91%"; null when there is nothing to measure against.
  final String? rate;

  /// "من الركوب المؤكَّد".
  final String rateCaption;

  /// The two halves of [total]: («ذهاب», «702»), («عودة», «582»).
  final List<(String, String)> split;

  const MonthHero({
    super.key,
    required this.label,
    required this.total,
    this.rate,
    this.rateCaption = '',
    this.split = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final soft = text.caption.copyWith(color: colors.onInk2);
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsetsDirectional.all(BasakSpace.s20),
        decoration: BoxDecoration(color: colors.ink, borderRadius: BasakRadius.all(BasakRadius.sheet)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: text.label.copyWith(color: colors.onInk2, fontWeight: FontWeight.w400)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(total,
                            maxLines: 1, style: text.total.copyWith(color: colors.onInk, fontSize: 40, height: 48 / 40)),
                      ),
                    ],
                  ),
                ),
                if (rate != null) ...[
                  const SizedBox(width: BasakSpace.s12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(rate!,
                          textDirection: TextDirection.ltr,
                          style: text.title.copyWith(color: colors.mint, fontSize: 24)),
                      Text(rateCaption, style: soft),
                    ],
                  ),
                ],
              ],
            ),
            if (split.isNotEmpty) ...[
              const SizedBox(height: BasakSpace.s16),
              Row(
                children: [
                  for (var i = 0; i < split.length; i++) ...[
                    if (i > 0) const SizedBox(width: BasakSpace.s8),
                    Expanded(
                      child: Container(
                        padding:
                            const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s10),
                        decoration:
                            BoxDecoration(color: colors.inkRaised, borderRadius: BasakRadius.all(BasakRadius.small)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(split[i].$1, style: soft),
                            Text(split[i].$2, maxLines: 1, style: text.headline.copyWith(color: colors.onInk)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A white card under its own heading: the chart, the scan results, the
/// busiest stops. [trailing] faces the heading (a chart's legend).
class TitledCard extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;

  const TitledCard({super.key, required this.title, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) => BasakCard(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s18, vertical: BasakSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: BasakSpace.s12,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: context.text.body.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: BasakSpace.s6),
            child,
          ],
        ),
      );
}

/// One day of a [DayBars] chart.
class DayBar {
  /// Under the bar: the day of the month.
  final String label;

  /// The lower part of the bar (going) and the upper part (returning).
  final int lower;
  final int upper;

  /// Today: its numbers are set heavier.
  final bool emphasised;

  const DayBar({required this.label, required this.lower, required this.upper, this.emphasised = false});

  int get total => lower + upper;
}

/// A bar per working day, its total printed over it: going below, returning
/// above. The days share the width; a month too long for it scrolls sideways
/// and opens on its latest days.
class DayBars extends StatelessWidget {
  final List<DayBar> days;

  /// What the chart shows, for screen readers.
  final String semanticLabel;

  const DayBars({super.key, required this.days, required this.semanticLabel});

  static const double _barHeight = 110;
  static const double _slot = 30;
  static const double _gap = 6;

  /// The two colours named: «ذهاب» and «عودة».
  static Widget legend(BuildContext context, {required String lower, required String upper}) {
    final colors = context.colors;
    Widget key(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BasakRadius.all(3))),
            const SizedBox(width: BasakSpace.s6),
            Text(label, style: context.text.caption.copyWith(color: colors.ink2)),
          ],
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [key(colors.teal, lower), const SizedBox(width: BasakSpace.s12), key(colors.sky, upper)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final peak = days.fold<int>(1, (max, d) => d.total > max ? d.total : max);

    Widget day(DayBar d) {
      final ink = d.emphasised ? colors.ink : colors.ink3;
      final weight = d.emphasised ? FontWeight.w600 : FontWeight.w400;
      double part(int value) => value <= 0 ? 0 : (value / peak * _barHeight).clamp(3.0, _barHeight);
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('${d.total}',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              textScaler: TextScaler.noScaling,
              style: text.tab.copyWith(color: ink, fontWeight: weight)),
          const SizedBox(height: BasakSpace.s4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 22),
            child: ClipRRect(
              borderRadius: BasakRadius.all(BasakSpace.s6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(height: part(d.upper), color: colors.sky),
                  Container(height: part(d.lower), color: colors.teal),
                ],
              ),
            ),
          ),
          const SizedBox(height: BasakSpace.s4),
          Text(d.label,
              maxLines: 1,
              textScaler: TextScaler.noScaling,
              style: text.caption.copyWith(color: ink, fontWeight: weight)),
        ],
      );
    }

    return Semantics(
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fits = days.length * _slot + (days.length - 1) * _gap <= constraints.maxWidth;
            final row = Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  fits ? Expanded(child: day(days[i])) : SizedBox(width: _slot, child: day(days[i])),
                ],
              ],
            );
            return Padding(
              padding: const EdgeInsetsDirectional.only(top: BasakSpace.s6),
              child: fits
                  ? row
                  // Opens on the latest days: the end of the month.
                  : SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: row),
            );
          },
        ),
      ),
    );
  }
}
