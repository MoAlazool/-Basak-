import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'basak_page.dart';
import 'status_chip.dart';
import 'tokens.dart';

/// More of the supervisor's set: the line row and the day pager of Home, the
/// trip card and the trip rows of Trips.

/// The line everything on screen is about, on Home. Shown only to a
/// supervisor of more than one line; opens the line sheet.
class LineSwitchRow extends StatelessWidget {
  /// "خط الزرقا".
  final String name;

  /// "النورس للنقل · 1 من 3 خطوط".
  final String caption;

  /// Null: the supervisor has this one line; the row only names it.
  final VoidCallback? onTap;

  /// Beside the name: "خط متوقف".
  final String? tag;

  const LineSwitchRow({super.key, required this.name, required this.caption, required this.onTap, this.tag});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return BasakPressable(
      onTap: onTap,
      semanticLabel: onTap == null ? 'الخط الحالي: $name' : 'الخط الحالي: $name. تغيير الخط',
      child: BasakCard(
        radius: BasakRadius.control,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: colors.tealTint, borderRadius: BasakRadius.all(BasakRadius.tile)),
              child: Icon(LucideIcons.bus, size: 18, color: colors.teal),
            ),
            const SizedBox(width: BasakSpace.s12),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.body.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        if (tag != null) ...[const SizedBox(width: BasakSpace.s8), BasakTag(tag!)],
                      ],
                    ),
                    Text(caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.caption.copyWith(color: colors.ink3)),
                  ],
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: BasakSpace.s8),
              Icon(LucideIcons.chevronDown, size: 18, color: colors.ink3),
            ],
          ],
        ),
      ),
    );
  }
}

/// A card that leads somewhere: a glyph in a tinted tile, what it is, one
/// line about it ("إشعار للطلاب · لكل الخط أو لركاب رحلة واحدة").
class EntryRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  /// Null: the row is there but cannot be used yet; [subtitle] says why.
  final VoidCallback? onTap;

  const EntryRow({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final off = onTap == null;
    return BasakPressable(
      onTap: onTap,
      child: BasakCard(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: off ? colors.sunken : colors.tealTint,
                borderRadius: BasakRadius.all(BasakRadius.small),
              ),
              child: Icon(icon, size: 20, color: off ? colors.ink3 : colors.teal),
            ),
            const SizedBox(width: BasakSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.body.copyWith(fontWeight: FontWeight.w600, color: off ? colors.ink3 : null)),
                  Text(subtitle, style: text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400)),
                ],
              ),
            ),
            if (!off) ...[
              const SizedBox(width: BasakSpace.s8),
              Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 18, color: colors.ink3),
            ],
          ],
        ),
      ),
    );
  }
}

/// A group kept closed until asked for: its name and count, one line about
/// it, and its content under a hairline once open ("لم يؤكّدوا اليوم · 5").
class DisclosureCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool expanded;
  final VoidCallback? onToggle;
  final Widget child;

  const DisclosureCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return BasakCard(
      padding: EdgeInsetsDirectional.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: expanded,
            child: BasakPressable(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title, style: text.body.copyWith(fontWeight: FontWeight.w600)),
                          if (subtitle != null)
                            Text(subtitle!, style: text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400)),
                        ],
                      ),
                    ),
                    const SizedBox(width: BasakSpace.s8),
                    Icon(expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18, color: colors.ink3),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) ...[
            Divider(height: 1, thickness: 1, color: colors.hairline),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16),
              child: child,
            ),
          ],
        ],
      ),
    );
  }
}

/// A person in a plain list: the name, one quiet line under it, and at most
/// one word at the end. 48 high at least; opens the rider sheet.
class PersonRow extends StatelessWidget {
  final String name;
  final String? caption;
  final Widget? trailing;
  final VoidCallback? onTap;

  const PersonRow({super.key, required this.name, this.caption, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return BasakPressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                  if (caption != null)
                    Text(caption!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.caption.copyWith(color: colors.ink3)),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: BasakSpace.s10), trailing!],
          ],
        ),
      ),
    );
  }
}

/// The trip on screen in Trips: its time set large, its direction, the way to
/// another trip, one line of where and when it arrives, and — under a
/// hairline — what [child] says about it (a `ProgressLine`).
class TripCard extends StatelessWidget {
  /// Already formatted with `BasakUi.time12`.
  final String time;

  /// "ذهاب" or "عودة".
  final String direction;

  /// "خط الزرقا · الوصول إلى الجامعة 8:20 ص".
  final String detail;

  /// A second, quieter line: the bus's seats ("المقاعد: 38 من 50").
  final String? note;

  /// [note] is something to act on ("يحتاج باصين").
  final bool noteWarns;

  /// Opens the trip sheet. Null: there is no other trip to change to.
  final VoidCallback? onChange;
  final Widget child;

  const TripCard({
    super.key,
    required this.time,
    required this.direction,
    required this.detail,
    this.note,
    this.noteWarns = false,
    required this.onChange,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Semantics(
      container: true,
      label: 'الرحلة المعروضة',
      child: BasakCard(
        radius: 24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: BasakSpace.s10,
                    children: [
                      Text(time, maxLines: 1, style: text.amount.copyWith(fontSize: 30, height: 40 / 30)),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(bottom: BasakSpace.s6),
                        child: Text(direction, style: text.body.copyWith(color: colors.ink2)),
                      ),
                    ],
                  ),
                ),
                if (onChange != null) ...[
                  const SizedBox(width: BasakSpace.s12),
                  BasakPressable(
                    onTap: onChange,
                    semanticLabel: 'تغيير الرحلة',
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 40),
                        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14),
                        decoration:
                            BoxDecoration(color: colors.tealTint, borderRadius: BasakRadius.all(BasakRadius.tile)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ExcludeSemantics(
                              child: Text('تغيير',
                                  style: text.bodySmall.copyWith(color: colors.teal, fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(width: BasakSpace.s6),
                            Icon(LucideIcons.chevronDown, size: 16, color: colors.teal),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: BasakSpace.s14),
            Text(detail, style: text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400)),
            if (note != null)
              Text(note!,
                  style: text.caption.copyWith(
                      color: noteWarns ? colors.warning : colors.ink3,
                      fontWeight: noteWarns ? FontWeight.w500 : FontWeight.w400)),
            const SizedBox(height: BasakSpace.s14),
            Divider(height: 1, thickness: 1, color: colors.hairline),
            const SizedBox(height: BasakSpace.s14),
            child,
          ],
        ),
      ),
    );
  }
}

/// One trip of the trip sheet: its time, how far away it is, how many ride,
/// and the radio. Scales to any number of trips.
class TripChoiceRow extends StatelessWidget {
  /// Already formatted with `BasakUi.time12`.
  final String time;

  /// "مضى موعدها", "الآن", "بعد 27 دقيقة", or nothing.
  final String? note;

  /// "38 طالباً".
  final String riders;
  final bool selected;

  /// Its time has passed, by the clock: the time is set quieter.
  final bool past;
  final VoidCallback? onTap;

  const TripChoiceRow({
    super.key,
    required this.time,
    this.note,
    required this.riders,
    required this.selected,
    this.past = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final quiet = text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400);
    return BasakPressable(
      onTap: onTap,
      selected: selected,
      selectionHaptic: true,
      child: AnimatedContainer(
        duration: BasakMotion.fade,
        curve: BasakMotion.fadeCurve,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s12, vertical: BasakSpace.s4),
        decoration: BoxDecoration(
          color: selected ? colors.tealTint : colors.ground,
          borderRadius: BasakRadius.all(BasakRadius.small),
          border: Border.all(color: selected ? colors.teal : Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 76),
              child: Text(time,
                  maxLines: 1, style: text.rowTitle.copyWith(color: past && !selected ? colors.ink3 : null)),
            ),
            const SizedBox(width: BasakSpace.s12),
            Expanded(
              child: Text(note ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: quiet),
            ),
            const SizedBox(width: BasakSpace.s8),
            Text(riders, maxLines: 1, style: quiet),
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

/// Cards swiped one at a time, the next one peeking in from the side it will
/// come from. As tall as its tallest card; the cards off centre are dimmed,
/// and tapping one brings it in. Pair it with `PagerDots`.
class PeekPager extends StatefulWidget {
  final List<Widget> children;
  final int index;
  final ValueChanged<int> onChanged;

  /// How much of the next card shows inside the pager's own width; the rest of
  /// what shows lies in the page's gutter.
  static const double peek = 4;
  static const double gap = BasakSpace.s10;

  const PeekPager({super.key, required this.children, required this.index, required this.onChanged});

  @override
  State<PeekPager> createState() => _PeekPagerState();
}

class _PeekPagerState extends State<PeekPager> {
  late final ScrollController _controller = ScrollController();
  double _stride = 0;
  bool _placed = false;

  /// A finger moved the cards: only then does where they rest choose the page
  /// (the pager's own moves, and the first layout, choose nothing).
  bool _dragged = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _offsetOf(int index) {
    if (!_controller.hasClients) return 0;
    return (index * _stride).clamp(0.0, _controller.position.maxScrollExtent);
  }

  @override
  void didUpdateWidget(PeekPager old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _show(widget.index, animate: true);
  }

  void _show(int index, {required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final target = _offsetOf(index);
      if ((_controller.offset - target).abs() < 1) return;
      if (animate && !MediaQuery.disableAnimationsOf(context)) {
        _controller.animateTo(target, duration: BasakMotion.page, curve: BasakMotion.pageCurve);
      } else {
        _controller.jumpTo(target);
      }
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.horizontal) return false;
    if (notification is ScrollStartNotification && notification.dragDetails != null) _dragged = true;
    if (notification is! ScrollEndNotification || !_dragged || _stride <= 0) return false;
    _dragged = false;
    final max = notification.metrics.maxScrollExtent;
    final pixels = notification.metrics.pixels;
    // The last card rests at the end of the scroll, short of a full stride.
    final index = pixels >= max - 1 && max > 0
        ? widget.children.length - 1
        : (pixels / _stride).round().clamp(0, widget.children.length - 1);
    if (index != widget.index) widget.onChanged(index);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.length < 2) return widget.children.isEmpty ? const SizedBox.shrink() : widget.children.first;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - PeekPager.peek - PeekPager.gap;
        _stride = width + PeekPager.gap;
        if (!_placed) {
          _placed = true;
          if (widget.index != 0) _show(widget.index, animate: false);
        }
        return NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
            // The neighbour shows through the page's gutter.
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < widget.children.length; i++) ...[
                  if (i > 0) const SizedBox(width: PeekPager.gap),
                  SizedBox(
                    width: width,
                    child: i == widget.index
                        ? widget.children[i]
                        : Semantics(
                            button: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => widget.onChanged(i),
                              child: AbsorbPointer(
                                child: Opacity(opacity: .45, child: widget.children[i]),
                              ),
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A whole screen that says one thing in a tone: a glyph on its tint, what
/// happened, one line of what to do ("الحساب موقوف"). The actions are the
/// screen's own, under it.
class ToneState extends StatelessWidget {
  final IconData icon;
  final BasakTone tone;
  final String title;
  final String message;

  const ToneState({super.key, required this.icon, required this.tone, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: tone.tint(colors), borderRadius: BasakRadius.all(22)),
              child: Icon(icon, size: 28, color: tone.foreground(colors)),
            ),
          ),
          const SizedBox(height: BasakSpace.s16),
          Text(title, textAlign: TextAlign.center, style: text.sheetTitle),
          const SizedBox(height: BasakSpace.s10),
          Text(message, textAlign: TextAlign.center, style: text.body.copyWith(color: colors.ink2)),
        ],
      ),
    );
  }
}
