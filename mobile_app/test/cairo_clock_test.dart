import 'package:basak_mobile/core/time/cairo_clock.dart';
import 'package:basak_mobile/features/student/daily_ride/models/vote_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cairo wall clock from an instant, summer (UTC+3) and winter (UTC+2)', () {
    // 19 Oct 2026 21:30 UTC is 00:30 the next day in Cairo (summer time).
    final summer = CairoClock.fromInstant(DateTime.utc(2026, 10, 19, 21, 30));
    expect([summer.year, summer.month, summer.day, summer.hour, summer.minute], [2026, 10, 20, 0, 30]);
    // 15 Jan 2027 13:00 UTC is 15:00 in Cairo.
    final winter = CairoClock.fromInstant(DateTime.utc(2027, 1, 15, 13));
    expect([winter.day, winter.hour], [15, 15]);
  });

  test('a reviewer in California sees the vote as a phone in Cairo does', () {
    final vote = VoteSettings.fallback;
    // 07:00 in California on 19 Oct (PDT, UTC-7) is 17:00 in Cairo the same day.
    final instant = DateTime.utc(2026, 10, 19, 14);
    final cairo = CairoClock.fromInstant(instant);
    expect(cairo.hour, 17);
    final ride = vote.rideDateFor(cairo);
    expect(vote.isOpenAt(cairo), vote.isOpenAt(DateTime(2026, 10, 19, 17)));
    expect(ride, vote.rideDateFor(DateTime(2026, 10, 19, 17)));
  });

  test('today is Cairo\'s date', () {
    CairoClock.debugNow = () => CairoClock.fromInstant(DateTime.utc(2026, 10, 19, 22, 5));
    addTearDown(() => CairoClock.debugNow = DateTime.now);
    expect(CairoClock.today(), '2026-10-20');
  });
}
