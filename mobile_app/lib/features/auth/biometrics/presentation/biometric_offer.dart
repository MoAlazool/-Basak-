import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:basak_mobile/core/ui/ui.dart';

import '../../../../core/sync/session.dart';
import '../biometric_device.dart';
import '../biometric_sign_in.dart';

/// What the app says when switching the sign-in on did not go through.
String biometricNotEnabledMessage(BiometricKind kind, BiometricCheck check) => switch (check) {
      BiometricCheck.lockedOut => 'أوقف هاتفك التحقق مؤقتاً بعد عدة محاولات. حاول لاحقاً.',
      BiometricCheck.unavailable => 'لا توجد بصمة أو وجه مسجّل في هاتفك الآن.',
      _ => 'لم يتم تفعيل ${kind.settingLabel}. حاول مرة أخرى.',
    };

/// Switches the sign-in on for the signed-in account: the phone confirms its
/// owner once, then the account is remembered. Says so either way. True when
/// it is on.
Future<bool> enableBiometricSignIn(BuildContext context, WidgetRef ref, BiometricKind kind) async {
  final account = await ref.read(biometricAccountReaderProvider)();
  if (account == null) return false;
  final check = await ref.read(biometricSignInProvider).enable(account);
  ref.invalidate(biometricEnabledProvider);
  if (!context.mounted) return check == BiometricCheck.passed;
  if (check == BiometricCheck.passed) {
    BasakToast.show(context, 'تم تفعيل ${kind.settingLabel}.');
    return true;
  }
  BasakToast.show(context, biometricNotEnabledMessage(kind, check), kind: BasakToastKind.failure);
  return false;
}

/// «دخول أسرع بـ Face ID؟» (board `BioEnable`): what it does, that the face
/// or the fingerprint never leaves the phone, «تفعيل» and «ليس الآن». Answers
/// true for «تفعيل».
Future<bool?> showBiometricOfferSheet(BuildContext context, BiometricKind kind) => BasakSheet.show<bool>(
      context,
      builder: (context) => Semantics(
        container: true,
        label: 'تفعيل الدخول بالقياسات الحيوية',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: BasakSpace.s6),
            SheetGlyph(kind.icon),
            const SizedBox(height: BasakSpace.s16),
            Semantics(header: true, child: Text(kind.offerTitle, style: context.text.title)),
            const SizedBox(height: BasakSpace.s10),
            Text(kind.offerBody, style: context.text.body.copyWith(color: context.colors.ink2)),
            const SizedBox(height: BasakSpace.s6),
          ],
        ),
      ),
      primary: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BasakButton(
            key: const Key('biometric-offer-enable'),
            label: kind.enableLabel,
            icon: kind.icon,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: BasakSpace.s2),
          SheetLink(
            key: const Key('biometric-offer-later'),
            label: 'ليس الآن',
            onTap: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );

/// Waits until «دخول أسرع؟» has been asked and answered (or was never due),
/// for whatever else the app asks at its start. False when the screen that
/// wanted to ask is gone meanwhile.
Future<bool> afterBiometricOffer(BuildContext context, WidgetRef ref) async {
  for (var waits = 0; waits < 240 && context.mounted && biometricOfferComesFirst(ref); waits++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return context.mounted;
}

/// Sits around the app of a signed-in account and, as soon as the app is up
/// after a sign-in with a password or a new account, asks «دخول أسرع؟». Never
/// on a phone with no biometrics enrolled, never twice for the same account,
/// never for an account that has it on already, and never on top of another
/// sheet: it waits until the screen under it is the one on show. It is the
/// first thing the app asks: the notifications explainer waits behind it
/// (`biometricOfferComesFirst`).
class BiometricOfferHost extends ConsumerStatefulWidget {
  const BiometricOfferHost({super.key, required this.child});

  final Widget child;

  /// One beat after the app's first frame, so the sheet rises over a drawn
  /// screen and not over the last frame of the sign-in.
  static const delay = Duration(milliseconds: 350);

  @override
  ConsumerState<BiometricOfferHost> createState() => _BiometricOfferHostState();
}

class _BiometricOfferHostState extends ConsumerState<BiometricOfferHost> {
  Timer? _timer;
  int _waits = 0;

  @override
  void initState() {
    super.initState();
    if (ref.read(biometricOfferPendingProvider)) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _waits = 0;
    _timer = Timer(BiometricOfferHost.delay, _offer);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _offer() async {
    if (!mounted || !ref.read(biometricOfferPendingProvider)) return;
    // Something else is being answered: wait for it, for a while.
    if (ModalRoute.of(context)?.isCurrent != true) {
      if (++_waits <= 60) {
        _timer = Timer(const Duration(seconds: 1), _offer);
      } else {
        // Given up for this run: nothing else is kept waiting for it.
        ref.read(biometricOfferPendingProvider.notifier).state = false;
      }
      return;
    }
    // Still "first" while it is being decided and shown: whatever else the
    // app wants to ask waits until this is answered.
    final open = ref.read(biometricOfferOpenProvider.notifier);
    open.state = true;
    ref.read(biometricOfferPendingProvider.notifier).state = false;
    try {
      final userId = ref.read(sessionUserIdProvider);
      if (userId == null) return;
      final signIn = ref.read(biometricSignInProvider);
      final offer = await signIn.offerFor(userId);
      if (offer == null || !mounted) return;
      // Asked once, whatever the answer; the switch in the account stays.
      await signIn.markOffered(userId);
      if (!mounted) return;
      if (await showBiometricOfferSheet(context, offer.kind) != true || !mounted) return;
      await enableBiometricSignIn(context, ref, offer.kind);
    } finally {
      open.state = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(biometricOfferPendingProvider, (_, pending) {
      if (pending) _schedule();
    });
    return widget.child;
  }
}
