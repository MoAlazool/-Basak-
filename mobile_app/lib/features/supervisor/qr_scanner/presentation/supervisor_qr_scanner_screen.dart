import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/basak_ui.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../data/supervisor_repository.dart';
import '../../models/supervisor_models.dart';
import '../models/scanned_student_details.dart';

/// Tab 2 — scan a student's QR, verify identity + subscription and record the
/// check-in for today's departure or return trip (supervisor_check_in_student).
class SupervisorQrScannerScreen extends ConsumerStatefulWidget {
  const SupervisorQrScannerScreen({super.key});

  @override
  ConsumerState<SupervisorQrScannerScreen> createState() =>
      _SupervisorQrScannerScreenState();
}

class _SupervisorQrScannerScreenState extends ConsumerState<SupervisorQrScannerScreen> {
  final MobileScannerController _cameraController = MobileScannerController();
  bool _isProcessing = false;
  late String _direction = DateTime.now().hour < 12 ? 'departure' : 'return';
  int _sessionCheckIns = 0;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final rawValue = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (rawValue == null || rawValue.trim().isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final result =
          await ref.read(supervisorRepoProvider).checkIn(rawValue, direction: _direction);
      if (result.outcome == CheckInOutcome.checkedIn) {
        _sessionCheckIns++;
        HapticFeedback.mediumImpact();
        ref.invalidate(supervisorDashboardProvider);
      } else {
        HapticFeedback.heavyImpact();
      }
      if (mounted) await _showResultSheet(result);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذر التحقق من الرمز. اتصل بالإنترنت أو راجع صحة الرمز.'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _showResultSheet(CheckInResult result) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _CheckInResultSheet(result: result),
      );

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
          MobileScanner(controller: _cameraController, onDetect: _onDetect),

          // Viewfinder
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                    color: _isProcessing ? AppColors.warning : AppColors.babyBlue, width: 2.5),
                borderRadius: BorderRadius.circular(24),
              ),
              child: _isProcessing
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : null,
            ),
          ),

          // Header: instructions + trip direction
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: GlassContainer(
              padding: const EdgeInsets.all(14),
              borderRadius: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(LucideIcons.scanLine, color: BasakUi.teal),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('امسح بطاقة الطالب للتحقق وتسجيل الصعود',
                          style: AppTextStyles.titleMedium.copyWith(color: BasakUi.ink)),
                    ),
                    if (_sessionCheckIns > 0)
                      BasakPill('$_sessionCheckIns',
                          background: const Color(0xFFE7F8F0),
                          foreground: const Color(0xFF07865A),
                          icon: LucideIcons.check),
                  ]),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'departure',
                            label: Text('رحلة الذهاب'),
                            icon: Icon(LucideIcons.sunrise, size: 16)),
                        ButtonSegment(
                            value: 'return',
                            label: Text('رحلة العودة'),
                            icon: Icon(LucideIcons.sunset, size: 16)),
                      ],
                      selected: {_direction},
                      onSelectionChanged: (value) => setState(() => _direction = value.first),
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: WidgetStateProperty.resolveWith((states) =>
                            states.contains(WidgetState.selected) ? BasakUi.softTeal : Colors.white),
                        foregroundColor: WidgetStateProperty.resolveWith((states) =>
                            states.contains(WidgetState.selected) ? BasakUi.teal : BasakUi.muted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Torch / camera switch
          Positioned(
            bottom: 110,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _roundButton(LucideIcons.flashlight, () => _cameraController.toggleTorch()),
                const SizedBox(width: 16),
                _roundButton(LucideIcons.switchCamera, () => _cameraController.switchCamera()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundButton(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: GlassContainer(
          width: 52,
          height: 52,
          borderRadius: 26,
          child: Icon(icon, color: BasakUi.teal, size: 22),
        ),
      );
}

class _CheckInResultSheet extends StatelessWidget {
  final CheckInResult result;

  const _CheckInResultSheet({required this.result});

  ({IconData icon, Color color, Color background, String title, String message}) get _status {
    final trip = result.direction == 'return' ? 'العودة' : 'الذهاب';
    final at = result.checkedInAt == null
        ? ''
        : ' الساعة ${BasakUi.time12('${result.checkedInAt!.hour}:${result.checkedInAt!.minute.toString().padLeft(2, '0')}')}';
    return switch (result.outcome) {
      CheckInOutcome.checkedIn => (
          icon: LucideIcons.circleCheck,
          color: const Color(0xFF07865A),
          background: const Color(0xFFE7F8F0),
          title: 'تم تسجيل الصعود',
          message: 'سُجّل حضور الطالب لرحلة $trip اليوم$at.'
        ),
      CheckInOutcome.alreadyCheckedIn => (
          icon: LucideIcons.badgeCheck,
          color: const Color(0xFF00658D),
          background: BasakUi.softTeal,
          title: 'مسجل مسبقاً',
          message: 'تم تسجيل هذا الطالب لرحلة $trip اليوم$at. لم يُسجل مرة ثانية.'
        ),
      CheckInOutcome.noActiveSubscription => (
          icon: LucideIcons.creditCard,
          color: const Color(0xFFB97812),
          background: const Color(0xFFFFF4E5),
          title: 'لا يوجد اشتراك ساري',
          message: 'الطالب على خطك لكن اشتراكه غير مفعل أو منتهي. لم يُسجل الصعود.'
        ),
      CheckInOutcome.outsideAssignedLines => (
          icon: LucideIcons.shieldAlert,
          color: AppColors.error,
          background: AppColors.errorLight,
          title: 'الطالب ليس على خطك',
          message: 'هذا الطالب غير مشترك في الخطوط المسندة إليك.'
        ),
      CheckInOutcome.notFound => (
          icon: LucideIcons.qrCode,
          color: AppColors.error,
          background: AppColors.errorLight,
          title: 'رمز غير معروف',
          message: 'هذا الرمز لا يخص أي طالب مسجل في باصك.'
        ),
      CheckInOutcome.offlineLookup => (
          icon: LucideIcons.wifiOff,
          color: const Color(0xFF8A5A00),
          background: const Color(0xFFFFF4E5),
          title: 'وضع عدم الاتصال',
          message: 'بيانات محفوظة من آخر تحقق. لم يُسجل الصعود — أعد المسح عند عودة الاتصال.'
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final student = result.student;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GlassContainer(
        blur: 20,
        opacity: 0.94,
        borderRadius: 28,
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: status.background, borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                Icon(status.icon, color: status.color, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(status.title,
                        style: AppTextStyles.titleLarge.copyWith(color: status.color)),
                    const SizedBox(height: 2),
                    Text(status.message,
                        style: AppTextStyles.labelSmall.copyWith(color: BasakUi.ink)),
                  ]),
                ),
              ]),
            ),
            if (student != null) ...[
              const SizedBox(height: 16),
              _studentDetails(student),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: BasakUi.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(LucideIcons.scanLine, size: 18),
              label: const Text('مسح الطالب التالي'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _studentDetails(ScannedStudentDetails student) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const CircleAvatar(
              radius: 22,
              backgroundColor: BasakUi.softTeal,
              child: Icon(LucideIcons.user, color: BasakUi.teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(student.fullName,
                    style: AppTextStyles.titleMedium.copyWith(color: BasakUi.ink)),
                Text(student.university,
                    style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted)),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          BasakInfoRow(icon: LucideIcons.phone, label: 'رقم الهاتف', value: student.phone),
          BasakInfoRow(
              icon: LucideIcons.bus, label: 'الخط', value: student.lineName ?? 'غير محدد'),
          BasakInfoRow(
              icon: LucideIcons.mapPin, label: 'المحطة', value: student.stationName ?? 'غير محدد'),
          BasakInfoRow(
            icon: LucideIcons.clock3,
            label: 'الموعد',
            value: student.departureTime == null
                ? '—'
                : 'ذهاب ${BasakUi.time12(student.departureTime)} · عودة ${BasakUi.time12(student.returnTime)}',
          ),
          BasakInfoRow(
            icon: LucideIcons.creditCard,
            label: 'الاشتراك',
            value: student.hasActiveSubscription ? 'نشط ومسدد' : 'غير مفعل / معلق',
            valueColor: student.hasActiveSubscription ? AppColors.success : AppColors.error,
          ),
          if (result.confirmedRideToday != null)
            BasakInfoRow(
              icon: LucideIcons.calendarCheck2,
              label: 'تأكيد الركوب في التطبيق',
              value: result.confirmedRideToday! ? 'أكد ركوب اليوم' : 'لم يؤكد',
              valueColor:
                  result.confirmedRideToday! ? AppColors.success : const Color(0xFFB97812),
            ),
        ],
      );
}
