import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/network/supabase_service.dart';
import 'core/sync/sync_hub.dart';
import 'core/theme/app_theme.dart';
import 'core/ui/tokens.dart';
import 'features/app_update/update_gate.dart';
import 'features/auth/biometrics/biometric_sign_in.dart';
import 'features/auth/biometrics/presentation/biometric_offer.dart';
import 'features/auth/models/user_role.dart';
import 'features/auth/presentation/login_register_screen.dart';
import 'features/auth/presentation/wrong_role_screen.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/notifications/presentation/notifications_host.dart';
import 'features/onboarding/onboarding_controller.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/auth/presentation/force_password_change_screen.dart';
import 'features/splash/splash_gate.dart';
import 'features/student/student_main_screen.dart';
import 'features/supervisor/supervisor_main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase client
  try {
    await SupabaseService.initialize();
  } catch (e) {
    debugPrint('Supabase init note: $e');
  }

  runApp(
    const ProviderScope(
      child: BasakApp(),
    ),
  );
}

class BasakApp extends ConsumerWidget {
  const BasakApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'باصك - Basak',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      locale: const Locale('ar'),
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Above every route: the banner of a push that arrives while the app is open.
      builder: (context, child) => BasakRoot(child: NotificationsHost(child: child ?? const SizedBox.shrink())),
      // The update check stands before everything, signed in or not; with no
      // answer (offline, an older server) it is simply the gate under it.
      home: const SplashGate(child: UpdateGate(child: AuthGate())),
    );
  }
}

/// What every screen of the app stands in: the phone's text size is followed
/// from 1.0 to 1.3 and no further, and the status bar's icons are dark, as the
/// ground needs them (a dark page sets its own, see [BasakChrome]).
class BasakRoot extends StatelessWidget {
  final Widget child;

  const BasakRoot({super.key, required this.child});

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: BasakChrome.onGround,
        child: MediaQuery.withClampedTextScaling(
          minScaleFactor: 1,
          maxScaleFactor: basakMaxTextScale,
          child: child,
        ),
      );
}

/// Dynamic Gateway: Routes user according to their verified role in Supabase
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final onboardingDone = ref.watch(onboardingProvider);

    // First launch on this device: onboarding comes before any role routing.
    if (onboardingDone == false) {
      return OnboardingScreen(isSignedIn: authState.isAuthenticated);
    }

    // Nobody signed in: whether this phone has a sign-in stored for Face ID
    // or a fingerprint decides the first screen, so it is read (from the
    // phone alone) before one is shown.
    final entryUnknown = !authState.isAuthenticated &&
        !authState.isInitialLoading &&
        ref.watch(biometricEntryReadyProvider).isLoading;

    if (authState.isInitialLoading || onboardingDone == null || entryUnknown) {
      // A moment only: the session and role are read from the device. It is
      // the splash's last frame, so the splash fading away over it shows no
      // change of colour.
      return const SplashView(progress: 1);
    }

    if (!authState.isAuthenticated) {
      return const LoginRegisterScreen();
    }

    switch (authState.role) {
      case UserRole.student:
        // After an admin password reset the student must choose a new password first.
        return ref.watch(mustChangePasswordProvider).maybeWhen(
              data: (mustChange) => mustChange
                  ? const ForcePasswordChangeScreen()
                  : const BiometricOfferHost(child: SyncScope(child: StudentMainScreen())),
              orElse: () => const BiometricOfferHost(child: SyncScope(child: StudentMainScreen())),
            );
      case UserRole.supervisor:
        return const BiometricOfferHost(child: SyncScope(child: SupervisorMainScreen()));
      case UserRole.admin:
      case UserRole.unknown:
        return const WrongRoleScreen();
    }
  }
}
