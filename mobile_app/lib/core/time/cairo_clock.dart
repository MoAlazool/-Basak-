import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest_10y.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The company's clock. Vote windows, ride days and "today" are Cairo's, as
/// the server reckons them (`Africa/Cairo`), wherever the phone is set: a
/// student abroad, or a reviewer in another time zone, sees the same open and
/// closed hours and sends the same ride date as a phone in Egypt.
///
/// [now] is Cairo's wall clock as a plain [DateTime]: its year, month, day,
/// hour and minute are Cairo's, so date and hour arithmetic on it is Cairo's.
/// It is not for measuring elapsed time against server timestamps; use
/// [DateTime.now] for that.
class CairoClock {
  CairoClock._();

  static tz.Location? _cairo;
  static bool _failed = false;

  /// Tests: a fixed clock, or the device's (test/flutter_test_config.dart).
  @visibleForTesting
  static DateTime Function()? debugNow;

  static DateTime now() {
    final override = debugNow;
    if (override != null) return override();
    return fromInstant(DateTime.now());
  }

  /// Cairo's wall clock at [instant].
  static DateTime fromInstant(DateTime instant) {
    final cairo = _location();
    if (cairo == null) return instant.toLocal();
    final t = tz.TZDateTime.from(instant, cairo);
    return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second, t.millisecond);
  }

  /// "2026-10-19": Cairo's date today.
  static String today() {
    final n = now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static tz.Location? _location() {
    if (_cairo != null || _failed) return _cairo;
    try {
      // Already loaded when local notifications started; harmless otherwise.
      try {
        _cairo = tz.getLocation('Africa/Cairo');
      } catch (_) {
        tz_data.initializeTimeZones();
        _cairo = tz.getLocation('Africa/Cairo');
      }
    } catch (error) {
      // Without the zone database the phone's clock is the best there is.
      debugPrint('CairoClock: $error');
      _failed = true;
    }
    return _cairo;
  }
}
