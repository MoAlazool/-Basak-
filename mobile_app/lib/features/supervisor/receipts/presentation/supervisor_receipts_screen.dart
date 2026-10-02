import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../data/supervisor_receipts_repository.dart';

final supervisorReceiptsRepoProvider =
    Provider((ref) => SupervisorReceiptsRepository());
final pendingReceiptsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(supervisorReceiptsRepoProvider).getPendingReceiptsQueue();
});

class SupervisorReceiptsScreen extends ConsumerWidget {
  const SupervisorReceiptsScreen({super.key});

  void _showRejectDialog(
      BuildContext context, WidgetRef ref, String receiptId) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(LucideIcons.alertOctagon, color: AppColors.error),
            const SizedBox(width: 8),
            Text('رفض إيصال التحويل', style: AppTextStyles.titleMedium),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'بحسب النظام، يجب كتابة سبب الرفض بوضوح ليتم إرساله للطالب.',
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText:
                    'سبب الرفض (إلزامي): صورة غير واضحة، المبلغ غير مطابق، إلخ...',
              ),
            ),
          ],
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
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('سبب الرفض إلزامي.')),
                );
                return;
              }
              Navigator.of(ctx).pop();
              try {
                await ref.read(supervisorReceiptsRepoProvider).rejectReceipt(
                      receiptId: receiptId,
                      rejectionReason: reason,
                    );
                ref.invalidate(pendingReceiptsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم رفض الإيصال وإشعار الطالب بالسبب.'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('خطأ: $e'),
                        backgroundColor: AppColors.error),
                  );
                }
              }
            },
            child: const Text('تأكيد الرفض'),
          ),
        ],
      ),
    );
  }

  Future<void> _approve(
      BuildContext context, WidgetRef ref, String receiptId) async {
    try {
      await ref.read(supervisorReceiptsRepoProvider).approveReceipt(receiptId);
      ref.invalidate(pendingReceiptsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم قبول الإيصال وتفعيل اشتراك الطالب بنجاح!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptsAsync = ref.watch(pendingReceiptsProvider);

    return GlassScaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('مراجعة إيصالات الطلاب',
                      style: AppTextStyles.displayMedium),
                  const SizedBox(height: 4),
                  Text('فحص وتأكيد إيصالات التحويل البنكي للاشتراكات الجديدة',
                      style: AppTextStyles.bodyMedium),
                ],
              ),
            ),
          ),
          receiptsAsync.when(
            data: (receipts) {
              if (receipts.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.checkCheck,
                            size: 50, color: AppColors.success),
                        const SizedBox(height: 12),
                        Text('لا توجد إيصالات معلقة',
                            style: AppTextStyles.titleMedium),
                        Text('تم فحص جميع الإيصالات بنجاح.',
                            style: AppTextStyles.bodyMedium),
                      ],
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final r = receipts[index];
                    final sub = r['subscriptions'] as Map<String, dynamic>?;
                    final student = sub?['students'] as Map<String, dynamic>?;
                    final line = sub?['lines'] as Map<String, dynamic>?;
                    final station = sub?['stations'] as Map<String, dynamic>?;
                    final attempt = r['attempt_number'] ?? 1;

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      child: GlassContainer(
                        padding: const EdgeInsets.all(16),
                        borderRadius: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(student?['full_name'] ?? 'اسم الطالب',
                                    style: AppTextStyles.titleMedium),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.babyBlueUltraLight,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'المحاولة $attempt من 5',
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: AppColors.babyBlueDark,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('الجامعة: ${student?['university'] ?? ""}',
                                style: AppTextStyles.bodyMedium),
                            Text('الهاتف: ${student?['phone'] ?? ""}',
                                style: AppTextStyles.bodyMedium),
                            Text(
                                'الخط: ${line?['name'] ?? ""} | المحطة: ${station?['name'] ?? ""}',
                                style: AppTextStyles.labelSmall
                                    .copyWith(color: AppColors.textSecondary)),
                            const SizedBox(height: 12),
                            if (r['signed_image_url'] is String)
                              GestureDetector(
                                onTap: () => showDialog<void>(
                                  context: context,
                                  builder: (ctx) => Dialog(
                                    child: InteractiveViewer(
                                      child: Image.network(
                                          r['signed_image_url'] as String),
                                    ),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    r['signed_image_url'] as String,
                                    height: 140,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Text('تعذر عرض صورة الإيصال'),
                                  ),
                                ),
                              ),
                            const Divider(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.success,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                    onPressed: () =>
                                        _approve(context, ref, r['id']),
                                    child: const Text('قبول وتفعيل'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.error,
                                      side: const BorderSide(
                                          color: AppColors.error),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                    onPressed: () => _showRejectDialog(
                                        context, ref, r['id']),
                                    child: const Text('رفض ببيان السبب'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: receipts.length,
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => SliverFillRemaining(
              child: Center(
                  child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('تعذر تحميل الإيصالات: $err',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => ref.invalidate(pendingReceiptsProvider),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              )),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}
