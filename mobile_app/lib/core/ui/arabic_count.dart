/// A number with its noun, as Arabic counts it: one and two have their own
/// words, three to ten take the plural, eleven and up the singular.
///
///   1 → "طالب واحد" · 2 → "طالبان" · 9 → "9 طلاب" · 38 → "38 طالباً" ·
///   100 → "100 طالب" · 103 → "103 طلاب" · 124 → "124 طالباً"
///
/// [oblique] is the form after a preposition or as an object ("إلى طالبين",
/// "في رحلتين"); it only changes the dual.
abstract final class ArabicCount {
  /// [one] "طالب واحد", [two] "طالبان", [twoOblique] "طالبين", [few] "طلاب"
  /// (3–10), [many] "طالباً" (11–99), [singular] "طالب" (a round hundred).
  /// [zero] stands for nothing at all ("لا أحد").
  static String of(
    int n, {
    required String zero,
    required String one,
    required String two,
    required String twoOblique,
    required String few,
    required String many,
    required String singular,
    bool oblique = false,
  }) {
    if (n <= 0) return zero;
    if (n == 1) return one;
    if (n == 2) return oblique ? twoOblique : two;
    final rest = n % 100;
    if (rest >= 3 && rest <= 10) return '$n $few';
    if (rest >= 11) return '$n $many';
    return '$n $singular';
  }

  /// "38 طالباً", "9 طلاب".
  static String students(int n, {bool oblique = false}) => of(n,
      zero: 'لا أحد',
      one: 'طالب واحد',
      two: 'طالبان',
      twoOblique: 'طالبين',
      few: 'طلاب',
      many: 'طالباً',
      singular: 'طالب',
      oblique: oblique);

  /// "124 مشتركاً", "5 مشتركين".
  static String subscribers(int n, {bool oblique = false}) => of(n,
      zero: 'لا مشتركين',
      one: 'مشترك واحد',
      two: 'مشتركان',
      twoOblique: 'مشتركَين',
      few: 'مشتركين',
      many: 'مشتركاً',
      singular: 'مشترك',
      oblique: oblique);

  /// "5 رحلات", "12 رحلة".
  static String trips(int n, {bool oblique = false}) => of(n,
      zero: 'لا رحلات',
      one: 'رحلة واحدة',
      two: 'رحلتان',
      twoOblique: 'رحلتين',
      few: 'رحلات',
      many: 'رحلة',
      singular: 'رحلة',
      oblique: oblique);

  /// "7 محطات", "12 محطة".
  static String stops(int n, {bool oblique = false}) => of(n,
      zero: 'لا محطات',
      one: 'محطة واحدة',
      two: 'محطتان',
      twoOblique: 'محطتين',
      few: 'محطات',
      many: 'محطة',
      singular: 'محطة',
      oblique: oblique);

  /// "3 خطوط", "12 خطاً".
  static String lines(int n, {bool oblique = false}) => of(n,
      zero: 'لا خطوط',
      one: 'خط واحد',
      two: 'خطان',
      twoOblique: 'خطين',
      few: 'خطوط',
      many: 'خطاً',
      singular: 'خط',
      oblique: oblique);

  /// "باصين", "3 باصات": how many buses a trip needs.
  static String buses(int n, {bool oblique = false}) => of(n,
      zero: 'لا باصات',
      one: 'باص واحد',
      two: 'باصان',
      twoOblique: 'باصين',
      few: 'باصات',
      many: 'باصاً',
      singular: 'باص',
      oblique: oblique);

  /// "27 دقيقة", "5 دقائق".
  static String minutes(int n, {bool oblique = false}) => of(n,
      zero: 'أقل من دقيقة',
      one: 'دقيقة واحدة',
      two: 'دقيقتان',
      twoOblique: 'دقيقتين',
      few: 'دقائق',
      many: 'دقيقة',
      singular: 'دقيقة',
      oblique: oblique);
}
