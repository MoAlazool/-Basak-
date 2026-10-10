import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'tokens.dart';

/// Copying, the app's one way: the box that was tapped says so itself. It
/// turns green with a tick and «تم النسخ» for [BasakMotion.copied], then goes
/// back to what it was. No toast comes up from the bottom for a copy.
///
/// [CopyFeedback] is the behaviour (the clipboard, the light tap, the timer);
/// [CopyRow], [CopyButton] and [CopyTile] are the three boxes it is drawn as.
class CopyFeedback extends StatefulWidget {
  /// What goes to the clipboard.
  final String value;

  /// After the value was copied (nothing to say: the box already said it).
  final VoidCallback? onCopied;

  /// [copied] is true while the box says «تم النسخ»; [copy] is its tap.
  final Widget Function(BuildContext context, bool copied, VoidCallback copy) builder;

  const CopyFeedback({super.key, required this.value, required this.builder, this.onCopied});

  /// What the box says in place of its own word.
  static const copiedLabel = 'تم النسخ';

  /// The colour change of a box, at once where the phone asks for less motion.
  static Duration fade(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : BasakMotion.fade;

  @override
  State<CopyFeedback> createState() => _CopyFeedbackState();
}

class _CopyFeedbackState extends State<CopyFeedback> {
  Timer? _timer;
  bool _copied = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.value));
    HapticFeedback.lightImpact();
    widget.onCopied?.call();
    _timer?.cancel();
    setState(() => _copied = true);
    _timer = Timer(BasakMotion.copied, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _copied, _copy);
}

/// One button to a screen reader, whatever it is drawn as: it says what it
/// copies, and then, without being asked, that it copied.
Widget _copyButton({
  required bool copied,
  required String label,
  required VoidCallback? onTap,
  required Widget child,
}) =>
    Semantics(
      liveRegion: copied,
      child: BasakPressable(
        onTap: onTap,
        semanticLabel: copied ? CopyFeedback.copiedLabel : label,
        child: ExcludeSemantics(child: child),
      ),
    );

/// The glyph and the word of a copy box, cross-fading to the tick and
/// «تم النسخ».
class _CopyWord extends StatelessWidget {
  final bool copied;
  final String label;
  final IconData icon;
  final Color color;

  /// The word's own colour where it differs from the glyph's (a tile at rest).
  final Color? wordColor;
  final TextStyle style;
  final double iconSize;

  /// The glyph over the word (a tile) instead of beside it.
  final bool stacked;

  const _CopyWord({
    required this.copied,
    required this.label,
    required this.icon,
    required this.color,
    required this.style,
    this.wordColor,
    this.iconSize = 16,
    this.stacked = false,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(copied ? LucideIcons.check : icon, size: iconSize, color: color);
    final word = Text(
      copied ? CopyFeedback.copiedLabel : label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: style.copyWith(color: wordColor ?? color),
    );
    return AnimatedSwitcher(
        duration: CopyFeedback.fade(context),
        switchInCurve: BasakMotion.fadeCurve,
        switchOutCurve: BasakMotion.fadeCurve,
        child: stacked
            ? Column(
                key: ValueKey(copied),
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [glyph, const SizedBox(height: BasakSpace.s6), word],
              )
            : Row(
                key: ValueKey(copied),
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [glyph, const SizedBox(width: BasakSpace.s6), Flexible(child: word)],
              ),
    );
  }
}

/// A value to copy, as a row of a card: its name over it, «نسخ» at the end.
/// The whole row is the button, and the whole row turns green.
class CopyRow extends StatelessWidget {
  /// «عنوان InstaPay», «رقم الحساب».
  final String label;
  final String value;

  /// Read left to right (a number, an address), at the start edge.
  final bool ltr;
  final VoidCallback? onCopied;

  const CopyRow({super.key, required this.label, required this.value, this.ltr = true, this.onCopied});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return CopyFeedback(
      value: value,
      onCopied: onCopied,
      builder: (context, copied, copy) => _copyButton(
        copied: copied,
        label: 'نسخ $label، $value',
        onTap: copy,
        child: AnimatedContainer(
          duration: CopyFeedback.fade(context),
          curve: BasakMotion.fadeCurve,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s10, vertical: BasakSpace.s6),
          decoration: BoxDecoration(
            color: copied ? colors.successTint : colors.surface,
            borderRadius: BasakRadius.all(BasakRadius.small),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.caption.copyWith(color: copied ? colors.success : colors.ink3)),
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: ltr ? TextDirection.ltr : null,
                        textAlign: ltr && Directionality.of(context) == TextDirection.rtl
                            ? TextAlign.end
                            : TextAlign.start,
                        style: text.rowTitle.copyWith(height: 24 / 16),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: BasakSpace.s12),
              // What the row does, and then that it did it. Not a button of
              // its own: the row is.
              AnimatedContainer(
                duration: CopyFeedback.fade(context),
                curve: BasakMotion.fadeCurve,
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: copied ? colors.surface : colors.sunken,
                  borderRadius: BasakRadius.all(BasakRadius.tile),
                ),
                child: _CopyWord(
                  copied: copied,
                  label: 'نسخ',
                  icon: LucideIcons.copy,
                  color: copied ? colors.success : colors.ink,
                  style: text.bodySmall.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A button that copies: «نسخ المبلغ», «نسخ الرقم». Drawn as the app's small
/// or medium button until it is tapped, then green for a moment.
class CopyButton extends StatelessWidget {
  final String label;

  /// Null: nothing to copy, and the button is drawn disabled.
  final String? value;

  /// [BasakButtonVariant.surface] (white, on the ground) or
  /// [BasakButtonVariant.secondary] (sunken, inside a sheet or a card).
  final BasakButtonVariant variant;
  final BasakButtonSize size;
  final bool expand;
  final VoidCallback? onCopied;

  const CopyButton({
    super.key,
    required this.label,
    required this.value,
    this.variant = BasakButtonVariant.secondary,
    this.size = BasakButtonSize.small,
    this.expand = true,
    this.onCopied,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final enabled = value != null && value!.isNotEmpty;
    final surface = variant == BasakButtonVariant.surface;
    final (double height, double radius, TextStyle style, double pad) = switch (size) {
      BasakButtonSize.large => (54.0, BasakRadius.control, text.rowTitle, BasakSpace.s18),
      BasakButtonSize.medium => (50.0, BasakRadius.control, text.body, BasakSpace.s16),
      BasakButtonSize.small => (44.0, BasakRadius.small, text.bodySmall, BasakSpace.s16),
    };
    return CopyFeedback(
      value: value ?? '',
      onCopied: onCopied,
      builder: (context, copied, copy) => _copyButton(
        copied: copied,
        label: label,
        onTap: enabled ? copy : null,
        child: AnimatedContainer(
          duration: CopyFeedback.fade(context),
          curve: BasakMotion.fadeCurve,
          constraints: BoxConstraints(minHeight: height),
          padding: EdgeInsetsDirectional.symmetric(horizontal: pad),
          alignment: expand ? Alignment.center : null,
          decoration: BoxDecoration(
            color: copied ? colors.successTint : (surface && enabled ? colors.surface : colors.sunken),
            borderRadius: BasakRadius.all(radius),
            boxShadow: surface && enabled && !copied ? BasakShadow.card : null,
          ),
          child: AnimatedSize(
            duration: CopyFeedback.fade(context),
            curve: BasakMotion.fadeCurve,
            child: _CopyWord(
              copied: copied,
              label: label,
              icon: LucideIcons.copy,
              iconSize: size == BasakButtonSize.small ? 16 : 20,
              color: copied ? colors.success : (enabled ? colors.ink : colors.disabled),
              style: style.copyWith(fontWeight: surface ? FontWeight.w600 : FontWeight.w500),
            ),
          ),
        ),
      ),
    );
  }
}

/// A copy among a sheet's row of tiles (`ActionTile`'s shape): «نسخ الرقم»
/// beside «واتساب» and «حفظ الرقم».
class CopyTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onCopied;

  const CopyTile({super.key, required this.label, required this.value, this.onCopied});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return CopyFeedback(
      value: value,
      onCopied: onCopied,
      builder: (context, copied, copy) => _copyButton(
        copied: copied,
        label: label,
        onTap: copy,
        child: AnimatedContainer(
          duration: CopyFeedback.fade(context),
          curve: BasakMotion.fadeCurve,
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s4, vertical: BasakSpace.s10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: copied ? colors.successTint : colors.ground,
            borderRadius: BasakRadius.all(BasakRadius.control),
          ),
          child: _CopyWord(
            copied: copied,
            label: label,
            icon: LucideIcons.copy,
            iconSize: 20,
            stacked: true,
            color: copied ? colors.success : colors.teal,
            wordColor: copied ? colors.success : colors.ink,
            style: context.text.label,
          ),
        ),
      ),
    );
  }
}
