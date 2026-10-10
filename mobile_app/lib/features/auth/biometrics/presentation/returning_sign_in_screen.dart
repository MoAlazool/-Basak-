import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:basak_mobile/core/ui/ui.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/avatar_image.dart';
import '../biometric_device.dart';
import '../biometric_sign_in.dart';

/// The sign-in of someone this phone already knows (boards `SignInFace`,
/// `SignInTouch`, `SignInBioFailed`): their photo and first name, the number
/// with its middle hidden, and the phone's own check. The password is one tap
/// away before, during and after a failed try. While the phone's prompt is up
/// the app draws nothing over itself (board `SignInPrompt`).
class ReturningSignInScreen extends ConsumerStatefulWidget {
  const ReturningSignInScreen({
    super.key,
    required this.stored,
    required this.onPassword,
    required this.onOtherAccount,
    required this.onFallback,
    this.startNow = false,
  });

  final StoredSignIn stored;

  /// «الدخول بكلمة المرور».
  final VoidCallback onPassword;

  /// «حساب آخر»: the stored sign-in is already gone when this is called.
  final VoidCallback onOtherAccount;

  /// The stored sign-in cannot be used (changed, expired, locked out): the
  /// ordinary sign-in, with the reason's line.
  final void Function(BiometricFallback reason) onFallback;

  /// Opened from the square button beside «دخول»: the phone asks at once.
  final bool startNow;

  /// Said under the glyph when the server could not be reached.
  static const offlineLine = 'تعذر الاتصال بالإنترنت. تحقق من الاتصال وحاول مرة أخرى.';

  @override
  ConsumerState<ReturningSignInScreen> createState() => _ReturningSignInScreenState();
}

class _ReturningSignInScreenState extends ConsumerState<ReturningSignInScreen> {
  bool _busy = false;
  bool _failed = false;

  /// No connection: nothing was lost, the same button tries again.
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    if (widget.startNow) WidgetsBinding.instance.addPostFrameCallback((_) => _signIn());
  }

  Future<void> _signIn() async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _offline = false;
    });
    final result = await ref.read(biometricSignInProvider).signIn();
    if (!mounted) return;
    switch (result) {
      case BiometricSignInResult.signedIn:
        return; // the app replaces the whole entry
      case BiometricSignInResult.notRecognised:
        HapticFeedback.mediumImpact();
        setState(() {
          _busy = false;
          _failed = true;
        });
      case BiometricSignInResult.offline:
        setState(() {
          _busy = false;
          _offline = true;
        });
      case BiometricSignInResult.usePassword:
        setState(() => _busy = false);
        widget.onPassword();
      case BiometricSignInResult.lockedOut:
      case BiometricSignInResult.changed:
      case BiometricSignInResult.expired:
        setState(() => _busy = false);
        widget.onFallback(result.fallback!);
    }
  }

  Future<void> _otherAccount() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(biometricSignInProvider).useAnotherAccount();
    if (!mounted) return;
    widget.onOtherAccount();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final account = widget.stored.account;
    final kind = widget.stored.kind;
    final photo = account.photoUrl;

    final line = _offline
        ? ReturningSignInScreen.offlineLine
        : _failed
            ? biometricNotRecognisedLine(supervisor: account.isSupervisor)
            : kind.hint;
    final amber = _failed || _offline;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: basakMaxTextScale,
      child: Scaffold(
        backgroundColor: colors.ground,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth),
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  child: ConstrainedBox(
                    // At least the screen, so the blocks spread over it.
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          BasakSpace.gutter, BasakSpace.s12, BasakSpace.gutter, BasakSpace.s16),
                      child: Column(
                        // Three blocks with the room shared between them: the glyph sits
                        // midway on a tall screen, and the page scrolls on a short one.
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: EntryLink(
                                  key: const Key('returning-other-account'),
                                  label: 'حساب آخر',
                                  inline: true,
                                  strong: true,
                                  onTap: _busy ? null : _otherAccount,
                                ),
                              ),
                              const SizedBox(height: BasakSpace.s18 + BasakSpace.s20),
                              Center(
                                child: PhotoRing(
                                  image: photo == null ? null : avatarImage(photo),
                                  name: account.firstName,
                                  size: 88,
                                ),
                              ),
                              const SizedBox(height: BasakSpace.s16),
                              Semantics(
                                header: true,
                                child: Text(
                                  account.firstName.isEmpty ? 'أهلاً بعودتك' : 'أهلاً بعودتك، ${account.firstName}',
                                  textAlign: TextAlign.center,
                                  style: text.display.copyWith(fontSize: 26, height: 36 / 26),
                                ),
                              ),
                              if (account.maskedPhone.isNotEmpty) ...[
                                const SizedBox(height: BasakSpace.s6),
                                Text(
                                  account.maskedPhone,
                                  textAlign: TextAlign.center,
                                  textDirection: TextDirection.ltr,
                                  style: text.body.copyWith(color: colors.ink2),
                                ),
                              ],
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s18),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  BiometricGlyph(
                                    key: const Key('returning-glyph'),
                                    icon: kind.icon,
                                    label: line,
                                    warning: _failed,
                                    onTap: _busy ? null : _signIn,
                                  ),
                                  const SizedBox(height: BasakSpace.s16),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 280),
                                    child: Semantics(
                                      liveRegion: amber,
                                      child: ExcludeSemantics(
                                        child: Text(
                                          line,
                                          key: const Key('returning-line'),
                                          textAlign: TextAlign.center,
                                          style: text.body.copyWith(color: amber ? colors.warning : colors.ink2),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              BasakButton(
                                key: const Key('returning-submit'),
                                label: _failed ? 'حاول مرة أخرى' : kind.signInLabel,
                                icon: _failed ? LucideIcons.refreshCw : kind.icon,
                                loading: _busy,
                                onPressed: _signIn,
                              ),
                              if (_failed) ...[
                                const SizedBox(height: BasakSpace.s8),
                                BasakButton(
                                  key: const Key('returning-password'),
                                  label: 'الدخول بكلمة المرور',
                                  variant: BasakButtonVariant.surface,
                                  size: BasakButtonSize.medium,
                                  onPressed: _busy ? null : widget.onPassword,
                                ),
                              ] else ...[
                                const SizedBox(height: BasakSpace.s2),
                                EntryLink(
                                  key: const Key('returning-password'),
                                  label: 'الدخول بكلمة المرور',
                                  tone: EntryLinkTone.quiet,
                                  onTap: _busy ? null : widget.onPassword,
                                ),
                                if (kind.alsoLine != null)
                                  Text(
                                    kind.alsoLine!,
                                    textAlign: TextAlign.center,
                                    style: text.caption.copyWith(color: colors.ink3),
                                  ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
