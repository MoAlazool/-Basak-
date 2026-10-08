import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../home/presentation/student_home_screen.dart';
import 'profile_editor.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(LucideIcons.alertTriangle, color: AppColors.error),
            const SizedBox(width: 8),
            Text('حذف الحساب نهائياً', style: AppTextStyles.titleMedium),
          ],
        ),
        content: Text(
          'حذف الحساب نهائي ولا يمكن التراجع عنه.\n\nسيؤدي الحذف إلى إلغاء الاشتراك الحالي وفقدان بياناته وسجلات الرحلات المرتبطة به.\n\nهل تريد حذف الحساب والاشتراك الآن؟',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ref.read(authStateProvider.notifier).deleteAccount();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('فشل الحذف: $e'),
                        backgroundColor: AppColors.error),
                  );
                }
              }
            },
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final detailsAsync = authState.isStudent && user != null
        ? ref.watch(studentProfileSummaryProvider(user.id))
        : const AsyncValue<Map<String, dynamic>?>.data(null);
    final subscriptionAsync =
        authState.isStudent ? ref.watch(currentSubscriptionProvider) : null;
    final profile = detailsAsync.valueOrNull;
    final fullName = profile?['full_name'] as String? ??
        user?.userMetadata?['full_name'] as String? ??
        (authState.isSupervisor ? 'حساب المشرف' : 'حساب الطالب');
    final phone = profile?['phone'] as String? ??
        user?.userMetadata?['phone'] as String? ??
        user?.email ??
        '';

    return GlassScaffold(
      canvas: const Color(0xFFEAF5FA),
      body: ColoredBox(
        color: const Color(0xFFEAF5FA),
        child: RefreshIndicator(
          color: AppColors.teal,
          onRefresh: () async {
            if (user != null) {
              ref.invalidate(studentProfileSummaryProvider(user.id));
            }
            if (authState.isStudent) {
              ref.invalidate(currentSubscriptionProvider);
            }
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('حسابي',
                  style: AppTextStyles.displayMedium
                      .copyWith(color: const Color(0xFF17384A))),
              const SizedBox(height: 20),

              // Profile Info Card
              GlassContainer(
                padding: const EdgeInsets.all(20),
                borderRadius: 24,
                child: authState.isStudent && user != null
                    ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        ProfileSection(
                            userId: user.id, profile: profile, fallbackName: fullName, fallbackPhone: phone),
                        if (subscriptionAsync?.valueOrNull != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                                color: const Color(0xFFF1F7FA), borderRadius: BorderRadius.circular(15)),
                            child: Row(children: [
                              const Icon(LucideIcons.busFront, size: 18, color: Color(0xFF00658D)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                    '${subscriptionAsync!.valueOrNull!.lineLabel} · محطة ${subscriptionAsync.valueOrNull!.stationName ?? '—'}',
                                    style: AppTextStyles.bodyMedium
                                        .copyWith(color: const Color(0xFF17384A), fontWeight: FontWeight.w600)),
                              ),
                            ]),
                          ),
                        ],
                      ])
                    : Column(children: [
                        const CircleAvatar(
                          radius: 36,
                          backgroundColor: Color(0xFFE2F2F9),
                          child: Icon(LucideIcons.user, size: 36, color: Color(0xFF00658D)),
                        ),
                        const SizedBox(height: 12),
                        Text(fullName, style: AppTextStyles.titleLarge),
                        const SizedBox(height: 4),
                        Text(phone, style: AppTextStyles.bodyMedium),
                      ]),
              ),
              const SizedBox(height: 24),

              // Actions Section
              Text('الإعدادات والأمان',
                  style: AppTextStyles.titleMedium
                      .copyWith(color: const Color(0xFF17384A))),
              const SizedBox(height: 12),

              GlassContainer(
                padding: const EdgeInsets.symmetric(vertical: 8),
                borderRadius: 20,
                // ListTile ink needs a Material above the glass background.
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(LucideIcons.logOut,
                            color: AppColors.textSecondary),
                        title: Text('تسجيل الخروج',
                            style: AppTextStyles.bodyLarge),
                        onTap: () =>
                            ref.read(authStateProvider.notifier).signOut(),
                      ),
                      if (authState.isStudent) const Divider(height: 1),
                      if (authState.isStudent)
                        ListTile(
                          leading: const Icon(LucideIcons.trash2,
                              color: AppColors.error),
                          title: Text(
                            'حذف الحساب وإعادة التسجيل',
                            style: AppTextStyles.bodyLarge.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'لحذف كافة البيانات والاشتراكات والبدء من جديد',
                            style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.error.withOpacity(0.8)),
                          ),
                          onTap: () => _showDeleteAccountDialog(context, ref),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 100), // clearance for floating nav bar
            ],
          ),
        ),
      ),
    ),
  );
}
}
