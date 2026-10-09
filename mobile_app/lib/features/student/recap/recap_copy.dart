// ملخّص الترم — كل الكلام في ملف واحد.
//
// THE ONE FILE TO EDIT. Every joke, title, college line and page sentence of
// the term recap is here, as plain text. Nothing else in the app holds recap
// copy: change a line here and it changes on the page and on the poster.
//
// How to edit
//   * Change the text between the quotes. Keep the quotes and the commas.
//   * To add a title, add one more quoted line to that pattern's list. A
//     student keeps the title they were drawn while the list keeps its length;
//     adding one may move some students to another title of the same pattern.
//   * To add a college or a department, copy a `RecapFamily(...)` block. Put a
//     more specific row above a more general one ("طب أسنان" above "طب"): the
//     first row whose `keywords` match wins.
//   * A sentence left empty ('') is simply not shown.
//
// Placeholders (written exactly like this, braces included)
//   {ي}        ride days                    {س}        hours on the bus
//   {ن} {ن2}   the count the sentence is about (see the comment on each line)
//   {من}       their own study days in the term (the "of 101")
//   {المحطة}   their stop                   {الخط}     their line
//   {الجامعة}  their university             {الكلية}   the family's short name
//   {اليوم}    their best weekday           {الأضعف}   their weakest weekday
//   {الأيام}   their own weekdays ("الأحد والثلاثاء والخميس")
//   {الوقت}    a time ("7:23")              {الشهر}    a month ("نوفمبر")
//   {مدة}      a length in days ("4 أيام ونص")
//   {اللقب}    their title                  {الترم}    the term's name
//
// Numbers never break the sentence: write a count placeholder followed by its
// noun in the plain form — "{ي} يوم", "{س} ساعة", "{ن} مرة" — and the app
// turns it into "يوم واحد", "يومين", "8 أيام" or "62 يوم" by itself. The
// nouns it knows are in [RecapCopy.nouns]; add a row there for a new noun.
//
// The voice (from the design): laughs with the student, never at them; about
// the road, sleep and the alarm clock — never grades, money, the company, the
// driver or other students; reads the same to any student (no إنتَ / إنتِ).

/// A noun in the four forms a count takes.
class RecapNoun {
  /// 1 — "يوم واحد".
  final String one;

  /// 2 — "يومين".
  final String two;

  /// 3 to 10, after the number — "أيام".
  final String few;

  /// 11 and more, after the number — "يوم". Also how the noun is written in
  /// the sentences of this file.
  final String many;

  const RecapNoun({required this.one, required this.two, required this.few, required this.many});
}

/// The habit a title is given for. The order here is the order they are tried
/// in: the rarer habit first, so the common titles do not crowd out the
/// interesting ones. (Names are used by the app: do not rename.)
enum RecapPattern {
  guest,
  midTerm,
  longRun,
  manyHours,
  shortWeek,
  thursdayOff,
  topWeekday,
  rarelyReturns,
  firstTripGoing,
  lastTripGoing,
  lastTripHome,
  firstTripHome,
  manyTimes,
  sameTime,
  regular,
  fallback,
}

/// The titles of one pattern, and the one line under the title that says why.
class RecapTitles {
  final List<String> titles;

  /// Under the title on the poster, in the student's own voice.
  final String posterWhy;

  /// Under the title on the title page. Empty: the poster's line is used.
  final String pageWhy;

  const RecapTitles({required this.titles, this.posterWhy = '', this.pageWhy = ''});
}

/// A college or a department and its line.
class RecapFamily {
  /// For whoever edits this file; not shown.
  final String name;

  /// Matched as whole words against the student's specialisation, then their
  /// college. A keyword of two words needs both ("علم نفس").
  final List<String> keywords;

  /// {الكلية} on the college page: «يا هندسة».
  final String call;

  /// The specialisation's own line: on the poster and on the college page.
  final String line;

  /// Hours page, under the comparison. Empty: nothing.
  final String hoursTail;

  /// College page, the box: a title and a line under it. Empty: [line].
  final String boxTitle;
  final String boxBody;

  const RecapFamily({
    required this.name,
    required this.keywords,
    required this.call,
    required this.line,
    this.hoursTail = '',
    this.boxTitle = '',
    this.boxBody = '',
  });
}

abstract final class RecapCopy {
  // ---------------------------------------------------------------- shared
  static const brand = 'باصك · ملخّص الترم';
  static const closeLabel = 'إغلاق';

  /// Read by a screen reader on the progress segments. {ن} page, {ن2} pages.
  static const progressLabel = 'الصفحة {ن} من {ن2}';

  // ---------------------------------------------------------------- nouns
  /// Keyed by the form written in the sentences.
  static const nouns = <String, RecapNoun>{
    'يوم': RecapNoun(one: 'يوم واحد', two: 'يومين', few: 'أيام', many: 'يوم'),
    'ساعة': RecapNoun(one: 'ساعة واحدة', two: 'ساعتين', few: 'ساعات', many: 'ساعة'),
    'مرة': RecapNoun(one: 'مرة واحدة', two: 'مرتين', few: 'مرات', many: 'مرة'),
    // Not on the counting board; needed by the college lines below.
    'رحلة': RecapNoun(one: 'رحلة واحدة', two: 'رحلتين', few: 'رحلات', many: 'رحلة'),
    'فصل': RecapNoun(one: 'فصل واحد', two: 'فصلين', few: 'فصول', many: 'فصل'),
    'لوحة': RecapNoun(one: 'لوحة واحدة', two: 'لوحتين', few: 'لوحات', many: 'لوحة'),
    'محاضرة': RecapNoun(one: 'محاضرة واحدة', two: 'محاضرتين', few: 'محاضرات', many: 'محاضرة'),
    'مواعيد': RecapNoun(one: 'معاد واحد', two: 'معادين', few: 'مواعيد', many: 'معاد'),
  };

  /// Half a day more: "4 أيام ونص".
  static const andHalf = ' ونص';

  // ---------------------------------------------------------------- weekdays
  /// ISO numbers: 1 Monday … 7 Sunday.
  static const weekdayNames = <int, String>{
    6: 'السبت',
    7: 'الأحد',
    1: 'الاثنين',
    2: 'الثلاثاء',
    3: 'الأربعاء',
    4: 'الخميس',
    5: 'الجمعة',
  };
  static const weekdayLetters = <int, String>{6: 'س', 7: 'ح', 1: 'ن', 2: 'ث', 3: 'ر', 4: 'خ', 5: 'ج'};

  /// Between the last two weekdays of {الأيام}: "الأحد والثلاثاء والخميس".
  static const and = ' و';

  static const months = <String>[
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  static const am = 'ص';
  static const pm = 'م';

  // ---------------------------------------------------------------- Home banner
  static const bannerTitle = 'ملخّص ترمك جاهز';

  /// With hours known.
  static const bannerHours = '{س} ساعة في الباص… والباقي جوّه.';

  /// Hours unknown.
  static const bannerDays = '{ي} يوم في الباص… والباقي جوّه.';

  // ---------------------------------------------------------------- 1 cover
  static const coverHeadline = 'ترمك\nفي الباص';

  /// The cover's one sentence is put together from these, in this order,
  /// joined by [coverJoin]; a part without its number is left out.
  static const coverHours = '{س} ساعة';
  static const coverDays = '{ي} يوم';

  /// Added when one time holds most of their rides.
  static const coverSameTime = 'ومعاد واحد ما بتغيّروش';
  static const coverJoin = '، ';
  static const coverEnd = '.';
  static const coverCta = 'يلا نشوف';

  // ---------------------------------------------------------------- 2 hours
  static const hoursKicker = 'وقتك على الطريق';

  /// Under the big number.
  static const hoursUnit = 'ساعة في الباص';
  static const hoursUnitFew = 'ساعات في الباص';

  /// What the hours are compared to, by range.
  static const hoursUnder10 = 'يعني فيلمين وخلاص.';
  static const hours10to24 = 'يعني يوم كامل… من غير نوم.';

  /// One to three days. {مدة} "يومين", "يوم ونص".
  static const hours1to3Days = 'يعني {مدة} من عمرك على الطريق.';

  /// Three to six days. {مدة} "4 أيام ونص".
  static const hours3to6Days = 'يعني {مدة} من عمرك جنب الشباك.';
  static const hoursOver6Days = 'ده مش باص، ده سكن.';
  static const hoursFootnote = 'رقم تقريبي، من مواعيد الرحلات اللي أكّدتها.';

  // ---------------------------------------------------------------- 3 days
  static const daysKicker = 'الحضور';

  /// A week of three days or fewer.
  static const daysKickerShortWeek = 'جدولك';
  static const daysUnit = 'يوم ركبت الباص';
  static const daysUnitFew = 'أيام ركبت الباص';

  /// Their best weekday.
  static const daysBest = '{اليوم} يومك.';

  /// Added when their weakest own day is well below the best.
  static const daysWeakest = 'و{الأضعف}؟ واضح إن عندك ظروف.';

  /// A week of three days or fewer. {ن} their days a week.
  static const daysShortWeek = '{ن} يوم في الأسبوع؟ ده جدول يتحسد عليه.';

  /// {ن} ridden of {من} own days.
  static const daysOwnShare = 'وحضرت {ن} من {من} في أيامك.';

  /// Added to [daysOwnShare] when some of their days were missed.
  static const daysOwnShareRest = 'الباقي إجازة رسمي، مش غياب.';

  /// Rides on days that are not theirs. {ن} those days.
  static const daysBonus = 'و{ن} يوم زيادة من عندك.';

  /// By how much they rode (share of their own days).
  static const daysLightRider = 'الباص كان بيسأل عليك.';
  static const daysRegular = 'حتى السواق غاب أكتر منك.';

  // ---------------------------------------------------------------- 4 shape
  static const shapeKicker = 'شكل ترمك';
  static const shapeLine = 'كل نقطة يوم في الباص.';

  /// Added when there is a long gap in the middle of the term.
  static const shapeMidGap = 'والفراغ اللي في النص؟ ميدتيرم… مصدّقينك.';

  /// Read by a screen reader. {ي} ridden, {من} days.
  static const shapeLabel = 'كل أيام الترم: {ي} يوم ركبت فيها من {من}';

  // ---------------------------------------------------------------- 5 longest run
  static const runKicker = 'من غير غياب';
  static const runUnit = 'يوم ورا بعض';
  static const runUnitFew = 'أيام ورا بعض';
  static const runLine = 'حتى المنبّه اتفاجئ.';

  /// The longest absence. {ن} days.
  static const runGapChip = 'أطول غيبة: {ن} يوم · كنا هنسأل عليك';

  // ---------------------------------------------------------------- 6 time
  static const timeKicker = 'معادك';

  /// Only one time was ever used.
  static const timeKickerOnly = 'معاد واحد طول الترم';

  /// {ن} rides at that time.
  static const timeUnit = 'ركبته {ن} مرة';
  static const timeLine = 'الباص بقى عارفك.';

  /// An earlier time used a few times. {ن} times, {الوقت} that time.
  static const timeEarly = 'وصحيت بدري {ن} مرة بس ولحقت {الوقت}. تتحسب لك.';

  // ---------------------------------------------------------------- 7 return
  static const returnKicker = 'الرجوع';
  static const returnUnit = 'مرة رجعت بالباص';
  static const returnUnitFew = 'مرات رجعت بالباص';

  /// Nearly always or mixed. {ن} days they did not return by bus.
  static const returnSkipped = 'و{ن} مرة قلت «هرجع لوحدي». رجعت إزاي؟ ما نعرفش، وما بنسألش.';

  /// Rarely. {ي} going, {ن} returning.
  static const returnRarely = '{ي} مرة رايح… و{ن} بس راجع.';

  /// Never: the headline in place of a number, and the line under it.
  static const returnNeverHeadline = 'تذكرة ذهاب بس';
  static const returnNeverLine = 'رجعت إزاي؟ ما نعرفش، وما بنسألش.';

  /// {الوقت} with ص / م.
  static const returnChip = 'معاد رجوعك المفضّل: {الوقت}';

  // ---------------------------------------------------------------- 8 stop
  /// {الخط} is written with its «خط».
  static const stopKicker = 'محطتك على {الخط}';

  /// They used more than one stop.
  static const stopKickerMostUsed = 'أكتر محطة على {الخط}';

  /// {ن} rides from it.
  static const stopLine = 'وقفت هنا {ن} مرة. الرصيف حفظ مكانك.';

  /// {ن} its place on the line, {ن2} the line's stops.
  static const stopChip = 'المحطة {ن} من {ن2}';
  static const stopChipTo = ' · إلى {الجامعة}';
  static const linePrefix = 'خط ';

  // ---------------------------------------------------------------- 9 college
  static const collegeKicker = 'كليتك';
  static const collegeHeadline = 'يا {الكلية}';

  /// No family matched: the university speaks.
  static const universityKicker = 'جامعتك';
  static const collegeEntered = 'ودخلت {الجامعة} {ي} مرة. الأمن حفظ شكلك.';

  // ---------------------------------------------------------------- 10 title
  static const titleKicker = 'لقبك الترم ده';
  static const titleCta = 'شوف البوستر';

  // ---------------------------------------------------------------- 11 share
  static const posterHead = 'ملخّص الترم';
  static const posterTitleKicker = 'لقبي الترم ده';
  static const posterPatternLabel = 'ترمي يوم بيوم';

  /// {ي} ridden of {من}.
  static const posterPatternCount = '{ي} يوم من {من}';

  /// The short recap.
  static const posterPatternCountShort = '{ي} يوم';
  static const posterSite = 'Basak.app';
  static const posterSeparator = ' · ';
  static const posterLabel = 'بوستر الملخّص: {اللقب}';

  /// The numbers on the poster: the word under each.
  static const statHours = 'ساعة';
  static const statDays = 'يوم';
  static const statTime = 'معادي';
  static const statReturnTime = 'رجوعي';
  static const statReturns = 'رجوع';
  static const statTimes = 'مواعيد مختلفة';
  static const statRides = 'ركوب';
  static const statBestDay = 'أكتر يوم';
  static const statWeek = 'في الأسبوع';
  static const statShare = 'من جدولي';

  static const share = 'شارك';
  static const save = 'حفظ الصورة';
  static const saved = 'تم حفظ البوستر في الاستوديو.';
  static const saveDenied = 'اسمح للتطبيق بحفظ الصور من إعدادات الهاتف ثم أعد المحاولة.';
  static const saveFailed = 'تعذر حفظ الصورة في الاستوديو. حاول مرة أخرى.';
  static const shareFailed = 'تعذر تجهيز الصورة. حاول مرة أخرى.';

  // ---------------------------------------------------------------- short recap
  /// One to seven rides: cover, this page, the poster.
  static const shortUnit = 'مرة ركبت الباص';
  static const shortUnitFew = 'مرات ركبت الباص';
  static const shortLine = 'في الترم كله. إحنا مش زعلانين… إحنا بس مستغربين.';
  static const shortChip = 'لقبك: {اللقب}';

  // ---------------------------------------------------------------- titles
  /// 66 titles in 16 patterns. `posterWhy` / `pageWhy` placeholders:
  /// {ي} ride days, {من} own days, {ن} the count the habit is about,
  /// {الوقت} the time it is about, {الشهر} the month of the first ride.
  static const titles = <RecapPattern, RecapTitles>{
    // Rides most of their own days (a week of four days or more).
    RecapPattern.regular: RecapTitles(
      titles: ['عمدة\n{المحطة}', 'المحطة باسمي', 'عضوية ذهبية', 'ركن أساسي', 'من أهل الباص', 'الكرسي محجوز'],
      posterWhy: '{ي} يوم على نفس المحطة. المحطة بقت باسمي.',
      pageWhy: 'ركبت {ي} يوم من {من}. أكتر من نص الترم على نفس الرصيف.',
    ),
    // Mostly the first trip of the day. {ن} rides on it.
    RecapPattern.firstTripGoing: RecapTitles(
      titles: ['ديك الفجر', 'قبل الشمس بشوية', 'أول الطابور', 'لجنة فتح البوابة', 'وردية الصبح'],
      posterWhy: '{ن} مرة على أول باص {الوقت}.',
    ),
    // Mostly the last trip going.
    RecapPattern.lastTripGoing: RecapTitles(
      titles: ['على آخر لحظة', '5 دقايق كمان', 'آخر باص الصبح', 'لحقته بالعافية'],
    ),
    // Same time nearly every day. {ن} rides at it.
    RecapPattern.sameTime: RecapTitles(
      titles: ['ساعة سويسرية', 'ع الدقيقة', 'منبّه بشري', 'معاد ثابت'],
      posterWhy: '{ن} مرة على باص {الوقت} بالظبط.',
    ),
    // Many different times. {ن} of them.
    RecapPattern.manyTimes: RecapTitles(
      titles: ['على حسب المزاج', 'مفاجأة اليوم', 'خط سير حر', 'كل يوم بحال'],
      posterWhy: '{ن} مواعيد مختلفة في ترم واحد.',
    ),
    // Mostly the last trip home. {ن} returns on it.
    RecapPattern.lastTripHome: RecapTitles(
      titles: ['آخر باص', 'الكلية بتقفل ورايا', 'وردية المسا', 'أمن المدرج', 'آخر نور في الكلية'],
      posterWhy: '{ن} مرة رجعت على باص {الوقت}.',
    ),
    // Mostly the first trip home.
    RecapPattern.firstTripHome: RecapTitles(
      titles: ['خروج مبكر', 'أول باص راجع', 'محاضرة واحدة وكفاية', 'الغدا في البيت'],
    ),
    // Rarely returns by bus. {ي} going, {ن} returning.
    RecapPattern.rarelyReturns: RecapTitles(
      titles: ['تذكرة ذهاب بس', 'ذهاب بلا عودة', 'رجوع حر', 'الرجوع على الله'],
      posterWhy: '{ي} مرة رايح… و{ن} بس راجع.',
    ),
    // A week of three days or fewer. {ي} ridden of {من}.
    RecapPattern.shortWeek: RecapTitles(
      titles: ['جدول على المقاس', 'دوام 3 أيام', 'ويك إند 4 أيام', 'أسبوع مضغوط'],
      posterWhy: '{الأيام}. {ي} من {من}.',
    ),
    // A long run without a miss.
    RecapPattern.longRun: RecapTitles(
      titles: ['حضور كامل', 'ولا يوم', 'سلسلة دهب', 'مفيش غياب'],
    ),
    // One weekday far above the rest.
    RecapPattern.topWeekday: RecapTitles(
      titles: ['{اليوم} بتاعي', 'بداية نار', 'يوم الحضور الرسمي'],
    ),
    // Thursdays far below the rest.
    RecapPattern.thursdayOff: RecapTitles(
      titles: ['ويك إند طويل', 'الخميس إجازة', 'أسبوع 5 أيام'],
    ),
    // Very many hours on the road.
    RecapPattern.manyHours: RecapTitles(
      titles: ['ساكن في الباص', 'الباص بيتي التاني', 'إقامة كاملة', 'عنواني: {الخط}'],
    ),
    // Subscribed mid-term. {ي} ridden of {من} since the first ride.
    RecapPattern.midTerm: RecapTitles(
      titles: ['نص ترم', 'الموسم التاني', 'وصول متأخر… بس وصول', 'انضمام رسمي'],
      posterWhy: 'اشتركت في {الشهر}، وركبت {ي} يوم من {من}.',
    ),
    // One to seven rides.
    RecapPattern.guest: RecapTitles(
      titles: ['ضيف شرف', 'ظهور خاص', 'زيارة خاطفة', 'كل سنة مرة'],
      posterWhy: '{ي} مرة في الترم كله. شرّفتكم.',
    ),
    // Nothing above matched.
    RecapPattern.fallback: RecapTitles(
      titles: ['عِشرة عُمر', 'من الدفعة', 'ركوب محترم', 'على الخط'],
    ),
  };

  /// A pattern without a line of its own says this under the title.
  static const titleWhyPlain = 'ركبت {ي} يوم من {من}.';

  // ---------------------------------------------------------------- colleges
  /// The account has no college at all.
  static const noCollegeLine = 'ما قلتلناش كليتك، بس الطريق عارفك.';

  /// A line for every specialisation. Departments first, then colleges; the
  /// first row that matches wins. First drafts: to be read aloud by students
  /// from each college before they ship, and each row should grow to three or
  /// four lines.
  static const families = <RecapFamily>[
    // ---- departments (matched on the specialisation the student typed)
    RecapFamily(
      name: 'هندسة مدنية',
      keywords: ['مدنية', 'مدني'],
      call: 'هندسة',
      line: 'عدّيت على نفس الكوبري {ي} مرة. ناقص تستلمه.',
    ),
    RecapFamily(
      name: 'هندسة معمارية',
      keywords: ['معمارية', 'معماري', 'عمارة'],
      call: 'هندسة',
      line: 'السهر للتسليم، والنوم في الباص. توزيع أحمال مظبوط.',
    ),
    RecapFamily(
      name: 'هندسة كهرباء',
      keywords: ['كهرباء', 'كهربية', 'كهربائية'],
      call: 'هندسة',
      line: 'شحن الموبايل وشحن النوم… الاتنين في الباص.',
    ),
    RecapFamily(
      name: 'هندسة ميكانيكا',
      keywords: ['ميكانيكا', 'ميكانيكية', 'ميكانيكي'],
      call: 'هندسة',
      line: 'صوت الموتور بقى أحنّ من صوت المنبّه.',
    ),
    RecapFamily(
      name: 'نظم معلومات',
      keywords: ['نظم معلومات', 'نظم'],
      call: 'حاسبات',
      line: 'السيستم واقع؟ الباص لأ. {ي} يوم uptime.',
    ),
    RecapFamily(
      name: 'ذكاء اصطناعي',
      keywords: ['ذكاء اصطناعي', 'ذكاء'],
      call: 'ذكاء اصطناعي',
      line: 'حتى الـAI ما توقّعش {ي} يوم صحيان بدري.',
    ),
    RecapFamily(
      name: 'محاسبة',
      keywords: ['محاسبة'],
      call: 'تجارة',
      line: 'الأصول: مكان جنب الشباك. الخصوم: المنبّه.',
    ),
    RecapFamily(
      name: 'إدارة أعمال',
      keywords: ['إدارة أعمال', 'إدارة'],
      call: 'تجارة',
      line: '{س} ساعة في الباص. هنكتبها «اجتماعات».',
    ),
    RecapFamily(
      name: 'اقتصاد',
      keywords: ['اقتصاد'],
      call: 'اقتصاد',
      line: 'العرض: كرسي واحد جنب الشباك. الطلب: الباص كله.',
    ),
    RecapFamily(
      name: 'لغة إنجليزية',
      keywords: ['إنجليزية', 'إنجليزي', 'english'],
      call: 'آداب',
      // \u200E keeps the «…» on the English side of the line.
      line: 'To bus or not to bus…\u200E وركبت {ي} مرة.',
    ),
    RecapFamily(
      name: 'تاريخ',
      keywords: ['تاريخ'],
      call: 'آداب',
      line: '{ي} رحلة. المؤرخين هيكتبوا عن الترم ده.',
    ),
    RecapFamily(
      name: 'جغرافيا',
      keywords: ['جغرافيا'],
      call: 'آداب',
      line: 'حافظ الطريق أحسن من الخريطة. {ي} مرة تكفي.',
    ),
    RecapFamily(
      name: 'علم نفس',
      keywords: ['علم نفس'],
      call: 'آداب',
      line: 'بتحلل الناس كلها… إلا اللي بيصحى {ي} يوم بدري بمزاجه.',
    ),
    RecapFamily(
      name: 'كيمياء',
      keywords: ['كيمياء'],
      call: 'علوم',
      line: 'تفاعل المنبّه مع النوم… الناتج دايماً 5 دقايق تأخير.',
    ),
    RecapFamily(
      name: 'فيزياء',
      keywords: ['فيزياء'],
      call: 'علوم',
      line: 'سرعة الباص ثابتة. سرعتك للمحطة هي اللي بتتغيّر.',
    ),
    RecapFamily(
      name: 'رياضيات',
      keywords: ['رياضيات'],
      call: 'علوم',
      line: '{ي} يوم × رحلتين. دي المسألة الوحيدة اللي اتحلّت.',
    ),

    // ---- colleges (more specific names first)
    RecapFamily(
      name: 'هندسة',
      keywords: ['هندسة'],
      call: 'هندسة',
      line: '{س} ساعة في الباص، ولسه الشيت ما اتحلّش.',
      hoursTail: 'ولسه الشيت ما اتحلّش.',
      // {ن} = hours ÷ 3.
      boxTitle: '{س} ساعة = {ن} محاضرة استاتيكا',
      boxBody: 'اختار اللي يوجع أقل.',
    ),
    RecapFamily(
      name: 'حاسبات ومعلومات',
      keywords: ['حاسبات', 'حاسب', 'حاسوب', 'كمبيوتر'],
      call: 'حاسبات',
      line: 'الكود ما اشتغلش، بس الباص كان بييجي. حاجة واحدة شغالة.',
    ),
    RecapFamily(
      name: 'طب أسنان',
      keywords: ['أسنان'],
      call: 'أسنان',
      line: '{ي} يوم ركوب، ولسه الناس بتقول: «بص على ضرسي كده».',
    ),
    RecapFamily(
      name: 'طب بيطري',
      keywords: ['بيطري'],
      call: 'بيطري',
      line: 'قطة الكلية حفظت مواعيدك من كتر ما بتيجي.',
    ),
    RecapFamily(
      name: 'علاج طبيعي',
      keywords: ['علاج طبيعي'],
      call: 'علاج طبيعي',
      line: '{س} ساعة قعدة في الباص. ضهرك محتاج حد من دفعتك.',
    ),
    RecapFamily(
      name: 'صيدلة',
      keywords: ['صيدلة'],
      call: 'صيدلة',
      line: 'جرعة الطريق: رحلتين في اليوم. الأعراض الجانبية: نوم مفاجئ.',
    ),
    RecapFamily(
      name: 'تمريض',
      keywords: ['تمريض'],
      call: 'تمريض',
      line: 'الشيفت بيبدأ من المحطة، مش من المستشفى.',
    ),
    RecapFamily(
      name: 'طب بشري',
      keywords: ['طب'],
      call: 'طب',
      line: 'الباص وصل {ي} مرة. التخرّج لسه في الطريق.',
    ),
    RecapFamily(
      name: 'تجارة',
      keywords: ['تجارة'],
      call: 'تجارة',
      line: '{س} ساعة. خلّيها في بند المصروفات وخلاص.',
    ),
    RecapFamily(
      name: 'حقوق',
      keywords: ['حقوق'],
      call: 'حقوق',
      line: 'المتهم: المنبّه. الحكم: براءة لعدم كفاية الأدلة.',
    ),
    RecapFamily(
      name: 'آداب',
      keywords: ['آداب'],
      call: 'آداب',
      line: '{ي} فصل في رواية اسمها «الطريق». البطل: حضرتك.',
    ),
    RecapFamily(
      name: 'إعلام',
      keywords: ['إعلام'],
      call: 'إعلام',
      line: 'عاجل: شاهد عيان يؤكد ركوبك {ي} يوم. والتفاصيل بعد الفاصل.',
    ),
    RecapFamily(
      name: 'ألسن ولغات',
      keywords: ['ألسن', 'لغات'],
      call: 'ألسن',
      line: 'كام لغة… و«صباح الخير» بتطلع بالعافية الساعة 7.',
    ),
    RecapFamily(
      name: 'رياض أطفال',
      keywords: ['رياض أطفال', 'طفولة'],
      call: 'رياض أطفال',
      line: 'صبر على الأطفال… وعنف مع المنبّه.',
    ),
    RecapFamily(
      name: 'تربية رياضية',
      keywords: ['تربية رياضية', 'رياضية'],
      call: 'تربية رياضية',
      line: 'جري للمحطة {ي} مرة. ده التمرين اللي بجد.',
    ),
    RecapFamily(
      name: 'تربية',
      keywords: ['تربية'],
      call: 'تربية',
      line: '{ي} يوم حضور. لو الباص بيدّي أعمال سنة كنت قفّلت.',
    ),
    RecapFamily(
      name: 'علوم',
      keywords: ['علوم'],
      call: 'علوم',
      line: 'التجربة: طالب + منبّه + باص. النتيجة: {ي} مرة نجاح.',
    ),
    RecapFamily(
      name: 'زراعة',
      keywords: ['زراعة'],
      call: 'زراعة',
      line: 'زرعت {ي} يوم في الباص. الحصاد آخر الترم.',
    ),
    RecapFamily(
      name: 'فنون',
      keywords: ['فنون'],
      call: 'فنون',
      line: '{ي} لوحة لنفس الطريق من نفس الشباك. المعرض جاهز.',
    ),
    RecapFamily(
      name: 'سياحة وفنادق',
      keywords: ['سياحة', 'فنادق'],
      call: 'سياحة وفنادق',
      line: '{ي} رحلة على نفس الخط. الخط ده محتاجك مرشد.',
    ),
    RecapFamily(
      name: 'آثار',
      keywords: ['آثار'],
      call: 'آثار',
      line: '{ي} رحلة على نفس الطريق. كمان كام سنة يبقى أثر.',
    ),
    RecapFamily(
      name: 'خدمة اجتماعية',
      keywords: ['خدمة اجتماعية'],
      call: 'خدمة اجتماعية',
      line: 'بتساعد الكل يلاقي كرسي… والكرسي بتاعك راح.',
    ),
  ];
}
