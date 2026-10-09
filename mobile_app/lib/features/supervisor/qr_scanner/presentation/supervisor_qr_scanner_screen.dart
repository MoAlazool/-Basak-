import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/basak_ui.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../data/supervisor_repository.dart';
import '../../models/supervisor_models.dart';
import '../../trips/presentation/supervisor_trips_screen.dart' show tripManifestProvider;
import '../models/scanned_student_details.dart';

/// Scan a student's QR, verify identity + subscription and record the check-in
/// (supervisor_check_in_student) for the Going or Return trip — once per
/// student, day and direction. Opened from the Trips page it is pinned to that
/// trip; as a tab the supervisor picks the direction.
class SupervisorQrScannerScreen extends ConsumerStatefulWidget {
  /// 'departure' | 'return'; null = chosen on screen (time-based default).
  final String? direction;
  final String? tripId;
  final String? tripLabel;

  const SupervisorQrScannerScreen({super.key, this.direction, this.tripId, this.tripLabel});

  @override
  ConsumerState<SupervisorQrScannerScreen> createState() => _SupervisorQrScannerScreenState();
}

class _SupervisorQrScannerScreenState extends ConsumerState<SupervisorQrScannerScreen>
    with WidgetsBindingObserver {
  // Started and stopped here rather than by the MobileScanner widget: with a
  // controller of our own the widget ignores app lifecycle, and on Android the
  // camera preview stays black after the app returns from the background (or
  // from the permission dialog) unless the camera is restarted.
  final MobileScannerController _cameraController = MobileScannerController(autoStart: false);
  bool _isProcessing = false;
  late String _direction = widget.direction ?? (DateTime.now().hour < 12 ? 'departure' : 'return');
  bool get _pinned => widget.direction != null;
  int _sessionCheckIns = 0;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final rawValue = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (rawValue == null || rawValue.trim().isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final result = await ref
          .read(supervisorRepoProvider)
          .checkIn(rawValue, direction: _direction, tripId: widget.tripId);
      // Every scan is in the month's log. Read again when that page is opened.
      ref.invalidate(supervisorMonthlySummaryProvider);
      if (result.outcome == CheckInOutcome.checkedIn) {
        _sessionCheckIns++;
        HapticFeedback.mediumImpact();
        // The day's numbers and the trip lists show the check-in. This is
        // their one refresh: the server's announcement of this scan is not
        // acted on again, nor is leaving the scanner.
        ref.invalidate(supervisorDashboardProvider);
        ref.invalidate(tripManifestProvider);
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startCamera());
  }

  Future<void> _startCamera() async {
    try {
      await _cameraController.start();
    } on MobileScannerException {
      // Shown by the scanner's errorBuilder.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The permission dialog itself changes the lifecycle state; leave the
    // camera alone until access has been granted.
    if (!_cameraController.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_startCamera());
      case AppLifecycleState.inactive:
        unawaited(_cameraController.stop());
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
    unawaited(_cameraController.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      body: Stack(
        children: [
          MobileScanner(
            controller: _cameraController,
            onDetect: _onDetect,
            errorBuilder: _cameraError,
          ),

          // Viewfinder (hidden while the camera error message is shown)
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _cameraController,
            builder: (context, state, child) =>
                state.error == null ? child! : const SizedBox.shrink(),
            child: Center(
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
                  const SizedBox(height: 10),
                  if (_pinned)
                    BasakPill(
                      '${_direction == 'return' ? 'رحلة العودة' : 'رحلة الذهاب'}'
                      '${widget.tripLabel != null ? ' · ${widget.tripLabel}' : ''}',
                      icon: _direction == 'return' ? LucideIcons.sunset : LucideIcons.sunrise,
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'departure',
                              label: Text('الذهاب'),
                              icon: Icon(LucideIcons.sunrise, size: 16)),
                          ButtonSegment(
                              value: 'return',
                              label: Text('العودة'),
                              icon: Icon(LucideIcons.sunset, size: 16)),
                        ],
                        selected: {_direction},
                        onSelectionChanged: (value) => setState(() => _direction = value.first),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text('يُسجَّل الطالب مرة واحدة لكل اتجاه (ذهاب / عودة) في اليوم.',
                      style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted)),
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

  /// Shown in place of the camera preview when the scanner cannot start.
  Widget _cameraError(BuildContext context, MobileScannerException error) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final unsupported = error.errorCode == MobileScannerErrorCode.unsupported;
    final details = error.errorDetails?.message;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(denied ? LucideIcons.cameraOff : LucideIcons.triangleAlert,
                  color: Colors.white, size: 40),
              const SizedBox(height: 14),
              Text(
                denied
                    ? 'لم يُسمح باستخدام الكاميرا. فعّل إذن الكاميرا لتطبيق باصك من إعدادات الهاتف ثم أعد المحاولة.'
                    : unsupported
                        ? 'لا توجد كاميرا متاحة على هذا الجهاز.'
                        : 'تعذر تشغيل الكاميرا. أغلق أي تطبيق آخر يستخدمها ثم أعد المحاولة.',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleMedium.copyWith(color: Colors.white),
              ),
              if (details != null && !denied) ...[
                const SizedBox(height: 6),
                Text(details,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.labelSmall.copyWith(color: Colors.white60)),
              ],
              if (!unsupported) ...[
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BasakUi.teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _startCamera,
                  icon: const Icon(LucideIcons.refreshCw, size: 18),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ],
          ),
        ),
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
          icon: LucideIcons.ban,
          color: AppColors.error,
          background: AppColors.errorLight,
          title: 'تم تسجيل حضوره اليوم بالفعل',
          message:
              'تم تسجيل حضور هذا الطالب اليوم بالفعل$at (رحلة $trip). لا يمكن تسجيله مرة أخرى قبل الغد.'
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
              decoration:
                  BoxDecoration(color: status.background, borderRadius: BorderRadius.circular(18)),
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

  static const _amber = Color(0xFFB97812);

  /// Whether the student voted to ride today, and the times they chose.
  ({String text, Color color}) get _vote {
    if (!result.hasRideVote) {
      return switch (result.confirmedRideToday) {
        true => (text: 'أكد ركوب اليوم', color: AppColors.success),
        false => (text: 'لم يؤكد', color: _amber),
        null => (text: 'لم يصوّت', color: _amber),
      };
    }
    final vote = result.rideVote;
    if (vote == null) return (text: 'لم يصوّت اليوم', color: _amber);
    if (!vote.isRiding) return (text: 'صوّت أنه لن يركب', color: AppColors.error);
    final back = vote.isReturning ? 'عودة ${BasakUi.time12(vote.returnTime)}' : 'بدون عودة';
    if (result.direction == 'return') {
      return vote.isReturning
          ? (text: 'أكّد الركوب · $back', color: AppColors.success)
          : (text: 'أكّد الذهاب فقط، بدون عودة', color: _amber);
    }
    return (
      text: 'أكّد الركوب · ذهاب ${BasakUi.time12(vote.departureTime)} · $back',
      color: AppColors.success,
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
          BasakInfoRow(icon: LucideIcons.bus, label: 'الخط', value: student.lineName ?? 'غير محدد'),
          BasakInfoRow(
              icon: LucideIcons.mapPin, label: 'المحطة', value: student.stationName ?? 'غير محدد'),
          BasakInfoRow(
            icon: LucideIcons.creditCard,
            label: 'الاشتراك',
            value: student.hasActiveSubscription ? 'نشط ومسدد' : 'غير مفعل / معلق',
            valueColor: student.hasActiveSubscription ? AppColors.success : AppColors.error,
          ),
          BasakInfoRow(
            icon: LucideIcons.calendarCheck2,
            label: 'تصويت اليوم',
            value: _vote.text,
            valueColor: _vote.color,
          ),
        ],
      );
}
