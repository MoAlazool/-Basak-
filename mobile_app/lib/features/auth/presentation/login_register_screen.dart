import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:basak_mobile/core/ui/ui.dart';

import '../../onboarding/onboarding_controller.dart';
import '../biometrics/biometric_sign_in.dart';
import '../biometrics/presentation/returning_sign_in_screen.dart';
import 'login_screen.dart';
import 'signup_screen.dart';
import 'welcome_screen.dart';

enum _Entry { welcome, returning, signIn, supervisor, signUp }

/// What a phone with nobody signed in shows: the welcome screen, and from it
/// the student's sign-in, the supervisor's sign-in and the sign-up. A phone
/// that has a sign-in stored for Face ID or a fingerprint opens on the
/// returning sign-in instead. They are switched in place, not pushed: once
/// someone is signed in the whole entry is replaced by the app, with no route
/// left over it.
class LoginRegisterScreen extends ConsumerStatefulWidget {
  const LoginRegisterScreen({super.key});

  @override
  ConsumerState<LoginRegisterScreen> createState() => _LoginRegisterScreenState();
}

class _LoginRegisterScreenState extends ConsumerState<LoginRegisterScreen> {
  // Onboarding's last page opens registration or sign-in directly.
  _Entry _view = authEntryOpensSignup
      ? _Entry.signUp
      : authEntryOpensSignIn
          ? _Entry.signIn
          : _Entry.welcome;

  /// The sign-ins stored on this phone that can still be used, the most
  /// recently used first. The first is the one the returning sign-in shows;
  /// all of them are behind the square button of the forms.
  List<StoredSignIn> _saved = const [];

  StoredSignIn? get _stored => _saved.isEmpty ? null : _saved.first;

  /// Why the ordinary sign-in is shown instead of the returning one.
  String? _notice;

  /// Someone has already chosen where to go: what the phone has stored no
  /// longer decides the first screen.
  bool _moved = false;

  @override
  void initState() {
    super.initState();
    _moved = _view != _Entry.welcome;
    // Said once: signing out later lands on the welcome screen.
    authEntryOpensSignup = false;
    authEntryOpensSignIn = false;
    // Known already when the app's gate waited for it; otherwise it arrives
    // a moment later (see build).
    final entry = ref.read(biometricEntryProvider).valueOrNull;
    if (entry != null) _open(entry);
  }

  /// What the phone has stored decides the first screen, once.
  void _open(BiometricEntry entry) {
    _saved = entry.saved;
    if (_moved) return;
    if (entry.stored != null) {
      _view = _Entry.returning;
    } else if (entry.fallback != null) {
      _notice = entry.fallbackLine;
      _view = entry.fallbackSupervisor ? _Entry.supervisor : _Entry.signIn;
    }
  }

  void _go(_Entry view) => setState(() {
        _moved = true;
        // The line belongs to the screen it was said on.
        if (view == _Entry.welcome || view == _Entry.signUp) _notice = null;
        _view = view;
      });

  /// The stored sign-in cannot be used: the ordinary sign-in, with the
  /// reason's line above its fields.
  void _fallBack(StoredSignIn stored, BiometricFallback reason) {
    final supervisor = stored.account.isSupervisor;
    _notice = reason.line(stored.kind, supervisor: supervisor);
    // Locked out is the phone's doing and passes, so the button stays; the
    // others have already dropped the stored sign-in, and the button with it.
    // Only that account's: whoever else is stored keeps their button.
    if (reason != BiometricFallback.lockedOut) {
      _saved = [
        for (final other in _saved)
          if (other.account.userId != stored.account.userId) other,
      ];
      ref.invalidate(biometricEntryProvider);
    }
    // Said on the form the person is on, or on the form of whose it was.
    if (_view == _Entry.signIn || _view == _Entry.supervisor) {
      setState(() {});
    } else {
      _go(supervisor ? _Entry.supervisor : _Entry.signIn);
    }
  }

  _Entry get _storedSignIn => (_stored?.account.isSupervisor ?? false) ? _Entry.supervisor : _Entry.signIn;

  /// Back from a sign-in: the returning sign-in when there is one.
  _Entry get _home => _saved.isEmpty ? _Entry.welcome : _Entry.returning;

  @override
  Widget build(BuildContext context) {
    ref.listen(biometricEntryProvider, (_, next) {
      final entry = next.valueOrNull;
      if (entry != null) setState(() => _open(entry));
    });
    final stored = _stored;

    return PopScope(
      canPop: _view == _home,
      onPopInvokedWithResult: (didPop, _) {
        // The sign-up walks back through its own steps first.
        if (!didPop && _view != _Entry.signUp) _go(_home);
      },
      child: AnimatedSwitcher(
        duration: BasakMotion.fade,
        switchInCurve: BasakMotion.fadeCurve,
        switchOutCurve: BasakMotion.fadeCurve,
        child: switch (_view) {
          _Entry.welcome => WelcomeScreen(
              key: const ValueKey('welcome'),
              onSignup: () => _go(_Entry.signUp),
              onSignIn: () => _go(_Entry.signIn),
              onSupervisor: () => _go(_Entry.supervisor),
            ),
          _Entry.returning when stored != null => ReturningSignInScreen(
              key: const ValueKey('returning'),
              stored: stored,
              onPassword: () => _go(_storedSignIn),
              // Someone else's turn: the ordinary sign-in. Nothing stored is
              // dropped, and the form keeps the button for it.
              onOtherAccount: () => _go(_Entry.signIn),
              onFallback: (reason) => _fallBack(stored, reason),
            ),
          _Entry.returning => const SizedBox.shrink(),
          _Entry.signIn => LoginScreen(
              key: const ValueKey('login'),
              notice: _notice,
              saved: _saved,
              onBiometricFallback: _fallBack,
              onBack: () => _go(_home),
              onSignup: () => _go(_Entry.signUp),
              onOtherRole: () => _go(_Entry.supervisor),
            ),
          _Entry.supervisor => LoginScreen(
              key: const ValueKey('supervisor-login'),
              supervisor: true,
              notice: _notice,
              saved: _saved,
              onBiometricFallback: _fallBack,
              onBack: () => _go(_home),
              onSignup: () => _go(_Entry.signUp),
              onOtherRole: () => _go(_Entry.signIn),
            ),
          _Entry.signUp => SignupScreen(
              key: const ValueKey('signup'),
              saved: _saved,
              onBiometricFallback: _fallBack,
              onBack: () => _go(_home),
            ),
        },
      ),
    );
  }
}
