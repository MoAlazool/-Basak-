import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/core/ui/ui.dart';

import '../providers/auth_provider.dart';

/// Shown to an account this app is not for (an admin, or one with no role):
/// what the app is for, where such an account belongs, and the way out.
class WrongRoleScreen extends ConsumerWidget {
  const WrongRoleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final text = context.text;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Scaffold(
        backgroundColor: colors.ground,
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
                          BasakSpace.gutter, BasakSpace.s24, BasakSpace.gutter, BasakSpace.s16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  BasakSpace.s16, 0, BasakSpace.s16, BasakSpace.s40),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ExcludeSemantics(
                                    child: Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                          color: colors.warningTint, borderRadius: BasakRadius.all(22)),
                                      child: Icon(LucideIcons.ban, size: 28, color: colors.warning),
                                    ),
                                  ),
                                  const SizedBox(height: BasakSpace.s16),
                                  Semantics(
                                    header: true,
                                    child: Text('هذا الحساب لا يعمل هنا',
                                        textAlign: TextAlign.center, style: text.sheetTitle),
                                  ),
                                  const SizedBox(height: BasakSpace.s10),
                                  Text('تطبيق باصك للطلاب والمشرفين. حسابات الإدارة تدخل من لوحة التحكم على الويب.',
                                      textAlign: TextAlign.center, style: text.body.copyWith(color: colors.ink2)),
                                ],
                              ),
                            ),
                          ),
                          BasakButton(
                            key: const Key('wrong-role-sign-out'),
                            label: 'تسجيل الخروج',
                            icon: LucideIcons.logOut,
                            variant: BasakButtonVariant.secondary,
                            onPressed: () => ref.read(authStateProvider.notifier).signOut(),
                          ),
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
