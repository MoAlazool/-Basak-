/// The app's shared formatters: the 12-hour clock every time is shown with,
/// and the Arabic names of months and weekdays.
class BasakUi {
  BasakUi._();

  static String time12(String? value) {
    if (value == null) return '—';
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
    if (match == null) return value;
    final rawHour = int.tryParse(match.group(1)!) ?? 0;
    final hour = rawHour % 12 == 0 ? 12 : rawHour % 12;
    return '$hour:${match.group(2)} ${rawHour < 12 ? 'ص' : 'م'}';
  }

  static const arabicMonths = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  static const arabicWeekdays = [
    'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد',
  ];

  static String dateLabel(DateTime date) =>
      '${arabicWeekdays[date.weekday - 1]}، ${date.day} ${arabicMonths[date.month - 1]}';
}
