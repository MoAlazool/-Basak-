import 'package:flutter/material.dart';

import 'basak_button.dart';
import 'tokens.dart';

/// What signing in with Face ID or a fingerprint is drawn with (boards
/// `SignInFace`, `SignInTouch`, `SignInBioFailed`, `SignIn`, `Profile`).

/// The large glyph of the returning sign-in: 120, white on the ground, the
/// phone's method in teal. Amber when the phone did not recognise its owner.
/// A tap starts the check, as the button under it does.
class BiometricGlyph extends StatelessWidget {
  final IconData icon;

  /// What a tap does, said to a screen reader.
  final String label;
  final VoidCallback? onTap;

  /// Not recognised: amber on its tint.
  final bool warning;

  const BiometricGlyph({super.key, required this.icon, required this.label, required this.onTap, this.warning = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BasakPressable(
      onTap: onTap,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: BasakMotion.fade,
        curve: BasakMotion.fadeCurve,
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: warning ? colors.warningTint : colors.surface,
          shape: BoxShape.circle,
          boxShadow: BasakShadow.card,
        ),
        child: Icon(icon, size: 56, color: warning ? colors.warning : colors.teal),
      ),
    );
  }
}

/// A square button on the ground, as tall as the primary one beside it (white,
/// teal glyph; `SquareIconButton` is its sunken sibling inside a dock):
/// Face ID or the fingerprint next to «دخول».
class GroundSquareButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const GroundSquareButton({super.key, required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BasakPressable(
      onTap: onPressed,
      semanticLabel: label,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BasakRadius.all(BasakRadius.control),
          boxShadow: BasakShadow.card,
        ),
        child: Icon(icon, size: 24, color: onPressed == null ? colors.disabled : colors.teal),
      ),
    );
  }
}

/// The app's switch: 46 × 28, teal when on. The row it closes names it, so
/// [label] is only what a screen reader says.
class BasakSwitch extends StatelessWidget {
  final bool value;

  /// Null: shown but not answering (while the change is being made).
  final ValueChanged<bool>? onChanged;
  final String label;

  const BasakSwitch({super.key, required this.value, required this.onChanged, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      toggled: value,
      child: BasakPressable(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        semanticLabel: label,
        selectionHaptic: true,
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: AnimatedContainer(
            duration: BasakMotion.fade,
            curve: BasakMotion.fadeCurve,
            width: 46,
            height: 28,
            padding: const EdgeInsetsDirectional.all(3),
            decoration: BoxDecoration(
              color: value ? colors.teal : colors.grabber,
              borderRadius: BasakRadius.all(BasakRadius.small),
            ),
            child: AnimatedAlign(
              duration: BasakMotion.fade,
              curve: BasakMotion.fadeCurve,
              alignment: value ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: colors.surface, shape: BoxShape.circle, boxShadow: BasakShadow.card),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A switch with its name, 52 high: the row of a setting that stands on its
/// own, outside a `SettingRows` card.
class SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const SwitchRow({super.key, required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: Text(label, style: context.text.body.copyWith(fontWeight: FontWeight.w500)),
              ),
            ),
            const SizedBox(width: BasakSpace.s12),
            BasakSwitch(value: value, onChanged: onChanged, label: label),
          ],
        ),
      );
}
