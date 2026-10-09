/// The colleges a student picks from at sign-up. The choice is saved as its
/// text (`students.college`), so a name here is what the dashboard, the card
/// and the term recap read. The recap matches a college by keyword
/// ("هندسة", "صيدلة", "حاسبات"…): every name below keeps its family's word.
/// Anything else is typed under «كلية أخرى».
const kColleges = <String>[
  // As drawn on the college sheet.
  'الهندسة',
  'الطب',
  'الصيدلة',
  'طب الأسنان',
  'الحاسبات والمعلومات',
  'العلوم',
  'التجارة',
  // The other families the recap has a line for.
  'الذكاء الاصطناعي',
  'العلاج الطبيعي',
  'التمريض',
  'الطب البيطري',
  'الحقوق',
  'الآداب',
  'الإعلام',
  'الألسن',
  'التربية',
  'رياض الأطفال',
  'التربية الرياضية',
  'الزراعة',
  'الفنون',
  'السياحة والفنادق',
  'الآثار',
  'الخدمة الاجتماعية',
];
