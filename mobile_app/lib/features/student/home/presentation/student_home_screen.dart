import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../daily_ride/data/daily_ride_repository.dart';
import '../../subscription/data/subscription_repository.dart';
import '../../subscription/models/subscription_model.dart';

final subscriptionRepoProvider = Provider((ref) => SubscriptionRepository());
final dailyRideRepoProvider = Provider((ref) => DailyRideRepository());

final currentSubscriptionProvider = FutureProvider<SubscriptionModel?>((ref) async {
  return ref.watch(subscriptionRepoProvider).getCurrentSubscription();
});

class StudentHomeScreen extends ConsumerStatefulWidget {
  final VoidCallback onNavigateToSubscription;
  final VoidCallback onNavigateToQr;

  const StudentHomeScreen({
    super.key,
    required this.onNavigateToSubscription,
    required this.onNavigateToQr,
  });

  @override
  ConsumerState<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends ConsumerState<StudentHomeScreen> {
  bool _isRidingTomorrow = false;
  bool _isLoadingRideToggle = false;

  @override
  void initState() {
    super.initState();
    _loadTomorrowRideStatus();
  }

  Future<void> _loadTomorrowRideStatus() async {
    final repo = ref.read(dailyRideRepoProvider);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final isRiding = await repo.getRideStatusForDate(tomorrow);
    if (mounted) {
      setState(() => _isRidingTomorrow = isRiding);
    }
  }

  Future<void> _toggleRide(bool value) async {
    setState(() => _isLoadingRideToggle = true);
    final repo = ref.read(dailyRideRepoProvider);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    try {
      final updated = await repo.toggleRide(rideDate: tomorrow, isRiding: value);
      if (mounted) {
        setState(() {
          _isRidingTomorrow = updated;
          _isLoadingRideToggle = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              updated ? 'تم تسجيل حضورك لرحلة الغد بنجاح!' : 'تم إلغاء تسجيل حضورك لرحلة الغد.',
              style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
            ),
            backgroundColor: updated ? AppColors.success : AppColors.textSecondary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingRideToggle = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subAsync = ref.watch(currentSubscriptionProvider);

    return GlassScaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // App Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('أهلاً بك 👋', style: AppTextStyles.labelSmall),
                      const SizedBox(height: 2),
                      Text('باصك - الجامعة', style: AppTextStyles.displayMedium),
                    ],
                  ),
                  IconButton(
                    onPressed: widget.onNavigateToQr,
                    icon: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        shape: BoxShape.circle,
                        boxShadow: AppColors.softShadow,
                      ),
                      child: const Icon(LucideIcons.qrCode, color: AppColors.babyBlueDark),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Daily Ride Toggle ("نازل بكرة") Glassmorphic Card
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: GlassContainer(
                blur: 16,
                opacity: 0.75,
                borderRadius: 24,
                padding: const EdgeInsets.all(20),
                border: Border.all(
                  color: _isRidingTomorrow ? AppColors.babyBlue : AppColors.glassBorder,
                  width: 1.5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _isRidingTomorrow
                                    ? AppColors.babyBlueUltraLight
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                LucideIcons.bus,
                                color: _isRidingTomorrow
                                    ? AppColors.babyBlueDark
                                    : AppColors.textSecondary,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('رحلة الغد ("نازل بكرة")', style: AppTextStyles.titleMedium),
                                Text(
                                  'ينتهي التأكيد يومياً الساعة 1:00 ظهراً',
                                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (_isLoadingRideToggle)
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        else
                          Switch.adaptive(
                            value: _isRidingTomorrow,
                            activeColor: AppColors.babyBlue,
                            onChanged: _toggleRide,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isRidingTomorrow
                            ? AppColors.successLight.withOpacity(0.7)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isRidingTomorrow ? LucideIcons.checkCircle2 : LucideIcons.info,
                            size: 16,
                            color: _isRidingTomorrow ? AppColors.success : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isRidingTomorrow
                                  ? 'أنت مسجل في باص الغد. سيتم حسابك ضمن أعداد الركاب.'
                                  : 'أنت غير مسجل لرحلة الغد. فعّل المفتاح قبل 1:00 ظهراً لتأكيد مقعدك.',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: _isRidingTomorrow
                                    ? const Color(0xFF065F46)
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Active Subscription Card / Status
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: subAsync.when(
                data: (sub) {
                  if (sub == null) {
                    return GlassContainer(
                      padding: const EdgeInsets.all(20),
                      borderRadius: 22,
                      child: Column(
                        children: [
                          const Icon(LucideIcons.ticket, size: 40, color: AppColors.babyBlue),
                          const SizedBox(height: 12),
                          Text('لا يوجد اشتراك نشط حالياً', style: AppTextStyles.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            'اختر خط سيرك ومحطة ركوبك واشترك الآن لفتح جدول الباصات.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.babyBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: widget.onNavigateToSubscription,
                            child: const Text('استعراض الخطوط والاشتراك'),
                          ),
                        ],
                      ),
                    );
                  }

                  return GlassContainer(
                    borderRadius: 24,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('اشتراكك الحالي', style: AppTextStyles.titleLarge),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: sub.isActive
                                    ? AppColors.successLight
                                    : AppColors.warningLight,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                sub.isActive
                                    ? 'نشط'
                                    : sub.isPendingReview
                                        ? 'قيد مراجعة الإيصال'
                                        : 'في انتظار الدفع',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: sub.isActive ? AppColors.success : AppColors.warning,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            const Icon(LucideIcons.mapPin, size: 18, color: AppColors.babyBlue),
                            const SizedBox(width: 8),
                            Text(sub.lineName ?? 'خط السير', style: AppTextStyles.titleMedium),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(LucideIcons.navigation, size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Text('محطة الركوب: ${sub.stationName ?? "المحطة"}', style: AppTextStyles.bodyMedium),
                          ],
                        ),
                        if (sub.isActive) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('الذهاب: ${sub.departureTime ?? "-"}', style: AppTextStyles.bodyMedium),
                              Text('العودة: ${sub.returnTime ?? "-"}', style: AppTextStyles.bodyMedium),
                            ],
                          ),
                          if (sub.supervisorPhone != null) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(LucideIcons.phoneCall, size: 16, color: AppColors.babyBlueDark),
                                const SizedBox(width: 8),
                                Text(
                                  'مشرف الخط: ${sub.supervisorName ?? ""} (${sub.supervisorPhone})',
                                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.babyBlueDark),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ],
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Text('خطأ: $err'),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)), // Bottom nav bar clearance
        ],
      ),
    );
  }
}
