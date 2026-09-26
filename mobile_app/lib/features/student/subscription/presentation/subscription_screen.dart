import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../lines/data/lines_repository.dart';
import '../../lines/models/line_model.dart';
import '../models/subscription_model.dart';
import '../../home/presentation/student_home_screen.dart';

final linesRepoProvider = Provider((ref) => LinesRepository());
final allLinesProvider = FutureProvider<List<LineModel>>((ref) async {
  return ref.watch(linesRepoProvider).getAllLines();
});

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  LineModel? _selectedLine;
  StationModel? _selectedStation;
  List<StationModel> _stations = [];
  String _selectedType = 'termly'; // termly | yearly | daily
  bool _isLoadingStations = false;
  bool _isSubmitting = false;

  Future<void> _onLineSelected(LineModel line) async {
    setState(() {
      _selectedLine = line;
      _selectedStation = null;
      _isLoadingStations = true;
    });

    final stations = await ref.read(linesRepoProvider).getStationsForLine(line.id);
    if (mounted) {
      setState(() {
        _stations = stations;
        _isLoadingStations = false;
      });
    }
  }

  Future<void> _createSubscription() async {
    if (_selectedLine == null || _selectedStation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار الخط ومحطة الركوب أولاً.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    double price = _selectedType == 'yearly'
        ? _selectedLine!.priceYearly
        : _selectedType == 'termly'
            ? _selectedLine!.priceTermly
            : _selectedLine!.priceDaily;

    try {
      await ref.read(subscriptionRepoProvider).createSubscription(
            lineId: _selectedLine!.id,
            stationId: _selectedStation!.id,
            type: _selectedType,
            price: price,
          );
      ref.invalidate(currentSubscriptionProvider);
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إنشاء طلب الاشتراك بنجاح!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _pickAndUploadReceipt(String subscriptionId) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final ext = picked.name.split('.').last;

    try {
      await ref.read(subscriptionRepoProvider).uploadReceipt(
            subscriptionId: subscriptionId,
            fileBytes: bytes,
            fileExtension: ext,
          );
      ref.invalidate(currentSubscriptionProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم رفع صورة الإيصال بنجاح وهو الآن قيد مراجعة المشرف.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subAsync = ref.watch(currentSubscriptionProvider);
    final linesAsync = ref.watch(allLinesProvider);

    return GlassScaffold(
      body: subAsync.when(
        data: (activeSub) {
          // If the student already has an active or pending subscription, show locked view with receipt flow
          if (activeSub != null) {
            return _buildActiveSubDetailView(activeSub);
          }
          // Otherwise show line/station selection flow
          return _buildSubscriptionSelectionView(linesAsync);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('خطأ: $err')),
      ),
    );
  }

  Widget _buildActiveSubDetailView(SubscriptionModel sub) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تفاصيل الاشتراك الحالي', style: AppTextStyles.displayMedium),
          const SizedBox(height: 16),

          // Main Subscription Glass Card
          GlassContainer(
            borderRadius: 24,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      sub.type == 'yearly'
                          ? 'اشتراك سنوي'
                          : sub.type == 'termly'
                              ? 'اشتراك فصلي (ترم)'
                              : 'اشتراك يومي (نقدي)',
                      style: AppTextStyles.titleLarge,
                    ),
                    Text(
                      '${sub.price.toStringAsFixed(0)} ج.م',
                      style: AppTextStyles.titleLarge.copyWith(color: AppColors.babyBlueDark),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('الخط: ${sub.lineName ?? ""}', style: AppTextStyles.bodyLarge),
                Text('محطة الركوب: ${sub.stationName ?? ""}', style: AppTextStyles.bodyMedium),
                const Divider(height: 24),

                // Status Banner
                if (sub.isPendingReview) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warningLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.clock, color: AppColors.warning, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'تم رفع الإيصال وبانتظار مراجعة واعتماد المشرف.',
                            style: AppTextStyles.labelSmall.copyWith(color: AppColors.warning),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (sub.isRejected) ...[
                  // Rejection flow with mandatory reason and re-upload (up to 5 attempts)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.xCircle, color: AppColors.error, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'تم رفض الإيصال من قِبل المشرف',
                              style: AppTextStyles.titleMedium.copyWith(color: AppColors.error),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'يمكنك إعادة رفع الإيصال بحد أقصى 4 مرات إضافية (5 محاولات إجمالاً).',
                          style: AppTextStyles.labelSmall.copyWith(color: AppColors.error),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _pickAndUploadReceipt(sub.id),
                          icon: const Icon(LucideIcons.uploadCloud, size: 18),
                          label: const Text('إعادة رفع إيصال التحويل'),
                        ),
                      ],
                    ),
                  ),
                ] else if (sub.status == 'pending_payment') ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.babyBlueUltraLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('يرجى تحويل المبلغ ورفع صورة إيصال التحويل البنكي', style: AppTextStyles.bodyMedium),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.babyBlue,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _pickAndUploadReceipt(sub.id),
                          icon: const Icon(LucideIcons.uploadCloud, size: 18),
                          label: const Text('رفع صورة الإيصال'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildSubscriptionSelectionView(AsyncValue<List<LineModel>> linesAsync) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('اختيار الخط والاشتراك', style: AppTextStyles.displayMedium),
          const SizedBox(height: 4),
          Text('اختر خط السير ثم محطة الركوب الخاصة بك', style: AppTextStyles.bodyMedium),
          const SizedBox(height: 20),

          // 1. Pick Line
          Text('1. خطوط السير المتاحة', style: AppTextStyles.titleMedium),
          const SizedBox(height: 8),
          linesAsync.when(
            data: (lines) => Column(
              children: lines.map((line) {
                final isSelected = _selectedLine?.id == line.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassContainer(
                    onTap: () => _onLineSelected(line),
                    borderRadius: 18,
                    padding: const EdgeInsets.all(16),
                    border: Border.all(
                      color: isSelected ? AppColors.babyBlue : AppColors.glassBorder,
                      width: isSelected ? 2 : 1,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? LucideIcons.checkCircle : LucideIcons.circle,
                          color: isSelected ? AppColors.babyBlue : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(line.name, style: AppTextStyles.titleMedium),
                              Text(
                                line.companyName ?? 'شركة النقل',
                                style: AppTextStyles.labelSmall.copyWith(color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Text('خطأ: $err'),
          ),

          // 2. Pick Station
          if (_selectedLine != null) ...[
            const SizedBox(height: 20),
            Text('2. محطة الركوب', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            if (_isLoadingStations)
              const Center(child: CircularProgressIndicator())
            else
              Column(
                children: _stations.map((st) {
                  final isSelected = _selectedStation?.id == st.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassContainer(
                      onTap: () => setState(() => _selectedStation = st),
                      borderRadius: 16,
                      padding: const EdgeInsets.all(14),
                      border: Border.all(
                        color: isSelected ? AppColors.babyBlue : AppColors.glassBorder,
                        width: isSelected ? 2 : 1,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isSelected ? LucideIcons.checkCircle : LucideIcons.mapPin,
                                color: isSelected ? AppColors.babyBlue : AppColors.textSecondary,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Text(st.name, style: AppTextStyles.bodyLarge),
                            ],
                          ),
                          Text(
                            'ذهاب: ${st.departureTime}',
                            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

            // 3. Subscription Type & Pricing
            const SizedBox(height: 20),
            Text('3. نوع الاشتراك', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildTypeCard('termly', 'ترم (فصلي)', _selectedLine!.priceTermly),
                const SizedBox(width: 10),
                _buildTypeCard('yearly', 'سنوي', _selectedLine!.priceYearly),
                const SizedBox(width: 10),
                _buildTypeCard('daily', 'يومي (كاش)', _selectedLine!.priceDaily),
              ],
            ),

            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.babyBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _isSubmitting ? null : _createSubscription,
              child: _isSubmitting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('تأكيد الاشتراك'),
            ),
          ],

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildTypeCard(String typeKey, String label, double price) {
    final isSelected = _selectedType == typeKey;
    return Expanded(
      child: GlassContainer(
        onTap: () => setState(() => _selectedType = typeKey),
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        border: Border.all(
          color: isSelected ? AppColors.babyBlue : AppColors.glassBorder,
          width: isSelected ? 2 : 1,
        ),
        child: Column(
          children: [
            Text(label, style: AppTextStyles.labelSmall.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              '${price.toStringAsFixed(0)} ج.م',
              style: AppTextStyles.titleMedium.copyWith(color: AppColors.babyBlueDark),
            ),
          ],
        ),
      ),
    );
  }
}
