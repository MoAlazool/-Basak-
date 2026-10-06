import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/network/supabase_service.dart';
import 'core/sync/sync_hub.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/models/user_role.dart';
import 'features/auth/presentation/login_register_screen.dart';
import 'features/auth/providers/auth_provider.dart';
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
      home: const SplashGate(child: AuthGate()),
    );
  }
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

    if (authState.isInitialLoading || onboardingDone == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!authState.isAuthenticated) {
      return const LoginRegisterScreen();
    }

    switch (authState.role) {
      case UserRole.student:
        // After an admin password reset the student must choose a new password first.
        return ref.watch(mustChangePasswordProvider).maybeWhen(
              data: (mustChange) =>
                  mustChange ? const ForcePasswordChangeScreen() : const SyncScope(child: StudentMainScreen()),
              orElse: () => const SyncScope(child: StudentMainScreen()),
            );
      case UserRole.supervisor:
        return const SyncScope(child: SupervisorMainScreen());
      case UserRole.admin:
      case UserRole.unknown:
        return Scaffold(
          appBar: AppBar(title: const Text('باصك')),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('حساب الإدارة أو غير محدد الدور داخل تطبيق الموبايل'),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => ref.read(authStateProvider.notifier).signOut(),
                  child: const Text('تسجيل الخروج'),
                ),
              ],
            ),
          ),
        );
    }
  }
}
