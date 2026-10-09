import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';

import '../../../../core/ui/ui.dart';
import '../../qr/data/student_qr_repository.dart';
import '../data/wallet_pass_repository.dart';

final walletPassRepoProvider = Provider((ref) => WalletPassRepository());

/// "Add to Apple Wallet" on iPhone, "Add to Google Wallet" on Android, nothing
/// elsewhere. The student cannot change how the card looks: the design is set
/// once for everyone from the admin dashboard.
class AddToWalletButton extends ConsumerStatefulWidget {
  final StudentPassDetails pass;

  /// Overridable for tests; defaults to the device's platform.
  final WalletPlatform? platform;

  const AddToWalletButton({super.key, required this.pass, this.platform});

  /// The card is the student's identity, so it is offered whenever there is a
  /// QR to put on it — with or without an active subscription. Issuing needs
  /// the server, so it is hidden while the screen shows offline-cached data.
  static bool canOffer(StudentPassDetails pass, WalletPlatform? platform) =>
      platform != null &&
      !pass.isOfflineCache &&
      (pass.qrValue ?? '').isNotEmpty;

  @override
  ConsumerState<AddToWalletButton> createState() => _AddToWalletButtonState();
}

class _AddToWalletButtonState extends ConsumerState<AddToWalletButton> {
  bool _busy = false;

  WalletPlatform? get _platform =>
      widget.platform ?? WalletPassRepository.platformFor(defaultTargetPlatform);

  Future<void> _add() async {
    final platform = _platform;
    if (platform == null || _busy) return;
    setState(() => _busy = true);
    try {
      final added = await ref.read(walletPassRepoProvider).addToWallet(platform);
      if (added && platform == WalletPlatform.apple && mounted) {
        BasakToast.show(context, 'تمت إضافة بطاقتك إلى Apple Wallet.');
      }
    } catch (error) {
      if (mounted) {
        BasakToast.show(context, error.toString().replaceFirst('Exception: ', ''), kind: BasakToastKind.failure);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform = _platform;
    if (!AddToWalletButton.canOffer(widget.pass, platform)) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final apple = platform == WalletPlatform.apple;
    // Each store's official button: Apple's is drawn by PassKit, Google's is
    // the black pill its brand rules describe.
    final shape = BasakRadius.all(apple ? BasakRadius.tile : BasakRadius.full);
    return Semantics(
      button: true,
      label: apple ? 'إضافة إلى Apple Wallet' : 'إضافة إلى Google Wallet',
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: Stack(fit: StackFit.expand, children: [
          if (apple)
            // Apple's own "Add to Apple Wallet" button, drawn by PassKit in the
            // phone's language. Taps are handled by the layer above it.
            const IgnorePointer(
              child: UiKitView(viewType: 'basak/add_pass_button'),
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(color: colors.walletBlack, borderRadius: shape),
              // Beside "كل التفاصيل" on a narrow phone the label shrinks to fit.
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.wallet, color: colors.onInk, size: 20),
                    const SizedBox(width: BasakSpace.s10),
                    Text('إضافة إلى Google Wallet',
                        style: context.text.bodySmall.copyWith(color: colors.onInk, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          Material(
            color: _busy ? colors.walletBusy : Colors.transparent,
            borderRadius: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _busy ? null : _add,
              child: _busy
                  ? Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: colors.onInk),
                      ),
                    )
                  : null,
            ),
          ),
        ]),
      ),
    );
  }
}
