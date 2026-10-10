import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/ui/arabic_count.dart';
import 'package:basak_mobile/features/student/daily_ride/models/vote_settings.dart';
import 'package:basak_mobile/features/supervisor/home/home_counts.dart';

void main() {
  group('a number with its noun', () {
    test('students: one, two, three to ten, eleven and up — as the boards write them', () {
      expect(ArabicCount.students(1), 'طالب واحد');
      expect(ArabicCount.students(2), 'طالبان');
      expect(ArabicCount.students(2, oblique: true), 'طالبين');
      expect(ArabicCount.students(3), '3 طلاب');
      expect(ArabicCount.students(9), '9 طلاب');
      expect(ArabicCount.students(10), '10 طلاب');
      expect(ArabicCount.students(11), '11 طالباً');
      expect(ArabicCount.students(12), '12 طالباً');
      expect(ArabicCount.students(38), '38 طالباً');
      expect(ArabicCount.students(99), '99 طالباً');
    });

    test('the hundreds follow their last two digits', () {
      expect(ArabicCount.students(100), '100 طالب');
      expect(ArabicCount.students(101), '101 طالب');
      expect(ArabicCount.students(103), '103 طلاب');
      expect(ArabicCount.students(110), '110 طلاب');
      expect(ArabicCount.students(111), '111 طالباً');
      expect(ArabicCount.subscribers(124), '124 مشتركاً');
      expect(ArabicCount.students(200), '200 طالب');
    });

    test('nobody is said in words, never "0 طالب"', () {
      expect(ArabicCount.students(0), 'لا أحد');
      expect(ArabicCount.students(-3), 'لا أحد');
    });

    test('trips, stops, lines, buses and minutes', () {
      expect(ArabicCount.trips(5), '5 رحلات');
      expect(ArabicCount.trips(6), '6 رحلات');
      expect(ArabicCount.trips(1), 'رحلة واحدة');
      expect(ArabicCount.trips(2), 'رحلتان');
      expect(ArabicCount.trips(2, oblique: true), 'رحلتين');
      expect(ArabicCount.trips(12), '12 رحلة');
      expect(ArabicCount.stops(7), '7 محطات');
      expect(ArabicCount.stops(12), '12 محطة');
      expect(ArabicCount.lines(3, oblique: true), '3 خطوط');
      expect(ArabicCount.buses(2, oblique: true), 'باصين');
      expect(ArabicCount.buses(3, oblique: true), '3 باصات');
      expect(ArabicCount.minutes(27), '27 دقيقة');
      expect(ArabicCount.minutes(5), '5 دقائق');
      expect(ArabicCount.subscribers(5), '5 مشتركين');
    });
  });

  group('the words of the supervisor\'s day', () {
    const vote = VoteSettings.fallback; // opens 4 PM the day before, closes 6 AM
    final sunday = DateTime(2026, 10, 11), monday = DateTime(2026, 10, 12);

    test('the day names itself', () {
      final now = DateTime(2026, 10, 11, 6, 50);
      expect(SupervisorWords.dayTitle(sunday, now), 'اليوم · الأحد 11 أكتوبر');
      expect(SupervisorWords.dayTitle(monday, now), 'غداً · الاثنين 12 أكتوبر');
      expect(SupervisorWords.dayTitle(DateTime(2026, 10, 9), now), 'الجمعة 9 أكتوبر', reason: 'a stale saved day');
      expect(SupervisorWords.date(sunday), 'الأحد 11 أكتوبر');
    });

    test('how firm the numbers are, from the company\'s vote window', () {
      expect(SupervisorWords.firmness(vote, sunday, DateTime(2026, 10, 11, 6, 50)),
          (text: 'نهائي · أُغلق التأكيد 6:00 ص', isFinal: true));
      expect(SupervisorWords.firmness(vote, monday, DateTime(2026, 10, 11, 19, 30)),
          (text: 'التأكيد مفتوح حتى 6:00 ص', isFinal: false));
      expect(SupervisorWords.firmness(vote, monday, DateTime(2026, 10, 11, 6, 50)),
          (text: 'يفتح التأكيد 4:00 م', isFinal: false));
      expect(SupervisorWords.firmness(vote, sunday, DateTime(2026, 10, 11, 5, 59)).isFinal, isFalse);
    });

    test('how much of the line rides', () {
      expect(SupervisorWords.shareSentence(107, 124, isFinal: true), 'سيركب 107 من 124 مشتركاً');
      expect(SupervisorWords.shareSentence(64, 124, isFinal: false), 'أكّد 64 من 124 مشتركاً حتى الآن');
      expect(SupervisorWords.inTrips(5), 'في 5 رحلات');
      expect(SupervisorWords.inTrips(2), 'في رحلتين');
      expect(SupervisorWords.inTrips(1), 'في رحلة واحدة');
    });

    test('how far a trip is, by the clock', () {
      final now = DateTime(2026, 10, 11, 7, 18);
      expect(SupervisorWords.distance('06:15:00', now), 'مضى موعدها');
      expect(SupervisorWords.distance('07:00:00', now), 'الآن');
      expect(SupervisorWords.distance('07:45:00', now), 'بعد 27 دقيقة');
      expect(SupervisorWords.distance('08:30:00', now), isNull);
      expect(SupervisorWords.isPast('06:15:00', now), isTrue);
      expect(SupervisorWords.isPast('07:00:00', now), isFalse, reason: 'the bus is still on its stops');
      expect(SupervisorWords.isPast('07:45:00', now), isFalse);
    });

    test('the seats of a bus: silent with room, "45 من 50" when nearly full, buses when over', () {
      expect(CapacityNote.forRow(38, null), isNull, reason: 'the company set no number');
      expect(CapacityNote.forRow(12, 50), isNull);
      expect(CapacityNote.forRow(39, 50), isNull);
      expect(CapacityNote.forRow(40, 50)?.text, '40 من 50');
      expect(CapacityNote.forRow(50, 50)?.warns, isFalse);
      expect(CapacityNote.forRow(51, 50)?.text, 'يحتاج باصين');
      expect(CapacityNote.forRow(51, 50)?.warns, isTrue);
      expect(CapacityNote.forRow(101, 50)?.text, 'يحتاج 3 باصات');
      expect(CapacityNote.forRow(0, 50), isNull);
      expect(CapacityNote.forTrip(38, 50)?.text, 'مقاعد الباص: 38 من 50');
      expect(CapacityNote.forTrip(62, 50)?.text, 'يحتاج باصين · الباص 50 مقعداً');
      expect(CapacityNote.forTrip(38, null), isNull);
    });
  });
}
