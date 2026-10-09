// One golden per design-system component (lib/core/ui), at 360 and 390 wide
// and at text scale 1.0 and 1.3, drawn with the app's real fonts.
//
// Goldens depend on the machine that drew them. `goldens/PLATFORM` records the
// OS they were made on; on any other OS the pictures are still built (so an
// overflow or an exception still fails) but not compared.
//   flutter test test/ui/components_golden_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/core/widgets/floating_glass_nav_bar.dart';
import 'package:basak_mobile/core/widgets/skeleton.dart';

const _widths = [360.0, 390.0];
const _scales = [1.0, 1.3];
final _platformFile = File('test/ui/goldens/PLATFORM');
final _shot = GlobalKey();

Future<void> _fonts() async {
  Future<ByteData> file(String name) async =>
      ByteData.view((await File('assets/fonts/$name').readAsBytes()).buffer);
  final readex = FontLoader('ReadexPro');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    readex.addFont(file('ReadexPro-$f.ttf'));
  }
  await readex.load();
  await (FontLoader('Lucide')..addFont(file('lucide.ttf'))).load();
}

class _Scene {
  final String name;
  final Widget Function(BuildContext context) build;

  /// The surface behind the component: the ground unless it lives on ink.
  final Color? background;

  /// Full-bleed: no padding around it, and this exact height (a whole page).
  final double? pageHeight;

  /// Holds something that never stops moving (a spinner, the skeleton's
  /// pulse): drawn at a fixed instant instead of waiting for it to settle.
  final bool animates;

  const _Scene(this.name, this.build, {this.background, this.pageHeight, this.animates = false});
}

Widget _gap([double height = BasakSpace.s12]) => SizedBox(height: height);

Widget _column(List<Widget> children) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) _gap(), children[i]],
      ],
    );

PassCard _pass(BasakStatus status, {String period = 'الفصل الأول', Widget? footer, String toCaption = 'خط الزرقا · النورس للنقل'}) =>
    PassCard(
      status: status,
      period: period,
      onPeriodTap: status == BasakStatus.active ? () {} : null,
      from: 'كوبري السرو',
      to: 'المنصورة الجديدة',
      toCaption: toCaption,
      footer: footer,
    );

final _scenes = <_Scene>[
  _Scene(
    'button',
    (context) => _column([
      BasakButton(label: 'متابعة للدفع', onPressed: () {}),
      BasakButton(label: 'لن أركب', onPressed: () {}, variant: BasakButtonVariant.secondary),
      BasakButton(label: 'اشترك في الفصل الثاني', onPressed: () {}, variant: BasakButtonVariant.tonal),
      const BasakButton(label: 'إرسال للمراجعة', onPressed: null),
      BasakButton(label: 'إرسال للمراجعة', onPressed: () {}, loading: true),
      Row(children: [
        Expanded(flex: 3, child: BasakButton(label: 'نعم، سأركب', onPressed: () {}, size: BasakButtonSize.medium)),
        const SizedBox(width: BasakSpace.s10),
        Expanded(
          flex: 2,
          child: BasakButton(
              label: 'لن أركب',
              onPressed: () {},
              size: BasakButtonSize.medium,
              variant: BasakButtonVariant.secondary),
        ),
      ]),
      Wrap(spacing: BasakSpace.s8, runSpacing: BasakSpace.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        BasakButton(
            label: 'تنزيل PDF',
            icon: LucideIcons.download,
            onPressed: () {},
            variant: BasakButtonVariant.surface,
            size: BasakButtonSize.small,
            expand: false),
        BasakButton(
            label: 'تغيير', onPressed: () {}, variant: BasakButtonVariant.quiet, size: BasakButtonSize.small, expand: false),
        BasakButton(
            label: 'حذف الحساب',
            onPressed: () {},
            variant: BasakButtonVariant.danger,
            size: BasakButtonSize.small,
            expand: false),
      ]),
      Row(children: [
        BasakIconButton(icon: LucideIcons.bell, label: 'التنبيهات', onPressed: () {}, badge: 2),
        const SizedBox(width: BasakSpace.s8),
        BasakIconButton(icon: LucideIcons.phone, label: 'اتصال', onPressed: () {}, onCard: true),
      ]),
    ]),
    animates: true,
  ),
  _Scene(
    'page_header',
    (context) => _column([
      BasakBackHeader(title: 'اشتراك جديد', subtitle: 'إلى جامعة المنصورة الجديدة', onBack: () {}),
      SectionHead('1 · حوّل المبلغ',
          trailing: BasakButton(
              label: 'تغيير', onPressed: () {}, variant: BasakButtonVariant.quiet, size: BasakButtonSize.small, expand: false)),
    ]),
  ),
  _Scene(
    'page_with_dock',
    (context) => BasakPage(
      header: BasakBackHeader(title: 'الدفع', onBack: () {}),
      dock: const BasakDock(child: BasakButton(label: 'إرسال للمراجعة', onPressed: null)),
      children: [
        const InfoRows(rows: [InfoRow(label: 'الخط', value: 'الزرقا'), InfoRow(label: 'الشركة', value: 'النورس للنقل')]),
        InlineError(message: 'تعذّر تحميل مواعيد الغد', onRetry: () {}),
        const BasakCard(child: Text('بطاقة')),
      ],
    ),
    pageHeight: 640,
  ),
  _Scene(
    'grouped_fields',
    (context) => _column([
      GroupedFields(children: [
        GroupedField(
          label: 'رقم الهاتف',
          controller: TextEditingController(text: '010 2345 6789'),
          ltr: true,
          keyboardType: TextInputType.phone,
        ),
        GroupedField(
          label: 'كلمة المرور',
          controller: TextEditingController(text: '12345678'),
          obscureText: true,
          trailing: Icon(LucideIcons.eye, size: 20, color: context.colors.ink3),
        ),
      ]),
      GroupedFields(children: [
        const GroupedField(label: 'الاسم بالكامل', hint: 'كما في بطاقتك الجامعية'),
        GroupedField(
          label: 'كلمة المرور',
          controller: TextEditingController(text: '1234'),
          error: '8 أحرف على الأقل.',
        ),
        GroupedValue(label: 'الجامعة', value: 'جامعة المنصورة الجديدة', locked: true, onTap: () {}),
        GroupedValue(label: 'الكلية', placeholder: 'اختر كليتك', onTap: () {}),
      ]),
      InlineError(message: 'تعذّر تحميل مواعيد الغد', onRetry: () {}),
    ]),
  ),
  _Scene(
    'info_rows',
    (context) => _column([
      InfoRows(rows: [
        const InfoRow(label: 'الخط', value: 'الزرقا'),
        const InfoRow(label: 'محطة الصعود', value: 'كوبري السرو'),
        const InfoRow(label: 'الشركة', value: 'شركة النورس للنقل الجماعي والرحلات'),
        InfoRow(label: 'الإيصال', value: '26-7F3A9C2E', ltrValue: true, onTap: () {}),
      ]),
      InfoRows(rows: [
        InfoRow(label: 'الفصل الثاني 2025/2026', caption: 'انتهى 28 مايو 2026 · الزرقا', onTap: () {}),
        InfoRow(label: 'الفصل الأول 2025/2026', caption: 'انتهى 15 يناير 2026 · الزرقا', onTap: () {}),
      ]),
    ]),
  ),
  // What the student's card tab adds: the sheet's sunken rows, the tinted
  // strip, and the outlined button and the empty page on the ink ground.
  _Scene(
    'card_parts',
    (context) => _column([
      const InfoRows(sunken: true, rows: [
        InfoRow(label: 'الجامعة', value: 'جامعة المنصورة الجديدة'),
        InfoRow(label: 'الهاتف', value: '010 2345 6789', ltrValue: true),
      ]),
      const InfoStrip(
          label: 'رحلة اليوم · الأحد 11 أكتوبر', value: 'ذهاب 7:23 ص · عودة 3:30 م', icon: LucideIcons.check),
      const InfoStrip(
          tone: BasakTone.warning, label: 'الإيصال', value: 'أُرسل اليوم 3:40 م', icon: LucideIcons.clock3),
      const InfoStrip(dense: true, label: 'رحلة اليوم · الأحد 11 أكتوبر', value: 'لم يؤكّد رحلة اليوم'),
      const FactGrid(dense: true, facts: [('الخط', 'الزرقا'), ('محطة الصعود', 'كوبري السرو')]),
      const StatusChip(BasakStatus.active, label: 'اشتراك نشط'),
      Container(
        padding: const EdgeInsetsDirectional.all(BasakSpace.s16),
        color: context.colors.ink,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          InkOutlineButton(label: 'كل التفاصيل', icon: LucideIcons.idCard, onPressed: () {}),
          _gap(),
          EmptyState(
            onInk: true,
            icon: LucideIcons.qrCode,
            title: 'البطاقة غير متاحة حالياً',
            message: 'تعذّر تجهيز بطاقتك. سجّل دخولك مرة أخرى، أو تواصل مع الدعم.',
            actionLabel: 'إعادة المحاولة',
            actionIcon: LucideIcons.refreshCw,
            onAction: () {},
          ),
        ]),
      ),
    ]),
  ),
  _Scene(
    'status_chip',
    (context) => _column([
      Wrap(spacing: BasakSpace.s10, runSpacing: BasakSpace.s10, children: [
        for (final status in BasakStatus.values) StatusChip(status),
      ]),
      Container(
        padding: const EdgeInsetsDirectional.all(BasakSpace.s16),
        color: context.colors.ink,
        child: const Align(
            alignment: AlignmentDirectional.centerStart, child: StatusChip(BasakStatus.active, onInk: true)),
      ),
      const Wrap(spacing: BasakSpace.s8, runSpacing: BasakSpace.s8, children: [
        BasakTag('وفّر 1,000 ج.م', tone: BasakTone.success),
        BasakTag('يومي متاح'),
        BasakTag('الفترة القادمة', tone: BasakTone.info),
        BasakTag('لم يصعد', tone: BasakTone.warning),
        BasakTag('متوقف', tone: BasakTone.danger),
      ]),
    ]),
  ),
  _Scene(
    'sheet',
    (context) => BasakSheetFrame(
      title: 'محطة الصعود',
      subtitle: 'خط الزرقا',
      primary: BasakButton(label: 'تأكيد', onPressed: () {}),
      child: Container(
        height: 64,
        decoration:
            BoxDecoration(color: context.colors.ground, borderRadius: BasakRadius.all(BasakRadius.control)),
      ),
    ),
    background: BasakPalette.inkRule,
  ),
  _Scene(
    'route_rail',
    (context) => _column([
      const BasakCard(child: RouteRail(from: 'كوبري السرو', to: 'المنصورة الجديدة')),
      const BasakCard(
        child: RouteRail(
            from: 'اختر محطتك', to: 'المنصورة الجديدة', toCaption: 'جامعتك', fromPending: true, large: true),
      ),
      Container(
        padding: const EdgeInsetsDirectional.all(BasakSpace.s20),
        decoration: BoxDecoration(color: context.colors.ink, borderRadius: BasakRadius.all(BasakRadius.card)),
        child: const RouteRail(
            from: 'موقف الزرقا الجديد أمام مجلس المدينة',
            to: 'جامعة المنصورة الجديدة الأهلية',
            onInk: true),
      ),
    ]),
  ),
  _Scene(
    'pass_card',
    (context) => _column([
      _pass(BasakStatus.active,
          toCaption: 'الجامعة', footer: PassStub(line: 'خط الزرقا', company: 'النورس للنقل', onShowCard: () {})),
      _pass(BasakStatus.pendingPayment,
          footer: PassAction(caption: 'المبلغ المطلوب', value: '4,500 ج.م', actionLabel: 'ادفع الآن', onAction: () {})),
      _pass(BasakStatus.rejected,
          footer:
              PassAction(caption: 'المحاولة 2 من 5', value: 'المبلغ غير مطابق', actionLabel: 'إيصال جديد', onAction: () {})),
      _pass(BasakStatus.expired,
          footer: PassAction(caption: 'الفصل الثاني', value: '4,500 ج.م', actionLabel: 'جدّد', onAction: () {})),
      _pass(BasakStatus.pendingReview,
          footer: const StepLine(steps: ['أُرسل الإيصال', 'المراجعة', 'التفعيل'], current: 1)),
      _pass(BasakStatus.upcoming,
          period: 'الفصل الثاني · 7 فبراير',
          toCaption: 'الجامعة',
          footer: PassStub(line: 'خط الزرقا', company: 'النورس للنقل', onShowCard: () {}, onInk: false)),
    ]),
  ),
  _Scene(
    'step_line',
    (context) => _column(const [
      BasakCard(child: StepLine(steps: ['أُرسل الإيصال', 'المراجعة', 'التفعيل'], current: 0)),
      BasakCard(child: StepLine(steps: ['أُرسل الإيصال', 'المراجعة', 'التفعيل'], current: 1)),
      BasakCard(child: StepLine(steps: ['أُرسل الإيصال', 'المراجعة', 'التفعيل'], current: 3)),
    ]),
  ),
  for (final (name, items, index, collapsed) in [
    ('tab_bar_student', FloatingGlassNavBar.studentNavItems, 0, false),
    ('tab_bar_student_card', FloatingGlassNavBar.studentNavItems, 2, false),
    ('tab_bar_student_collapsed', FloatingGlassNavBar.studentNavItems, 0, true),
    ('tab_bar_supervisor', FloatingGlassNavBar.supervisorNavItems, 1, false),
  ])
    _Scene(
      name,
      (context) => Padding(
        padding: const EdgeInsetsDirectional.only(top: BasakSpace.s10),
        child: BasakTabBar(currentIndex: index, onTabSelected: (_) {}, items: items, collapsed: collapsed),
      ),
      pageHeight: 84,
    ),
  _Scene(
    'connection_strip',
    (context) => _column([
      ConnectionStrip(state: ConnectionStripState.offline, dataTime: '8:15 ص', onRetry: () {}),
      const ConnectionStrip(state: ConnectionStripState.syncing),
      const ConnectionStrip(state: ConnectionStripState.backOnline),
      const ConnectionStrip(
          state: ConnectionStripState.offline, dataTime: '8:15 ص', note: 'المسح لا يسجّل الصعود الآن'),
    ]),
  ),
  _Scene(
    'toast',
    (context) => _column(const [
      BasakToastBody(message: 'تم نسخ عنوان InstaPay'),
      BasakToastBody(message: 'تعذّر إرسال الإيصال. حاول مرة أخرى.', kind: BasakToastKind.failure),
      BasakToastBody(message: 'تم إرسال الإشعار إلى 38 طالباً.', kind: BasakToastKind.info),
    ]),
  ),
  _Scene(
    'empty_state',
    (context) => _column([
      const EmptyState(
          icon: LucideIcons.bell, title: 'لا توجد تنبيهات بعد', message: 'ستظهر هنا حركة الباص وحالة اشتراكك.'),
      EmptyState(
          icon: LucideIcons.bus,
          title: 'لا توجد خطوط لجامعتك بعد',
          message: 'سنخبرك عند إضافة خط.',
          actionLabel: 'تحديث',
          onAction: () {}),
      const LiveAlertBanner(title: 'الباص تحرّك من موقف الزرقا', time: 'قبل 4 دقائق'),
    ]),
  ),
  _Scene(
    'skeleton',
    (context) => const Skeleton(
      child: SkeletonCard(
        padding: EdgeInsetsDirectional.all(BasakSpace.card),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Bone(width: 120),
          SizedBox(height: BasakSpace.s12),
          Bone(width: 200, height: 20),
          SizedBox(height: BasakSpace.s12),
          Bone(height: 48, radius: BasakRadius.small),
        ]),
      ),
    ),
    animates: true,
  ),
  _Scene(
    'choice_tile',
    (context) => _column([
      ChoiceGrid(children: [
        ChoiceTile(label: 'الفصل الأول', value: '4,500', selected: true, onTap: () {}),
        ChoiceTile(label: 'الفصل الثاني', value: '4,500', selected: false, onTap: () {}),
        ChoiceTile(label: 'الفصلان معاً', value: '8,000', selected: false, onTap: () {}, tag: 'وفّر 1,000'),
      ]),
      BasakCard(
        child: ChoiceGrid(children: [
          for (final (i, time) in ['6:15 ص', '7:00 ص', '7:45 ص', '8:30 ص', '9:15 ص'].indexed)
            ChoiceTile(label: time, selected: i == 1, onTap: () {}, onCard: true),
        ]),
      ),
      ChoiceGrid(children: [ChoiceTile(label: 'الفصل الثاني', value: '4,500', selected: true, onTap: () {})]),
    ]),
  ),
  _Scene(
    'radio_card',
    (context) => BasakCard(
      padding: const EdgeInsetsDirectional.all(BasakSpace.s16),
      child: _column([
        RadioCard(
            title: 'الزرقا', subtitle: 'جامعة المنصورة الجديدة · 124 مشتركاً', selected: true, onTap: () {}),
        RadioCard(
            title: 'دمياط الجديدة',
            subtitle: 'جامعة دمياط · 86 مشتركاً',
            selected: false,
            onTap: () {},
            tag: const BasakTag('متوقف', tone: BasakTone.danger)),
      ]),
    ),
  ),
  _Scene(
    'chips',
    (context) => _column([
      BasakSegmented<int>(
          options: const [0, 1], value: 0, onChanged: (_) {}, label: (v) => v == 0 ? 'الكل' : 'غير المقروءة · 2'),
      BasakChips<String>(
        options: const ['InstaPay', 'فودافون كاش', 'اتصالات كاش', 'البنك الأهلي', 'بنك مصر'],
        value: 'InstaPay',
        onChanged: (_) {},
        label: (v) => v,
      ),
      BasakCard(
        padding: const EdgeInsetsDirectional.all(BasakSpace.s16),
        child: ChipChoice<int>(options: const [5, 10, 15, 20, 30], value: 15, onChanged: (_) {}, label: (v) => '$v'),
      ),
    ]),
  ),
  _Scene(
    'line_card',
    (context) => _column([
      LineCard(
          name: 'الزرقا', stops: '7 محطات', fromPrice: '4,500', firstDeparture: '6:15 ص', lastReturn: '5:30 م', onTap: () {}),
      LineCard(
          name: 'كفر سعد',
          stops: '6 محطات',
          fromPrice: '4,800',
          firstDeparture: '6:00 ص',
          lastReturn: '4:30 م',
          tag: 'يومي متاح',
          onTap: () {}),
      const LineCard.unavailable(name: 'شربين', stops: '4 محطات', reason: 'الاشتراك مغلق حالياً'),
    ]),
  ),
  _Scene(
    'builder_row',
    (context) => _column([
      BuilderRow(
          state: BuilderRowState.chosen, step: 2, title: 'الخط والمحطة', value: 'الزرقا · كوبري السرو', onChange: () {}),
      const BuilderRow(state: BuilderRowState.open, step: 3, title: 'الفترة'),
      const BuilderRow(state: BuilderRowState.locked, step: 3, title: 'الفترة'),
    ]),
  ),
  _Scene(
    'photo_ring',
    (context) => BasakCard(
      child: Row(children: [
        PhotoRing(name: 'سارة أحمد', size: 60, ring: context.colors.mint),
        const SizedBox(width: BasakSpace.s18),
        PhotoRing(name: 'سارة أحمد', size: 60, ring: context.colors.pendingRing),
        const SizedBox(width: BasakSpace.s18),
        const PhotoRing(name: 'سارة أحمد'),
      ]),
    ),
  ),
  _Scene(
    'fact_grid',
    (context) => const BasakCard(
      padding: EdgeInsetsDirectional.all(BasakSpace.s16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        FactGrid(facts: [
          ('الخط', 'الزرقا'),
          ('محطة الصعود', 'كوبري السرو'),
          ('الفترة', 'الفصل الأول'),
          ('الشركة', 'النورس للنقل'),
        ]),
        SizedBox(height: BasakSpace.s14),
        InfoStrip(label: 'رحلة اليوم', value: 'ذهاب 7:23 ص · عودة 3:30 م'),
      ]),
    ),
  ),
  _Scene(
    'progress_line',
    (context) => const BasakCard(
      padding: EdgeInsetsDirectional.all(BasakSpace.s16),
      child: ProgressLine(sentence: 'صعد 14 من 38', trailing: 'بقي 24', value: 14 / 38),
    ),
  ),
  _Scene(
    'counts_hero',
    (context) => _column([
      CountsHero(
        day: 'اليوم · الأحد 11 أكتوبر',
        firmness: 'نهائي · أُغلق التأكيد 6:00 ص',
        isFinal: true,
        going: 107,
        goingTrips: 'في 5 رحلات',
        returning: 105,
        returningTrips: 'في 6 رحلات',
        shareSentence: 'سيركب 107 من 124 مشتركاً',
        share: 107 / 124,
        onShare: () {},
      ),
      PagerDots(count: 2, index: 0, onTap: (_) {}, labels: const ['اليوم', 'غداً']),
    ]),
  ),
  _Scene(
    'bar_list',
    (context) => BarList(title: 'الذهاب', trailing: '4 رحلات', rows: [
      BarRow(time: '6:15 ص', count: 12, share: 12 / 38, state: BarRowState.past, onTap: () {}),
      BarRow(time: '7:00 ص', count: 38, share: 1, state: BarRowState.next, onTap: () {}),
      BarRow(time: '7:45 ص', count: 27, share: 27 / 38, onTap: () {}),
      BarRow(time: '8:30 ص', count: 21, share: 21 / 38, onTap: () {}),
    ]),
  ),
  _Scene(
    'stop_row',
    (context) => BasakCard(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        StopRow(
            name: 'ميت الخولي', time: '7:07 ص', boarded: 4, expected: 4, state: StopState.done, isFirst: true, onToggle: () {}),
        StopRow(
          name: 'شرباص',
          time: '7:15 ص',
          boarded: 1,
          expected: 2,
          state: StopState.current,
          expanded: true,
          onToggle: () {},
          riders: [
            StopRider(name: 'ندى إبراهيم خليل', boardedAt: '7:15 ص', onTap: () {}),
            StopRider(name: 'كريم محمد عبد الله', onTap: () {}),
          ],
        ),
        StopRow(
            name: 'كوبري السرو', time: '7:23 ص', boarded: 0, expected: 8, state: StopState.upcoming, isLast: true, onToggle: () {}),
      ]),
    ),
  ),
  _Scene(
    'stat_meter',
    (context) => _column(const [
      Row(children: [
        Expanded(child: StatTile(value: '118', label: 'طالباً مختلفاً')),
        SizedBox(width: BasakSpace.s8),
        Expanded(child: StatTile(value: '9', label: 'أيام عمل')),
      ]),
      BasakCard(
        padding: EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Meter(label: 'صعود مسجَّل', value: '1,284', share: .95, tone: BasakTone.success),
          Meter(label: 'مسح مكرَّر', value: '52', share: .04),
        ]),
      ),
    ]),
  ),
  _Scene(
    'scan_chrome',
    (context) => _column([
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(child: ScanChrome.pill(context, label: 'ذهاب · 7:00 ص', onTap: () {}, semanticLabel: 'الرحلة: ذهاب 7:00 ص. تغيير')),
        const SizedBox(width: BasakSpace.s12),
        ScanChrome.pill(context, label: '14 / 38', icon: LucideIcons.users, ltr: true, semanticLabel: 'صعد 14 من 38'),
      ]),
      Row(children: [
        Expanded(child: ScanChrome.toggle(context, icon: LucideIcons.flashlight, label: 'الإضاءة', on: true, onTap: () {})),
        const SizedBox(width: BasakSpace.s10),
        Expanded(
            child: ScanChrome.toggle(context, icon: LucideIcons.switchCamera, label: 'قلب الكاميرا', on: false, onTap: () {})),
      ]),
    ]),
    background: BasakPalette.scanPanel,
  ),
  _Scene(
    'result_header',
    (context) => _column(const [
      BasakCard(
        child: ResultHeader(
            tone: BasakTone.success, icon: LucideIcons.check, title: 'تم تسجيل الصعود', message: 'ذهاب 7:00 ص · سُجّل 7:23 ص'),
      ),
      BasakCard(
        child: ResultHeader(tone: BasakTone.info, icon: LucideIcons.info, title: 'سبق تسجيله اليوم'),
      ),
      BasakCard(
        child: ResultHeader(tone: BasakTone.danger, icon: LucideIcons.x, title: 'لا يوجد اشتراك ساري'),
      ),
      BasakCard(
        child: ResultHeader(tone: BasakTone.warning, icon: LucideIcons.wifiOff, title: 'بدون إنترنت · لم يُسجَّل'),
      ),
    ]),
  ),
  _Scene(
    'home_parts',
    (context) => _column([
      const Wrap(spacing: BasakSpace.s8, runSpacing: BasakSpace.s8, children: [
        IconPill(icon: LucideIcons.clock3, label: 'حتى 6:00 ص', tone: BasakTone.warning),
        IconPill(icon: LucideIcons.clock3, label: 'يفتح 4:00 م', tone: BasakTone.info),
        IconPill(icon: LucideIcons.check, label: 'مؤكدة', tone: BasakTone.success),
        IconPill(icon: LucideIcons.clock3, label: 'مغلق'),
      ]),
      BasakCard(
        child: _column([
          TimeGrid(children: [
            for (final (i, time) in ['6:38 ص', '7:23 ص', '8:08 ص', '8:53 ص', '9:38 ص'].indexed)
              TimeTile(label: time, selected: i == 1, onTap: () {}),
          ]),
          TimeTile(label: 'لن أعود بالباص', selected: false, wide: true, onTap: () {}),
          const Row(children: [
            Expanded(child: ValueTile(label: 'الذهاب', value: '7:23 ص')),
            SizedBox(width: BasakSpace.s10),
            Expanded(child: ValueTile(label: 'العودة', value: '3:30 م')),
          ]),
          const WeekStrip(days: [
            (letter: 'س', day: 10, mark: WeekDayMark.confirmed),
            (letter: 'ح', day: 11, mark: WeekDayMark.confirmed),
            (letter: 'ن', day: 12, mark: WeekDayMark.asked),
            (letter: 'ث', day: 13, mark: WeekDayMark.open),
            (letter: 'ر', day: 14, mark: WeekDayMark.open),
            (letter: 'خ', day: 15, mark: WeekDayMark.open),
            (letter: 'ج', day: 16, mark: WeekDayMark.off),
          ]),
        ]),
      ),
      InkBanner(icon: LucideIcons.bus, title: 'الباص تحرّك من موقف الزرقا', message: 'مشرف الباص · الآن', onTap: () {}),
      PageError(
        title: 'لا يوجد اتصال',
        message: 'نحتاج الإنترنت مرة واحدة لتحميل بياناتك. بعدها تعمل بطاقتك واشتراكك بدون اتصال.',
        onAction: () {},
      ),
    ]),
  ),
  _Scene(
    'sheet_parts',
    (context) => BasakCard(
      child: _column([
        const SheetGlyph(LucideIcons.bell),
        const SheetPoint(icon: LucideIcons.userRound, text: 'ترى الشركة اسمك وهاتفك وجامعتك وصورتك.'),
        const SheetPoint(icon: LucideIcons.shieldCheck, text: 'لا يتغيّر حسابك ولا اشتراكاتك لدى شركات أخرى.'),
        Row(children: [
          Expanded(child: ActionTile(icon: LucideIcons.messageCircle, label: 'واتساب', onTap: () {})),
          const SizedBox(width: BasakSpace.s8),
          Expanded(child: ActionTile(icon: LucideIcons.userRoundPlus, label: 'حفظ الرقم', onTap: () {})),
          const SizedBox(width: BasakSpace.s8),
          Expanded(child: ActionTile(icon: LucideIcons.copy, label: 'نسخ الرقم', onTap: () {})),
        ]),
        SheetLink(label: 'ليس الآن', onTap: () {}),
      ]),
    ),
  ),
];

void main() {
  setUpAll(_fonts);

  final update = autoUpdateGoldenFiles;
  final madeOn = _platformFile.existsSync() ? _platformFile.readAsStringSync().trim() : null;
  final compare = update || madeOn == Platform.operatingSystem;

  if (update) {
    setUpAll(() {
      _platformFile.parent.createSync(recursive: true);
      _platformFile.writeAsStringSync('${Platform.operatingSystem}\n');
    });
  }

  for (final scene in _scenes) {
    for (final width in _widths) {
      for (final scale in _scales) {
        final file = 'goldens/${scene.name}_${width.toInt()}_${scale == 1 ? '100' : '130'}.png';
        testWidgets('${scene.name} at ${width.toInt()}, text ×$scale', (tester) async {
          // Real shadows, as on a phone (tests draw them as solid blocks by default).
          debugDisableShadows = false;
          tester.view.physicalSize = Size(width, 3200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: RepaintBoundary(
                  key: _shot,
                  child: Builder(
                    builder: (context) => Container(
                      width: width,
                      height: scene.pageHeight,
                      color: scene.background ?? context.colors.ground,
                      padding: scene.pageHeight == null ? const EdgeInsetsDirectional.all(BasakSpace.s16) : null,
                      child: scene.build(context),
                    ),
                  ),
                ),
              ),
            ),
          ));
          try {
            if (scene.animates) {
              await tester.pump(const Duration(milliseconds: 100));
            } else {
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
            if (compare) await expectLater(find.byKey(_shot), matchesGoldenFile(file));
          } finally {
            debugDisableShadows = true;
          }
        });
      }
    }
  }
}
