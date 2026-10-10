import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Remembers (per device) that the first-launch onboarding has been completed.
/// State: null = still reading storage, false = show onboarding, true = done.
class OnboardingController extends StateNotifier<bool?> {
  OnboardingController() : super(null) {
    _load();
  }

  /// Already completed (tests and previews).
  OnboardingController.completed() : super(true);

  static const _storage = FlutterSecureStorage();
  static const _key = 'basak.onboarding.v1.completed';

  Future<void> _load() async {
    try {
      state = await _storage.read(key: _key) == 'true';
    } catch (_) {
      // Unreadable storage must never block the app: treat as completed.
      state = true;
    }
  }

  Future<void> complete({bool openSignup = false, bool openSignIn = false}) async {
    authEntryOpensSignup = openSignup;
    authEntryOpensSignIn = openSignIn;
    state = true;
    try {
      await _storage.write(key: _key, value: 'true');
    } catch (_) {}
  }
}

/// Whether the auth screen should open on registration (set by onboarding's
/// final page). Read once when the auth screen is first built.
bool authEntryOpensSignup = false;

/// Whether the auth screen should open on sign-in (onboarding's «لديّ حساب»).
/// Neither set: the welcome screen.
bool authEntryOpensSignIn = false;

final onboardingProvider =
    StateNotifierProvider<OnboardingController, bool?>((ref) => OnboardingController());
