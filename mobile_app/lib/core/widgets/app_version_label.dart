import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../ui/tokens.dart';

/// "الإصدار 1.0.2": the installed build's version (pubspec `version`), so it
/// can never drift from what is actually installed.
class AppVersionLabel extends StatelessWidget {
  const AppVersionLabel({super.key});

  static Future<PackageInfo>? _info;

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
        future: _info ??= PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          final version = snapshot.data?.version;
          if (version == null || version.isEmpty) return const SizedBox(height: 16);
          return Text(
            'الإصدار $version',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: context.text.caption.copyWith(color: context.colors.ink3),
          );
        },
      );
}
