import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:basak_mobile/core/ui/ui.dart';

import '../../../../core/widgets/avatar_image.dart';
import '../biometric_device.dart';
import '../biometric_sign_in.dart';

/// «اختر الحساب»: whose stored sign-in to use, when this phone holds several
/// and the form does not say which. Names and numbers with their middle
/// hidden only; the phone's check comes after the choice.
Future<StoredSignIn?> showBiometricAccountSheet(BuildContext context, List<StoredSignIn> saved) =>
    BasakSheet.show<StoredSignIn>(
      context,
      builder: (context) {
        final colors = context.colors;
        final text = context.text;
        return Semantics(
          container: true,
          label: 'اختيار الحساب',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text('اختر الحساب', style: text.sheetTitle)),
              const SizedBox(height: BasakSpace.s4),
              Text('الحسابات التي فعّلت الدخول السريع على هذا الهاتف.',
                  style: text.bodySmall.copyWith(color: colors.ink2)),
              const SizedBox(height: BasakSpace.s14),
              for (final stored in saved) ...[
                BasakPressable(
                  key: Key('biometric-account-${stored.account.userId}'),
                  onTap: () => Navigator.of(context).pop(stored),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 64),
                    padding:
                        const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s10),
                    decoration:
                        BoxDecoration(color: colors.ground, borderRadius: BasakRadius.all(BasakRadius.control)),
                    child: Row(
                      children: [
                        PhotoRing(
                          name: stored.account.firstName,
                          image: stored.account.photoUrl == null ? null : avatarImage(stored.account.photoUrl!),
                          size: 44,
                        ),
                        const SizedBox(width: BasakSpace.s12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stored.account.firstName.isEmpty
                                    ? (stored.account.isSupervisor ? 'مشرف' : 'طالب')
                                    : stored.account.firstName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.rowTitle.copyWith(fontWeight: FontWeight.w500),
                              ),
                              if (stored.account.maskedPhone.isNotEmpty)
                                SizedBox(
                                  width: double.infinity,
                                  child: Text(
                                    stored.account.maskedPhone,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: TextDirection.ltr,
                                    // Read left to right, still at the start edge.
                                    textAlign: Directionality.of(context) == TextDirection.rtl
                                        ? TextAlign.end
                                        : TextAlign.start,
                                    style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: BasakSpace.s8),
                        Icon(stored.kind.icon, size: 20, color: colors.teal),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: BasakSpace.s8),
              ],
            ],
          ),
        );
      },
    );

/// The square button beside a form's main button, on a phone that has a
/// sign-in stored for Face ID or a fingerprint: a tap asks the phone and
/// signs in, with nothing typed.
///
/// Whose sign-in: the only one stored; with several, the one whose number is
/// in the form ([typed]), and when the form says nothing the person is asked
/// (see [showBiometricAccountSheet]). What goes wrong is handed back to the
/// form, which is the way round it.
class BiometricQuickButton extends ConsumerStatefulWidget {
  const BiometricQuickButton({
    super.key,
    required this.saved,
    this.typed,
    this.enabled = true,
    this.onBusy,
    this.onNotRecognised,
    this.onOffline,
    this.onUsePassword,
    this.onFallback,
  });

  /// The sign-ins this phone can use, the most recently used first. Not empty.
  final List<StoredSignIn> saved;

  /// What is in the form's first field now.
  final String Function()? typed;

  /// Off while the form itself is busy.
  final bool enabled;

  /// The phone's check is up, or its sign-in is on its way to the server.
  final ValueChanged<bool>? onBusy;

  /// Closed or not recognised: nothing was lost, the button tries again.
  final void Function(StoredSignIn stored)? onNotRecognised;
  final VoidCallback? onOffline;

  /// The phone's prompt offered the password and it was chosen.
  final VoidCallback? onUsePassword;

  /// That account's stored sign-in cannot be used (its session ended, the
  /// phone's biometrics changed, the phone locked its check).
  final void Function(StoredSignIn stored, BiometricFallback reason)? onFallback;

  @override
  ConsumerState<BiometricQuickButton> createState() => _BiometricQuickButtonState();
}

class _BiometricQuickButtonState extends ConsumerState<BiometricQuickButton> {
  bool _busy = false;

  void _setBusy(bool busy) {
    if (mounted) setState(() => _busy = busy);
    widget.onBusy?.call(busy);
  }

  Future<void> _signIn() async {
    if (_busy || widget.saved.isEmpty) return;
    FocusScope.of(context).unfocus();
    var stored = BiometricSignIn.pick(widget.saved, widget.typed?.call() ?? '');
    stored ??= await showBiometricAccountSheet(context, widget.saved);
    if (stored == null || !mounted) return;
    _setBusy(true);
    final result = await ref.read(biometricSignInProvider).signIn(userId: stored.account.userId);
    if (!mounted) return;
    switch (result) {
      case BiometricSignInResult.signedIn:
        return; // the app replaces the whole entry
      case BiometricSignInResult.notRecognised:
        HapticFeedback.mediumImpact();
        _setBusy(false);
        widget.onNotRecognised?.call(stored);
      case BiometricSignInResult.offline:
        _setBusy(false);
        widget.onOffline?.call();
      case BiometricSignInResult.usePassword:
        _setBusy(false);
        widget.onUsePassword?.call();
      case BiometricSignInResult.lockedOut:
      case BiometricSignInResult.changed:
      case BiometricSignInResult.expired:
        _setBusy(false);
        widget.onFallback?.call(stored, result.fallback!);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Named and drawn after what the phone offers, the same for every account.
    final kind = widget.saved.first.kind;
    return GroundSquareButton(
      icon: kind.icon,
      label: kind.signInLabel,
      loading: _busy,
      onPressed: widget.enabled ? _signIn : null,
    );
  }
}
