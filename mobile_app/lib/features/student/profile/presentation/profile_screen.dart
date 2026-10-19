import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/network/network_errors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../auth/biometrics/presentation/biometric_setting_row.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../rating/rating.dart';
import '../../home/presentation/student_home_screen.dart';
import '../../offers/offers_repository.dart';
import 'help_sheet.dart';
import 'profile_editor.dart';
import 'package:basak_mobile/core/constants/legal_links.dart';

/// The installed build's version ("1.0.6"); null where it cannot be read.
final appVersionProvider = FutureProvider<String?>((ref) async {
  try {
    final version = (await PackageInfo.fromPlatform()).version;
    return version.isEmpty ? null : version;
  } catch (_) {
    return null;
  }
});

/// «حسابي»: who is signed in, their details behind one «تعديل», what the app
/// itself offers (help, signing in with Face ID), signing out, and
/// deleting the account as a quiet link beside the version. The company, the
/// line and the supervisor are on Home and the subscription tab, not here.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await BasakDialog.confirm(
      context,
      icon: LucideIcons.trash2,
      title: 'حذف الحساب نهائياً؟',
      message: 'يُحذف حسابك وبياناتك وصورك، وتتوقف بطاقتك عن العمل. الإيصالات الرسمية التي صدرت لك تبقى لدى شركتك سجلاً مالياً. لا يمكن التراجع عن الحذف.',
      confirmLabel: 'تأكيد الحذف',
    );
    if (!confirmed) return;
    try {
      await ref.read(authStateProvider.notifier).deleteStudentAccount();
    } catch (e) {
      if (context.mounted) {
        BasakToast.show(context, 'فشل الحذف: ${errorMessage(e)}', kind: BasakToastKind.failure);
      }
    }
  }

  /// «التطبيق»: help, and signing in with Face ID or a fingerprint (on a
  /// phone that has one enrolled). Notifications and offers have no switch
  /// here: the phone's own settings hold the first, and offers are part of
  /// the app.
  List<SettingRow> _appRows(BuildContext context, WidgetRef ref) {
    final journey = ref.watch(helpJourneyProvider);
    final support = ref.watch(helpSupportProvider);
    final biometric = biometricSettingRow(context, ref);
    return [
      // Nobody to turn to yet (no subscription, no channels): no row.
      if (journey.isNotEmpty || support.isNotEmpty)
        SettingRow(
          key: const Key('profile-help'),
          label: HelpSheet.title,
          onTap: () => HelpSheet.show(context, journey: journey, support: support),
        ),
      if (biometric != null) biometric,
      // Always there: the store's page for the app, asked for by the student.
      SettingRow(
        key: const Key('profile-rate'),
        label: 'قيّم التطبيق',
        external: true,
        onTap: () => rateFromSettings(context, ref),
      ),
      // The privacy policy and the terms, reachable after sign-up too.
      SettingRow(
        key: const Key('profile-privacy'),
        label: 'سياسة الخصوصية',
        external: true,
        onTap: () => LegalLinks.open(context, LegalLinks.privacy),
      ),
      SettingRow(
        key: const Key('profile-terms'),
        label: 'شروط الاستخدام',
        external: true,
        onTap: () => LegalLinks.open(context, LegalLinks.terms),
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final student = authState.isStudent ? user : null;
    final detailsAsync = student != null
        ? ref.watch(studentProfileSummaryProvider(student.id))
        : const AsyncValue<Map<String, dynamic>?>.data(null);
    final profile = detailsAsync.valueOrNull;
    final fullName = profile?['full_name'] as String? ??
        user?.userMetadata?['full_name'] as String? ??
        (authState.isSupervisor ? 'حساب المشرف' : 'حساب الطالب');
    final phone =
        profile?['phone'] as String? ?? user?.userMetadata?['phone'] as String? ?? user?.email ?? '';
    final appRows = student != null ? _appRows(context, ref) : const <SettingRow>[];

    return BasakPage(
      bottomInset: BasakPage.tabBarClearance,
      onRefresh: () async {
        if (user != null) ref.invalidate(studentProfileSummaryProvider(user.id));
        if (authState.isStudent) ref.invalidate(currentSubscriptionProvider);
        if (authState.isStudent) ref.invalidate(offersProvider);
      },
      children: [
        Semantics(header: true, child: Text('حسابي', style: context.text.display)),
        if (student != null && detailsAsync.isLoading && !detailsAsync.hasValue)
          // First load on this phone only; afterwards the saved profile shows at once.
          const BasakCard(
            radius: BasakRadius.sheet,
            padding: EdgeInsetsDirectional.all(BasakSpace.s20),
            child: ProfileSkeleton(),
          )
        else if (student != null)
          ProfileSection(userId: student.id, profile: profile, fallbackName: fullName, fallbackPhone: phone)
        else
          IdentityCard(name: fullName, phone: phone),
        if (appRows.isNotEmpty) GroupSection(title: 'التطبيق', child: SettingRows(rows: appRows)),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BasakButton(
              key: const Key('profile-sign-out'),
              label: 'تسجيل الخروج',
              icon: LucideIcons.logOut,
              variant: BasakButtonVariant.surface,
              size: BasakButtonSize.medium,
              onPressed: () => ref.read(authStateProvider.notifier).signOut(),
            ),
            if (authState.isStudent)
              QuietFooter(
                actionKey: const Key('profile-delete'),
                actionLabel: 'حذف الحساب',
                onAction: () => _deleteAccount(context, ref),
                version: ref.watch(appVersionProvider).valueOrNull,
              ),
          ],
        ),
      ],
    );
  }
}
