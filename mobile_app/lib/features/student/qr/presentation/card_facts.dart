import 'package:flutter/widgets.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/basak_ui.dart' show BasakUi;
import '../../daily_ride/data/daily_ride_repository.dart';
import '../data/student_qr_repository.dart';

/// What the card and its details sheet say about a pass: one reading of the
/// subscription's state and of today's ride, so both show the same facts.

/// Where the student's subscription stands, as a supervisor must read it.
enum CardStanding {
  active,
  upcoming,
  pendingReview,
  pendingPayment,
  rejected,
  expired,
  none;

  static CardStanding of(StudentPassDetails pass) {
    final status = pass.subscriptionStatus;
    if (status == null || pass.subscriptionId == null && pass.lineName == null) return none;
    if (status == 'expired' || pass.periodPhase == 'expired') return expired;
    return switch (status) {
      'active' => pass.periodPhase == 'upcoming' ? upcoming : active,
      'pending_review' => pendingReview,
      'pending_payment' => pendingPayment,
      'rejected' => rejected,
      _ => none,
    };
  }

  /// Only this one lets a student board.
  bool get isActive => this == active;

  BasakStatus get status => switch (this) {
        active => BasakStatus.active,
        upcoming => BasakStatus.upcoming,
        pendingReview => BasakStatus.pendingReview,
        pendingPayment => BasakStatus.pendingPayment,
        rejected => BasakStatus.rejected,
        expired || none => BasakStatus.expired,
      };

  /// The chip's words where they differ from the status's own.
  String? get chipLabel => switch (this) {
        active => 'اشتراك نشط',
        none => 'لا يوجد اشتراك',
        _ => null,
      };

  /// The ring around the photo: the status at a glance, always beside its chip.
  Color ring(BasakColors colors) => switch (this) {
        active => colors.mint,
        pendingReview => colors.pendingRing,
        rejected => colors.refusedFrame,
        upcoming || pendingPayment => colors.sky,
        expired || none => colors.grabber,
      };
}

/// Today's ride as far as this phone already knows it (see [KnownRides]).
class TodayRide {
  final DateTime day;

  /// The vote, or null when the student has not voted for today.
  final DailyRideDetails? vote;

  const TodayRide(this.day, this.vote);

  /// Null until a read has covered today: the card then says nothing about it.
  static TodayRide? known([DateTime? now]) {
    final today = now ?? DateTime.now();
    final found = KnownRides.on(today);
    return found.known ? TodayRide(today, found.ride) : null;
  }

  bool get isRiding => vote?.isRiding ?? false;

  /// "رحلة اليوم · الأحد 11 أكتوبر".
  String get title => 'رحلة اليوم · ${BasakUi.arabicWeekdays[day.weekday - 1]} ${CardDates.dayMonth(day)}';

  String? get going => isRiding && (vote!.departureTime ?? '').isNotEmpty ? BasakUi.time12(vote!.departureTime) : null;

  /// The return as the student is shown it: the time the bus leaves the university.
  String? returning(StudentPassDetails pass) {
    final time = vote?.returnTime ?? '';
    if (!isRiding || !vote!.isReturning || time.isEmpty) return null;
    final stop = time.length >= 5 ? time.substring(0, 5) : time;
    return BasakUi.time12(pass.returnStartTimes[stop] ?? time);
  }

  /// "ذهاب 7:23 ص · عودة 3:30 م", or that the ride is not confirmed.
  String summary(StudentPassDetails pass) {
    final parts = [
      if (going != null) 'ذهاب $going',
      if (returning(pass) != null) 'عودة ${returning(pass)}',
    ];
    return parts.isEmpty ? 'لم يؤكّد رحلة اليوم' : parts.join(' · ');
  }
}

abstract final class CardDates {
  static DateTime? parse(String? value) => value == null || value.isEmpty ? null : DateTime.tryParse(value);

  /// "11 أكتوبر".
  static String dayMonth(DateTime date) => '${date.day} ${BasakUi.arabicMonths[date.month - 1]}';

  /// "14 يناير 2027".
  static String full(DateTime date) => '${dayMonth(date)} ${date.year}';

  /// "20 سبتمبر – 14 يناير 2027".
  static String? range(String? start, String? end) {
    final from = parse(start);
    final to = parse(end);
    if (to == null) return from == null ? null : full(from);
    return from == null ? full(to) : '${dayMonth(from)} – ${full(to)}';
  }

  /// "أُرسل اليوم 3:40 م" for a receipt sent at [sentAt] (the server's time stamp).
  static String sent(String sentAt, [DateTime? now]) {
    final at = DateTime.tryParse(sentAt)?.toLocal();
    if (at == null) return 'استلمنا إيصالك';
    final today = now ?? DateTime.now();
    final sameDay = at.year == today.year && at.month == today.month && at.day == today.day;
    final time = BasakUi.time12('${at.hour}:${at.minute.toString().padLeft(2, '0')}');
    return 'أُرسل ${sameDay ? 'اليوم' : dayMonth(at)} $time';
  }
}

/// "010 2345 6789": an Egyptian mobile number in the groups people say it in.
String cardPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\s+'), '');
  return RegExp(r'^\d{11}$').hasMatch(digits)
      ? '${digits.substring(0, 3)} ${digits.substring(3, 7)} ${digits.substring(7)}'
      : phone;
}
