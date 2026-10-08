import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/avatar_image.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../home/presentation/student_home_screen.dart';

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
          'حذف الحساب نهائي ولا يمكن التراجع عنه.\n\nلا يمكن تغيير الصورة الشخصية إلا بحذف الحساب وإعادة التسجيل.\n\nسيؤدي الحذف إلى إلغاء الاشتراك الحالي وفقدان بياناته وسجلات الرحلات المرتبطة به.\n\nهل تريد حذف الحساب والاشتراك الآن؟',
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
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: const Color(0xFFE2F2F9),
                      backgroundImage: profile?['profile_image_signed_url']
                              is String
                          ? avatarImage(
                              profile!['profile_image_signed_url'] as String)
                          : null,
                      child: profile?['profile_image_signed_url'] is String
                          ? null
                          : const Icon(LucideIcons.user,
                              size: 36, color: Color(0xFF00658D)),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      fullName,
                      style: AppTextStyles.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phone,
                      style: AppTextStyles.bodyMedium,
                    ),
                    if (authState.isStudent) ...[
                      const SizedBox(height: 6),
                      Text(
                        profile?['university'] as String? ??
                            (detailsAsync.isLoading
                                ? 'جارٍ تحميل الجامعة...'
                                : 'الجامعة المسجلة'),
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      Text(
                        profile?['college'] as String? ?? 'الكلية المسجلة',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      if (subscriptionAsync?.valueOrNull != null) ...[
                        const SizedBox(height: 15),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                              color: const Color(0xFFF1F7FA),
                              borderRadius: BorderRadius.circular(15)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  const Icon(LucideIcons.busFront,
                                      size: 18, color: Color(0xFF00658D)),
                                  const SizedBox(width: 7),
                                  Expanded(
                                      child: Text(
                                          subscriptionAsync!
                                                  .valueOrNull!.lineName ??
                                              'مسار النقل',
                                          style: AppTextStyles.titleMedium))
                                ]),
                                const SizedBox(height: 7),
                                Text(
                                    'المحطة: ${subscriptionAsync.valueOrNull!.stationName ?? '—'}',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.textSecondary)),
                              ]),
                        ),
                      ],
                    ],
                    const Divider(height: 32),

                    // Fixed Profile Notice Banner
                    if (authState.isStudent)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.lock,
                                size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'تعديل البيانات مغلق. لتغيير خط السير أو المحطة يجب حذف الحساب وإعادة التسجيل.',
                                style: AppTextStyles.labelSmall
                                    .copyWith(color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
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
