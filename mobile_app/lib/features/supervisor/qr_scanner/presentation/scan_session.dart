import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/session.dart';
import '../../models/supervisor_models.dart';

/// What the scanner remembers while the supervisor moves between the tabs:
/// how many it boarded since sign-in, the last boarding, and the direction
/// chosen on the scanner tab. It stores; it fetches nothing.
class ScanSession {
  /// Boardings recorded by this phone since sign-in.
  final int boarded;

  /// The last boarding recorded, to open again from the camera.
  final CheckInResult? last;

  /// 'departure' | 'return' as chosen on the scanner tab; null = not chosen,
  /// so the tab follows the trip picked on Trips, or the clock.
  final String? direction;

  const ScanSession({this.boarded = 0, this.last, this.direction});
}

class ScanSessionNotifier extends Notifier<ScanSession> {
  @override
  ScanSession build() {
    // Another account starts from nothing.
    ref.watch(sessionUserIdProvider);
    return const ScanSession();
  }

  void recordBoarding(CheckInResult result) =>
      state = ScanSession(boarded: state.boarded + 1, last: result, direction: state.direction);

  void chooseDirection(String direction) =>
      state = ScanSession(boarded: state.boarded, last: state.last, direction: direction);
}

final scanSessionProvider = NotifierProvider<ScanSessionNotifier, ScanSession>(ScanSessionNotifier.new);
