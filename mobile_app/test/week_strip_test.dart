import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/features/student/daily_ride/models/vote_settings.dart';
import 'package:basak_mobile/features/student/home/presentation/ride_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Sunday 11 October 2026: its week runs from Saturday the 10th.
  final asked = DateTime(2026, 10, 11);

  group('the week under the ride vote', () {
    test('each day shows its own answer: riding, not riding, asked, off, open', () {
      final week = RideWords.week(
        asked: asked,
        statuses: {DateTime(2026, 10, 10): true, DateTime(2026, 10, 12): false},
        vote: VoteSettings.fallback,
        ringAsked: true,
      );
      expect(week[0].mark, WeekDayMark.confirmed);
      expect(week[1].mark, WeekDayMark.asked);
      expect(week[2].mark, WeekDayMark.declined);
      expect([for (final d in week) d.day], [10, 11, 12, 13, 14, 15, 16]);
      // The asked day, once answered, shows the answer instead of the ring.
      final answered = RideWords.week(
          asked: asked, statuses: {asked: true}, vote: VoteSettings.fallback, ringAsked: false);
      expect(answered[1].mark, WeekDayMark.confirmed);
    });

    test('a tapped day says where it stands', () {
      final day = DateTime(2026, 10, 12);
      expect(RideWords.dayNote(day, riding: true, off: false, asked: false), contains('أكّدت أنك ستركب'));
      expect(RideWords.dayNote(day, riding: false, off: false, asked: false), contains('لن تركب'));
      expect(RideWords.dayNote(day, riding: null, off: true, asked: false), contains('لا رحلات'));
      expect(RideWords.dayNote(day, riding: null, off: false, asked: true), contains('بانتظار إجابتك'));
      expect(RideWords.dayNote(day, riding: null, off: false, asked: false), contains('لم تصوّت'));
      expect(RideWords.dayNote(day, riding: true, off: false, asked: false), startsWith('يوم الاثنين 12'));
    });

    testWidgets('a confirmed day is a green disc, and a tap reports the day', (tester) async {
      final tapped = <int>[];
      Widget strip(WeekDayMark second) => MaterialApp(
            theme: AppTheme.lightTheme,
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: WeekStrip(
                  days: [
                    (letter: 'س', day: 10, mark: WeekDayMark.confirmed),
                    (letter: 'ح', day: 11, mark: second),
                    (letter: 'ن', day: 12, mark: WeekDayMark.declined),
                    (letter: 'ث', day: 13, mark: WeekDayMark.open),
                    (letter: 'ر', day: 14, mark: WeekDayMark.open),
                    (letter: 'خ', day: 15, mark: WeekDayMark.open),
                    (letter: 'ج', day: 16, mark: WeekDayMark.off),
                  ],
                  onDayTap: tapped.add,
                ),
              ),
            ),
          );
      Color? discOf(int index) {
        final box = tester.widget<AnimatedContainer>(
            find.descendant(of: find.byKey(Key('week-day-$index')), matching: find.byType(AnimatedContainer)));
        return (box.decoration as BoxDecoration).color;
      }

      await tester.pumpWidget(strip(WeekDayMark.asked));
      final colors = BasakColors.light;
      expect(discOf(0), colors.success);
      expect(discOf(2), colors.dangerTint);
      expect(discOf(1), colors.surface, reason: 'asked: a ring, not filled');

      // The student answers: the asked day turns green.
      await tester.pumpWidget(strip(WeekDayMark.confirmed));
      await tester.pumpAndSettle();
      expect(discOf(1), colors.success);

      await tester.tap(find.byKey(const Key('week-day-2')));
      expect(tapped, [2]);
    });
  });
}
