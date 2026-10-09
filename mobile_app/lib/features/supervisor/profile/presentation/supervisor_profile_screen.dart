import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/avatar_image.dart';
import '../../../../core/widgets/basak_ui.dart' show BasakUi;
import '../../../../core/widgets/skeleton.dart';
import '../../../auth/biometrics/presentation/biometric_setting_row.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../notifications/presentation/notification_preferences_screen.dart';
import '../../../notifications/push/push_messaging.dart';
import '../../../notifications/push/push_providers.dart';
import '../../../student/home/presentation/supervisor_contact_sheet.dart';
import '../../../student/profile/presentation/help_sheet.dart';
import '../../../student/profile/presentation/profile_screen.dart' show appVersionProvider;
import '../../data/supervisor_repository.dart';
import '../../home/presentation/line_sheet.dart';
import '../../models/supervisor_models.dart';
import '../../monthly/presentation/supervisor_monthly_screen.dart';

/// Asks before a supervisor is signed out of this phone, then does it. Used
/// by the account page and by the suspended-account screen.
Future<void> confirmSupervisorSignOut(BuildContext context, WidgetRef ref) async {
  final confirmed = await BasakDialog.confirm(
    context,
    icon: LucideIcons.logOut,
    title: 'تسجيل الخروج',
    message: 'هل تريد تسجيل الخروج من حساب المشرف على هذا الجهاز؟',
    confirmLabel: 'تسجيل الخروج',
  );
  if (confirmed) await ref.read(authStateProvider.notifier).signOut();
}

/// «حسابي»: who the supervisor is, which company and lines they work for,
/// what the app itself offers, and signing out. The details and the password
/// are the company's to change, and the page says so. Data comes from
/// `get_supervisor_dashboard()` (the supervisor's own row only).
class SupervisorProfileScreen extends ConsumerWidget {
  const SupervisorProfileScreen({super.key});

  /// «العمل»: the company, the lines (the sheet that chooses one, when there
  /// is a choice) and the month's summary.
  List<SettingRow> _workRows(BuildContext context, SupervisorDashboard data) {
    final now = DateTime.now();
    return [
      SettingRow(label: 'الشركة', value: data.profile.companyName ?? 'غير محددة'),
      SettingRow(
        key: const Key('supervisor-lines'),
        label: 'الخطوط',
        value: data.lines.isEmpty ? 'لا يوجد خط مسند' : ArabicCount.lines(data.lines.length),
        onTap: data.lines.isEmpty ? null : () => SupervisorLineSheet.show(context),
      ),
      SettingRow(
        key: const Key('supervisor-monthly'),
        label: 'ملخص الشهر',
        value: '${BasakUi.arabicMonths[now.month - 1]} ${now.year}',
        onTap: () => SupervisorMonthlyScreen.open(context),
      ),
    ];
  }

  /// «التطبيق»: help (the people the app knows, when it knows any), then
  /// which pushes reach this phone, then signing in with Face ID or a
  /// fingerprint on phones that have one enrolled.
  List<SettingRow> _appRows(BuildContext context, WidgetRef ref) {
    final support = ref.watch(helpSupportProvider);
    final pushReady = ref.watch(pushReadyProvider).valueOrNull == true;
    final permission = pushReady ? ref.watch(pushPermissionProvider).valueOrNull : null;
    final biometric = biometricSettingRow(context, ref);
    return [
      if (support.isNotEmpty)
        SettingRow(
          key: const Key('supervisor-help'),
          label: HelpSheet.title,
          onTap: () => HelpSheet.show(context, journey: const [], support: support),
        ),
      // The supervisor's own switches (which kinds of push), with the phone's
      // permission at their top.
      SettingRow(
        key: const Key('supervisor-phone-notifications'),
        label: 'إشعارات الهاتف',
        value: permission == null ? null : (permission == PushPermission.granted ? 'مفعّلة' : 'متوقفة'),
        onTap: () => NotificationPreferencesScreen.open(context),
      ),
      if (biometric != null) biometric,
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(supervisorDashboardProvider);
    final data = dashboard.valueOrNull;
    final photoUrl = ref.watch(supervisorPhotoUrlProvider).valueOrNull;
    final version = ref.watch(appVersionProvider).valueOrNull;
    final text = context.text;
    final colors = context.colors;

    return BasakPage(
      bottomInset: BasakPage.tabBarClearance,
      onRefresh: () async {
        ref.invalidate(supervisorDashboardProvider);
        ref.invalidate(pushPermissionProvider);
        try {
          await ref.read(supervisorDashboardProvider.future);
        } catch (_) {
          // Said by the page itself.
        }
      },
      children: [
        Semantics(header: true, child: Text('حسابي', style: text.display)),
        if (data != null) ...[
          IdentityCard(
            name: data.profile.fullName,
            phone: SupervisorContactSheet.readable(data.profile.phone),
            photo: photoUrl == null ? null : avatarImage(photoUrl),
            // Active or stopped by the company: the stopped one borrows the
            // refused status's red, under its own word.
            trailing: StatusChip(
              data.profile.isActive ? BasakStatus.active : BasakStatus.rejected,
              label: data.profile.isActive ? null : 'موقوف',
            ),
          ),
          GroupSection(title: 'العمل', child: SettingRows(rows: _workRows(context, data))),
        ] else if (dashboard.hasError)
          BasakCard(
            child: InlineError(
              message: 'تعذّر تحميل بيانات الحساب. تحقّق من الاتصال بالإنترنت ثم أعد المحاولة.',
              onRetry: () => ref.invalidate(supervisorDashboardProvider),
            ),
          )
        else
          // First load on this phone only; afterwards the saved copy shows at once.
          const BasakCard(
            radius: BasakRadius.sheet,
            padding: EdgeInsetsDirectional.all(BasakSpace.s20),
            child: ProfileSkeleton(),
          ),
        GroupSection(title: 'التطبيق', child: SettingRows(rows: _appRows(context, ref))),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s4),
          child: Text(
            'بياناتك وكلمة المرور تديرها شركتك. لتغييرها تواصل مع إدارة الشركة.',
            style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BasakButton(
              key: const Key('supervisor-sign-out'),
              label: 'تسجيل الخروج',
              icon: LucideIcons.logOut,
              variant: BasakButtonVariant.surface,
              onPressed: () => confirmSupervisorSignOut(context, ref),
            ),
            if (version != null) ...[
              const SizedBox(height: BasakSpace.s8),
              Text(
                'باصك $version',
                textAlign: TextAlign.center,
                style: text.caption.copyWith(color: colors.ink3),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
