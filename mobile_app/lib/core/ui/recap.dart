import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'tokens.dart';

/// The term recap's pieces (boards `Recap*`): the story's chrome, what a page
/// is made of, the term as a pattern of dots, the 9:16 poster and the banner
/// that opens it from Home. The one place the expressive palette
/// ([BasakRecapColors]) and the poster type roles are used.

/// The five grounds a story page is drawn on.
enum StoryGround {
  ink,
  teal,
  sky,
  mint,
  light;

  bool get dark => this == ink || this == teal;

  Color get background => switch (this) {
        ink => BasakPalette.ink,
        teal => BasakPalette.teal,
        sky => BasakRecapColors.sky,
        mint => BasakPalette.mint,
        light => BasakPalette.ground,
      };

  Color get foreground => dark ? BasakPalette.surface : BasakPalette.ink;

  /// The small word above a page's idea.
  Color get kicker => switch (this) {
        ink || teal => BasakPalette.sky,
        mint => BasakRecapColors.onMint,
        sky || light => BasakPalette.teal,
      };

  /// The big rings behind the page.
  Color get ring => switch (this) {
        ink => BasakRecapColors.inkRaised,
        teal => BasakRecapColors.tealRaised,
        sky => BasakRecapColors.skyDeep,
        mint => BasakRecapColors.mintDeep,
        light => BasakPalette.ground,
      };

  /// What stands out on the page: a link, the title, the time.
  Color get accent => this == ink ? BasakPalette.mint : foreground;

  /// A chip's or a box's fill.
  Color get raised => switch (this) {
        ink => BasakRecapColors.inkRaised,
        teal => BasakRecapColors.tealRaised,
        _ => BasakPalette.ink.withValues(alpha: .12),
      };

  Color get segmentRest => switch (this) {
        ink => BasakPalette.surface.withValues(alpha: .3),
        teal => BasakPalette.surface.withValues(alpha: .35),
        _ => BasakPalette.ink.withValues(alpha: .22),
      };
}

/// A ring behind a story page. Offsets are from the page's end edge and from
/// its top or bottom, as on the boards (390 wide).
class StoryRing {
  final double end;
  final double? top;
  final double? bottom;
  final double size;
  final double stroke;

  const StoryRing({required this.end, this.top, this.bottom, required this.size, required this.stroke});
}

abstract final class _Type {
  static TextStyle of(BuildContext context, double size, double line, FontWeight weight) =>
      context.text.posterTitle.copyWith(fontSize: size, height: line / size, fontWeight: weight);
}

/// One page of the story: its ground and rings, the progress segments, the
/// brand line and the close button, with [child] filling the rest. A tap
/// anywhere goes on; a tap on the leading edge goes back. No timer.
class StoryScaffold extends StatelessWidget {
  final StoryGround ground;
  final List<StoryRing> rings;

  /// 0-based.
  final int index;
  final int count;
  final String brand;
  final String closeLabel;
  final String? progressLabel;
  final VoidCallback onClose;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final Widget child;

  const StoryScaffold({
    super.key,
    required this.ground,
    required this.index,
    required this.count,
    required this.brand,
    required this.closeLabel,
    required this.onClose,
    required this.child,
    this.rings = const [],
    this.progressLabel,
    this.onNext,
    this.onPrevious,
  });

  @override
  Widget build(BuildContext context) {
    final fg = ground.foreground;
    final inset = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: ground.dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: ground.dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: ground.background,
        systemNavigationBarIconBrightness: ground.dark ? Brightness.light : Brightness.dark,
      ),
      child: ColoredBox(
        color: ground.background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (final ring in rings)
              PositionedDirectional(
                end: ring.end,
                top: ring.top,
                bottom: ring.bottom,
                width: ring.size,
                height: ring.size,
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: ground.ring, width: ring.stroke),
                    ),
                  ),
                ),
              ),
            // The taps: all of the page goes on, its leading quarter goes back.
            Positioned.fill(
              child: Row(
                children: [
                  if (onPrevious != null)
                    Expanded(
                      child: GestureDetector(
                        key: const Key('story-back'),
                        behavior: HitTestBehavior.opaque,
                        onTap: onPrevious,
                      ),
                    ),
                  Expanded(
                    flex: 3,
                    child: GestureDetector(
                      key: const Key('story-next'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onNext,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.only(top: inset.top + BasakSpace.s12, bottom: inset.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          label: progressLabel,
                          child: Row(
                            children: [
                              for (var i = 0; i < count; i++) ...[
                                if (i > 0) const SizedBox(width: 3),
                                Expanded(
                                  child: AnimatedContainer(
                                    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : BasakMotion.fade,
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: i <= index ? fg : ground.segmentRest,
                                      borderRadius: BasakRadius.all(2),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: BasakSpace.s8),
                        Row(
                          children: [
                            Expanded(
                              child: IgnorePointer(
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(start: BasakSpace.s4),
                                  child: Text(
                                    brand,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.text.label.copyWith(color: fg.withValues(alpha: .85)),
                                  ),
                                ),
                              ),
                            ),
                            BasakPressable(
                              key: const Key('story-close'),
                              onTap: onClose,
                              semanticLabel: closeLabel,
                              child: SizedBox.square(
                                dimension: BasakSpace.tapTarget,
                                child: Icon(LucideIcons.x, size: 20, color: fg),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A story page's own content: centred in the height it has, start-aligned,
/// 14 between its parts. Taps fall through to the page. Scales down as a
/// whole rather than clip when the screen is short or the text is large.
class StoryBody extends StatelessWidget {
  final List<Widget> children;

  const StoryBody({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.s28, BasakSpace.s8, BasakSpace.s28, BasakSpace.s40),
        child: LayoutBuilder(
          builder: (context, box) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(
                width: box.maxWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(height: BasakSpace.s14),
                      children[i],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One line that shrinks to the width it has instead of wrapping or clipping.
class _FitLine extends StatelessWidget {
  final Widget child;

  const _FitLine({required this.child});

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: child,
      );
}

/// 15 / 24 · 600 — the small word above a page's idea.
class StoryKicker extends StatelessWidget {
  final String text;
  final StoryGround ground;

  /// Follows [text] left to right: the years, "2026 / 2027".
  final String? ltrTail;

  const StoryKicker({super.key, required this.text, required this.ground, this.ltrTail});

  @override
  Widget build(BuildContext context) {
    final style = context.text.body.copyWith(color: ground.kicker, fontWeight: FontWeight.w600);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: text),
        if (ltrTail != null) ...[
          if (text.isNotEmpty) const TextSpan(text: ' · '),
          // Kept left to right inside the Arabic line.
          TextSpan(text: '\u2066$ltrTail\u2069'),
        ],
      ]),
      style: style,
    );
  }
}

/// The big number of a page and the words under it: "109" / "ساعة في الباص",
/// or a time with its «ص».
class StoryNumber extends StatelessWidget {
  final String numeral;

  /// Beside a time: «ص» or «م». The number is then set a step smaller.
  final String? suffix;
  final String? unit;
  final StoryGround ground;

  /// The number in the page's accent (the time page).
  final bool accent;

  const StoryNumber({
    super.key,
    required this.numeral,
    required this.ground,
    this.suffix,
    this.unit,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ? ground.accent : ground.foreground;
    final big = suffix == null
        ? context.text.posterNumeral.copyWith(color: color, letterSpacing: -3)
        : _Type.of(context, 124, 134, FontWeight.w700).copyWith(color: color, letterSpacing: -3);
    return MediaQuery.withNoTextScaling(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _FitLine(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(numeral, textDirection: TextDirection.ltr, style: big),
                if (suffix != null) ...[
                  const SizedBox(width: BasakSpace.s10),
                  Text(suffix!, style: _Type.of(context, 40, 48, FontWeight.w700).copyWith(color: color)),
                ],
              ],
            ),
          ),
          if (unit != null)
            _FitLine(
              child: Text(unit!, style: _Type.of(context, 30, 40, FontWeight.w600).copyWith(color: ground.foreground)),
            ),
        ],
      ),
    );
  }
}

/// How large a story headline is set.
enum StoryHeadlineSize {
  /// 68 / 78 — the cover.
  cover,

  /// 76 / 88 — «يا هندسة».
  call,

  /// 52 / 64 — the title of the term.
  title,
}

/// A headline of one or two lines, each shrinking to the page's width. A long
/// one without a line break of its own is broken where its two lines come out
/// most even.
class StoryHeadline extends StatelessWidget {
  final String text;
  final StoryGround ground;
  final StoryHeadlineSize size;
  final bool accent;

  const StoryHeadline({
    super.key,
    required this.text,
    required this.ground,
    this.size = StoryHeadlineSize.title,
    this.accent = false,
  });

  /// [text] in at most two lines for [width]: its own break when it has one,
  /// otherwise the most even one when it does not fit on a line.
  static List<String> lines(String text, TextStyle style, double width) {
    if (text.contains('\n')) return text.split('\n');
    double measure(String s) {
      final painter = TextPainter(
          text: TextSpan(text: s, style: style), textDirection: TextDirection.rtl, maxLines: 1)
        ..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    }

    if (measure(text) <= width) return [text];
    final words = text.split(' ');
    if (words.length < 2) return [text];
    var best = 1;
    double? bestWidth;
    for (var i = 1; i < words.length; i++) {
      final a = measure(words.sublist(0, i).join(' ')), b = measure(words.sublist(i).join(' '));
      final widest = a > b ? a : b;
      if (bestWidth == null || widest < bestWidth) {
        bestWidth = widest;
        best = i;
      }
    }
    return [words.sublist(0, best).join(' '), words.sublist(best).join(' ')];
  }

  @override
  Widget build(BuildContext context) {
    final color = accent ? ground.accent : ground.foreground;
    final style = switch (size) {
      StoryHeadlineSize.cover => context.text.storyTitle,
      StoryHeadlineSize.call => _Type.of(context, 76, 88, FontWeight.w700),
      StoryHeadlineSize.title => _Type.of(context, 52, 64, FontWeight.w700),
    }
        .copyWith(color: color);
    return MediaQuery.withNoTextScaling(
      child: LayoutBuilder(
        builder: (context, box) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // «يا هندسة» stays one line and shrinks; the others may take two.
            for (final line in size == StoryHeadlineSize.call ? [text] : lines(text, style, box.maxWidth))
              _FitLine(child: Text(line, maxLines: 1, style: style)),
          ],
        ),
      ),
    );
  }
}

/// How a sentence of a story page is set.
enum StoryLineLevel {
  /// 20 / 32 · 500.
  lead,

  /// 19 / 30 · 500 — beside a chart or a rail.
  body,

  /// 17 / 28 · 500, a little quieter.
  second,

  /// 12 / 18, quiet: "رقم تقريبي…".
  note,
}

class StoryLine extends StatelessWidget {
  final String text;
  final StoryGround ground;
  final StoryLineLevel level;

  const StoryLine({super.key, required this.text, required this.ground, this.level = StoryLineLevel.lead});

  @override
  Widget build(BuildContext context) {
    final fg = ground.foreground;
    final style = switch (level) {
      StoryLineLevel.lead => _Type.of(context, 20, 32, FontWeight.w500).copyWith(color: fg),
      StoryLineLevel.body => _Type.of(context, 19, 30, FontWeight.w500).copyWith(color: fg),
      StoryLineLevel.second => _Type.of(context, 17, 28, FontWeight.w500).copyWith(color: fg.withValues(alpha: .9)),
      StoryLineLevel.note => context.text.caption.copyWith(color: fg.withValues(alpha: .7), fontWeight: FontWeight.w500),
    };
    return Text(text, style: style);
  }
}

/// A rounded note under a page's sentence: "أطول غيبة: 9 أيام".
class StoryChip extends StatelessWidget {
  final String text;
  final StoryGround ground;
  final IconData? icon;

  const StoryChip({super.key, required this.text, required this.ground, this.icon});

  @override
  Widget build(BuildContext context) {
    final fg = ground.foreground;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s8),
      decoration: BoxDecoration(color: ground.raised, borderRadius: BasakRadius.all(BasakRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: BasakSpace.s8),
          ],
          Flexible(
            child: Text(text, style: context.text.bodySmall.copyWith(color: fg, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

/// "يلا نشوف ‹" — where a tap leads.
class StoryCta extends StatelessWidget {
  final String text;
  final StoryGround ground;

  const StoryCta({super.key, required this.text, required this.ground});

  @override
  Widget build(BuildContext context) {
    final color = ground == StoryGround.ink ? BasakPalette.mint : ground.foreground;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: BasakSpace.s10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: context.text.body.copyWith(color: color, fontWeight: FontWeight.w600)),
          const SizedBox(width: BasakSpace.s8),
          Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 18, color: color),
        ],
      ),
    );
  }
}

/// A set-off box: a strong line and a word under it.
class StoryBox extends StatelessWidget {
  final String title;
  final String? body;
  final StoryGround ground;

  const StoryBox({super.key, required this.title, required this.ground, this.body});

  @override
  Widget build(BuildContext context) {
    final fg = ground.foreground;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s18, vertical: BasakSpace.s16),
      decoration: BoxDecoration(
        color: ground.dark ? ground.raised : BasakPalette.ink.withValues(alpha: .1),
        borderRadius: BasakRadius.all(BasakRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: (body == null
                    ? _Type.of(context, 19, 30, FontWeight.w600)
                    : _Type.of(context, 22, 32, FontWeight.w700))
                .copyWith(color: fg),
          ),
          if (body != null) ...[
            const SizedBox(height: BasakSpace.s4),
            Text(body!, style: _Type.of(context, 16, 26, FontWeight.w500).copyWith(color: fg)),
          ],
        ],
      ),
    );
  }
}

/// One weekday of [StoryBars].
class StoryBar {
  final String letter;

  /// Null: not one of the student's days — an empty slot.
  final int? count;

  /// 0 to 1 of the tallest bar.
  final double height;
  final bool strong;

  const StoryBar({required this.letter, this.count, this.height = 0, this.strong = false});
}

/// The weekdays as bars, 120 at the tallest. A day that is not the student's
/// is an empty slot, never a short bar.
class StoryBars extends StatelessWidget {
  final List<StoryBar> bars;
  final StoryGround ground;
  final String? semanticLabel;

  const StoryBars({super.key, required this.bars, required this.ground, this.semanticLabel});

  static const double _tallest = 120;

  @override
  Widget build(BuildContext context) {
    final fg = ground.foreground;
    final count = context.text.label.copyWith(color: fg, fontWeight: FontWeight.w600);
    final letter = context.text.bodySmall.copyWith(color: fg, fontWeight: FontWeight.w500);
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: MediaQuery.withNoTextScaling(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(top: BasakSpace.s10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < bars.length; i++) ...[
                  if (i > 0) const SizedBox(width: BasakSpace.s10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (bars[i].count == null) ...[
                          Text('—', style: count.copyWith(color: fg.withValues(alpha: .45), fontWeight: FontWeight.w500)),
                          const SizedBox(height: BasakSpace.s6),
                          Container(
                            height: 14,
                            decoration: BoxDecoration(
                              borderRadius: BasakRadius.all(7),
                              border: Border.all(color: fg.withValues(alpha: .3), width: 1.5),
                            ),
                          ),
                          const SizedBox(height: BasakSpace.s6),
                          Text(bars[i].letter, style: letter.copyWith(color: fg.withValues(alpha: .5))),
                        ] else ...[
                          Text('${bars[i].count}', style: count),
                          const SizedBox(height: BasakSpace.s6),
                          Container(
                            height: (bars[i].height * _tallest).clamp(BasakSpace.s10, _tallest),
                            decoration: BoxDecoration(
                              color: bars[i].strong ? fg : fg.withValues(alpha: .32),
                              borderRadius: BasakRadius.all(BasakRadius.tag),
                            ),
                          ),
                          const SizedBox(height: BasakSpace.s6),
                          Text(
                            bars[i].letter,
                            style: letter.copyWith(fontWeight: bars[i].strong ? FontWeight.w700 : FontWeight.w500),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A dot of the term: nothing there, a day not ridden, a ride.
enum TermDot { none, off, on }

/// One week of [StoryCalendar].
class StoryWeek {
  final String? month;
  final List<TermDot> days;

  const StoryWeek({required this.days, this.month});
}

/// The shape of the term on its light page: a white card, a row per week, a
/// dot per study day.
class StoryCalendar extends StatelessWidget {
  final List<String> letters;
  final List<StoryWeek> weeks;
  final String? semanticLabel;

  const StoryCalendar({super.key, required this.letters, required this.weeks, this.semanticLabel});

  static const double _dot = 16;
  static const double _label = 52;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final small = context.text.caption.copyWith(color: colors.ink3, fontWeight: FontWeight.w500, height: 16 / 12);

    Widget row(Widget lead, List<Widget> cells) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: _label, child: lead),
            for (final cell in cells) ...[
              const SizedBox(width: BasakSpace.s10),
              SizedBox(width: _dot, height: _dot, child: cell),
            ],
          ],
        );

    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: MediaQuery.withNoTextScaling(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s18, vertical: BasakSpace.s16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BasakRadius.all(BasakRadius.card),
              boxShadow: BasakShadow.card,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  row(const SizedBox(), [
                    for (final l in letters) Center(child: Text(l, style: small)),
                  ]),
                  for (final week in weeks) ...[
                    const SizedBox(height: BasakSpace.s6),
                    row(
                      Text(week.month ?? '', maxLines: 1, style: small),
                      [
                        for (final day in week.days)
                          day == TermDot.none
                              ? const SizedBox()
                              : DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: day == TermDot.on ? colors.teal : colors.track,
                                  ),
                                ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The line as a rail with the student's stop called out.
class StoryRail extends StatelessWidget {
  final List<String> before;
  final String stop;
  final List<String> after;
  final StoryGround ground;

  const StoryRail({
    super.key,
    required this.stop,
    required this.ground,
    this.before = const [],
    this.after = const [],
  });

  @override
  Widget build(BuildContext context) {
    final fg = ground.foreground;
    final small = context.text.bodySmall.copyWith(color: fg.withValues(alpha: .7), fontWeight: FontWeight.w500);

    Widget minor(String name) => SizedBox(
          height: 30,
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: BasakPalette.surface,
                      border: Border.all(color: fg, width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: BasakSpace.s14),
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: small)),
            ],
          ),
        );

    final single = before.isEmpty && after.isEmpty;
    return MediaQuery.withNoTextScaling(
      child: Stack(
        children: [
          if (!single)
            PositionedDirectional(
              start: 10,
              top: 14,
              bottom: 14,
              width: 2,
              child: ColoredBox(color: fg.withValues(alpha: .35)),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final name in before) minor(name),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: fg,
                        boxShadow: [BoxShadow(color: fg.withValues(alpha: .18), spreadRadius: 5)],
                      ),
                    ),
                    const SizedBox(width: BasakSpace.s14),
                    Expanded(
                      child: Text(
                        stop,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.amount.copyWith(color: fg, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              for (final name in after) minor(name),
            ],
          ),
        ],
      ),
    );
  }
}

/// The term as a pattern: a column per week, a dot per study day. No two
/// students' patterns are alike. Dots are 10 with 5 between, smaller when the
/// term has more weeks than the width holds.
class TermPattern extends StatelessWidget {
  /// A column per week, top to bottom in the week's order.
  final List<List<TermDot>> weeks;
  final Color on;
  final Color off;

  const TermPattern({super.key, required this.weeks, required this.on, required this.off});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: LayoutBuilder(builder: (context, box) {
        final n = weeks.isEmpty ? 1 : weeks.length;
        // At least 3 between two columns.
        final dot = ((box.maxWidth - (n - 1) * 3) / n).clamp(2.0, 10.0);
        final gap = dot / 2;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final week in weeks)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < week.length; i++) ...[
                    if (i > 0) SizedBox(height: gap),
                    Container(
                      width: dot,
                      height: dot,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: week[i] == TermDot.on ? on : off),
                    ),
                  ],
                ],
              ),
          ],
        );
      }),
    );
  }
}

/// The poster's five colour themes.
enum PosterTheme {
  ink,
  teal,
  mint,
  sky,
  light;

  Color get background => switch (this) {
        ink => BasakPalette.ink,
        teal => BasakPalette.teal,
        mint => BasakPalette.mint,
        sky => BasakRecapColors.sky,
        light => BasakPalette.surface,
      };

  Color get foreground => this == ink || this == teal ? BasakPalette.surface : BasakPalette.ink;

  /// Labels and the second tone.
  Color get soft => switch (this) {
        ink => BasakRecapColors.onInkSoft,
        teal => BasakRecapColors.onTealSoft,
        mint => BasakRecapColors.onMintSoft,
        sky => BasakRecapColors.onSkySoft,
        light => BasakPalette.ink2,
      };

  /// The title, the rule beside the line, a ridden day.
  Color get accent => switch (this) {
        ink => BasakPalette.mint,
        teal => BasakPalette.surface,
        mint || sky => BasakPalette.ink,
        light => BasakPalette.teal,
      };

  Color get tile => switch (this) {
        ink => BasakRecapColors.inkRaised,
        teal => BasakRecapColors.tealRaised,
        mint || sky => BasakPalette.ink.withValues(alpha: .1),
        light => BasakPalette.ground,
      };

  Color get dotOff => switch (this) {
        ink => BasakRecapColors.inkDim,
        teal => BasakRecapColors.tealDim,
        mint || sky => BasakPalette.ink.withValues(alpha: .16),
        light => BasakRecapColors.lightDim,
      };
}

/// One number of the poster.
class PosterStat {
  final String value;
  final String label;
  final bool ltr;

  const PosterStat(this.value, this.label, {this.ltr = false});
}

/// The 9:16 share card, 318 × 566 as drawn, square-cornered: it is the picture
/// that is shared ([PosterFrame] rounds it and scales it on the page). It
/// uses its whole height: head, title, the specialisation's line, the term as
/// a pattern, the numbers, the signature — evenly spaced. Nothing under 12,
/// nothing lighter than 500. Text does not follow the phone's text size: the
/// poster is a picture.
class RecapPoster extends StatelessWidget {
  final PosterTheme theme;

  /// "ملخّص الترم" and, at the other end, the term.
  final String head;
  final String? term;

  /// The years beside the term, left to right: "2026/27".
  final String? years;
  final String titleKicker;

  /// One or two lines ("عمدة\nكوبري السرو").
  final String title;
  final String why;

  /// The specialisation's own line; left out when there is none.
  final String? line;
  final String patternLabel;
  final String patternCount;
  final List<List<TermDot>> pattern;
  final List<PosterStat> stats;

  /// "سارة · خط الزرقا".
  final String signature;
  final String site;
  final String? semanticLabel;

  const RecapPoster({
    super.key,
    required this.theme,
    required this.head,
    required this.titleKicker,
    required this.title,
    required this.why,
    required this.patternLabel,
    required this.patternCount,
    required this.pattern,
    required this.stats,
    required this.signature,
    required this.site,
    this.term,
    this.years,
    this.line,
    this.semanticLabel,
  });

  static const Size size = Size(318, 566);
  static const double _pad = 22;

  @override
  Widget build(BuildContext context) {
    final fg = theme.foreground, soft = theme.soft;
    TextStyle type(double s, double l, FontWeight w, Color c) => _Type.of(context, s, l, w).copyWith(color: c);

    final inner = size.width - _pad * 2;
    final big = type(46, 54, FontWeight.w700, theme.accent);
    final two = type(40, 48, FontWeight.w700, theme.accent);
    final oneLine = StoryHeadline.lines(title, big, inner);
    final titleLines = oneLine.length == 1 ? oneLine : StoryHeadline.lines(title, two, inner);
    final titleStyle = titleLines.length == 1 ? big : two;

    final card = Container(
      width: size.width,
      height: size.height,
      color: theme.background,
      padding: const EdgeInsets.all(_pad),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(head, style: type(14, 20, FontWeight.w700, fg)),
              const SizedBox(width: BasakSpace.s8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    if (term != null) TextSpan(text: term),
                    if (term != null && years != null) const TextSpan(text: ' · '),
                    if (years != null) TextSpan(text: '\u2066$years\u2069'),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: type(12, 18, FontWeight.w500, soft),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(titleKicker, style: type(13, 20, FontWeight.w500, soft)),
              for (final l in titleLines) _FitLine(child: Text(l, maxLines: 1, style: titleStyle)),
              Padding(
                padding: const EdgeInsetsDirectional.only(top: BasakSpace.s4),
                child: Text(why, maxLines: 3, overflow: TextOverflow.ellipsis, style: type(14, 22, FontWeight.w500, fg)),
              ),
            ],
          ),
          if (line != null)
            Container(
              padding: const EdgeInsetsDirectional.only(start: BasakSpace.s12),
              decoration: BoxDecoration(
                border: BorderDirectional(start: BorderSide(color: theme.accent, width: 3)),
              ),
              child: Text(line!, maxLines: 3, overflow: TextOverflow.ellipsis, style: type(14, 22, FontWeight.w500, fg)),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text(patternLabel, maxLines: 1, style: type(12, 16, FontWeight.w500, soft))),
                  Text(patternCount, maxLines: 1, style: type(12, 16, FontWeight.w500, soft)),
                ],
              ),
              const SizedBox(height: BasakSpace.s8),
              TermPattern(weeks: pattern, on: theme.accent, off: theme.dotOff),
            ],
          ),
          Row(
            children: [
              for (var i = 0; i < stats.length; i++) ...[
                if (i > 0) const SizedBox(width: BasakSpace.s6),
                Expanded(
                  child: Container(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s10, vertical: 9),
                    decoration: BoxDecoration(color: theme.tile, borderRadius: BasakRadius.all(BasakRadius.small)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FitLine(
                          child: Text(
                            stats[i].ltr ? '\u2066${stats[i].value}\u2069' : stats[i].value,
                            maxLines: 1,
                            style: type(20, 26, FontWeight.w700, fg),
                          ),
                        ),
                        _FitLine(
                          child: Text(stats[i].label, maxLines: 1, style: type(12, 16, FontWeight.w500, soft)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  signature,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type(12, 18, FontWeight.w500, soft),
                ),
              ),
              const SizedBox(width: BasakSpace.s8),
              Text(site, textDirection: TextDirection.ltr, style: type(13, 18, FontWeight.w700, fg)),
            ],
          ),
        ],
      ),
    );

    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: MediaQuery.withNoTextScaling(
          child: card,
        ),
      ),
    );
  }
}

/// The poster on its page: as large as the room allows, never larger than
/// drawn, rounded, with a floating shadow under it. [boundaryKey] names the
/// repaint boundary around the poster itself, from which its picture is taken
/// (square corners, no shadow).
class PosterFrame extends StatelessWidget {
  final Widget child;
  final Key? boundaryKey;

  const PosterFrame({super.key, required this.child, this.boundaryKey});

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: BasakRadius.all(30), boxShadow: BasakShadow.floating),
          child: ClipRRect(
            borderRadius: BasakRadius.all(30),
            child: RepaintBoundary(key: boundaryKey, child: child),
          ),
        ),
      );
}

/// How one story page gives way to the next: a short slide and fade, or a
/// plain fade when the phone asks for less motion. [forward] is the way the
/// student is going.
class StoryTransition extends StatelessWidget {
  final int index;
  final bool forward;
  final Widget child;

  const StoryTransition({super.key, required this.index, required this.child, this.forward = true});

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final towards = (forward ? -1.0 : 1.0) * (Directionality.of(context) == TextDirection.rtl ? 1 : -1);
    return AnimatedSwitcher(
      duration: still ? BasakMotion.fade : BasakMotion.page,
      switchInCurve: BasakMotion.fadeCurve,
      switchOutCurve: BasakMotion.fadeCurve,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, if (current != null) current]),
      transitionBuilder: (child, animation) {
        final fade = FadeTransition(opacity: animation, child: child);
        if (still || child.key != ValueKey(index)) return fade;
        return SlideTransition(
          position: Tween(begin: Offset(.08 * towards, 0), end: Offset.zero).animate(animation),
          child: fade,
        );
      },
      child: KeyedSubtree(key: ValueKey(index), child: child),
    );
  }
}

/// «ملخّص ترمك جاهز»: the mint card on Home that opens the recap.
class RecapBanner extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onTap;

  const RecapBanner({super.key, required this.title, required this.message, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return BasakPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s14),
        decoration: BoxDecoration(color: colors.mint, borderRadius: BasakRadius.all(BasakRadius.card)),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: colors.ink, borderRadius: BasakRadius.all(BasakRadius.small)),
              child: Icon(LucideIcons.sparkles, size: 22, color: colors.mint),
            ),
            const SizedBox(width: BasakSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.rowTitle),
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.label.copyWith(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: BasakSpace.s8),
            Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 20, color: colors.ink),
          ],
        ),
      ),
    );
  }
}
