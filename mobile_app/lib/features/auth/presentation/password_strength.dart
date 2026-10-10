/// How strong a password is, for the meter under a new-password field:
/// 1 weak, 2 medium, 3 strong, with the word that names it.
({int level, String label}) passwordStrength(String value) {
  var score = 0;
  if (value.length >= 8) score++;
  if (RegExp(r'[A-Z]').hasMatch(value) && RegExp(r'[a-z]').hasMatch(value)) score++;
  if (RegExp(r'\d').hasMatch(value)) score++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;
  if (score < 2) return (level: 1, label: 'ضعيفة');
  if (score < 4) return (level: 2, label: 'متوسطة');
  return (level: 3, label: 'قوية');
}

/// The shortest password the server takes.
const passwordMinLength = 8;

const passwordTooShortMessage = 'كلمة المرور 8 أحرف على الأقل.';
const passwordMismatchMessage = 'كلمتا المرور غير متطابقتين.';
