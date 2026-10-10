import 'package:flutter/material.dart';

import 'package:basak_mobile/core/ui/ui.dart';

import '../../../core/widgets/app_version_label.dart';

/// The entry screen of a phone nobody is signed in on: the mark, the name,
/// one line, the two ways in for a student and a quiet one for supervisors.
class WelcomeScreen extends StatelessWidget {
  final VoidCallback onSignup;
  final VoidCallback onSignIn;
  final VoidCallback onSupervisor;

  const WelcomeScreen({super.key, required this.onSignup, required this.onSignIn, required this.onSupervisor});

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: basakMaxTextScale,
      child: Scaffold(
        backgroundColor: context.colors.ground,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth),
              child: CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          BasakSpace.s24, BasakSpace.s24, BasakSpace.s24, BasakSpace.s8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Expanded(
                            child: Padding(
                              padding: EdgeInsetsDirectional.only(bottom: BasakSpace.s24),
                              child: Center(child: BrandHero(tagline: 'اشتراك الباص الجامعي، بكل بساطة.')),
                            ),
                          ),
                          BasakButton(
                            key: const Key('welcome-signup'),
                            label: 'إنشاء حساب طالب',
                            onPressed: onSignup,
                          ),
                          const SizedBox(height: BasakSpace.s10),
                          BasakButton(
                            key: const Key('welcome-signin'),
                            label: 'تسجيل الدخول',
                            onPressed: onSignIn,
                            variant: BasakButtonVariant.surface,
                          ),
                          const SizedBox(height: BasakSpace.s6),
                          EntryLink(
                            key: const Key('welcome-supervisor'),
                            label: 'دخول المشرفين',
                            tone: EntryLinkTone.quiet,
                            inline: true,
                            onTap: onSupervisor,
                          ),
                          // The installed version, for whoever is asked "which build?".
                          const AppVersionLabel(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
