import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import 'home.dart';
import 'status_chip.dart';
import 'tokens.dart';

/// What the app says about itself: the store rating and the two update states
/// (boards `RateIOS`, `RateAndroid`, `UpdateAvailable`, `UpdateRequired`).

/// How a sheet that asks for something opens: its glyph, the title (with a
/// quiet fact at its far end: a version) and one sentence of why.
class PromptIntro extends StatelessWidget {
  final IconData icon;
  final String title;

  /// A number or a code at the end of the title's line, read left to right.
  final String? fact;
  final String? message;

  /// What a screen reader calls the whole sheet.
  final String semanticLabel;

  const PromptIntro({
    super.key,
    required this.icon,
    required this.title,
    required this.semanticLabel,
    this.fact,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: BasakSpace.s6),
          SheetGlyph(icon),
          const SizedBox(height: BasakSpace.s16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Semantics(header: true, child: Text(title, style: text.title))),
              if (fact != null) ...[
                const SizedBox(width: BasakSpace.s12),
                Text(
                  fact!,
                  textDirection: TextDirection.ltr,
                  style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400),
                ),
              ],
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: BasakSpace.s10),
            Text(message!, style: text.body.copyWith(color: colors.ink2)),
          ],
        ],
      ),
    );
  }
}

/// A short list of things that are true, each behind a green tick, on the
/// ground's colour inside a sheet: what a new version brings.
class CheckLines extends StatelessWidget {
  final List<String> lines;

  const CheckLines({super.key, required this.lines});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s14),
      decoration: BoxDecoration(color: colors.ground, borderRadius: BasakRadius.all(BasakRadius.control)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, line) in lines.indexed) ...[
            if (i > 0) const SizedBox(height: BasakSpace.s10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: BasakSpace.s4),
                  child: Icon(LucideIcons.check, size: 16, color: colors.success),
                ),
                const SizedBox(width: BasakSpace.s10),
                Expanded(child: Text(line, style: context.text.body)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Two or more small facts on one sunken pill, a dot between them:
/// «إصدارك 2.3.1 · المطلوب 2.5.0». Each value reads left to right.
class FactPill extends StatelessWidget {
  final List<({String label, String value})> facts;

  const FactPill({super.key, required this.facts});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The value is isolated so its dots never reorder inside the Arabic line.
    final line = [for (final fact in facts) '${fact.label} \u2066${fact.value}\u2069'].join(' · ');
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s6),
      decoration: BoxDecoration(color: colors.sunken, borderRadius: BasakRadius.all(BasakRadius.full)),
      child: Text(
        line,
        textAlign: TextAlign.center,
        style: context.text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400),
      ),
    );
  }
}

/// A whole screen that stands in the way until one thing is done: an amber
/// glyph, what to do, why, the facts, and under them the way out ([actions]:
/// the one primary button first). The middle scrolls when it cannot fit.
class BlockingNotice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final List<({String label, String value})> facts;
  final List<Widget> actions;

  /// One quiet line under the actions.
  final String? footnote;

  const BlockingNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.facts = const [],
    required this.actions,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s12, vertical: BasakSpace.s8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SheetGlyph(icon, tone: BasakTone.warning),
                        const SizedBox(height: BasakSpace.s18),
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            // 24 / 34: between a question and a page title.
                            style: text.title.copyWith(fontSize: 24, height: 34 / 24),
                          ),
                        ),
                        const SizedBox(height: BasakSpace.s10),
                        Text(message, textAlign: TextAlign.center, style: text.body.copyWith(color: colors.ink2)),
                        if (facts.isNotEmpty) ...[
                          const SizedBox(height: BasakSpace.s20),
                          FactPill(facts: facts),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              for (final (i, action) in actions.indexed) ...[
                if (i > 0) const SizedBox(height: BasakSpace.s2),
                action,
              ],
              if (footnote != null)
                Text(footnote!, textAlign: TextAlign.center, style: text.caption.copyWith(color: colors.ink3)),
            ],
          ),
        ),
      ),
    );
  }
}
