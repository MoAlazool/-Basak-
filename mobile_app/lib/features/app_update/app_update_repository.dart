import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/constants/supabase_tables.dart';
import '../../core/network/supabase_service.dart';
import 'app_version.dart';

/// The one request behind the update check.
abstract class AppVersionGateway {
  /// `get_app_version(p_platform)`: one platform's row, or null.
  Future<Object?> appVersion(String platform);
}

class SupabaseAppVersionGateway implements AppVersionGateway {
  const SupabaseAppVersionGateway();

  @override
  Future<Object?> appVersion(String platform) async =>
      await SupabaseService.client.rpc(SupabaseRpcs.getAppVersion, params: {'p_platform': platform});
}

/// Whether this installation should update. It never stands in the app's way:
/// no connection, a server without the function, an answer it cannot read —
/// each means "no update".
class AppUpdateRepository {
  final AppVersionGateway _gateway;

  /// How long the answer is waited for before the app carries on without it.
  final Duration timeout;

  AppUpdateRepository({AppVersionGateway? gateway, this.timeout = const Duration(seconds: 8)})
      : _gateway = gateway ?? const SupabaseAppVersionGateway();

  /// The name the server knows this platform by; null where there is no store.
  static String? get platform => switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        _ => null,
      };

  Future<AppUpdate> check({required String? installed}) async {
    final platform = AppUpdateRepository.platform;
    if (platform == null || AppVersion.tryParse(installed) == null) return AppUpdate.none;
    try {
      final answer = await _gateway.appVersion(platform).timeout(timeout);
      return AppUpdate.resolve(installed: installed, answer: answer);
    } catch (_) {
      return AppUpdate.none;
    }
  }
}

final appUpdateRepoProvider = Provider((ref) => AppUpdateRepository());

/// The installed build's version ("1.0.6"); null where it cannot be read.
final installedVersionProvider = FutureProvider<String?>((ref) async {
  try {
    final version = (await PackageInfo.fromPlatform()).version;
    return version.isEmpty ? null : version;
  } catch (_) {
    return null;
  }
});

/// Asked once per run of the app, signed in or not: one request.
final appUpdateProvider = FutureProvider<AppUpdate>((ref) async {
  final repository = ref.watch(appUpdateRepoProvider);
  return repository.check(installed: await ref.watch(installedVersionProvider.future));
});
