import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/network/supabase_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/models/user_role.dart';
import 'features/auth/presentation/login_register_screen.dart';
import 'features/auth/providers/auth_provider.dart';
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
      home: const AuthGate(),
    );
  }
}

/// Dynamic Gateway: Routes user according to their verified role in Supabase
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    if (authState.isInitialLoading) {
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
        return const StudentMainScreen();
      case UserRole.supervisor:
        return const SupervisorMainScreen();
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
