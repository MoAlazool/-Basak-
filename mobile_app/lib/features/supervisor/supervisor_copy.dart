import '../../core/widgets/basak_ui.dart' show BasakUi;

/// The words the supervisor's screens share besides `ArabicCount`: the noun
/// of a number printed apart from it, numbers with their thousands, a
/// direction, a clock time.
abstract final class SupervisorCopy {
  /// The noun alone, for a number printed apart from it (a counter tile).
  static String noun(
    int n, {
    required String one,
    required String two,
    required String few,
    required String many,
    required String hundred,
  }) {
    if (n == 1) return one;
    if (n == 2) return two;
    final tail = n % 100;
    if (n == 0 || (tail >= 3 && tail <= 10)) return few;
    if (tail >= 11) return many;
    return hundred;
  }

  /// "1,284".
  static String grouped(int n) {
    final digits = n.abs().toString();
    final out = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  /// "ذهاب" or "عودة", for the server's 'departure' | 'return'.
  static String direction(String wire) => wire == 'return' ? 'عودة' : 'ذهاب';

  /// "الذهاب" or "العودة".
  static String theDirection(String wire) => wire == 'return' ? 'العودة' : 'الذهاب';

  /// "7:23 ص".
  static String clock(DateTime at) =>
      BasakUi.time12('${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}');
}
