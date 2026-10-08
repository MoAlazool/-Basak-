import 'package:flutter/material.dart';
import '../../../../core/widgets/skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/avatar_image.dart';
import '../../../../core/widgets/basak_ui.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../notifications/presentation/notification_preferences_screen.dart';
import '../../data/supervisor_repository.dart';
import '../../models/supervisor_models.dart';

/// Tab 4 — the supervisor's own account: identity, company, assigned lines and
/// stations. Data comes from get_supervisor_dashboard() (own row only).
class SupervisorProfileScreen extends ConsumerWidget {
  const SupervisorProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(supervisorDashboardProvider);
    final authUser = ref.watch(authStateProvider).user;

    return GlassScaffold(
      body: BasakPage(
        onRefresh: () async {
          ref.invalidate(supervisorDashboardProvider);
          await ref.read(supervisorDashboardProvider.future);
        },
        children: [
          const BasakPageHeader(title: 'حسابي', subtitle: 'بيانات حساب المشرف'),
          const SizedBox(height: 18),
          dashboard.when(
            loading: () => const SkeletonCard(radius: 24, child: ProfileSkeleton()),
            error: (_, __) => BasakMessageCard(
              icon: LucideIcons.wifiOff,
              title: 'تعذر تحميل بيانات الحساب',
              message: 'تحقق من الاتصال بالإنترنت ثم أعد المحاولة.',
              actionLabel: 'إعادة المحاولة',
              onAction: () => ref.invalidate(supervisorDashboardProvider),
            ),
            data: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _identityCard(data.profile, ref.watch(supervisorPhotoUrlProvider).valueOrNull),
                const BasakSectionTitle('الشركة والتكليف'),
                _assignmentCard(data),
                if (data.lines.isNotEmpty) ...[
                  BasakSectionTitle('المحطات المسندة',
                      trailing: BasakPill('${data.totals.stations} محطة',
                          icon: LucideIcons.mapPin)),
                  for (final line in data.lines) ...[
                    _lineStations(line),
                    const SizedBox(height: 10),
                  ],
                ],
                const BasakSectionTitle('تفاصيل الحساب'),
                _accountCard(
                    data.profile, authUser?.email, authUser?.lastSignInAt),
              ],
            ),
          ),
          const BasakSectionTitle('الإعدادات والأمان'),
          Container(
            decoration: BasakUi.card(),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: [
                ListTile(
                  leading: const Icon(LucideIcons.bell, color: BasakUi.muted),
                  title: Text('إعدادات الإشعارات',
                      style:
                          AppTextStyles.bodyLarge.copyWith(color: BasakUi.ink)),
                  subtitle: Text('ما يصلك كإشعار على الهاتف',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: BasakUi.muted)),
                  trailing: const Icon(LucideIcons.chevronLeft,
                      size: 18, color: BasakUi.muted),
                  onTap: () => NotificationPreferencesScreen.open(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(LucideIcons.lock, color: BasakUi.muted),
                  title: Text('تغيير كلمة المرور أو البيانات',
                      style:
                          AppTextStyles.bodyLarge.copyWith(color: BasakUi.ink)),
                  subtitle: Text('تتم عن طريق إدارة شركتك',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: BasakUi.muted)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      const Icon(LucideIcons.logOut, color: AppColors.error),
                  title: Text('تسجيل الخروج',
                      style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.error, fontWeight: FontWeight.w700)),
                  onTap: () => _confirmSignOut(context, ref),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('تسجيل الخروج'),
          content:
              const Text('هل تريد تسجيل الخروج من حساب المشرف على هذا الجهاز؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white),
              onPressed: () {
                Navigator.of(ctx).pop();
                ref.read(authStateProvider.notifier).signOut();
              },
              child: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      );

  Widget _identityCard(SupervisorProfile profile, String? photoUrl) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BasakUi.card(radius: 24),
        child: Column(children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
                gradient: BasakUi.heroGradient,
                shape: BoxShape.circle,
                image: photoUrl == null
                    ? null
                    : DecorationImage(image: avatarImage(photoUrl), fit: BoxFit.cover)),
            alignment: Alignment.center,
            child: photoUrl != null
                ? null
                : Text(
                    profile.fullName.trim().isEmpty
                        ? 'م'
                        : profile.fullName.trim().characters.first,
                    style: AppTextStyles.displayMedium
                        .copyWith(color: Colors.white, fontSize: 30),
                  ),
          ),
          const SizedBox(height: 12),
          Text(profile.fullName,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLarge.copyWith(color: BasakUi.ink)),
          const SizedBox(height: 4),
          Text(profile.phone,
              textDirection: TextDirection.ltr,
              style: AppTextStyles.bodyMedium.copyWith(color: BasakUi.muted)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, alignment: WrapAlignment.center, children: [
            const BasakPill('مشرف حافلة', icon: LucideIcons.userCheck),
            profile.isActive
                ? const BasakPill('الحساب نشط',
                    background: Color(0xFFE7F8F0),
                    foreground: Color(0xFF07865A))
                : const BasakPill('الحساب موقوف',
                    background: AppColors.errorLight,
                    foreground: AppColors.error),
          ]),
        ]),
      );

  Widget _assignmentCard(SupervisorDashboard data) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BasakUi.card(),
        child: Column(children: [
          BasakInfoRow(
              icon: LucideIcons.building2,
              label: 'الشركة',
              value: data.profile.companyName ?? 'غير محددة'),
          BasakInfoRow(
            icon: LucideIcons.bus,
            label: data.lines.length > 1 ? 'الخطوط' : 'الخط',
            value: data.lines.isEmpty
                ? 'لا يوجد خط مسند'
                : data.lines.map((l) => l.name).join('، '),
          ),
          BasakInfoRow(
            icon: LucideIcons.listChecks,
            label: 'نوع التكليف',
            value: data.profile.isDirectlyAssigned
                ? '${data.lines.length} خط مسند من الشركة'
                : 'لا يوجد خط مسند',
          ),
          BasakInfoRow(
              icon: LucideIcons.users,
              label: 'الطلاب المشتركون',
              value: '${data.totals.registeredStudents}'),
        ]),
      );

  Widget _lineStations(SupervisorLine line) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BasakUi.card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(LucideIcons.busFront, size: 18, color: BasakUi.teal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(line.name,
                  style:
                      AppTextStyles.titleMedium.copyWith(color: BasakUi.ink)),
            ),
            if (!line.isActive)
              const BasakPill('متوقف',
                  background: AppColors.errorLight,
                  foreground: AppColors.error),
          ]),
          const SizedBox(height: 10),
          if (line.stations.isEmpty)
            Text('لا توجد محطات نشطة',
                style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted))
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final station in line.stations)
                BasakPill('${station.orderIndex}. ${station.name}',
                    background: const Color(0xFFF1F7FA),
                    foreground: BasakUi.ink),
            ]),
          if (line.schedules.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final trip in line.schedules)
                BasakPill(
                    '${trip.university} ${BasakUi.time12(trip.departureTime)}',
                    background: const Color(0xFFEEF0FF),
                    foreground: const Color(0xFF4F46E5),
                    icon: LucideIcons.graduationCap),
            ]),
          ],
        ]),
      );

  Widget _accountCard(
      SupervisorProfile profile, String? loginEmail, String? lastSignIn) {
    final since = profile.createdAt;
    final last = DateTime.tryParse(lastSignIn ?? '')?.toLocal();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BasakUi.card(),
      child: Column(children: [
        const BasakInfoRow(
            icon: LucideIcons.badgeCheck, label: 'نوع الحساب', value: 'مشرف'),
        BasakInfoRow(
            icon: LucideIcons.phone, label: 'رقم الدخول', value: profile.phone),
        if (since != null)
          BasakInfoRow(
              icon: LucideIcons.calendarPlus,
              label: 'تاريخ الإنشاء',
              value:
                  '${since.day} ${BasakUi.arabicMonths[since.month - 1]} ${since.year}'),
        if (last != null)
          BasakInfoRow(
              icon: LucideIcons.history,
              label: 'آخر تسجيل دخول',
              value: '${last.day}/${last.month}/${last.year}'),
        BasakInfoRow(
          icon: LucideIcons.building,
          label: 'حالة الشركة',
          value: profile.companyActive ? 'مفعّلة' : 'غير مفعّلة',
          valueColor:
              profile.companyActive ? const Color(0xFF07865A) : AppColors.error,
        ),
      ]),
    );
  }
}
