import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:basak_mobile/core/ui/ui.dart';

/// Where the terms and the privacy policy live, in one place for the whole app
/// (sign-up, both profiles). The App Store asks for the privacy policy inside
/// the app as well as on the listing, and the link must open a real page.
///
/// Set at build time, like the Supabase values:
///   --dart-define=PRIVACY_URL=https://…/legal/privacy.html
///   --dart-define=TERMS_URL=https://…/legal/terms.html
/// The pages themselves are in admin_web/public/legal/ and are served by the
/// dashboard's site. Use the same privacy link in App Store Connect.
class LegalLinks {
  LegalLinks._();

  static const String terms = String.fromEnvironment('TERMS_URL', defaultValue: 'https://basak-sand.vercel.app/terms');
  static const String privacy = String.fromEnvironment('PRIVACY_URL', defaultValue: 'https://basak-sand.vercel.app/privacy#privacy');

  /// Opens [url] in the browser; says so on the page when it cannot.
  static Future<void> open(BuildContext context, String url) async {
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      BasakToast.show(context, 'تعذر فتح الرابط على هذا الجهاز.', kind: BasakToastKind.failure);
    }
  }
}
