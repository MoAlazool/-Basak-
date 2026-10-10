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
          InkOutlineButton(label: 'التفاصيل', icon: LucideIcons.rotate3d, onPressed: () {}),
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
      BasakToastBody(message: 'تم حفظ جهة الاتصال.'),
      BasakToastBody(message: 'تعذّر إرسال الإيصال. حاول مرة أخرى.', kind: BasakToastKind.failure),
      BasakToastBody(message: 'تم إرسال الإشعار إلى 38 طالباً.', kind: BasakToastKind.info),
    ]),
  ),
  _Scene(
    'toast_action',
    (context) => BasakToastBody(
      message: 'لا يوجد إذن لاستخدام الكاميرا. اسمح لتطبيق باصك باستخدام الكاميرا من إعدادات الهاتف ثم أعد المحاولة.',
      kind: BasakToastKind.failure,
      actionLabel: 'فتح الإعدادات',
      onAction: () {},
    ),
  ),
  _Scene(
    'app_prompts',
    (context) => _column([
      BasakCard(
        child: _column(const [
          PromptIntro(
            icon: LucideIcons.download,
            title: 'تحديث جديد متاح',
            fact: '2.4.0',
            semanticLabel: 'تحديث متاح',
          ),
          CheckLines(lines: [
            'الدخول ببصمة الوجه أو الإصبع',
            'ملخص الترم في نهاية كل فصل، جاهز للمشاركة مع أصحابك',
            'إصلاحات في رفع الإيصال',
          ]),
        ]),
      ),
      const BasakCard(
        child: PromptIntro(
          icon: LucideIcons.star,
          title: 'هل يعجبك باصك؟',
          message: 'تقييمك في المتجر يساعد طلاباً آخرين على الوصول إلينا، ويأخذ أقل من دقيقة.',
          semanticLabel: 'تقييم التطبيق',
        ),
      ),
      const Center(
        child: FactPill(facts: [(label: 'إصدارك', value: '2.1.0'), (label: 'المطلوب', value: '2.3.0')]),
      ),
    ]),
  ),
  _Scene(
    'blocking_notice',
    pageHeight: 640,
    (context) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.gutter, BasakSpace.s40, BasakSpace.gutter, BasakSpace.s20),
      child: BlockingNotice(
        icon: LucideIcons.download,
        title: 'حدّث التطبيق للمتابعة',
        message: 'هذا الإصدار لم يعد مدعوماً. التحديث يأخذ دقيقة، ولا يغيّر حسابك أو اشتراكك.',
        facts: const [(label: 'إصدارك', value: '2.1.0'), (label: 'المطلوب', value: '2.3.0')],
        actions: [
          BasakButton(label: 'تحديث من Google Play', icon: LucideIcons.download, onPressed: () {}),
          SheetLink(label: 'عرض بطاقتي', accent: true, onTap: () {}),
        ],
        footnote: 'بطاقتك تعمل عند الصعود حتى قبل التحديث.',
      ),
    ),
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
    'scan_parts',
    (context) => _column(const [
      ScanNotice(lead: 'بدون إنترنت.', message: 'المسح يعرض بيانات محفوظة ولا يسجّل الصعود.'),
      SizedBox(height: 180, child: Center(child: ScanFrame())),
      SizedBox(height: 140, child: Center(child: ScanFrame(color: BasakPalette.refusedFrame))),
      ScanLastRow(label: 'آخر صعود: يوسف طارق حسن', time: '7:17 ص'),
    ]),
    background: BasakPalette.scanPanel,
  ),
  _Scene(
    'scan_person',
    (context) => _column(const [
      BasakCard(
        child: PersonFacts(name: 'سارة أحمد محمود', caption: 'جامعة المنصورة الجديدة', facts: [
          PersonFact('المحطة', 'كوبري السرو'),
          PersonFact('تأكيد اليوم', 'ذهاب 7:23 ص · عودة 3:30 م'),
          PersonFact('الهاتف', '010 2345 6789', ltr: true),
        ]),
      ),
      BasakCard(
        child: PersonFacts(name: 'عمر خالد منصور', caption: 'جامعة المنصورة الجديدة', facts: [
          PersonFact('الخط والمحطة', 'الزرقا · السرو'),
          PersonFact('الاشتراك', 'غير مفعّل أو منتهٍ', tone: BasakTone.danger),
        ]),
      ),
    ]),
  ),
  _Scene(
    'scan_gate',
    (context) => ScanGate(
      title: 'اسمح باستخدام الكاميرا',
      message: 'المسح يحتاج الكاميرا لقراءة رمز الطالب. فعّل الإذن لتطبيق باصك من إعدادات الهاتف.',
      primaryLabel: 'فتح الإعدادات',
      primaryIcon: LucideIcons.settings,
      onPrimary: () {},
      secondaryLabel: 'إعادة المحاولة',
      onSecondary: () {},
    ),
    pageHeight: 560,
  ),
  _Scene(
    'send_parts',
    (context) => _column([
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
              child: AudienceTile(title: 'ركاب رحلة', subtitle: 'من أكّدوا موعداً', selected: true, onTap: () {})),
          const SizedBox(width: BasakSpace.s8),
          Expanded(
              child: AudienceTile(title: 'كل طلاب الخط', subtitle: '124 مشتركاً', selected: false, onTap: () {})),
        ]),
      ),
      const AudienceTile(title: 'ركاب رحلة', subtitle: 'لا توجد تأكيدات بعد', selected: false, onTap: null),
      PickRow(value: 'اليوم · ذهاب 7:00 ص', note: '38 طالباً', onTap: () {}),
      PickRow(label: 'يصل إلى', value: 'كل طلاب خط الزرقا · 124', opensSheet: false, onTap: () {}),
      MessageRows(rows: [
        MessageRow(
            title: 'تأخير في موعد الحافلة', preview: 'ستتأخر الحافلة نحو … دقيقة. نعتذر عن التأخير.', onTap: () {}),
        MessageRow(
            title: 'الحافلة تحركت',
            preview: 'بدأت رحلة الذهاب والحافلة في طريقها. كن في محطتك في الموعد.',
            onTap: () {}),
      ]),
      LinkCard(icon: LucideIcons.pencil, title: 'رسالة أخرى', subtitle: 'اكتب العنوان والنص بنفسك', onTap: () {}),
      const BasakCard(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NotificationPreview(
              sender: 'باصك · مشرف الباص',
              title: 'تأخير في موعد الحافلة',
              body: 'ستتأخر الحافلة نحو 15 دقيقة. نعتذر عن التأخير.'),
          SizedBox(height: BasakSpace.s16),
          ReachLine(count: '38 طالباً', audience: 'ركاب ذهاب 7:00 ص اليوم'),
        ]),
      ),
      CountedField(label: 'العنوان', controller: TextEditingController(text: 'تغيير مكان الركوب'), maxLength: 80),
      CountedField(
          label: 'نص الإشعار',
          controller: TextEditingController(text: 'غداً الركوب من أمام البنك بدل الموقف.'),
          maxLength: 600,
          lines: 5),
    ]),
  ),
  _Scene(
    'month_parts',
    (context) => _column([
      MonthSwitcher(label: 'أكتوبر 2026', onPrevious: () {}, onNext: null),
      const MonthHero(
        label: 'تسجيلات الصعود',
        total: '1,284',
        rate: '91%',
        rateCaption: 'من الركوب المؤكَّد',
        split: [('ذهاب', '702'), ('عودة', '582')],
      ),
      TitledCard(
        title: 'الصعود اليومي',
        trailing: DayBars.legend(context, lower: 'ذهاب', upper: 'عودة'),
        child: const DayBars(
          semanticLabel: 'الصعود في كل يوم عمل من أكتوبر',
          days: [
            DayBar(label: '1', lower: 83, upper: 69),
            DayBar(label: '3', lower: 82, upper: 66),
            DayBar(label: '4', lower: 85, upper: 71),
            DayBar(label: '5', lower: 79, upper: 66),
            DayBar(label: '6', lower: 76, upper: 61),
            DayBar(label: '7', lower: 84, upper: 70),
            DayBar(label: '8', lower: 81, upper: 69),
            DayBar(label: '10', lower: 86, upper: 72),
            DayBar(label: '11', lower: 52, upper: 32, emphasised: true),
          ],
        ),
      ),
    ]),
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
          const Expanded(child: CopyTile(label: 'نسخ الرقم', value: '01012345678')),
        ]),
        SheetLink(label: 'ليس الآن', onTap: () {}),
      ]),
    ),
  ),
  _Scene(
    'subscribe_parts',
    (context) => _column([
      const BuilderStepHead(step: 1, title: 'شركة النقل'),
      CompanyRow(name: 'النورس للنقل', caption: '4 خطوط إلى جامعتك', onTap: () {}),
      const BuilderStepHead(step: 3, title: 'الفترة'),
      ChoiceGrid(children: [
        PeriodTile(label: 'الفصل الأول', amount: '4,500', selected: true, onTap: () {}),
        PeriodTile(label: 'الفصل الثاني', amount: '4,500', selected: false, onTap: () {}, tag: 'الفترة القادمة', tagTone: BasakTone.info),
        PeriodTile(label: 'الفصلان معاً', amount: '8,000', selected: false, onTap: () {}, tag: 'وفّر 1,000'),
      ]),
      ChoiceGrid(children: [PeriodTile(label: 'الفصل الأول', amount: '4,500', selected: true, onTap: () {})]),
      QuietPriceRow(label: 'أو يوم واحد، نقداً في الباص', value: '60 ج.م', onTap: () {}),
      PeriodRow(
          title: 'الفصلان معاً', caption: 'حتى 28 مايو 2027', amount: '8,000', tag: 'وفّر 1,000', selected: false, onTap: () {}),
      PeriodRow(
          title: 'يوم واحد',
          caption: 'اليوم فقط · الدفع نقداً في الباص',
          amount: '40',
          tag: 'نقداً',
          tagTone: BasakTone.warning,
          selected: true,
          onTap: () {}),
      BasakCard(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          StationRow(name: 'موقف الزرقا', firstPass: 'من 6:15 ص', selected: false, isFirst: true, onTap: () {}),
          StationRow(
              name: 'كوبري السرو',
              passesCaption: 'يمرّ الباص صباحاً',
              allPasses: '6:38 · 7:23 · 8:08 · 8:53 · 9:38 ص',
              selected: true,
              onTap: () {}),
          StationRow(name: 'فارسكور', firstPass: 'من 7:05 ص', selected: false, isLast: true, onTap: () {}),
          const ReviewRow(label: 'الفترة', value: 'الفصل الأول'),
          const ReviewRow(label: 'صالح حتى', value: '14 يناير 2027'),
          const ReviewAmount(money: '4,500 ج.م'),
        ]),
      ),
      EmptyState(
        page: true,
        icon: LucideIcons.bus,
        title: 'لا توجد خطوط لجامعتك بعد',
        message: 'لا توجد حالياً شركات أو خطوط متاحة لجامعة المنصورة الجديدة. تظهر هنا فور إضافتها.',
        actionLabel: 'تحديث',
        actionIcon: LucideIcons.refreshCw,
        onAction: () {},
      ),
    ]),
  ),
  _Scene(
    'inbox_parts',
    (context) => _column([
      PageTitleBar(title: 'التنبيهات', actions: [TextAction(label: 'قراءة الكل', onTap: () {})]),
      ActionNotice(
        icon: LucideIcons.bellOff,
        title: 'الإشعارات متوقفة',
        message: 'فعّلها من إعدادات الهاتف لتصلك التنبيهات.',
        actionLabel: 'فتح إعدادات الهاتف',
        onAction: () {},
      ),
      SearchBox(hint: 'ابحث في الإشعارات', onChanged: (_) {}),
      GroupSection(
        title: 'اليوم',
        child: AlertRows(rows: [
          AlertRow(
              icon: LucideIcons.bus,
              tone: BasakTone.success,
              title: 'الباص تحرّك من موقف الزرقا',
              body: 'رحلة 7:00 ص · خط الزرقا',
              time: '6:58 ص',
              unread: true,
              onTap: () {}),
          AlertRow(
              icon: LucideIcons.megaphone,
              tone: BasakTone.info,
              title: 'رسالة من مشرف الباص عن مكان الركوب غداً',
              body: 'غداً الركوب من أمام البنك بدل الموقف بسبب أعمال في الطريق.',
              time: '6:20 ص',
              unread: true,
              onTap: () {}),
          AlertRow(
              icon: LucideIcons.clock3, title: 'لم تؤكد رحلة الغد بعد', body: 'التأكيد متاح حتى 6:00 ص.', time: '9:00 م', onTap: () {}),
          AlertRow(icon: LucideIcons.check, tone: BasakTone.success, title: 'تم تفعيل اشتراكك', body: '', time: '4:12 م', onTap: () {}),
        ]),
      ),
      Row(children: const [
        ToneTile(LucideIcons.megaphone, tone: BasakTone.info, size: 44),
        SizedBox(width: BasakSpace.s12),
        ToneTile(LucideIcons.ban, tone: BasakTone.danger),
        SizedBox(width: BasakSpace.s12),
        ToneTile(LucideIcons.hourglass, tone: BasakTone.warning),
      ]),
    ]),
  ),
  _Scene(
    'account_parts',
    (context) => _column([
      IdentityCard(name: 'سارة أحمد محمود', phone: '010 2345 6789', onChangePhoto: () {}),
      IdentityCard(name: 'محمد عادل فؤاد عبد الرحمن العزول', phone: '010 5551 2301', onChangePhoto: () {}),
      const IdentityCard(name: 'محمود السيد', phone: '010 1122 3344'),
      GroupSection(
        title: 'بياناتي',
        actionLabel: 'تعديل',
        onAction: () {},
        child: const SettingRows(rows: [
          SettingRow(label: 'الجامعة', value: 'المنصورة الجديدة', locked: true),
          SettingRow(label: 'الكلية', value: 'الهندسة'),
          SettingRow(label: 'التخصص', value: 'لم يُضف بعد', muted: true),
          SettingRow(label: 'البريد الإلكتروني', value: 'mohamed.adel.fouad@students.example.edu.eg', ltrValue: true),
        ]),
      ),
      GroupSection(
        title: 'التطبيق',
        child: SettingRows(rows: [
          SettingRow(label: 'المساعدة والدعم', onTap: () {}),
          SettingRow(label: 'الدخول بـ Face ID', trailing: Switch(value: true, onChanged: (_) {})),
          SettingRow(label: 'إشعارات الهاتف', value: 'مفعّلة', external: true, onTap: () {}),
        ]),
      ),
      QuietFooter(actionLabel: 'حذف الحساب', onAction: () {}, version: '1.0.6'),
    ]),
  ),
  _Scene(
    'account_sheet_parts',
    (context) => _column([
      const SheetField(label: 'التخصص', hint: 'اختياري'),
      const SheetField(label: 'البريد الإلكتروني', hint: 'name@example.com', ltr: true, error: 'اكتب بريداً إلكترونياً صحيحاً.'),
      SheetValueField(label: 'الكلية', value: 'الهندسة', placeholder: 'لم يُضف بعد', icon: LucideIcons.chevronDown, onTap: () {}),
      SheetValueField(
          label: 'تاريخ الميلاد', value: '14 مارس 2005', placeholder: 'اختر التاريخ', icon: LucideIcons.calendar, onTap: () {}, onClear: () {}),
      SheetValueField(
          label: 'تاريخ الميلاد', value: null, placeholder: 'اختر التاريخ', icon: LucideIcons.calendar, onTap: () {}, onClear: () {}),
      GroupSection(
        title: 'عن رحلتك واشتراكك',
        child: LinkRows(rows: [
          LinkRow(person: 'محمود السيد', title: 'محمود السيد', subtitle: 'مشرف الباص · خط الزرقا', onTap: () {}),
          LinkRow(icon: LucideIcons.messageCircle, title: '[قناة الدعم 1]', subtitle: '[وصف قصير أو أوقات العمل]', onTap: () {}),
        ]),
      ),
      BasakDialogFrame(
        icon: LucideIcons.trash2,
        title: 'حذف الحساب نهائياً؟',
        message: 'يُحذف حسابك وبياناتك، وتتوقف بطاقتك عن العمل. لا يمكن التراجع عن الحذف.',
        confirmLabel: 'تأكيد الحذف',
        onAnswer: (_) {},
      ),
    ]),
    background: BasakPalette.surface,
  ),
  _Scene(
    'skeleton_lists',
    (context) => _column([
      const SkeletonList(rows: 3),
      const SkeletonList(rows: 2, avatars: false),
      const SkeletonCard(
          radius: BasakRadius.sheet, padding: EdgeInsetsDirectional.all(BasakSpace.s20), child: ProfileSkeleton()),
      // A new photo on its way: the spinner never settles, like the bones.
      IdentityCard(name: 'سارة أحمد محمود', phone: '010 2345 6789', onChangePhoto: () {}, busy: true),
    ]),
    animates: true,
  ),
  _Scene(
    'entry_parts',
    (context) => _column([
      const StepRail(steps: ['بياناتك', 'دراستك', 'صورتك', 'كلمة المرور'], current: 0),
      const StepRail(steps: ['بياناتك', 'دراستك', 'صورتك', 'كلمة المرور'], current: 2),
      const InfoNote('لا يمكن تغيير الجامعة بعد التسجيل.'),
      const StrengthMeter(level: 1, label: 'ضعيفة'),
      const StrengthMeter(level: 2, label: 'متوسطة'),
      const StrengthMeter(level: 3, label: 'قوية'),
      CheckRow(value: true, onChanged: (_) {}, child: const Text('أوافق على الشروط وسياسة الخصوصية.')),
      CheckRow(value: false, onChanged: (_) {}, child: const Text('أوافق على الشروط وسياسة الخصوصية.')),
      const FieldNote('وافق على الشروط وسياسة الخصوصية للمتابعة.'),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: CheckRow(quiet: true, value: true, onChanged: (_) {}, child: const Text('تذكّر رقمي')),
      ),
      CodeField(controller: TextEditingController(text: '4827')),
      CodeField(controller: TextEditingController(text: '12'), hasError: true),
      EntryLink(label: 'لديّ رمز بالفعل', onTap: () {}),
      EntryLink(label: 'تخطي', tone: EntryLinkTone.quiet, onTap: () {}),
      EntryLink(label: 'تسجيل الخروج', tone: EntryLinkTone.danger, onTap: () {}),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('طالب جديد؟'),
        const SizedBox(width: BasakSpace.s6),
        EntryLink(label: 'إنشاء حساب', inline: true, strong: true, onTap: () {}),
        const SizedBox(width: BasakSpace.s12),
        PasswordEye(hidden: true, onTap: () {}),
        PasswordEye(hidden: false, onTap: () {}),
      ]),
      const Center(child: PhotoDrop()),
    ]),
  ),
  _Scene(
    'entry_sheet_parts',
    (context) => _column([
      BasakSearchField(controller: TextEditingController(), hint: 'ابحث باسم الجامعة أو المدينة'),
      BasakSearchField(controller: TextEditingController(text: 'المنصورة'), hint: 'ابحث باسم الكلية'),
      SheetRadioRow(title: 'جامعة المنصورة الجديدة', subtitle: 'المنصورة الجديدة', selected: true, onTap: () {}),
      SheetRadioRow(
          title: 'جامعة الدلتا للعلوم والتكنولوجيا', subtitle: 'جمصة', selected: false, onTap: () {}),
      SheetRadioRow(title: 'الهندسة', selected: true, onTap: () {}),
      SheetRadioRow(title: 'الحاسبات والمعلومات', selected: false, onTap: () {}),
      SheetActionRow(icon: LucideIcons.camera, label: 'التقاط صورة بالكاميرا', onTap: () {}),
      SheetActionRow(icon: LucideIcons.image, label: 'اختيار من الصور', onTap: () {}),
    ]),
    background: BasakPalette.surface,
  ),
  _Scene(
    'biometric_parts',
    (context) => _column([
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        BiometricGlyph(icon: LucideIcons.scanFace, label: 'انظر إلى الهاتف للدخول', onTap: () {}),
        BiometricGlyph(icon: LucideIcons.fingerprint, label: 'لم يتعرّف الهاتف عليك', warning: true, onTap: () {}),
      ]),
      Row(children: [
        Expanded(child: BasakButton(label: 'دخول', onPressed: () {})),
        const SizedBox(width: BasakSpace.s8),
        GroundSquareButton(icon: LucideIcons.scanFace, label: 'الدخول بـ Face ID', onPressed: () {}),
      ]),
      BasakCard(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SwitchRow(label: 'الدخول بـ Face ID', value: true, onChanged: (_) {}),
          SwitchRow(label: 'الدخول بالبصمة أو الوجه', value: false, onChanged: (_) {}),
        ]),
      ),
    ]),
  ),
  _Scene(
    'copy_boxes',
    (context) => _column(const [
      BasakCard(
        padding: EdgeInsetsDirectional.all(BasakSpace.s6),
        child: CopyRow(label: 'عنوان InstaPay', value: 'elnawras@instapay'),
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: CopyButton(label: 'نسخ المبلغ', value: '4500', variant: BasakButtonVariant.surface, expand: false),
      ),
      CopyButton(label: 'نسخ الرقم', value: '01012345678', size: BasakButtonSize.medium),
      CopyButton(label: 'نسخ الرقم', value: null, size: BasakButtonSize.medium),
    ]),
  ),
  _Scene(
    'school_and_logo',
    (context) => _column([
      const BasakCard(child: SchoolLine(college: 'الهندسة', university: 'جامعة المنصورة')),
      const BasakCard(
        child: SchoolLine(
          college: 'كلية الحاسبات والمعلومات والذكاء الاصطناعي',
          university: 'جامعة المنصورة الجديدة الأهلية للعلوم والتكنولوجيا',
        ),
      ),
      Row(children: [
        CompanyLogo(name: 'شركة النورس للنقل'),
        const SizedBox(width: BasakSpace.s12),
        CompanyLogo(name: 'المستقبل', size: 56),
        const SizedBox(width: BasakSpace.s12),
        CompanyLogo(name: 'Delta Bus', size: 32, radius: BasakRadius.tile),
      ]),
    ]),
  ),
  _Scene(
    'splash_rail',
    (context) => _column(const [
      Center(child: SplashRail(progress: 0)),
      Center(child: SplashRail(progress: .5)),
      Center(child: SplashRail(progress: .8)),
      Center(child: SplashRail(progress: 1)),
    ]),
    background: BasakPalette.ink,
  ),
  _Scene(
    'pay_parts',
    (context) => _column([
      MoneyText('4,500 ج.م', style: context.text.amount, unitSize: 16),
      PayeeCard(name: 'شركة النورس للنقل', method: 'تحويل بنكي · البنك الأهلي المصري', fields: [
        CopyField(label: 'رقم الحساب', value: '0123 4567 8901 234'),
        CopyField(label: 'IBAN', value: 'EG00 0003 0000 0000 0000 0000 000'),
      ]),
      const Disclosure(
        icon: LucideIcons.info,
        title: 'قبل التحويل',
        child: NumberedList(items: ['حوّل المبلغ كاملاً في عملية واحدة.', 'اكتب اسمك الثلاثي في ملاحظات التحويل.']),
      ),
      UploadZone(requirement: 'صورة واضحة فيها رقم العملية والتاريخ', actions: [
        BasakButton(
            label: 'الكاميرا', icon: LucideIcons.camera, onPressed: () {},
            variant: BasakButtonVariant.surface, size: BasakButtonSize.small),
        BasakButton(
            label: 'من الصور', icon: LucideIcons.image, onPressed: () {},
            variant: BasakButtonVariant.surface, size: BasakButtonSize.small),
      ]),
      const BasakCard(
        child: SendProgress(title: 'جارٍ رفع الصورة', sent: .62, steps: ['التجهيز', 'الرفع', 'الإرسال'], current: 1),
      ),
      const RejectionCard(
          attempt: 'المحاولة 2 من 5', reason: 'المبلغ في الإيصال 4,000 ج.م والمطلوب 4,500 ج.م. حوّل الفرق.'),
      const NoticeCard(message: 'لم تضف الشركة بيانات التحويل بعد. تواصل مع إدارة الشركة للحصول عليها.'),
      Row(children: [
        const ToneGlyph(LucideIcons.ban),
        const SizedBox(width: BasakSpace.s12),
        SquareIconButton(icon: LucideIcons.image, label: 'حفظ كصورة', onPressed: () {}),
        const SizedBox(width: BasakSpace.s12),
        SquareIconButton(icon: LucideIcons.share2, label: 'مشاركة', onPressed: () {}),
      ]),
      const ResultBody(title: 'استلمنا إيصالك', message: 'تراجعه شركة النورس للنقل، وسيصلك إشعار عند تفعيل اشتراكك.'),
    ]),
  ),
  _Scene(
    'subscription_parts',
    (context) => _column([
      const PeriodCard(
        status: BasakStatus.active,
        meta: '2026 / 2027',
        metaLtr: true,
        title: 'الفصل الأول',
        note: 'باقي 95 يوماً',
        bar: ValidityBar(elapsed: .18, from: '20 سبتمبر', to: '14 يناير 2027'),
      ),
      PeriodCard(
        status: BasakStatus.pendingPayment,
        meta: '2026 / 2027',
        metaLtr: true,
        title: 'الفصل الأول',
        footer: AmountAction(caption: 'المبلغ المطلوب', money: '4,500 ج.م', actionLabel: 'ادفع الآن', onAction: () {}),
      ),
      const PeriodCard(
          status: BasakStatus.pendingReview, meta: '2026 / 2027', metaLtr: true, title: 'الفصلان معاً',
          note: 'أُرسل اليوم 3:40 م'),
      OfferCard(
          title: 'الفصل الثاني متاح الآن', subtitle: 'نفس الخط والمحطة · 4,500 ج.م', actionLabel: 'اشترك', onAction: () {}),
      const OfferSummary(caption: 'الفصل الثاني · نفس الخط والمحطة', value: 'الزرقا · كوبري السرو', money: '4,500 ج.م'),
      InfoRows(
        rows: [
          InfoRow(label: 'الفصل الثاني 2025/2026', caption: 'انتهى 28 مايو 2026 · الزرقا', onTap: () {}),
          InfoRow(label: 'تعذّر تحميل الإيصال', onRetry: () {}),
        ],
        footer: BasakButton(
            label: 'عرض كل الاشتراكات السابقة · 5', onPressed: () {},
            variant: BasakButtonVariant.quiet, size: BasakButtonSize.small),
      ),
      const DisclosureGroup(sections: [
        DisclosureSection(title: 'الاشتراك', rows: [
          ('الفترة', 'الفصل الأول 2026/2027', false),
          ('الصلاحية', '20 سبتمبر – 14 يناير 2027', false),
        ]),
        DisclosureSection(title: 'الطالب', rows: [('الهاتف', '010 2345 6789', true)]),
      ]),
    ]),
  ),
  // The supervisor's Home and Trips: the line row, a trip row with the bus's
  // seats, the trip card, the trip sheet's rows, a closed group, an entry.
  _Scene(
    'supervisor_trip_parts',
    (context) => _column([
      LineSwitchRow(name: 'خط الزرقا', caption: 'النورس للنقل · 1 من 3 خطوط', onTap: () {}),
      const LineSwitchRow(name: 'خط السنبلاوين', caption: 'النورس للنقل', tag: 'خط متوقف', onTap: null),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: BarList(title: 'الذهاب', trailing: '3 رحلات', rows: [
              BarRow(time: '6:15 ص', count: 12, share: .2, state: BarRowState.past, onTap: () {}),
              BarRow(
                  time: '7:00 ص',
                  count: 62,
                  share: 1,
                  state: BarRowState.next,
                  note: 'يحتاج باصين',
                  noteWarns: true,
                  onTap: () {}),
              BarRow(time: '7:45 ص', count: 45, share: .73, note: '45 من 50', onTap: () {}),
            ]),
          ),
          const SizedBox(width: BasakSpace.s8),
          Expanded(
            child: BarList(title: 'العودة', trailing: 'رحلتان', rows: [
              BarRow(time: '12:30 م', count: 8, share: .26, onTap: () {}),
              BarRow(time: '3:30 م', count: 31, share: 1, onTap: () {}),
            ]),
          ),
        ],
      ),
      TripCard(
        time: '7:00 ص',
        direction: 'ذهاب',
        detail: 'خط الزرقا · الوصول إلى الجامعة 8:20 ص',
        note: 'مقاعد الباص: 38 من 50',
        onChange: () {},
        child: const ProgressLine(sentence: 'صعد 14 من 38', trailing: 'بقي 24', value: 14 / 38),
      ),
      BasakCard(
        child: _column([
          TripChoiceRow(time: '6:15 ص', note: 'مضى موعدها', riders: '12 طالباً', selected: false, past: true, onTap: () {}),
          TripChoiceRow(time: '7:00 ص', note: 'الآن', riders: '38 طالباً', selected: true, onTap: () {}),
          TripChoiceRow(time: '12:30 م', note: 'بعد 27 دقيقة', riders: '9 طلاب', selected: false, onTap: () {}),
        ]),
      ),
      BasakCard(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          StopRow(
            name: 'شرباص',
            time: '7:15 ص',
            boarded: 0,
            expected: 2,
            countLabel: '2',
            state: StopState.upcoming,
            isFirst: true,
            isLast: true,
            expanded: true,
            onToggle: () {},
            riders: const [
              StopRider(name: 'ندى إبراهيم خليل', plain: true),
              StopRider(name: 'كريم محمد عبد الله', plain: true),
            ],
          ),
        ]),
      ),
      DisclosureCard(
        title: 'لم يؤكّدوا اليوم · 5',
        subtitle: 'مشتركون على الخط لم يحدّدوا موعدهم',
        expanded: false,
        onToggle: () {},
        child: const SizedBox.shrink(),
      ),
      DisclosureCard(
        title: 'لم يؤكّدوا اليوم · 2',
        subtitle: 'مشتركون على الخط لم يحدّدوا موعدهم',
        expanded: true,
        onToggle: () {},
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          PersonRow(name: 'سلمى عبد الرحمن', caption: 'شرباص', onTap: () {}),
          PersonRow(name: 'عمر خالد', caption: 'كوبري السرو', onTap: () {}),
        ]),
      ),
      EntryRow(
          icon: LucideIcons.megaphone, title: 'إشعار للطلاب', subtitle: 'لكل الخط أو لركاب رحلة واحدة', onTap: () {}),
      const ToneState(
        icon: LucideIcons.userX,
        tone: BasakTone.danger,
        title: 'الحساب موقوف',
        message: 'أوقفت إدارة الشركة حساب المشرف. تواصل مع شركتك لإعادة تفعيله.',
      ),
    ]),
  ),
  // ---- the term recap (boards Recap*)
  _Scene(
    'recap_banner',
    (context) => RecapBanner(title: 'ملخّص ترمك جاهز', message: '109 ساعة في الباص… والباقي جوّه.', onTap: () {}),
  ),
  _Scene(
    'recap_story_page',
    (context) => StoryScaffold(
      ground: StoryGround.sky,
      rings: const [StoryRing(end: -200, bottom: -220, size: 440, stroke: 56)],
      index: 2,
      count: 11,
      brand: 'باصك · ملخّص الترم',
      closeLabel: 'إغلاق',
      onClose: () {},
      onNext: () {},
      child: const StoryBody(children: [
        StoryKicker(text: 'جدولك', ground: StoryGround.sky),
        StoryNumber(numeral: '41', unit: 'يوم ركبت الباص', ground: StoryGround.sky),
        StoryBars(ground: StoryGround.sky, bars: [
          StoryBar(letter: 'س'),
          StoryBar(letter: 'ح', count: 14, height: 1, strong: true),
          StoryBar(letter: 'ن'),
          StoryBar(letter: 'ث', count: 14, height: 1, strong: true),
          StoryBar(letter: 'ر', count: 5, height: .36),
          StoryBar(letter: 'خ', count: 13, height: .93, strong: true),
        ]),
        StoryLine(text: '3 أيام في الأسبوع؟ ده جدول يتحسد عليه.', ground: StoryGround.sky, level: StoryLineLevel.body),
        StoryLine(
            text: 'وحضرت 41 من 45 في أيامك. الباقي إجازة رسمي، مش غياب.',
            ground: StoryGround.sky,
            level: StoryLineLevel.second),
        StoryChip(text: 'أطول غيبة: 9 أيام · كنا هنسأل عليك', ground: StoryGround.sky, icon: LucideIcons.calendar),
      ]),
    ),
    pageHeight: 760,
  ),
  _Scene(
    'recap_story_parts',
    (context) => ColoredBox(
      color: StoryGround.ink.background,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(BasakSpace.s20),
        child: _column([
          const StoryKicker(text: 'الفصل الأول', ground: StoryGround.ink, ltrTail: '2026 / 2027'),
          const StoryHeadline(text: 'عمدة\nكوبري السرو', ground: StoryGround.ink, accent: true),
          const StoryHeadline(text: 'وصول متأخر… بس وصول', ground: StoryGround.ink, accent: true),
          const StoryNumber(numeral: '7:23', suffix: 'ص', unit: 'ركبته 41 مرة', ground: StoryGround.ink, accent: true),
          const StoryLine(text: 'الباص بقى عارفك.', ground: StoryGround.ink),
          const StoryLine(text: 'رقم تقريبي، من مواعيد الرحلات اللي أكّدتها.', ground: StoryGround.ink, level: StoryLineLevel.note),
          const StoryBox(title: '109 ساعة = 36 محاضرة استاتيكا', body: 'اختار اللي يوجع أقل.', ground: StoryGround.ink),
          const StoryCta(text: 'شوف البوستر', ground: StoryGround.ink),
          const StoryRail(
            before: ['موقف الزرقا', 'ميت الخولي'],
            stop: 'كوبري السرو',
            after: ['السرو', 'فارسكور'],
            ground: StoryGround.ink,
          ),
          StoryCalendar(letters: const ['س', 'ح', 'ن', 'ث', 'ر', 'خ'], weeks: [
            const StoryWeek(month: 'سبتمبر', days: [TermDot.none, TermDot.on, TermDot.on, TermDot.off, TermDot.off, TermDot.on]),
            for (var w = 0; w < 4; w++)
              StoryWeek(month: w == 1 ? 'أكتوبر' : null, days: [
                for (var d = 0; d < 6; d++) (w * 5 + d * 3) % 4 == 0 ? TermDot.off : TermDot.on,
              ]),
          ]),
        ]),
      ),
    ),
  ),
  for (final theme in PosterTheme.values)
    _Scene(
      'recap_poster_${theme.name}',
      (context) => Center(
        child: PosterFrame(
          child: RecapPoster(
            theme: theme,
            head: 'ملخّص الترم',
            term: 'الفصل الأول',
            years: '2026/27',
            titleKicker: 'لقبي الترم ده',
            title: theme == PosterTheme.teal ? 'ديك الفجر' : 'عمدة\nكوبري السرو',
            why: '62 يوم على نفس المحطة. المحطة بقت باسمي.',
            line: theme == PosterTheme.mint ? null : '109 ساعة في الباص، ولسه الشيت ما اتحلّش.',
            patternLabel: 'ترمي يوم بيوم',
            patternCount: '62 يوم من 101',
            pattern: [
              for (var w = 0; w < 17; w++)
                [for (var d = 0; d < 6; d++) (w * 7 + d * 5) % 8 < 5 && (w < 8 || w > 9) ? TermDot.on : TermDot.off],
            ],
            stats: [
              const PosterStat('109', 'ساعة'),
              const PosterStat('62', 'يوم'),
              if (theme != PosterTheme.sky) const PosterStat('7:23 ص', 'معادي') else const PosterStat('91%', 'من جدولي', ltr: true),
            ],
            signature: 'سارة · خط الزرقا',
            site: 'Basak.app',
          ),
        ),
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
