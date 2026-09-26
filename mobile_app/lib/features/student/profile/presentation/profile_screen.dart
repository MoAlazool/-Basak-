import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../../auth/providers/auth_provider.dart';

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
          'بحسب لوائح النظام، لا يمكن تعديل بيانات الخط أو المحطة داخل التطبيق.\n\nلتغيير أي بيانات يجب حذف الحساب وإعادة التسجيل من جديد بالبيانات الجديدة.\n\nهل أنت متأكد من رغبتك في حذف الحساب؟',
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ref.read(authStateProvider.notifier).deleteAccount();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('فشل الحذف: $e'), backgroundColor: AppColors.error),
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

    return GlassScaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الملف الشخصي', style: AppTextStyles.displayMedium),
            const SizedBox(height: 20),

            // Profile Info Card
            GlassContainer(
              padding: const EdgeInsets.all(20),
              borderRadius: 24,
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: AppColors.babyBlueLight.withOpacity(0.5),
                    child: const Icon(LucideIcons.user, size: 36, color: AppColors.babyBlueDark),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.userMetadata?['full_name'] ?? 'اسم الطالب',
                    style: AppTextStyles.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.userMetadata?['phone'] ?? user?.email ?? '',
                    style: AppTextStyles.bodyMedium,
                  ),
                  const Divider(height: 32),

                  // Fixed Profile Notice Banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.lock, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'تعديل البيانات مغلق. لتغيير خط السير أو المحطة يجب حذف الحساب وإعادة التسجيل.',
                            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
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
            Text('الإعدادات والأمان', style: AppTextStyles.titleMedium),
            const SizedBox(height: 12),

            GlassContainer(
              padding: const EdgeInsets.symmetric(vertical: 8),
              borderRadius: 20,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(LucideIcons.logOut, color: AppColors.textSecondary),
                    title: Text('تسجيل الخروج', style: AppTextStyles.bodyLarge),
                    onTap: () => ref.read(authStateProvider.notifier).signOut(),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(LucideIcons.trash2, color: AppColors.error),
                    title: Text(
                      'حذف الحساب وإعادة التسجيل',
                      style: AppTextStyles.bodyLarge.copyWith(color: AppColors.error, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'لحذف كافة البيانات والاشتراكات والبدء من جديد',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.error.withOpacity(0.8)),
                    ),
                    onTap: () => _showDeleteAccountDialog(context, ref),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 100), // clearance for floating nav bar
          ],
        ),
      ),
    );
  }
}
