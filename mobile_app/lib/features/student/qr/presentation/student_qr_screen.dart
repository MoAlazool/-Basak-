import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../data/student_qr_repository.dart';

final studentQrRepoProvider = Provider((ref) => StudentQrRepository());
final studentQrProvider = FutureProvider<String?>((ref) async {
  return ref.watch(studentQrRepoProvider).getStudentQrCode();
});

class StudentQrScreen extends ConsumerWidget {
  const StudentQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qrAsync = ref.watch(studentQrProvider);

    return GlassScaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('رمز التعريف الجامعي', style: AppTextStyles.displayMedium),
              const SizedBox(height: 6),
              Text(
                'أظهر هذا الرمز لمشرف الباص للتحقق من بيانات اشتراكك',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 24),

              // Glass QR Display Card
              GlassContainer(
                blur: 18,
                opacity: 0.85,
                borderRadius: 28,
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    qrAsync.when(
                      data: (qrValue) {
                        if (qrValue == null) {
                          return const Text('تعذر تحميل رمز الـ QR.');
                        }
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.babyBlue.withOpacity(0.15),
                                blurRadius: 15,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: QrImageView(
                            data: qrValue,
                            version: QrVersions.auto,
                            size: 200.0,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: AppColors.textPrimary,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        );
                      },
                      loading: () => const SizedBox(
                        width: 200,
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (err, _) => Text('خطأ: $err'),
                    ),
                    const SizedBox(height: 20),

                    // Important Notice Banner (Core Business Rule: QR scan never marks attendance)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.babyBlueUltraLight.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.babyBlueLight.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.alertCircle, size: 18, color: AppColors.babyBlueDark),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'تنبيه: مسح الرمز مخصص للتحقق فقط ولا يسجل الحضور. مصدر الحضور الوحيد هو مفتاح "نازل بكرة" اليومي.',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.babyBlueDark,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 100), // clearance for bottom nav bar
            ],
          ),
        ),
      ),
    );
  }
}
