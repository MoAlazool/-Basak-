import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/ui/ui.dart';
import '../subscription/presentation/receipt_card.dart' show ReceiptExport;
import 'recap_copy.dart';
import 'recap_engine.dart';

/// Handing the poster's picture to the phone. Replaceable in tests, where
/// there is no share sheet and no photo library.
abstract final class RecapExport {
  static const fileName = 'basak-recap.png';

  @visibleForTesting
  static Future<void> Function(Uint8List png, Rect? origin)? debugShare;

  @visibleForTesting
  static Future<void> Function(Uint8List png)? debugSave;

  /// The system share sheet, as the receipt's picture is shared.
  static Future<void> share(Uint8List png, {Rect? origin}) =>
      debugShare?.call(png, origin) ?? ReceiptExport.share(png, fileName, 'image/png', origin: origin);

  /// Straight to the photo library.
  static Future<void> save(Uint8List png) async {
    if (debugSave != null) return debugSave!(png);
    if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
      throw const _SaveDenied();
    }
    await Gal.putImageBytes(png, name: 'basak-recap');
  }
}

class _SaveDenied implements Exception {
  const _SaveDenied();
}

enum _Export { share, save }

/// «ملخّص الترم»: the story the student taps through, one idea a page, ending
/// on the poster they can share or save. Which pages there are, and every
/// word on them, was decided by [TermRecap]; this only draws them.
class RecapScreen extends StatefulWidget {
  final TermRecap recap;

  const RecapScreen({super.key, required this.recap});

  static Future<void> open(BuildContext context, TermRecap recap) =>
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => RecapScreen(recap: recap),
      ));

  /// The poster of [recap], as it is drawn on the last page and in the picture.
  static RecapPoster poster(TermRecap recap) => RecapPoster(
        theme: PosterTheme.values[recap.theme % PosterTheme.values.length],
        head: RecapCopy.posterHead,
        term: recap.termName,
        years: recap.yearsShort,
        titleKicker: RecapCopy.posterTitleKicker,
        title: recap.title,
        why: recap.titleWhy,
        line: recap.line,
        patternLabel: RecapCopy.posterPatternLabel,
        patternCount: recap.patternCount,
        pattern: [
          for (final week in recap.weeks)
            [for (final cell in week.cells) cell == RecapCell.on ? TermDot.on : TermDot.off],
        ],
        stats: [for (final s in recap.stats) PosterStat(s.value, s.label, ltr: s.ltr)],
        signature: recap.signature,
        site: RecapCopy.posterSite,
        semanticLabel: recapFill(RecapCopy.posterLabel, {'اللقب': recap.title.replaceAll('\n', ' ')}),
      );

  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen> {
  final _posterKey = GlobalKey();
  int _index = 0;
  bool _forward = true;
  _Export? _exporting;

  TermRecap get _recap => widget.recap;
  List<RecapPage> get _pages => _recap.pages;

  void _go(int to) {
    if (to < 0 || to >= _pages.length || to == _index) return;
    setState(() {
      _forward = to > _index;
      _index = to;
    });
  }

  /// The poster as a picture 1080 wide, whatever size it has on this screen.
  Future<Uint8List> _picture() async {
    final boundary = _posterKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1080 / RecapPoster.size.width);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _export(_Export how) async {
    if (_exporting != null) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _exporting = how);
    try {
      final png = await _picture();
      if (how == _Export.share) {
        await RecapExport.share(png, origin: origin);
      } else {
        await RecapExport.save(png);
        if (mounted) BasakToast.show(context, RecapCopy.saved);
      }
    } on _SaveDenied {
      if (mounted) BasakToast.show(context, RecapCopy.saveDenied, kind: BasakToastKind.failure);
    } on GalException catch (e) {
      if (mounted) {
        BasakToast.show(
            context, e.type == GalExceptionType.accessDenied ? RecapCopy.saveDenied : RecapCopy.saveFailed,
            kind: BasakToastKind.failure);
      }
    } catch (_) {
      if (mounted) {
        BasakToast.show(context, how == _Export.save ? RecapCopy.saveFailed : RecapCopy.shareFailed,
            kind: BasakToastKind.failure);
      }
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  static StoryGround _ground(RecapPageKind kind) => switch (kind) {
        RecapPageKind.cover || RecapPageKind.time || RecapPageKind.title => StoryGround.ink,
        RecapPageKind.hours || RecapPageKind.back => StoryGround.teal,
        RecapPageKind.days || RecapPageKind.stop || RecapPageKind.short => StoryGround.sky,
        RecapPageKind.run || RecapPageKind.college => StoryGround.mint,
        RecapPageKind.shape || RecapPageKind.share => StoryGround.light,
      };

  static List<StoryRing> _rings(RecapPageKind kind) => switch (kind) {
        RecapPageKind.cover => const [
            StoryRing(end: -170, bottom: -150, size: 420, stroke: 52),
            StoryRing(end: 150, top: -260, size: 360, stroke: 40),
          ],
        RecapPageKind.hours => const [StoryRing(end: -190, top: 120, size: 460, stroke: 60)],
        RecapPageKind.days || RecapPageKind.short => const [StoryRing(end: -200, bottom: -220, size: 440, stroke: 56)],
        RecapPageKind.run => const [StoryRing(end: 120, bottom: -240, size: 460, stroke: 60)],
        RecapPageKind.time => const [StoryRing(end: -180, top: -140, size: 420, stroke: 52)],
        RecapPageKind.back => const [StoryRing(end: -210, bottom: -200, size: 460, stroke: 60)],
        RecapPageKind.college => const [StoryRing(end: -190, top: -150, size: 420, stroke: 52)],
        RecapPageKind.title => const [
            StoryRing(end: -170, bottom: -150, size: 420, stroke: 52),
            StoryRing(end: 170, top: -250, size: 340, stroke: 40),
          ],
        RecapPageKind.shape || RecapPageKind.stop || RecapPageKind.share => const [],
      };

  /// What a page is made of, top to bottom.
  List<Widget> _parts(RecapPage page, StoryGround ground) {
    StoryLine line(int i, StoryLineLevel level) => StoryLine(text: page.lines[i], ground: ground, level: level);
    List<Widget> lines(StoryLineLevel first) => [
          for (var i = 0; i < page.lines.length; i++) line(i, i == 0 ? first : StoryLineLevel.second),
        ];
    final kicker = StoryKicker(text: page.kicker, ground: ground);
    Widget number({bool accent = false}) => StoryNumber(
          numeral: page.numeral ?? '',
          suffix: page.numeralSuffix,
          unit: page.unit,
          ground: ground,
          accent: accent,
        );
    Widget? chip(IconData? icon) =>
        page.chip == null ? null : StoryChip(text: page.chip!, ground: ground, icon: icon);

    final parts = switch (page.kind) {
      RecapPageKind.cover => [
          StoryKicker(text: page.kicker, ground: ground, ltrTail: _recap.yearsLong),
          StoryHeadline(text: page.headline ?? '', ground: ground, size: StoryHeadlineSize.cover),
          ...lines(StoryLineLevel.lead),
          if (page.cta != null) StoryCta(text: page.cta!, ground: ground),
        ],
      RecapPageKind.hours => [
          kicker,
          number(),
          ...lines(StoryLineLevel.lead),
          if (page.footnote != null) StoryLine(text: page.footnote!, ground: ground, level: StoryLineLevel.note),
        ],
      RecapPageKind.days => [
          kicker,
          number(),
          StoryBars(
            ground: ground,
            bars: [
              for (final bar in _recap.bars)
                StoryBar(
                  letter: bar.letter,
                  count: bar.own ? bar.count : null,
                  height: bar.height,
                  strong: bar.strong,
                ),
            ],
          ),
          ...lines(StoryLineLevel.body),
        ],
      RecapPageKind.shape => [
          kicker,
          StoryCalendar(
            semanticLabel: page.footnote,
            letters: [for (final w in _recap.studyWeekdays) RecapCopy.weekdayLetters[w]!],
            weeks: [
              for (final week in _recap.weeks)
                StoryWeek(month: week.month, days: [
                  for (final cell in week.cells)
                    switch (cell) {
                      RecapCell.on => TermDot.on,
                      RecapCell.off => TermDot.off,
                      RecapCell.none => TermDot.none,
                    },
                ]),
            ],
          ),
          ...lines(StoryLineLevel.second),
        ],
      RecapPageKind.run => [kicker, number(), ...lines(StoryLineLevel.lead), chip(LucideIcons.calendar)],
      RecapPageKind.time => [kicker, number(accent: true), ...lines(StoryLineLevel.lead)],
      RecapPageKind.back => [
          kicker,
          if (page.numeral != null)
            number()
          else
            StoryHeadline(text: page.headline ?? '', ground: ground),
          ...lines(StoryLineLevel.body),
          chip(LucideIcons.clock3),
        ],
      RecapPageKind.stop => [
          kicker,
          StoryRail(
            before: _recap.stopsBefore,
            stop: page.headline ?? '',
            after: _recap.stopsAfter,
            ground: ground,
          ),
          ...lines(StoryLineLevel.body),
          chip(LucideIcons.mapPin),
        ],
      RecapPageKind.college => [
          kicker,
          StoryHeadline(text: page.headline ?? '', ground: ground, size: StoryHeadlineSize.call),
          if (page.boxTitle != null) StoryBox(title: page.boxTitle!, body: page.boxBody, ground: ground),
          ...lines(StoryLineLevel.second),
        ],
      RecapPageKind.title => [
          kicker,
          StoryHeadline(text: page.headline ?? '', ground: ground, accent: true),
          ...lines(StoryLineLevel.body),
          if (page.cta != null) StoryCta(text: page.cta!, ground: ground),
        ],
      RecapPageKind.short => [kicker, number(), ...lines(StoryLineLevel.lead), chip(null)],
      RecapPageKind.share => const <Widget?>[],
    };
    return parts.whereType<Widget>().toList();
  }

  Widget _sharePage() {
    final busy = _exporting != null;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.s20, BasakSpace.s6, BasakSpace.s20, BasakSpace.s24),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: PosterFrame(boundaryKey: _posterKey, child: RecapScreen.poster(_recap)),
            ),
          ),
          const SizedBox(height: BasakSpace.s14),
          Row(
            children: [
              Expanded(
                child: BasakButton(
                  key: const Key('recap-share'),
                  label: RecapCopy.share,
                  icon: LucideIcons.share2,
                  loading: _exporting == _Export.share,
                  onPressed: busy ? null : () => _export(_Export.share),
                ),
              ),
              const SizedBox(width: BasakSpace.s8),
              Expanded(
                child: BasakButton(
                  key: const Key('recap-save'),
                  label: RecapCopy.save,
                  icon: LucideIcons.download,
                  variant: BasakButtonVariant.surface,
                  loading: _exporting == _Export.save,
                  onPressed: busy ? null : () => _export(_Export.save),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_index];
    final ground = _ground(page.kind);
    final last = _index == _pages.length - 1;
    return Scaffold(
      backgroundColor: ground.background,
      body: StoryTransition(
        index: _index,
        forward: _forward,
        child: StoryScaffold(
          ground: ground,
          rings: _rings(page.kind),
          index: _index,
          count: _pages.length,
          brand: RecapCopy.brand,
          closeLabel: RecapCopy.closeLabel,
          progressLabel: recapFill(RecapCopy.progressLabel, {'ن': '${_index + 1}', 'ن2': '${_pages.length}'}),
          onClose: () => Navigator.of(context).maybePop(),
          onNext: last ? null : () => _go(_index + 1),
          onPrevious: _index == 0 ? null : () => _go(_index - 1),
          child: page.kind == RecapPageKind.share
              ? _sharePage()
              : StoryBody(key: Key('recap-page-${page.kind.name}'), children: _parts(page, ground)),
        ),
      ),
    );
  }
}
