import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/ui/ui.dart';
import '../../../notifications/push/notification_platform.dart';
import 'scanner_view.dart';

/// Scans a student's card and records the boarding (`supervisor_check_in_student`)
/// for the Going or Return trip: once per student, day and direction.
///
/// As a tab it sends no trip: each student is boarded on their own trip, and
/// only the direction is chosen. Opened from Trips it is pinned to that trip
/// ([direction], [tripId]). This widget owns the camera; everything drawn over
/// it, and what happens with a code, is [ScannerView].
class SupervisorQrScannerScreen extends ConsumerStatefulWidget {
  /// 'departure' | 'return'; null = chosen on screen.
  final String? direction;
  final String? tripId;

  /// The pinned trip's time, as it is shown ("7:00 ص").
  final String? tripLabel;

  /// The pinned trip's line: with it the count pill reads boarded / expected.
  final String? lineId;

  /// Off while the scanner is a tab that is not in front: the camera stops.
  final bool active;

  const SupervisorQrScannerScreen({
    super.key,
    this.direction,
    this.tripId,
    this.tripLabel,
    this.lineId,
    this.active = true,
  });

  @override
  ConsumerState<SupervisorQrScannerScreen> createState() => _SupervisorQrScannerScreenState();
}

class _SupervisorQrScannerScreenState extends ConsumerState<SupervisorQrScannerScreen>
    with WidgetsBindingObserver {
  // Started and stopped here rather than by the MobileScanner widget: with a
  // controller of our own the widget ignores app lifecycle, and on Android the
  // camera preview stays black after the app returns from the background (or
  // from the permission dialog) unless the camera is restarted.
  final MobileScannerController _camera = MobileScannerController(autoStart: false);
  final _view = GlobalKey<ScannerViewState>();

  void _onDetect(BarcodeCapture capture) {
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (raw == null) return;
    // The camera never stops: a code read while a result is shown is ignored.
    unawaited(_view.currentState?.handleCode(raw));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) unawaited(_startCamera());
  }

  @override
  void didUpdateWidget(SupervisorQrScannerScreen old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    unawaited(widget.active ? _startCamera() : _camera.stop());
  }

  Future<void> _startCamera() async {
    try {
      await _camera.start();
    } on MobileScannerException {
      // Shown by the view, from the controller's own state.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The permission dialog itself changes the lifecycle state; leave the
    // camera alone until access has been granted.
    if (!widget.active || !_camera.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_startCamera());
      case AppLifecycleState.inactive:
        unawaited(_camera.stop());
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
    unawaited(_camera.dispose());
  }

  static ScanCameraState _stateOf(MobileScannerException? error) => switch (error?.errorCode) {
        null => ScanCameraState.ready,
        MobileScannerErrorCode.permissionDenied => ScanCameraState.denied,
        MobileScannerErrorCode.unsupported => ScanCameraState.unsupported,
        _ => ScanCameraState.failed,
      };

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<MobileScannerState>(
        valueListenable: _camera,
        builder: (context, camera, _) => ScannerView(
          key: _view,
          camera: MobileScanner(
            controller: _camera,
            onDetect: _onDetect,
            placeholderBuilder: (context) => const ScanBackdrop(),
            errorBuilder: (context, error) => const ScanBackdrop(),
          ),
          cameraState: _stateOf(camera.error),
          torchOn: camera.torchState == TorchState.on,
          frontCamera: camera.cameraDirection == CameraFacing.front,
          onToggleTorch:
              camera.torchState == TorchState.unavailable ? null : () => unawaited(_camera.toggleTorch()),
          onFlipCamera: () => unawaited(_camera.switchCamera()),
          onRetryCamera: () => unawaited(_startCamera()),
          onOpenSettings: () => unawaited(NotificationPlatform.openAppSettings()),
          direction: widget.direction,
          tripId: widget.tripId,
          tripLabel: widget.tripLabel,
          lineId: widget.lineId,
          inTab: widget.direction == null,
        ),
      );
}
