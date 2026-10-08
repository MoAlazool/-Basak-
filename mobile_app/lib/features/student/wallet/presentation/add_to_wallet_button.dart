import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
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
    final messenger = ScaffoldMessenger.of(context);
    try {
      final added = await ref.read(walletPassRepoProvider).addToWallet(platform);
      if (added && platform == WalletPlatform.apple) {
        messenger.showSnackBar(const SnackBar(
          content: Text('تمت إضافة بطاقتك إلى Apple Wallet.'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ));
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
    final apple = platform == WalletPlatform.apple;
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
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(LucideIcons.wallet, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text('إضافة إلى Google Wallet',
                    style: AppTextStyles.bodyMedium.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ]),
            ),
          Material(
            color: _busy ? Colors.black45 : Colors.transparent,
            borderRadius: BorderRadius.circular(apple ? 12 : 26),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _busy ? null : _add,
              child: _busy
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
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
