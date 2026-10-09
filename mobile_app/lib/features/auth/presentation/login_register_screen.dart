import 'package:flutter/material.dart';

import 'package:basak_mobile/core/ui/ui.dart';

import '../../onboarding/onboarding_controller.dart';
import 'login_screen.dart';
import 'signup_screen.dart';
import 'welcome_screen.dart';

enum _Entry { welcome, signIn, supervisor, signUp }

/// What a phone with nobody signed in shows: the welcome screen, and from it
/// the student's sign-in, the supervisor's sign-in and the sign-up. They are
/// switched in place, not pushed: once someone is signed in the whole entry
/// is replaced by the app, with no route left over it.
class LoginRegisterScreen extends StatefulWidget {
  const LoginRegisterScreen({super.key});

  @override
  State<LoginRegisterScreen> createState() => _LoginRegisterScreenState();
}

class _LoginRegisterScreenState extends State<LoginRegisterScreen> {
  // Onboarding's last page opens registration or sign-in directly.
  _Entry _view = authEntryOpensSignup
      ? _Entry.signUp
      : authEntryOpensSignIn
          ? _Entry.signIn
          : _Entry.welcome;

  @override
  void initState() {
    super.initState();
    // Said once: signing out later lands on the welcome screen.
    authEntryOpensSignup = false;
    authEntryOpensSignIn = false;
  }

  void _go(_Entry view) => setState(() => _view = view);

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _view == _Entry.welcome,
        onPopInvokedWithResult: (didPop, _) {
          // The sign-up walks back through its own steps first.
          if (!didPop && _view != _Entry.signUp) _go(_Entry.welcome);
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
            _Entry.signIn => LoginScreen(
                key: const ValueKey('login'),
                onBack: () => _go(_Entry.welcome),
                onSignup: () => _go(_Entry.signUp),
                onOtherRole: () => _go(_Entry.supervisor),
              ),
            _Entry.supervisor => LoginScreen(
                key: const ValueKey('supervisor-login'),
                supervisor: true,
                onBack: () => _go(_Entry.welcome),
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
