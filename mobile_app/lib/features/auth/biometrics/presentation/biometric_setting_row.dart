import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:basak_mobile/core/ui/ui.dart';

import '../biometric_device.dart';
import '../biometric_sign_in.dart';
import 'biometric_offer.dart';

/// The account's switch, «الدخول بـ Face ID» (named after what the phone
/// has). Two shapes of the same row:
///
///   * [biometricSettingRow] gives a `SettingRow` for a `SettingRows` card
///     (the student's «التطبيق»), or null on a phone with nothing enrolled;
///   * [BiometricSettingRow] is the row as a widget of its own, for a screen
///     that lays its rows out itself (the supervisor's account). It takes no
///     room on a phone with nothing enrolled.
SettingRow? biometricSettingRow(BuildContext context, WidgetRef ref) {
  final offer = ref.watch(biometricOfferProvider).valueOrNull;
  if (offer == null) return null;
  return SettingRow(
    key: const Key('profile-biometric'),
    label: offer.kind.settingLabel,
    trailing: _BiometricSwitch(kind: offer.kind),
  );
}

class BiometricSettingRow extends ConsumerWidget {
  const BiometricSettingRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(biometricOfferProvider).valueOrNull;
    if (offer == null) return const SizedBox.shrink();
    final enabled = ref.watch(biometricEnabledProvider).valueOrNull ?? false;
    return _Toggle(
      kind: offer.kind,
      builder: (context, busy, toggle) => SwitchRow(
        label: offer.kind.settingLabel,
        value: enabled,
        onChanged: busy ? null : toggle,
      ),
    );
  }
}

class _BiometricSwitch extends ConsumerWidget {
  const _BiometricSwitch({required this.kind});

  final BiometricKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(biometricEnabledProvider).valueOrNull ?? false;
    return _Toggle(
      kind: kind,
      builder: (context, busy, toggle) => BasakSwitch(
        key: const Key('biometric-switch'),
        label: kind.settingLabel,
        value: enabled,
        onChanged: busy ? null : toggle,
      ),
    );
  }
}

/// Switching on asks the phone to confirm its owner; switching off forgets
/// the stored sign-in at once.
class _Toggle extends ConsumerStatefulWidget {
  const _Toggle({required this.kind, required this.builder});

  final BiometricKind kind;
  final Widget Function(BuildContext context, bool busy, ValueChanged<bool> toggle) builder;

  @override
  ConsumerState<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends ConsumerState<_Toggle> {
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (on) {
        await enableBiometricSignIn(context, ref, widget.kind);
      } else {
        await ref.read(biometricSignInProvider).disable();
        ref.invalidate(biometricEnabledProvider);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _busy, _toggle);
}
