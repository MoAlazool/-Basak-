import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../data/qr_scanner_repository.dart';
import '../models/scanned_student_details.dart';

final qrScannerRepoProvider = Provider((ref) => QrScannerRepository());

class SupervisorQrScannerScreen extends ConsumerStatefulWidget {
  const SupervisorQrScannerScreen({super.key});

  @override
  ConsumerState<SupervisorQrScannerScreen> createState() => _SupervisorQrScannerScreenState();
}

class _SupervisorQrScannerScreenState extends ConsumerState<SupervisorQrScannerScreen> {
  final MobileScannerController _cameraController = MobileScannerController();
  bool _isProcessing = false;

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue;
    if (rawValue == null) return;

    setState(() => _isProcessing = true);

    try {
      final details = await ref.read(qrScannerRepoProvider).lookupStudentByQr(rawValue);
      if (mounted) {
        _showStudentDetailsSheet(details);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في البحث: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showStudentDetailsSheet(ScannedStudentDetails student) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: GlassContainer(
          blur: 20,
          opacity: 0.90,
          borderRadius: 28,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.babyBlueUltraLight,
                        child: const Icon(LucideIcons.user, color: AppColors.babyBlueDark),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(student.fullName, style: AppTextStyles.titleLarge),
                          Text(student.university, style: AppTextStyles.bodyMedium),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
              const Divider(height: 24),
              _buildDetailRow(LucideIcons.phone, 'رقم الهاتف', student.phone),
              _buildDetailRow(LucideIcons.mapPin, 'المحطة', student.stationName ?? 'غير محدد'),
              _buildDetailRow(LucideIcons.bus, 'الخط', student.lineName ?? 'غير محدد'),
              _buildDetailRow(
                LucideIcons.creditCard,
                'حالة الاشتراك',
                student.hasActiveSubscription ? 'نشط ومسدد' : 'غير مسدد / معلق',
                valueColor: student.hasActiveSubscription ? AppColors.success : AppColors.error,
              ),
              if (student.paymentDate != null)
                _buildDetailRow(LucideIcons.calendarCheck, 'تاريخ الاعتماد', student.paymentDate!),

              const SizedBox(height: 12),
              // Prominent Notice: QR Scan does NOT mark attendance!
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.info, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تم الاستعلام بنجاح. هذا الإجراء للاطلاع فقط ولا يغير سجل الحضور.',
                        style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.babyBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() => _isProcessing = false);
                },
                child: const Text('إغلاق والاستعلام عن طالب آخر'),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _isProcessing = false);
    });
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.babyBlueDark),
              const SizedBox(width: 8),
              Text(label, style: AppTextStyles.bodyMedium),
            ],
          ),
          Text(
            value,
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      body: Stack(
        children: [
          MobileScanner(
            controller: _cameraController,
            onDetect: _onDetect,
          ),

          // Glass viewfinder overlay
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.babyBlue, width: 2.5),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),

          // Top Info Banner
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              borderRadius: 20,
              child: Row(
                children: [
                  const Icon(LucideIcons.scanLine, color: AppColors.babyBlueDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'وجه الكاميرا نحو رمز QR الخاص بالطالب للاستعلام الفوري',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
