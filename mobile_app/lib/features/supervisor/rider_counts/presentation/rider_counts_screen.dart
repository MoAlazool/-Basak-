import '../../data/supervisor_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../data/rider_counts_repository.dart';
import '../models/station_rider_count_model.dart';

final riderCountsRepoProvider = Provider((ref) => RiderCountsRepository());

class RiderCountsScreen extends ConsumerStatefulWidget {
  const RiderCountsScreen({super.key});

  @override
  ConsumerState<RiderCountsScreen> createState() => _RiderCountsScreenState();
}

class _RiderCountsScreenState extends ConsumerState<RiderCountsScreen> {
  bool _isTomorrowSelected = DateTime.now().hour >= 16;
  bool _isLoading = true;
  List<StationRiderCountModel> _counts = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  /// [silent] keeps the current numbers on screen while fresh ones are fetched
  /// (used when a student confirms or cancels and the server announces it).
  Future<void> _loadCounts({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate =
        _isTomorrowSelected ? today.add(const Duration(days: 1)) : today;

    try {
      final counts =
          await ref.read(riderCountsRepoProvider).getAssignedStationRiderCounts(
                targetDate: targetDate,
              );
      if (mounted) {
        setState(() {
          _counts = counts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The dashboard is refreshed by live events; when it changes, so may these counts.
    ref.listen(supervisorDashboardProvider, (_, next) {
      if (next.hasValue && !next.isLoading) _loadCounts(silent: true);
    });
    final totalRiders = _counts.fold<int>(0, (sum, st) => sum + st.ridingCount);
    final totalReturners =
        _counts.fold<int>(0, (sum, st) => sum + st.returningCount);

    return GlassScaffold(
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('أعداد الذهاب والعودة',
                      style: AppTextStyles.displayMedium),
                  const SizedBox(height: 4),
                  Text(
                    'الأعداد تتحدث مباشرة حسب اختيارات الطلاب للرحلة وموعد العودة.',
                    style: AppTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: 16),

                  // Day Switcher Pill (اليوم vs غداً)
                  Row(
                    children: [
                      Expanded(
                        child: GlassContainer(
                          onTap: () {
                            setState(() => _isTomorrowSelected = false);
                            _loadCounts();
                          },
                          borderRadius: 16,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          color: !_isTomorrowSelected
                              ? AppColors.babyBlueLight
                              : Colors.white,
                          child: Center(
                            child: Text(
                              'رحلة اليوم',
                              style: AppTextStyles.titleMedium.copyWith(
                                color: !_isTomorrowSelected
                                    ? const Color(0xFF0C4A6E)
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GlassContainer(
                          onTap: () {
                            setState(() => _isTomorrowSelected = true);
                            _loadCounts();
                          },
                          borderRadius: 16,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          color: _isTomorrowSelected
                              ? AppColors.babyBlueLight
                              : Colors.white,
                          child: Center(
                            child: Text(
                              'رحلة غداً (المؤكدين)',
                              style: AppTextStyles.titleMedium.copyWith(
                                color: _isTomorrowSelected
                                    ? const Color(0xFF0C4A6E)
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Total Riders Summary Card
                  GlassContainer(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.babyBlueUltraLight,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(LucideIcons.users,
                                  color: AppColors.babyBlueDark),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('إجمالي الرحلة',
                                    style: AppTextStyles.labelSmall),
                                Text('$totalRiders ذهاب',
                                    style: AppTextStyles.displayMedium),
                                Text('$totalReturners عودة',
                                    style: AppTextStyles.bodyMedium),
                              ],
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: _loadCounts,
                          icon: const Icon(LucideIcons.refreshCw,
                              color: AppColors.babyBlueDark),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Station Breakdown List
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(child: Text('خطأ: $_error')),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final st = _counts[index];
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    child: GlassContainer(
                      padding: const EdgeInsets.all(16),
                      borderRadius: 18,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppColors.babyBlueUltraLight,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    '${st.orderIndex}',
                                    style: AppTextStyles.labelSmall.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.babyBlueDark,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(st.stationName,
                                      style: AppTextStyles.titleMedium),
                                  if (st.universityName != null)
                                    Text('رحلة ${st.universityName}',
                                        style: AppTextStyles.labelSmall
                                            .copyWith(
                                                color: const Color(0xFF3F51B5),
                                                fontWeight: FontWeight.w700)),
                                  if (st.lineName.isNotEmpty)
                                    Text(st.lineName,
                                        style: AppTextStyles.labelSmall
                                            .copyWith(
                                                color:
                                                    AppColors.textSecondary)),
                                  Text(
                                    'الذهاب: ${st.departureTime} · العودة: ${st.returnTime}',
                                    style: AppTextStyles.labelSmall.copyWith(
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: st.ridingCount > 0
                                  ? AppColors.babyBlueUltraLight
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${st.ridingCount} ذهاب\n${st.returningCount} عودة',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: st.ridingCount > 0
                                    ? AppColors.babyBlueDark
                                    : AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: _counts.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}
