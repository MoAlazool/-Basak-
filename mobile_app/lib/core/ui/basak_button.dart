import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Anything tappable that is not a Material button: gives the 120 ms press,
/// the button semantics and a 48 × 48 minimum target.
class BasakPressable extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final String? semanticLabel;
  final bool? selected;

  /// A selection click on tap: tabs and chips.
  final bool selectionHaptic;

  /// Off for a control drawn smaller on purpose inside a larger target.
  final bool enforceTapTarget;

  const BasakPressable({
    super.key,
    required this.onTap,
    required this.child,
    this.semanticLabel,
    this.selected,
    this.selectionHaptic = false,
    this.enforceTapTarget = true,
  });

  @override
  State<BasakPressable> createState() => _BasakPressableState();
}

class _BasakPressableState extends State<BasakPressable> {
  bool _down = false;

  void _set(bool down) {
    if (widget.onTap != null && down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    Widget child = AnimatedScale(
      scale: _down ? BasakMotion.pressScale : 1,
      duration: BasakMotion.press,
      child: widget.child,
    );
    if (widget.enforceTapTarget) {
      child = ConstrainedBox(
        constraints: const BoxConstraints(minWidth: BasakSpace.tapTarget, minHeight: BasakSpace.tapTarget),
        child: child,
      );
    }
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.selectionHaptic) HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: child,
      ),
    );
  }
}

enum BasakButtonVariant {
  /// Teal. One per route, pinned to the bottom.
  primary,

  /// Sunken: the other answer ("لن أركب").
  secondary,

  /// Teal tint: an optional next step.
  tonal,

  /// White with the card shadow: a small action on the ground ("نسخ المبلغ").
  surface,

  /// Text only, teal: "تغيير".
  quiet,

  /// Text only, red: destructive.
  danger,
}

enum BasakButtonSize {
  /// 54 high, radius 16.
  large,

  /// 50 high, radius 16: a pair of answers side by side.
  medium,

  /// 44 high, radius 14.
  small,
}

class BasakButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final BasakButtonVariant variant;
  final BasakButtonSize size;
  final IconData? icon;

  /// Shows a spinner in place of the label and ignores taps.
  final bool loading;

  /// While [loading]: said beside the spinner ("جارٍ الإرسال…").
  final String? loadingLabel;

  /// Fills the width it is given. Off: as wide as its label.
  final bool expand;

  const BasakButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = BasakButtonVariant.primary,
    this.size = BasakButtonSize.large,
    this.icon,
    this.loading = false,
    this.loadingLabel,
    this.expand = true,
  });

  bool get _textOnly => variant == BasakButtonVariant.quiet || variant == BasakButtonVariant.danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final enabled = onPressed != null;

    final (Color background, Color foreground, FontWeight weight) = switch (variant) {
      BasakButtonVariant.primary => (colors.teal, colors.onTeal, FontWeight.w600),
      BasakButtonVariant.secondary => (colors.sunken, colors.ink, FontWeight.w500),
      BasakButtonVariant.tonal => (colors.tealTint, colors.teal, FontWeight.w600),
      BasakButtonVariant.surface => (colors.surface, colors.ink, FontWeight.w600),
      BasakButtonVariant.quiet => (Colors.transparent, colors.teal, FontWeight.w600),
      BasakButtonVariant.danger => (Colors.transparent, colors.danger, FontWeight.w600),
    };
    final fill = enabled || _textOnly ? background : colors.sunken;
    final ink = enabled ? foreground : colors.disabled;

    final (double height, double radius, TextStyle style, double pad) = switch (size) {
      BasakButtonSize.large => (54.0, BasakRadius.control, text.rowTitle, BasakSpace.s18),
      BasakButtonSize.medium => (50.0, BasakRadius.control, text.body, BasakSpace.s16),
      BasakButtonSize.small => (44.0, BasakRadius.small, text.bodySmall, BasakSpace.s16),
    };

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading) ...[
          SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2.25, color: ink),
          ),
          if (loadingLabel != null) ...[
            const SizedBox(width: BasakSpace.s10),
            Flexible(
              child: Text(
                loadingLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(color: ink, fontWeight: weight),
              ),
            ),
          ],
        ] else ...[
          if (icon != null) ...[
            Icon(icon, size: size == BasakButtonSize.small ? 16 : 20, color: ink),
            const SizedBox(width: BasakSpace.s8),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(color: ink, fontWeight: weight),
            ),
          ),
        ],
      ],
    );

    return BasakPressable(
      onTap: loading ? null : onPressed,
      semanticLabel: loading ? (loadingLabel ?? label) : null,
      child: AnimatedContainer(
        duration: BasakMotion.fade,
        curve: BasakMotion.fadeCurve,
        constraints: BoxConstraints(minHeight: height),
        padding: EdgeInsetsDirectional.symmetric(horizontal: _textOnly ? BasakSpace.s12 : pad),
        alignment: expand ? Alignment.center : null,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BasakRadius.all(radius),
          boxShadow: variant == BasakButtonVariant.surface && enabled ? BasakShadow.card : null,
        ),
        child: content,
      ),
    );
  }
}

/// An outlined button on the ink ground, 48 high: «التفاصيل» under the
/// student's card. Quiet on purpose; the card above it is what is read.
class InkOutlineButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// Said in place of [label] to a screen reader, where the label is short
  /// for what the button does («التفاصيل»: «اقلب البطاقة لعرض التفاصيل»).
  final String? semanticLabel;

  const InkOutlineButton({super.key, required this.label, required this.onPressed, this.icon, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BasakPressable(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      child: Container(
        constraints: const BoxConstraints(minHeight: BasakSpace.tapTarget),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BasakRadius.all(BasakRadius.control),
          border: Border.all(color: colors.inkOutline, width: 1.5),
        ),
        child: ExcludeSemantics(
          excluding: semanticLabel != null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: colors.onInk),
                const SizedBox(width: BasakSpace.s8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall.copyWith(color: colors.onInk, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round 44 button holding one icon: back, the bell, call. Its target is 48.
class BasakIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// White with the card shadow (on the ground) or sunken (inside a card).
  final bool onCard;

  /// An unread count, shown as a red badge. Null or zero: no badge.
  final int? badge;

  const BasakIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.onCard = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final count = badge ?? 0;
    return BasakPressable(
      onTap: onPressed,
      semanticLabel: label,
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: onCard ? colors.sunken : colors.surface,
                shape: BoxShape.circle,
                boxShadow: onCard ? null : BasakShadow.card,
              ),
              // Without a tap it is drawn quieter: the next month, on the current one.
              child: Icon(icon, size: 20, color: onPressed == null ? colors.disabled : colors.ink),
            ),
            if (count > 0)
              PositionedDirectional(
                top: -3,
                end: -3,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.badge,
                    borderRadius: BasakRadius.all(BasakRadius.full),
                    border: Border.all(color: colors.ground, width: 2, strokeAlign: BorderSide.strokeAlignOutside),
                  ),
                  child: Text(
                    count > 99 ? '+99' : '$count',
                    textScaler: TextScaler.noScaling,
                    style: context.text.tab.copyWith(color: colors.surface, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
