import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/basak_ui.dart' show BasakUi;
import '../../daily_ride/models/vote_settings.dart';

/// What the ride card has to say right now.
enum RideCardKind {
  /// The vote is open and the student has not said yes: the question.
  ask,

  /// The vote is open and a ride is confirmed: its two times, and "تعديل".
  confirmed,

  /// A ride is confirmed and its vote has closed: the times, nothing to change.
  confirmedLocked,

  /// The last vote is answered and the next one has not opened yet.
  notOpen,

  /// The vote closed with no answer from the student.
  closed,

  /// The vote is open, but the line has no departure time to choose.
  noTimes,
}

/// Where the ride vote stands at one moment: which card to draw, for which
/// ride day, and the opening and closing it talks about. The same rule as
/// [VoteSettings], which the server applies too.
class RideMoment {
  final RideCardKind kind;

  /// The ride day the card is about.
  final DateTime day;

  /// When the vote for [day] opens and closes.
  final DateTime opens;
  final DateTime closes;

  /// [RideCardKind.closed] only: the next ride day and when its vote opens.
  final DateTime? nextDay;
  final DateTime? nextOpens;

  /// Whether the app reminds the student when the vote for [day] opens.
  final bool reminds;

  const RideMoment({
    required this.kind,
    required this.day,
    required this.opens,
    required this.closes,
    this.nextDay,
    this.nextOpens,
    this.reminds = false,
  });

  bool get isConfirmed => kind == RideCardKind.confirmed || kind == RideCardKind.confirmedLocked;

  /// [known]: the votes were read (false while they could not be, offline
  /// with nothing saved). [riding] and [voted] are about the ride day in
  /// force at [now] ([VoteSettings.rideDateFor]).
  static RideMoment resolve({
    required VoteSettings vote,
    required DateTime now,
    required bool known,
    required bool riding,
    required bool voted,
    required bool hasDepartures,
  }) {
    final ride = vote.rideDateFor(now);
    final window = vote.windowFor(ride);
    if (vote.isOpenAt(now)) {
      return RideMoment(
        kind: riding ? RideCardKind.confirmed : (hasDepartures ? RideCardKind.ask : RideCardKind.noTimes),
        day: ride,
        opens: window.opens,
        closes: window.closes,
      );
    }
    if (riding) {
      return RideMoment(
          kind: RideCardKind.confirmedLocked, day: ride, opens: window.opens, closes: window.closes);
    }
    final next = DateTime(ride.year, ride.month, ride.day + 1);
    final nextWindow = vote.windowFor(next);
    if (known && !voted) {
      return RideMoment(
        kind: RideCardKind.closed,
        day: ride,
        opens: window.opens,
        closes: window.closes,
        nextDay: next,
        nextOpens: nextWindow.opens,
      );
    }
    return RideMoment(
      kind: RideCardKind.notOpen,
      day: next,
      opens: nextWindow.opens,
      closes: nextWindow.closes,
      reminds: vote.remindsFor(next),
    );
  }
}

/// The words the ride card and its sheet share.
abstract final class RideWords {
  /// "الاثنين 12 أكتوبر".
  static String date(DateTime day) =>
      '${BasakUi.arabicWeekdays[day.weekday - 1]} ${day.day} ${BasakUi.arabicMonths[day.month - 1]}';

  /// "6:00 ص".
  static String clock(DateTime at) =>
      BasakUi.time12('${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}');

  static int _daysFromToday(DateTime day, DateTime now) =>
      // Rounded: a day is 23 or 25 hours long when the clocks change.
      (DateTime(day.year, day.month, day.day).difference(DateTime(now.year, now.month, now.day)).inHours / 24).round();

  /// When: "اليوم", "غداً", "يوم الثلاثاء".
  static String when(DateTime day, DateTime now) => switch (_daysFromToday(day, now)) {
        0 => 'اليوم',
        1 => 'غداً',
        _ => 'يوم ${BasakUi.arabicWeekdays[day.weekday - 1]}',
      };

  /// Whose ride: "رحلة اليوم", "رحلة الغد", "رحلة يوم الثلاثاء".
  static String rideOf(DateTime day, DateTime now) => switch (_daysFromToday(day, now)) {
        0 => 'رحلة اليوم',
        1 => 'رحلة الغد',
        _ => 'رحلة يوم ${BasakUi.arabicWeekdays[day.weekday - 1]}',
      };

  static String question(DateTime day, DateTime now) => 'هل ستركب ${when(day, now)}؟';

  /// The seven days (Saturday to Friday) of the week [asked] falls in.
  static List<({String letter, int day, WeekDayMark mark})> week({
    required DateTime asked,
    required Map<DateTime, bool> statuses,
    required VoteSettings vote,
    required bool ringAsked,
  }) {
    const letters = ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج'];
    final first = DateTime(asked.year, asked.month, asked.day - (asked.weekday + 1) % 7);
    return [
      for (var i = 0; i < 7; i++)
        () {
          final day = DateTime(first.year, first.month, first.day + i);
          final WeekDayMark mark;
          if (statuses[day] == true) {
            mark = WeekDayMark.confirmed;
          } else if (ringAsked && DateUtils.isSameDay(day, asked)) {
            mark = WeekDayMark.asked;
          } else if (vote.offWeekdays.contains(day.weekday) || vote.offDates.contains(day)) {
            mark = WeekDayMark.off;
          } else {
            mark = WeekDayMark.open;
          }
          return (letter: letters[i], day: day.day, mark: mark);
        }(),
    ];
  }
}

/// Tomorrow's ride on Home: the question, the confirmed ride, or why there is
/// nothing to answer right now. Answering "yes" opens the ride sheet.
class RideCard extends StatelessWidget {
  final RideMoment moment;
  final DateTime now;

  /// No connection: the answer cannot be sent, and the card says so.
  final bool offline;

  /// An answer is on its way to the server.
  final bool saving;

  /// The confirmed ride's times, already formatted. [returnLabel] null: no
  /// return by bus.
  final String? departureLabel;
  final String? returnLabel;

  final List<({String letter, int day, WeekDayMark mark})> week;

  final VoidCallback onYes;
  final VoidCallback onNo;
  final VoidCallback onEdit;

  const RideCard({
    super.key,
    required this.moment,
    required this.now,
    this.offline = false,
    this.saving = false,
    this.departureLabel,
    this.returnLabel,
    this.week = const [],
    required this.onYes,
    required this.onNo,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final m = moment;
    final closes = RideWords.clock(m.closes);
    final quiet = text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400);
    final help = text.bodySmall.copyWith(color: colors.ink2);
    final needsInternet =
        Text('التأكيد يحتاج اتصالاً بالإنترنت، ومتاح حتى $closes.', style: text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400));

    Widget head(String label, Widget? pill) => Row(
          children: [
            Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: quiet)),
            if (pill != null) ...[const SizedBox(width: BasakSpace.s8), pill],
          ],
        );

    Widget answers({required bool enabled}) => Row(
          children: [
            Expanded(
              flex: 3,
              child: BasakButton(
                key: const Key('ride-yes'),
                label: 'نعم، سأركب',
                size: BasakButtonSize.medium,
                onPressed: enabled && !saving ? onYes : null,
              ),
            ),
            const SizedBox(width: BasakSpace.s10),
            Expanded(
              flex: 2,
              child: BasakButton(
                key: const Key('ride-no'),
                label: 'لن أركب',
                size: BasakButtonSize.medium,
                variant: BasakButtonVariant.secondary,
                loading: saving,
                onPressed: enabled ? onNo : null,
              ),
            ),
          ],
        );

    final strip = week.isEmpty
        ? const <Widget>[]
        : [
            const SizedBox(height: BasakSpace.s14),
            Container(height: 1, color: colors.hairline),
            const SizedBox(height: BasakSpace.s14),
            WeekStrip(days: week),
          ];

    final List<Widget> children;
    switch (m.kind) {
      case RideCardKind.ask:
        children = [
          head(
            RideWords.date(m.day),
            offline ? null : IconPill(icon: LucideIcons.clock3, label: 'حتى $closes', tone: BasakTone.warning),
          ),
          const SizedBox(height: BasakSpace.s12),
          Text(RideWords.question(m.day, now), style: text.sheetTitle),
          const SizedBox(height: BasakSpace.s14),
          answers(enabled: !offline),
          if (offline) ...[const SizedBox(height: BasakSpace.s12), needsInternet] else ...strip,
        ];
      case RideCardKind.confirmed || RideCardKind.confirmedLocked:
        final locked = m.kind == RideCardKind.confirmedLocked;
        children = [
          head(
            '${RideWords.rideOf(m.day, now)} · ${RideWords.date(m.day)}',
            const IconPill(icon: LucideIcons.check, label: 'مؤكدة', tone: BasakTone.success),
          ),
          const SizedBox(height: BasakSpace.s14),
          Row(
            children: [
              Expanded(child: ValueTile(label: 'الذهاب', value: departureLabel ?? '—')),
              const SizedBox(width: BasakSpace.s10),
              Expanded(child: ValueTile(label: 'العودة', value: returnLabel ?? 'بدون عودة')),
            ],
          ),
          const SizedBox(height: BasakSpace.s14),
          if (locked)
            Text('أُغلق التأكيد $closes.', style: text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400))
          else
            Row(
              children: [
                Expanded(
                  child: offline
                      ? needsInternet
                      : Text('التعديل متاح حتى $closes',
                          style: text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400)),
                ),
                const SizedBox(width: BasakSpace.s12),
                BasakButton(
                  key: const Key('ride-edit'),
                  label: 'تعديل',
                  size: BasakButtonSize.small,
                  variant: BasakButtonVariant.secondary,
                  expand: false,
                  loading: saving,
                  onPressed: offline ? null : onEdit,
                ),
              ],
            ),
          ...strip,
        ];
      case RideCardKind.noTimes:
        children = [
          head(RideWords.date(m.day), IconPill(icon: LucideIcons.clock3, label: 'حتى $closes', tone: BasakTone.warning)),
          const SizedBox(height: BasakSpace.s12),
          Text(RideWords.question(m.day, now), style: text.sheetTitle),
          const SizedBox(height: BasakSpace.s12),
          Text('لم يضف المشرف مواعيد ذهاب لهذا الخط بعد.', style: help),
          const SizedBox(height: BasakSpace.s12),
          answers(enabled: false),
        ];
      case RideCardKind.notOpen:
        children = [
          head(
            RideWords.date(m.day),
            IconPill(icon: LucideIcons.clock3, label: 'يفتح ${RideWords.clock(m.opens)}', tone: BasakTone.info),
          ),
          const SizedBox(height: BasakSpace.s12),
          Text(RideWords.question(m.day, now), style: text.sheetTitle),
          const SizedBox(height: BasakSpace.s12),
          Text(
            'يفتح التأكيد ${RideWords.when(m.opens, now)} ${RideWords.clock(m.opens)} ويبقى حتى $closes.'
            '${m.reminds ? ' نذكّرك عند فتحه.' : ''}',
            style: help,
          ),
          const SizedBox(height: BasakSpace.s12),
          answers(enabled: false),
        ];
      case RideCardKind.closed:
        final next = m.nextDay ?? m.day;
        final nextOpens = m.nextOpens ?? m.opens;
        children = [
          head(RideWords.date(m.day), const IconPill(icon: LucideIcons.clock3, label: 'مغلق')),
          const SizedBox(height: BasakSpace.s12),
          Text('انتهى وقت تأكيد ${RideWords.rideOf(m.day, now)}', style: text.sheetTitle),
          const SizedBox(height: BasakSpace.s12),
          Text(
            'أُغلق التأكيد $closes ولم تسجّل رحلة. '
            'يفتح تأكيد يوم ${BasakUi.arabicWeekdays[next.weekday - 1]} '
            '${RideWords.when(nextOpens, now)} ${RideWords.clock(nextOpens)}.',
            style: help,
          ),
          const SizedBox(height: BasakSpace.s12),
          answers(enabled: false),
        ];
    }

    return Semantics(
      container: true,
      label: RideWords.rideOf(m.day, now),
      child: BasakCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

/// In place of the ride card while the subscription is not active yet.
class RideLockedCard extends StatelessWidget {
  const RideLockedCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      container: true,
      child: BasakCard(
        color: colors.sunken,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s18, vertical: BasakSpace.s16),
        child: Row(
          children: [
            Icon(LucideIcons.lock, size: 20, color: colors.ink2),
            const SizedBox(width: BasakSpace.s12),
            Expanded(
              child: Text('تأكيد الرحلات يبدأ بعد تفعيل الاشتراك.',
                  style: context.text.bodySmall.copyWith(color: colors.ink2)),
            ),
          ],
        ),
      ),
    );
  }
}
