import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

/// Existing auth entry point retained for the app router.
class LoginRegisterScreen extends StatefulWidget {
  const LoginRegisterScreen({super.key});

  @override
  State<LoginRegisterScreen> createState() => _LoginRegisterScreenState();
}

class _LoginRegisterScreenState extends State<LoginRegisterScreen> {
  bool _showSignup = false;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 360),
        reverseDuration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0.045, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: _showSignup
            ? SignupScreen(
                key: const ValueKey('signup'),
                onLogin: () => setState(() => _showSignup = false),
              )
            : LoginScreen(
                key: const ValueKey('login'),
                onSignup: () => setState(() => _showSignup = true),
              ),
      );
}
