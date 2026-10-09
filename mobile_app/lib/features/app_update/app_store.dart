import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

/// The way out to the phone's store: its page for the app, and its own review
/// dialog. Nothing here throws; each answers whether the store took over.
class AppStore {
  const AppStore();

  /// What this phone's store is called. Latin, as the stores write it.
  static String get name => defaultTargetPlatform == TargetPlatform.iOS ? 'App Store' : 'Google Play';

  /// Opens the app's page: [url] when the dashboard has one, otherwise the
  /// store's own listing (which Google Play finds by itself).
  Future<bool> open(String? url) async {
    final link = url == null ? null : Uri.tryParse(url);
    if (link != null) {
      try {
        if (await launchUrl(link, mode: LaunchMode.externalApplication)) return true;
      } catch (_) {}
    }
    try {
      await InAppReview.instance.openStoreListing();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The store's own review dialog, over the app. False where the store
  /// does not offer one. (The store decides whether it really appears: it
  /// shows it only so often.)
  Future<bool> requestReview() async {
    try {
      if (!await InAppReview.instance.isAvailable()) return false;
      await InAppReview.instance.requestReview();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final appStoreProvider = Provider<AppStore>((ref) => const AppStore());
