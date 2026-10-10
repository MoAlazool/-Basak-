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

  /// The sign-in stored on this phone, while it can still be used.
  StoredSignIn? _stored;

  /// Why the ordinary sign-in is shown instead of the returning one.
  String? _notice;

  /// The returning sign-in was opened from the square button: ask at once.
  bool _startNow = false;

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
    _stored = entry.stored;
    if (_moved) return;
    if (entry.stored != null) {
      _view = _Entry.returning;
    } else if (entry.fallback != null) {
      _notice = entry.fallbackLine;
      _view = entry.fallbackSupervisor ? _Entry.supervisor : _Entry.signIn;
    }
  }

  void _go(_Entry view, {bool startNow = false}) => setState(() {
        _moved = true;
        _startNow = startNow;
        // The line belongs to the screen it was said on.
        if (view == _Entry.welcome || view == _Entry.signUp) _notice = null;
        _view = view;
      });

  _Entry get _storedSignIn => (_stored?.account.isSupervisor ?? false) ? _Entry.supervisor : _Entry.signIn;

  /// Back from a sign-in: the returning sign-in when there is one.
  _Entry get _home => _stored == null ? _Entry.welcome : _Entry.returning;

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
              startNow: _startNow,
              onPassword: () => _go(_storedSignIn),
              onOtherAccount: () {
                _stored = null;
                ref.invalidate(biometricEntryProvider);
                _go(_Entry.welcome);
              },
              onFallback: (reason) {
                final supervisor = stored.account.isSupervisor;
                _notice = reason.line(stored.kind, supervisor: supervisor);
                // Locked out is the phone's doing and passes; the others
                // have already dropped the stored sign-in.
                if (reason != BiometricFallback.lockedOut) {
                  _stored = null;
                  ref.invalidate(biometricEntryProvider);
                }
                _go(supervisor ? _Entry.supervisor : _Entry.signIn);
              },
            ),
          _Entry.returning => const SizedBox.shrink(),
          _Entry.signIn => LoginScreen(
              key: const ValueKey('login'),
              notice: _notice,
              biometric: stored != null && !stored.account.isSupervisor ? stored.kind : null,
              onBiometric: () => _go(_Entry.returning, startNow: true),
              onBack: () => _go(_home),
              onSignup: () => _go(_Entry.signUp),
              onOtherRole: () => _go(_Entry.supervisor),
            ),
          _Entry.supervisor => LoginScreen(
              key: const ValueKey('supervisor-login'),
              supervisor: true,
              notice: _notice,
              biometric: stored != null && stored.account.isSupervisor ? stored.kind : null,
              onBiometric: () => _go(_Entry.returning, startNow: true),
              onBack: () => _go(_home),
              onSignup: () => _go(_Entry.signUp),
              onOtherRole: () => _go(_Entry.signIn),
            ),
          _Entry.signUp => SignupScreen(
              key: const ValueKey('signup'),
              onBack: () => _go(_Entry.welcome),
            ),
        },
      ),
    );
  }
}
