// The term recap's engine: what it measures, which pages it shows and what
// each one says, for the students on the recap boards and for thin data.
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/features/auth/data/colleges.dart';
import 'package:basak_mobile/features/student/recap/recap_copy.dart';
import 'package:basak_mobile/features/student/recap/recap_engine.dart';

import 'support/recap_fixtures.dart';

List<RecapPageKind> kinds(TermRecap r) => [for (final p in r.pages) p.kind];
RecapPage page(TermRecap r, RecapPageKind kind) => r.pages.firstWhere((p) => p.kind == kind);

void main() {
  group('the copy bank', () {
    test('66 titles in 16 patterns, 38 specialisations and the fallback', () {
      expect(RecapCopy.titles.keys.toSet(), RecapPattern.values.toSet());
      expect(RecapCopy.titles.values.fold<int>(0, (n, t) => n + t.titles.length), 66);
      expect(RecapCopy.families, hasLength(38));
      expect(RecapCopy.noCollegeLine, isNotEmpty);
    });

    test('every college of the sign-up sheet has a line of its own', () {
      for (final college in kColleges) {
        expect(recapFamilyFor(college: college), isNotNull, reason: college);
      }
      String? name(String? college, [String? specialisation]) =>
          recapFamilyFor(college: college, specialisation: specialisation)?.name;
      expect(name('الطب'), 'طب بشري');
      expect(name('طب الأسنان'), 'طب أسنان');
      expect(name('الطب البيطري'), 'طب بيطري');
      expect(name('العلاج الطبيعي'), 'علاج طبيعي');
      expect(name('الحاسبات والمعلومات'), 'حاسبات ومعلومات', reason: '«معلومات» holds «علوم» but is another word');
      expect(name('العلوم'), 'علوم');
      expect(name('التربية الرياضية'), 'تربية رياضية');
      expect(name('رياض الأطفال'), 'رياض أطفال');
      expect(name('التربية'), 'تربية');
      expect(name('الألسن'), 'ألسن ولغات');
      expect(name('كلية الهندسة بدمياط'), 'هندسة');
      // The department speaks before the college.
      expect(name('الهندسة', 'هندسة مدنية'), 'هندسة مدنية');
      expect(name('التجارة', 'المحاسبة'), 'محاسبة');
      expect(name('العلوم', 'فيزياء'), 'فيزياء');
      expect(name('الآداب', 'علم النفس'), 'علم نفس');
      expect(name('الحاسبات والمعلومات', 'نظم المعلومات'), 'نظم معلومات');
      // Nothing to say is not a wrong guess.
      expect(name('الدراسات الإسلامية'), isNull);
      expect(name(null), isNull);
      expect(name('الهندسة', 'قسم لا نعرفه'), 'هندسة');
    });
  });

  group('numbers never break the sentence', () {
    test('one, two, three to ten, eleven and more', () {
      expect([1, 2, 3, 10, 11, 62].map((n) => recapCount(n, 'يوم')),
          ['يوم واحد', 'يومين', '3 أيام', '10 أيام', '11 يوم', '62 يوم']);
      expect([1, 2, 7, 109].map((n) => recapCount(n, 'ساعة')), ['ساعة واحدة', 'ساعتين', '7 ساعات', '109 ساعة']);
      expect([1, 2, 6, 41].map((n) => recapCount(n, 'مرة')), ['مرة واحدة', 'مرتين', '6 مرات', '41 مرة']);
    });

    test('a count takes its noun\'s form inside a sentence', () {
      expect(recapFill('عدّيت على نفس الكوبري {ي} مرة. ناقص تستلمه.', {'ي': 9}),
          'عدّيت على نفس الكوبري 9 مرات. ناقص تستلمه.');
      expect(recapFill('{ي} يوم × رحلتين.', {'ي': 2}), 'يومين × رحلتين.');
      expect(recapFill('{س} ساعة = {ن} محاضرة استاتيكا', {'س': 109, 'ن': 36}), '109 ساعة = 36 محاضرة استاتيكا');
      expect(recapFill('{ي} يوم من {من}', {'ي': 62, 'من': 101}), '62 يوم من 101');
      expect(recapFill('يا {الكلية}', {'الكلية': 'هندسة'}), 'يا هندسة');
    });

    test('a sentence whose number is unknown is left out', () {
      expect(recapFill('{س} ساعة في الباص، ولسه الشيت ما اتحلّش.', {'س': null, 'ي': 12}), isNull);
      expect(recapFill('', {}), isNull);
    });

    test('the draw is fixed', () {
      expect(recapDraw('student-1|regular', 6), recapDraw('student-1|regular', 6));
      expect({for (var i = 0; i < 60; i++) recapDraw('student-$i|regular', 6)}, hasLength(6));
    });
  });

  group('the nine students on the board', () {
    test('Sara, the regular: every page of row 08', () {
      final r = recapOf(sara(), key: keyDrawing('regular', 0, 6))!;
      expect((r.rideDays, r.ownTotal, r.ownRidden, r.extraRides), (62, 101, 62, 0));
      expect(r.ownWeek, isFalse);
      expect(r.tier, RecapTier.regular);
      expect([for (final b in r.bars) b.count], [9, 13, 12, 11, 10, 7]);
      expect([for (final b in r.bars) b.strong], [false, true, false, false, false, false]);
      expect((r.longestRun, r.longestGap, r.gapInTheMiddle), (14, 9, true));
      expect((r.favouriteTime, r.favouriteTimeRides, r.returnDays, r.hours), ('07:23', 41, 55, 109));
      expect(r.pattern, RecapPattern.regular);
      expect(r.title, 'عمدة\nكوبري السرو');

      expect(kinds(r), [
        RecapPageKind.cover, RecapPageKind.hours, RecapPageKind.days, RecapPageKind.shape, RecapPageKind.run,
        RecapPageKind.time, RecapPageKind.back, RecapPageKind.stop, RecapPageKind.college, RecapPageKind.title,
        RecapPageKind.share,
      ]);
      final cover = page(r, RecapPageKind.cover);
      expect((cover.kicker, r.yearsLong, cover.headline), ('الفصل الأول', '2026 / 2027', 'ترمك\nفي الباص'));
      expect(cover.lines, ['109 ساعة، 62 يوم، ومعاد واحد ما بتغيّروش.']);
      expect(cover.cta, 'يلا نشوف');

      final hours = page(r, RecapPageKind.hours);
      expect((hours.kicker, hours.numeral, hours.unit), ('وقتك على الطريق', '109', 'ساعة في الباص'));
      expect(hours.lines, ['يعني 4 أيام ونص من عمرك جنب الشباك.', 'ولسه الشيت ما اتحلّش.']);
      expect(hours.footnote, 'رقم تقريبي، من مواعيد الرحلات اللي أكّدتها.');

      final days = page(r, RecapPageKind.days);
      expect((days.kicker, days.numeral, days.unit), ('الحضور', '62', 'يوم ركبت الباص'));
      expect(days.lines, ['الأحد يومك. والخميس؟ واضح إن عندك ظروف.']);

      expect(page(r, RecapPageKind.shape).lines, ['كل نقطة يوم في الباص. والفراغ اللي في النص؟ ميدتيرم… مصدّقينك.']);
      expect(r.weeks, hasLength(17));
      expect(r.weeks.first.cells.first, RecapCell.none, reason: 'the Saturday before the term began');
      expect([for (final w in r.weeks) if (w.month != null) w.month], ['سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر', 'يناير']);
      expect(r.weeks.expand((w) => w.cells).where((c) => c == RecapCell.on), hasLength(62));
      expect(r.weeks.expand((w) => w.cells).where((c) => c != RecapCell.none), hasLength(101));

      final run = page(r, RecapPageKind.run);
      expect((run.kicker, run.numeral, run.unit), ('من غير غياب', '14', 'يوم ورا بعض'));
      expect(run.lines, ['حتى المنبّه اتفاجئ.']);
      expect(run.chip, 'أطول غيبة: 9 أيام · كنا هنسأل عليك');

      final time = page(r, RecapPageKind.time);
      expect((time.kicker, time.numeral, time.numeralSuffix, time.unit), ('معادك', '7:23', 'ص', 'ركبته 41 مرة'));
      expect(time.lines, ['الباص بقى عارفك.', 'وصحيت بدري 3 مرات بس ولحقت 6:38. تتحسب لك.']);

      final back = page(r, RecapPageKind.back);
      expect((back.kicker, back.numeral, back.unit), ('الرجوع', '55', 'مرة رجعت بالباص'));
      expect(back.lines, ['و7 مرات قلت «هرجع لوحدي». رجعت إزاي؟ ما نعرفش، وما بنسألش.']);
      expect(back.chip, 'معاد رجوعك المفضّل: 3:30 م');

      final stop = page(r, RecapPageKind.stop);
      expect((stop.kicker, stop.headline), ('محطتك على خط الزرقا', 'كوبري السرو'));
      expect(r.stopsBefore, ['موقف الزرقا', 'ميت الخولي', 'شرباص']);
      expect(r.stopsAfter, ['السرو', 'الروضة', 'فارسكور']);
      expect(stop.lines, ['وقفت هنا 62 مرة. الرصيف حفظ مكانك.']);
      expect(stop.chip, 'المحطة 4 من 7 · إلى جامعة المنصورة الجديدة');

      final college = page(r, RecapPageKind.college);
      expect((college.kicker, college.headline), ('كليتك', 'يا هندسة'));
      expect((college.boxTitle, college.boxBody), ('109 ساعة = 36 محاضرة استاتيكا', 'اختار اللي يوجع أقل.'));
      expect(college.lines, ['ودخلت جامعة المنصورة الجديدة 62 مرة. الأمن حفظ شكلك.']);

      final title = page(r, RecapPageKind.title);
      expect((title.kicker, title.headline, title.cta), ('لقبك الترم ده', 'عمدة\nكوبري السرو', 'شوف البوستر'));
      expect(title.lines, ['ركبت 62 يوم من 101. أكتر من نص الترم على نفس الرصيف.']);

      expect(r.titleWhy, '62 يوم على نفس المحطة. المحطة بقت باسمي.');
      expect(r.line, '109 ساعة في الباص، ولسه الشيت ما اتحلّش.');
      expect(r.patternCount, '62 يوم من 101');
      expect([for (final s in r.stats) (s.value, s.label)], [('109', 'ساعة'), ('62', 'يوم'), ('7:23 ص', 'معادي')]);
      expect(r.signature, 'سارة · خط الزرقا', reason: 'first name and line only');
      expect(r.yearsShort, '2026/27');
      expect(r.bannerLine, '109 ساعة في الباص… والباقي جوّه.');
    });

    test('the same student always draws the same title; friends rarely share it', () {
      final titles = {for (var i = 0; i < 40; i++) recapOf(sara(), key: 'student-$i')!.title};
      expect(titles, hasLength(6));
      expect(titles, contains('المحطة باسمي'));
      expect(recapOf(sara(), key: 'a')!.title, recapOf(sara(), key: 'a')!.title);
      expect({for (var i = 0; i < 40; i++) recapOf(sara(), key: 'student-$i')!.theme}, {0, 1, 2, 3, 4});
    });

    test('Yousef, the early riser', () {
      final r = recapOf(yousef())!;
      expect((r.rideDays, r.ownTotal), (71, 96));
      expect(r.pattern, RecapPattern.firstTripGoing, reason: 'rarer than riding most days, which also fits');
      expect(RecapCopy.titles[RecapPattern.firstTripGoing]!.titles, contains(r.title));
      expect(r.titleWhy, '58 مرة على أول باص 6:15.');
      expect(r.line, 'الباص وصل 71 مرة. التخرّج لسه في الطريق.');
      expect(r.patternCount, '71 يوم من 96');
      expect(r.stats.last.value, '6:15 ص');
    });

    test('Nada, last one home', () {
      final r = recapOf(nada())!;
      expect((r.rideDays, r.ownTotal, r.tier), (52, 98, RecapTier.standard));
      expect(r.pattern, RecapPattern.lastTripHome);
      expect(r.titleWhy, '38 مرة رجعت على باص 5:30.');
      expect(r.line, 'الكود ما اشتغلش، بس الباص كان بييجي. حاجة واحدة شغالة.');
      expect((r.stats.last.value, r.stats.last.label), ('5:30 م', 'رجوعي'));
      expect(r.signature, 'ندى · خط دمياط الجديدة');
    });

    test('Karim, one way only', () {
      final r = recapOf(karim())!;
      expect((r.rideDays, r.ownTotal, r.returnDays), (44, 99, 6));
      expect(r.pattern, RecapPattern.rarelyReturns);
      expect(r.titleWhy, '44 مرة رايح… و6 بس راجع.');
      expect(r.line, 'الأصول: مكان جنب الشباك. الخصوم: المنبّه.');
      expect((r.stats.last.value, r.stats.last.label), ('6 مرات', 'رجوع'));
      final back = page(r, RecapPageKind.back);
      expect((back.numeral, back.unit), ('6', 'مرات رجعت بالباص'));
      expect(back.lines, ['44 مرة رايح… و6 بس راجع.']);
    });

    test('Menna, never the same time', () {
      final r = recapOf(menna())!;
      expect((r.rideDays, r.ownTotal, r.distinctTimes), (39, 97, 5));
      expect(r.pattern, RecapPattern.manyTimes);
      expect(r.titleWhy, '5 مواعيد مختلفة في ترم واحد.');
      expect(r.line!.replaceAll('\u200E', ''), 'To bus or not to bus… وركبت 39 مرة.');
      expect((r.stats.last.value, r.stats.last.label), ('5', 'مواعيد مختلفة'));
    });

    test('Omar, a handful of rides: the short recap', () {
      final r = recapOf(omar())!;
      expect((r.rideDays, r.tier, r.pattern), (6, RecapTier.short, RecapPattern.guest));
      expect(kinds(r), [RecapPageKind.cover, RecapPageKind.short, RecapPageKind.share]);
      expect(page(r, RecapPageKind.cover).lines, isEmpty);
      final short = page(r, RecapPageKind.short);
      expect((short.kicker, short.numeral, short.unit), ('الفصل الأول', '6', 'مرات ركبت الباص'));
      expect(short.lines, [
        'في الترم كله. إحنا مش زعلانين… إحنا بس مستغربين.',
        'المتهم: المنبّه. الحكم: براءة لعدم كفاية الأدلة.',
      ]);
      expect(short.chip, 'لقبك: ${r.title}');
      expect(RecapCopy.titles[RecapPattern.guest]!.titles, contains(r.title));
      expect(r.titleWhy, '6 مرات في الترم كله. شرّفتكم.');
      expect(r.patternCount, '6 أيام');
      expect([for (final s in r.stats) (s.value, s.label)], [('6 مرات', 'ركوب'), ('الأحد', 'أكتر يوم')]);
    });

    test('Mariam, three days a week: 41 of 45 is 91%, not half the term', () {
      final r = recapOf(mariam())!;
      expect(r.ownWeekdays, {7, 2, 4});
      expect((r.ownWeek, r.rideDays, r.ownTotal, r.ownRidden, r.attendancePercent), (true, 41, 45, 41, 91));
      expect(r.tier, RecapTier.regular);
      expect(r.pattern, RecapPattern.shortWeek, reason: '«عمدة» needs a week of four days');
      expect(RecapCopy.titles[RecapPattern.shortWeek]!.titles, contains(r.title));
      expect(r.titleWhy, 'الأحد والثلاثاء والخميس. 41 من 45.');
      expect(r.line, 'جرعة الطريق: رحلتين في اليوم. الأعراض الجانبية: نوم مفاجئ.');
      expect(r.patternCount, '41 يوم من 45');
      expect([for (final s in r.stats) (s.value, s.label)],
          [('41', 'يوم'), ('3 أيام', 'في الأسبوع'), ('91%', 'من جدولي')]);

      // The days page of board RecapDays3.
      final days = page(r, RecapPageKind.days);
      expect((days.kicker, days.numeral, days.unit), ('جدولك', '41', 'يوم ركبت الباص'));
      expect(days.lines, [
        '3 أيام في الأسبوع؟ ده جدول يتحسد عليه.',
        'وحضرت 41 من 45 في أيامك. الباقي إجازة رسمي، مش غياب.',
      ]);
      expect([for (final b in r.bars) b.own ? b.count : null], [null, 14, null, 14, null, 13]);
      expect([for (final b in r.bars) b.strong], [false, true, false, true, false, true]);
      // A day off is not an absence: runs are counted in her days.
      expect(r.longestRun, greaterThanOrEqualTo(9));
      expect(r.longestGap, 1);
      // Only her days carry a dot.
      expect(r.weeks.expand((w) => w.cells).where((c) => c != RecapCell.none), hasLength(45));
    });

    test('Ahmed, subscribed mid-term: counted from the first ride', () {
      final r = recapOf(ahmed())!;
      expect((r.rideDays, r.ownTotal, r.attendancePercent), (31, 36, 86));
      expect(r.pattern, RecapPattern.midTerm);
      expect(r.titleWhy, 'اشتركت في نوفمبر، وركبت 31 يوم من 36.');
      expect(r.line, 'سرعة الباص ثابتة. سرعتك للمحطة هي اللي بتتغيّر.');
      expect(r.patternCount, '31 يوم من 36');
      expect(r.weeks, hasLength(17), reason: 'the whole term is drawn; the weeks before the first ride stay empty');
    });

    test('Hadeer, same time every time', () {
      final r = recapOf(hadeer())!;
      expect((r.rideDays, r.ownTotal, r.favouriteTimeRides), (49, 94, 47));
      expect(r.pattern, RecapPattern.sameTime);
      expect(r.titleWhy, '47 مرة على باص 7:45 بالظبط.');
      expect(r.line, '49 يوم حضور. لو الباص بيدّي أعمال سنة كنت قفّلت.');
      expect(r.signature, 'هدير · خط دمياط الجديدة', reason: 'a line stored with its «خط» is not given a second one');
    });
  });

  group('thin and odd data', () {
    test('no rides: no recap, and so no banner', () {
      expect(recapOf(recapJson(rides: const [])), isNull);
    });

    test('1 to 7 rides is the short recap, 8 is a full one', () {
      final days = studyDays();
      for (final n in [1, 2, 7]) {
        final r = recapOf(recapJson(rides: days.sublist(0, n)))!;
        expect(kinds(r), [RecapPageKind.cover, RecapPageKind.short, RecapPageKind.share], reason: '$n rides');
        expect(r.pattern, RecapPattern.guest);
      }
      expect(page(recapOf(recapJson(rides: days.sublist(0, 1)))!, RecapPageKind.short).unit, 'مرة ركبت الباص');
      expect(recapOf(recapJson(rides: days.sublist(0, 1)))!.stats.first.value, 'مرة واحدة');
      final eight = recapOf(recapJson(rides: pick(days, 13, {0})))!;
      expect((eight.rideDays, eight.tier), (8, RecapTier.light));
      expect(kinds(eight), containsAll([RecapPageKind.days, RecapPageKind.shape, RecapPageKind.title]));
      expect(page(eight, RecapPageKind.days).unit, 'أيام ركبت الباص');
      expect(page(eight, RecapPageKind.days).lines.last, 'الباص كان بيسأل عليك.');
      expect(kinds(eight), isNot(contains(RecapPageKind.run)), reason: 'no run of four days');
    });

    test('never returned by bus: «تذكرة ذهاب بس», and no zero shown as a failure', () {
      final r = recapOf(recapJson(rides: pick(studyDays(), 5, {0, 2}), returning: (i) => null))!;
      expect(r.returnDays, 0);
      final back = page(r, RecapPageKind.back);
      expect((back.numeral, back.headline, back.chip), (null, 'تذكرة ذهاب بس', null));
      expect(back.lines, ['رجعت إزاي؟ ما نعرفش، وما بنسألش.']);
      expect(r.pattern, RecapPattern.rarelyReturns);
      expect(r.titleWhy, 'ركبت 41 يوم من 101.', reason: 'not «و0 بس راجع»');
      expect([for (final s in r.stats) s.label], isNot(contains('رجوع')));
    });

    test('always returned: nothing is said about the days they did not', () {
      final r = recapOf(recapJson(rides: pick(studyDays(), 2, {0})))!;
      expect(page(r, RecapPageKind.back).lines, isEmpty);
      expect(page(r, RecapPageKind.back).chip, 'معاد رجوعك المفضّل: 3:30 م');
    });

    test('one time all term', () {
      final r = recapOf(recapJson(rides: pick(studyDays(), 2, {0})))!;
      final time = page(r, RecapPageKind.time);
      expect(time.kicker, 'معاد واحد طول الترم');
      expect(time.lines, ['الباص بقى عارفك.']);
    });

    test('no trip length: the hours page and every hours line drop out', () {
      final json = sara()..['trip_length'] = {'departure_minutes': null, 'return_minutes': null};
      final r = recapOf(json, key: keyDrawing('regular', 0, 6))!;
      expect(r.hours, isNull);
      expect(kinds(r), isNot(contains(RecapPageKind.hours)));
      expect(kinds(r), hasLength(10));
      expect(page(r, RecapPageKind.cover).lines, ['62 يوم، ومعاد واحد ما بتغيّروش.']);
      expect(r.line, isNull, reason: 'engineering\'s line is about hours');
      expect(page(r, RecapPageKind.college).boxTitle, isNull);
      expect([for (final s in r.stats) s.label], ['يوم', 'معادي']);
      expect(r.bannerLine, '62 يوم في الباص… والباقي جوّه.');
      for (final p in r.pages) {
        expect([p.unit, p.boxTitle, ...p.lines].whereType<String>().where((s) => s.contains('ساعة')), isEmpty);
      }
    });

    test('a ride\'s own trip length is used before the stop\'s average; the way back mirrors it', () {
      final days = pick(studyDays(), 2, {0}).sublist(0, 20);
      final r = recapOf(recapJson(rides: days, tripMinutes: 30, rideMinutes: (i) => i < 10 ? 60 : null))!;
      // 10 rides of 60 and 10 of 30, each there and back.
      expect(r.hours, 30);
      final oneWay = recapOf(recapJson(rides: days, tripMinutes: 30, returning: (i) => null))!;
      expect(oneWay.hours, 10);
      final unknown = recapOf(recapJson(rides: days, tripMinutes: null, rideMinutes: (i) => i == 0 ? 45 : null))!;
      expect(unknown.hours, 2);
      expect(kinds(unknown), isNot(contains(RecapPageKind.hours)), reason: 'under three hours known: nothing is said');
      expect(unknown.bannerLine, '20 يوم في الباص… والباقي جوّه.');
    });

    test('the hours comparison follows the range', () {
      String? compared(int minutes, int rides) {
        final r = recapOf(recapJson(
            rides: pick(studyDays(), 1, {0}).sublist(0, rides), tripMinutes: minutes, returning: (i) => null))!;
        return page(r, RecapPageKind.hours).lines.first;
      }

      expect(compared(30, 16), 'يعني فيلمين وخلاص.'); // 8 h
      expect(compared(60, 20), 'يعني يوم كامل… من غير نوم.'); // 20 h
      expect(compared(60, 36), 'يعني يوم ونص من عمرك على الطريق.'); // 36 h
      expect(compared(60, 48), 'يعني يومين من عمرك على الطريق.'); // 48 h
      expect(compared(60, 96), 'يعني 4 أيام من عمرك جنب الشباك.'); // 96 h
      expect(compared(120, 80), 'ده مش باص، ده سكن.'); // 160 h
    });

    test('ties: the earlier day and the earlier time, never "the only"', () {
      // Every Sunday and every Monday: the same count.
      final days = studyDays(weekdays: {7, 1});
      final r = recapOf(recapJson(rides: days, departure: (i) => i.isEven ? '08:10' : '07:23'))!;
      expect(r.weekdayCounts[7], r.weekdayCounts[1]);
      expect(r.bestWeekday, 7);
      expect(r.weakestWeekday, isNull, reason: 'no day is well below the best');
      expect(r.favouriteTime, '07:23');
      for (final p in r.pages) {
        expect(p.lines.join(' '), isNot(contains('الوحيد')));
      }
    });

    test('no college: the university speaks, and nothing looks missing', () {
      final r = recapOf(sara()..['student'] = {'full_name': 'سارة أحمد', 'university': 'جامعة المنصورة الجديدة'})!;
      expect(r.family, isNull);
      expect(r.line, 'ما قلتلناش كليتك، بس الطريق عارفك.');
      final college = page(r, RecapPageKind.college);
      expect((college.kicker, college.headline), ('جامعتك', 'جامعة المنصورة الجديدة'));
      expect(college.boxTitle, 'ما قلتلناش كليتك، بس الطريق عارفك.');
      expect(page(r, RecapPageKind.hours).lines, ['يعني 4 أيام ونص من عمرك جنب الشباك.']);
      expect(r.data.firstName, 'سارة');
    });

    test('a college without a line: no wrong guess, on the page or the poster', () {
      final json = sara();
      (json['student'] as Map)['college'] = 'الدراسات الإسلامية';
      final r = recapOf(json)!;
      expect(r.line, isNull);
      expect(page(r, RecapPageKind.college).kicker, 'جامعتك');
      expect(page(r, RecapPageKind.college).boxTitle, isNull);
    });

    test('changed stop: the most used one, said as «أكتر محطة»', () {
      final r = recapOf(recapJson(rides: pick(studyDays(), 2, {0}), stopsUsed: 2))!;
      expect(page(r, RecapPageKind.stop).kicker, 'أكتر محطة على خط الزرقا');
    });

    test('a long line draws three stops on each side of theirs', () {
      final stations = [for (var i = 1; i <= 20; i++) 'محطة $i'];
      final r = recapOf(recapJson(rides: pick(studyDays(), 2, {0}), stations: stations, stop: 'محطة 2'))!;
      expect(r.stopsBefore, ['محطة 1']);
      expect(r.stopsAfter, ['محطة 3', 'محطة 4', 'محطة 5']);
      expect(page(r, RecapPageKind.stop).chip, startsWith('المحطة 2 من 20'));
    });

    test('a ride outside their days is a bonus, not a broken pattern', () {
      final json = mariam();
      final extra = [DateTime.utc(2026, 11, 2), DateTime.utc(2026, 12, 9)]; // a Monday, a Wednesday
      final base = RecapData.tryParse(json)!;
      final rides = [...base.rides.map((r) => r.date), ...extra]..sort();
      final r = recapOf(recapJson(
          name: 'مريم حسن', college: 'الصيدلة', rides: rides, holidays: base.offDates.toList()))!;
      expect(r.ownWeekdays, {7, 2, 4});
      expect((r.rideDays, r.ownRidden, r.ownTotal, r.extraRides), (43, 41, 45, 2));
      expect(page(r, RecapPageKind.days).lines.last, 'ويومين زيادة من عندك.');
      expect(r.longestGap, 1);
    });

    test('scattered rides do not make a one-day week', () {
      // Eight Sundays in a row, then a little of everything.
      final days = studyDays();
      final rides = {...studyDays(weekdays: {7}).take(6), ...pick(days, 13, {1})}.toList()..sort();
      final r = recapOf(recapJson(rides: rides))!;
      expect(r.ownWeek, isFalse, reason: 'their "own day" holds under two thirds of their rides');
      expect(r.tier, RecapTier.light);
    });

    test('an answer that is not a recap is not read', () {
      expect(RecapData.tryParse(null), isNull);
      expect(RecapData.tryParse('nope'), isNull);
      expect(RecapData.tryParse({'student': {}}), isNull);
      final bare = RecapData.tryParse({
        'rides': [
          {'date': '2026-10-04', 'returns_by_bus': true},
          {'date': 'x'},
          'junk',
        ],
      })!;
      expect(bare.rides, hasLength(1));
      final r = TermRecap.build(bare, studentKey: 's')!;
      expect(kinds(r), [RecapPageKind.cover, RecapPageKind.short, RecapPageKind.share]);
      expect(r.title, isNotEmpty);
      expect(r.signature, '');
    });
  });

  group('when Home shows the banner', () {
    test('from two weeks before the term ends to four weeks after', () {
      final end = DateTime.utc(2027, 1, 14);
      expect(recapWindowOpen(DateTime.utc(2026, 12, 30), end), isFalse);
      expect(recapWindowOpen(DateTime.utc(2026, 12, 31), end), isTrue);
      expect(recapWindowOpen(DateTime(2027, 1, 14, 23, 30), end), isTrue);
      expect(recapWindowOpen(DateTime.utc(2027, 2, 11), end), isTrue);
      expect(recapWindowOpen(DateTime.utc(2027, 2, 12), end), isFalse);
      expect(recapWindowOpen(DateTime.utc(2027, 1, 1), null), isFalse);
    });

    test('the recap answers by the server\'s day', () {
      expect(recapOf(sara())!.bannerOpen(), isTrue);
      expect(recapOf(ahmed())!.bannerOpen(), isFalse, reason: 'the 12th of December is too early');
    });
  });
}
