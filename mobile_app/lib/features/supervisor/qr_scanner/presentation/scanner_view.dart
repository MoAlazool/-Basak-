import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/offline_cache.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../data/supervisor_repository.dart';
import '../../models/supervisor_models.dart';
import '../../selection/supervisor_selection.dart';
import '../../supervisor_copy.dart';
import '../../trips/presentation/supervisor_trips_screen.dart' show tripManifestProvider;
import 'scan_result_sheet.dart';
import 'scan_session.dart';

/// Whether there is a camera picture to scan with.
enum ScanCameraState {
  ready,

  /// The phone does not let the app use the camera.
  denied,

  /// The phone has no camera.
  unsupported,

  /// The camera could not be started (another app holds it).
  failed,
}

/// Everything of the scanner but the camera itself: the two pills, the frame
/// and its hint, the last boarding, the two toggles, the offline sentence,
/// and what happens with a code once it is read ([ScannerViewState.handleCode]).
///
/// The scanner tab sends no trip: each student is boarded on their own trip
/// in the chosen direction. Opened from Trips it is pinned to that trip
/// ([direction] and [tripId]). The first pill says which of the two holds.
class ScannerView extends ConsumerStatefulWidget {
  /// The live picture, or a `ScanBackdrop` where there is none.
  final Widget camera;
  final ScanCameraState cameraState;
  final bool torchOn;
  final bool frontCamera;
  final VoidCallback? onToggleTorch;
  final VoidCallback? onFlipCamera;
  final VoidCallback? onRetryCamera;
  final VoidCallback? onOpenSettings;

  /// 'departure' | 'return' of the pinned trip; null on the scanner tab.
  final String? direction;
  final String? tripId;

  /// The pinned trip's time, as it is shown ("7:00 ص").
  final String? tripLabel;

  /// The pinned trip's line, for its boarded / expected count.
  final String? lineId;

  /// Under the floating tab bar: its controls stay above it.
  final bool inTab;

  const ScannerView({
    super.key,
    required this.camera,
    this.cameraState = ScanCameraState.ready,
    this.torchOn = false,
    this.frontCamera = false,
    this.onToggleTorch,
    this.onFlipCamera,
    this.onRetryCamera,
    this.onOpenSettings,
    this.direction,
    this.tripId,
    this.tripLabel,
    this.lineId,
    this.inTab = true,
  });

  @override
  ConsumerState<ScannerView> createState() => ScannerViewState();
}

class ScannerViewState extends ConsumerState<ScannerView> {
  /// A code is with the server.
  bool _checking = false;

  /// A result is on screen: the next code waits for it to close.
  CheckInOutcome? _showing;

  bool get _pinned => widget.direction != null;

  /// The pinned trip's direction; on the tab the one chosen there, else the
  /// direction of the trip picked on Trips, else the clock's.
  String get _direction {
    if (_pinned) return widget.direction!;
    final chosen = ref.read(scanSessionProvider).direction;
    if (chosen != null) return chosen;
    final selection = ref.read(supervisorSelectionProvider);
    if (selection.hasTrip) return selection.direction!.wire;
    return DateTime.now().hour < 12 ? 'departure' : 'return';
  }

  /// Checks one scanned code and shows what the server said. A code read
  /// while another is being checked or shown is ignored.
  Future<void> handleCode(String raw) async {
    final code = raw.trim();
    if (code.isEmpty || _checking || _showing != null) return;
    setState(() => _checking = true);
    final CheckInResult result;
    try {
      result = await ref.read(supervisorRepoProvider).checkIn(code, direction: _direction, tripId: widget.tripId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking = false);
      BasakToast.show(context, 'تعذر التحقق من الرمز. اتصل بالإنترنت أو راجع صحة الرمز.',
          kind: BasakToastKind.failure);
      return;
    }
    // Every scan is in the month's log. Read again when that page is opened.
    ref.invalidate(supervisorMonthlySummaryProvider);
    switch (result.outcome) {
      case CheckInOutcome.checkedIn:
        HapticFeedback.mediumImpact();
        ref.read(scanSessionProvider.notifier).recordBoarding(result);
        // The day's numbers and the trip lists show the boarding. This is
        // their one refresh: the server's announcement of this scan is not
        // acted on again, nor is leaving the scanner.
        ref.invalidate(supervisorDashboardProvider);
        ref.invalidate(tripManifestProvider);
      case CheckInOutcome.alreadyCheckedIn:
        // A notice, not an error: the student is on the bus.
        HapticFeedback.lightImpact();
      case CheckInOutcome.noActiveSubscription:
      case CheckInOutcome.outsideAssignedLines:
      case CheckInOutcome.notFound:
      case CheckInOutcome.offlineLookup:
        HapticFeedback.heavyImpact();
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _showing = result.outcome;
    });
    await ScanResultSheet.show(context, result,
        tripLabel: widget.tripLabel, closesItself: result.outcome.isSuccess);
    if (mounted) setState(() => _showing = null);
  }

  Future<void> _reopenLast(CheckInResult last) async {
    if (_checking || _showing != null) return;
    setState(() => _showing = last.outcome);
    await ScanResultSheet.show(context, last, tripLabel: widget.tripLabel);
    if (mounted) setState(() => _showing = null);
  }

  /// The scanner tab boards each student on their own trip; only the
  /// direction is chosen.
  Future<void> _chooseDirection(String current) async {
    final picked = await BasakSheet.show<String>(
      context,
      title: 'الرحلة',
      subtitle: 'يُسجَّل كل طالب في رحلته التي أكّدها.',
      largeTitle: true,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final wire in const ['departure', 'return']) ...[
            SheetRadioRow(
              title: SupervisorCopy.theDirection(wire),
              selected: wire == current,
              onTap: () => Navigator.of(sheet).pop(wire),
            ),
            const SizedBox(height: BasakSpace.s4),
          ],
        ],
      ),
    );
    if (picked != null && mounted) ref.read(scanSessionProvider.notifier).chooseDirection(picked);
  }

  Color? _frameColor(BasakColors colors) => switch (_showing) {
        CheckInOutcome.checkedIn => colors.mint,
        CheckInOutcome.noActiveSubscription ||
        CheckInOutcome.outsideAssignedLines ||
        CheckInOutcome.notFound =>
          colors.refusedFrame,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottom = widget.inTab ? BasakPage.tabBarClearance : BasakSpace.s16 + MediaQuery.paddingOf(context).bottom;

    final Widget body = switch (widget.cameraState) {
      ScanCameraState.ready => _scanner(context, bottom),
      ScanCameraState.denied => ScanGate(
          key: const Key('scan-permission'),
          title: 'اسمح باستخدام الكاميرا',
          message: 'المسح يحتاج الكاميرا لقراءة رمز الطالب. فعّل الإذن لتطبيق باصك من إعدادات الهاتف.',
          primaryLabel: 'فتح الإعدادات',
          primaryIcon: LucideIcons.settings,
          onPrimary: widget.onOpenSettings,
          secondaryLabel: 'إعادة المحاولة',
          onSecondary: widget.onRetryCamera,
          bottomInset: bottom,
        ),
      ScanCameraState.unsupported => ScanGate(
          key: const Key('scan-no-camera'),
          icon: LucideIcons.cameraOff,
          title: 'لا توجد كاميرا',
          message: 'لا توجد كاميرا متاحة على هذا الجهاز.',
          bottomInset: bottom,
        ),
      ScanCameraState.failed => ScanGate(
          key: const Key('scan-camera-failed'),
          icon: LucideIcons.cameraOff,
          title: 'تعذر تشغيل الكاميرا',
          message: 'تعذر تشغيل الكاميرا. أغلق أي تطبيق آخر يستخدمها ثم أعد المحاولة.',
          primaryLabel: 'إعادة المحاولة',
          primaryIcon: LucideIcons.refreshCw,
          onPrimary: widget.onRetryCamera,
          bottomInset: bottom,
        ),
    };

    // The surface is dark: the phone's own status icons turn light on it.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: BasakChrome.onDark(colors.scanBase),
      child: Material(
        color: colors.scanBase,
        child: MediaQuery.withClampedTextScaling(maxScaleFactor: basakMaxTextScale, child: body),
      ),
    );
  }

  Widget _scanner(BuildContext context, double bottom) {
    final colors = context.colors;
    final session = ref.watch(scanSessionProvider);
    // Rebuilt when the trip picked on Trips changes: the tab follows it.
    ref.watch(supervisorSelectionProvider);
    final direction = _direction;

    final String tripText;
    final String tripSemantics;
    if (_pinned) {
      tripText = [SupervisorCopy.direction(direction), if (widget.tripLabel != null) widget.tripLabel!].join(' · ');
      tripSemantics = 'الرحلة: ${tripText.replaceAll(' · ', ' ')}';
    } else {
      tripText = '${SupervisorCopy.direction(direction)} · رحلة كل طالب';
      tripSemantics = 'الرحلة: ${SupervisorCopy.theDirection(direction)}، كل طالب في رحلته. تغيير';
    }

    // Pinned to a trip of a known line: how many of its riders have boarded.
    // Otherwise what this phone boarded since sign-in.
    final manifest = _pinned && widget.lineId != null
        ? ref
            .watch(tripManifestProvider((lineId: widget.lineId!, direction: direction, tripId: widget.tripId)))
            .valueOrNull
        : null;
    final String countText;
    final String countSemantics;
    if (manifest != null) {
      countText = '${manifest.checkedIn} / ${manifest.totalStudents}';
      countSemantics = 'صعد ${manifest.checkedIn} من ${manifest.totalStudents}';
    } else {
      countText = '${session.boarded}';
      countSemantics = 'صعد ${session.boarded} منذ فتح التطبيق';
    }

    final last = session.last;

    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(child: widget.camera),
        SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth),
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(BasakSpace.gutter, BasakSpace.s12, BasakSpace.gutter, bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: ScanChrome.pill(
                            context,
                            label: tripText,
                            semanticLabel: tripSemantics,
                            onTap: _pinned ? null : () => _chooseDirection(direction),
                          ),
                        ),
                        const SizedBox(width: BasakSpace.s12),
                        KeyedSubtree(
                          key: const Key('scan-count'),
                          child: ScanChrome.pill(
                            context,
                            label: countText,
                            icon: LucideIcons.users,
                            ltr: true,
                            semanticLabel: countSemantics,
                          ),
                        ),
                      ],
                    ),
                    ValueListenableBuilder<DateTime?>(
                      valueListenable: OfflineCache.offlineSince,
                      builder: (context, since, _) => since == null
                          ? const SizedBox.shrink()
                          : const Padding(
                              padding: EdgeInsetsDirectional.only(top: BasakSpace.s12),
                              child: ScanNotice(
                                key: Key('scan-offline'),
                                lead: 'بدون إنترنت.',
                                message: 'المسح يعرض بيانات محفوظة ولا يسجّل الصعود.',
                              ),
                            ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(child: ScanFrame(color: _frameColor(colors), busy: _checking)),
                            const SizedBox(height: BasakSpace.s20),
                            Text(
                              'ضع رمز الطالب داخل الإطار',
                              textAlign: TextAlign.center,
                              style: context.text.body.copyWith(color: colors.onInk2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (last?.student != null) ...[
                      ScanLastRow(
                        key: const Key('scan-last'),
                        label: 'آخر صعود: ${last!.student!.fullName}',
                        time: last.checkedInAt == null ? '' : SupervisorCopy.clock(last.checkedInAt!),
                        onTap: () => _reopenLast(last),
                      ),
                      const SizedBox(height: BasakSpace.s10),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: ScanChrome.toggle(
                            context,
                            icon: LucideIcons.zap,
                            label: 'الإضاءة',
                            on: widget.torchOn,
                            onTap: widget.onToggleTorch,
                          ),
                        ),
                        const SizedBox(width: BasakSpace.s10),
                        Expanded(
                          child: ScanChrome.toggle(
                            context,
                            icon: LucideIcons.switchCamera,
                            label: 'قلب الكاميرا',
                            on: widget.frontCamera,
                            onTap: widget.onFlipCamera,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
