import 'package:flutter/material.dart';
import '../../../../core/widgets/skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/sync/own_changes.dart';
import '../../../../core/sync/session.dart';
import '../../qr/presentation/student_qr_screen.dart';
import 'subscription_screen.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/basak_ui.dart';
import '../../home/presentation/student_home_screen.dart';
import '../models/sale_catalog.dart';
import '../models/subscription_draft.dart';
import '../models/subscription_model.dart';

/// Companies, lines, stations and the options on sale for the signed-in
/// student. It is the largest read of the app (every line that serves the
/// student's university), so it is read only while something on screen shows
/// it: the purchase flow, and the "next period" card of a running
/// subscription. Nothing reads it at start or in the background.
///
/// Once read it is kept for the session. A change that can alter it (a line,
/// its prices, the student's subscriptions, a return to the app) only marks it
/// stale: it is read again at once when it is on screen, otherwise the next
/// time it is shown. From its saved copy first, like everything else.
final saleCatalogProvider = FutureProvider<SaleCatalog>((ref) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(subscriptionRepoProvider).getSaleCatalog();
});

/// Creates the subscription on the server. The only write of the whole flow:
/// it runs once, when the student confirms the review.
final subscriptionCreatorProvider =
    Provider<Future<SubscriptionModel> Function(SubscriptionRequest)>((ref) {
  final repo = ref.watch(subscriptionRepoProvider);
  return (request) async {
    // The server announces the new subscription back to this phone; it is
    // already shown from the answer below, so that echo reads nothing again.
    final echo = OwnChanges.begin('subscriptions', op: 'INSERT');
    try {
      final created = await repo.createSubscription(
        lineId: request.lineId,
        stationId: request.stationId,
        departureTime: request.departureTime,
        returnTime: request.returnTime,
        type: request.type,
        price: request.price,
        departureTripId: request.departureTripId,
        returnTripId: request.returnTripId,
        periodCode: request.periodCode,
        academicYear: request.academicYear,
      );
      echo.done(id: created.id, keep: const Duration(minutes: 1));
      // The lists were updated from the answer (answered from memory), and
      // the card follows them. What is on sale changes too, but the student
      // is leaving the purchase flow: the screen marks the catalog stale once
      // the flow is off screen (see SubscriptionScreen), so it is not read
      // again for nobody.
      ref.invalidate(currentSubscriptionProvider);
      ref.invalidate(allSubscriptionsProvider);
      ref.invalidate(studentQrProvider);
      return created;
    } catch (_) {
      echo.failed();
      rethrow;
    }
  };
});

const _ink = Color(0xFF17384A);
const _brand = Color(0xFF00658D);
const _stepNames = ['الشركة', 'الخط', 'المحطة', 'الفترة', 'المراجعة'];
const _green = Color(0xFF22C55E);
const _greenSoft = Color(0xFFE7F8F0);
const _rail = Color(0xFFBBF7D0);

/// "8,000 ج.م"
String formatMoney(double value) {
  final digits = value.toStringAsFixed(0);
  final grouped = digits.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return '$grouped ج.م';
}

String _money(double value) => formatMoney(value);

/// Periods in the order a student thinks of them, not by date.
const _optionOrder = ['first', 'second', 'both', 'summer'];
List<SaleOption> _ordered(List<SaleOption> options) => [...options]
  ..sort((a, b) => _optionOrder.indexOf(a.option).compareTo(_optionOrder.indexOf(b.option)));

/// Company → Line → Boarding station → Period → Review.
///
/// The student moves freely backward and forward and can change any choice:
/// the choices are a [SubscriptionDraft] held here, and nothing is written
/// until "تأكيد والانتقال للدفع" on the review.
class PurchaseFlow extends ConsumerStatefulWidget {
  /// Choices to start from (e.g. the line and station of the running
  /// subscription when paying the next period).
  final SubscriptionDraft initial;

  /// Daily cash rides are offered only to a student with no open subscription.
  final bool allowDaily;

  /// Whether the flow is on screen now. While it is not (its tab is built in
  /// the background, or another tab is in front) the catalog is not read or
  /// listened to; what was last shown stays.
  final bool visible;

  /// Leaves the flow without subscribing (shown when there is somewhere to
  /// go back to).
  final VoidCallback? onCancel;
  final ValueChanged<SubscriptionModel> onCreated;

  const PurchaseFlow({
    super.key,
    this.initial = const SubscriptionDraft(),
    this.allowDaily = true,
    this.visible = true,
    this.onCancel,
    required this.onCreated,
  });

  @override
  ConsumerState<PurchaseFlow> createState() => _PurchaseFlowState();
}

class _PurchaseFlowState extends ConsumerState<PurchaseFlow> {
  late SubscriptionDraft _draft = widget.initial;
  late DraftStep _step = widget.initial.firstOpenStep;
  bool _submitting = false;

  /// The catalog as last shown (null: the flow has not been on screen yet).
  AsyncValue<SaleCatalog>? _shown;

  void _go(DraftStep step) {
    if (_draft.canOpen(step)) setState(() => _step = step);
  }

  void _back() {
    if (_step.index > 0) {
      setState(() => _step = DraftStep.values[_step.index - 1]);
    } else {
      widget.onCancel?.call();
    }
  }

  void _choose(SubscriptionDraft next, DraftStep then) => setState(() {
        _draft = next;
        _step = next.canOpen(then) ? then : next.firstOpenStep;
      });

  Future<void> _confirm(SaleCatalog catalog) async {
    final request = SubscriptionRequest.from(_draft, catalog);
    if (request == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final created = await ref.read(subscriptionCreatorProvider)(request);
      if (!mounted) return;
      setState(() => _submitting = false);
      widget.onCreated(created);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      // The offer may have changed since it was shown: read it again.
      ref.invalidate(saleCatalogProvider);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage(e)), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched only while on screen: behind another tab nothing is read, and a
    // change that marks the catalog stale waits until the flow is shown again.
    if (widget.visible) _shown = ref.watch(saleCatalogProvider);
    final catalogAsync = _shown;
    if (catalogAsync == null) return const PurchaseFlowSkeleton();
    return catalogAsync.when(
      loading: () => const PurchaseFlowSkeleton(),
      error: (e, _) => _message('تعذر تحميل الشركات والخطوط: ${errorMessage(e)}', retry: true),
      data: (catalog) {
        // Whatever was chosen and is no longer offered is dropped.
        final draft = _draft.reconciled(catalog);
        final step = draft.canOpen(_step) ? _step : draft.firstOpenStep;
        if (draft != _draft || step != _step) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _draft = draft;
                _step = step;
              });
            }
          });
        }
        final canLeave = step == DraftStep.company && widget.onCancel == null;
        return PopScope(
          canPop: canLeave,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back();
          },
          // Its own Material, so the cards' ink is drawn above the page colour.
          child: Material(
            type: MaterialType.transparency,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (step == DraftStep.company && widget.onCancel != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('flow-back'),
                  onPressed: _back,
                  icon: const Icon(LucideIcons.arrowRight, size: 18),
                  label: const Text('العودة إلى اشتراكاتي'),
                ),
              ),
            _progress(draft, step),
            if (step != DraftStep.company)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    key: const Key('flow-back'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _brand,
                      side: const BorderSide(color: Color(0xFFCFE0EA)),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _submitting ? null : _back,
                    icon: const Icon(LucideIcons.arrowRight, size: 17),
                    label: Text('الخطوة السابقة: ${_stepNames[step.index - 1]}'),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Text('اشتراكي الجامعي',
                style: AppTextStyles.displayMedium.copyWith(color: _ink)),
            const SizedBox(height: 6),
            Text(_subtitles[step.index],
                style: AppTextStyles.bodyMedium.copyWith(color: const Color(0xFF718695))),
            const SizedBox(height: 22),
            if (catalog.companies.isEmpty)
              _message(
                  'لا توجد حالياً شركات أو خطوط متاحة لجامعتك'
                  '${catalog.universityName == null ? '' : ' (${catalog.universityName})'}.',
                  retry: true)
            else
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: KeyedSubtree(
                  key: ValueKey(step),
                  child: switch (step) {
                    DraftStep.company => _companyStep(catalog, draft),
                    DraftStep.line => _lineStep(catalog, draft),
                    DraftStep.station => _stationStep(catalog, draft),
                    DraftStep.period => _periodStep(catalog, draft),
                    DraftStep.review => _reviewStep(catalog, draft),
                  },
                ),
              ),
          ]),
          ),
        );
      },
    );
  }

  static const _subtitles = [
    'اختر شركة النقل التي تخدم جامعتك.',
    'اختر خط سير حافلتك.',
    'اختر المحطة التي ستركب منها.',
    'اختر مدة اشتراكك.',
    'راجع اختياراتك قبل الدفع.',
  ];
  static const _numerals = ['١', '٢', '٣', '٤', '٥'];

  // ── Shared pieces ──────────────────────────────────────────────────

  Widget _message(String text, {bool retry = false}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BasakUi.card(),
        child: Column(children: [
          Text(text,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          if (retry)
            TextButton.icon(
              onPressed: () => ref.invalidate(saleCatalogProvider),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('تحديث'),
            ),
        ]),
      );

  /// "الخطوة ٢ من ٥" with the five dots; a step already reachable can be
  /// tapped to go straight to it.
  Widget _progress(SubscriptionDraft draft, DraftStep step) {
    final n = step.index + 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(.94),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE3EDF3))),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('الخطوة $n من 5',
              style: AppTextStyles.labelSmall.copyWith(color: _brand, fontWeight: FontWeight.bold)),
          Text(
              n == 5
                  ? 'الخطوة الأخيرة'
                  : n == 4
                      ? 'متبقي خطوة واحدة'
                      : 'متبقي ${5 - n} خطوات',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
        ]),
        const SizedBox(height: 13),
        Row(children: [
          for (final s in DraftStep.values) ...[
            InkWell(
              key: Key('flow-step-${s.name}'),
              customBorder: const CircleBorder(),
              onTap: draft.canOpen(s) && !_submitting ? () => _go(s) : null,
              child: CircleAvatar(
                  radius: 15,
                  backgroundColor: s.index <= step.index ? _brand : const Color(0xFFE7EEF4),
                  child: Icon(s.index < step.index ? LucideIcons.check : LucideIcons.circle,
                      size: 15,
                      color: s.index <= step.index ? Colors.white : AppColors.textSecondary)),
            ),
            if (s != DraftStep.review)
              Expanded(
                  child: Container(
                      height: 2,
                      color: s.index < step.index ? _brand : const Color(0xFFE7EEF4))),
          ]
        ]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final s in DraftStep.values)
            Expanded(
              child: Text(_stepNames[s.index],
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  textAlign: s.index == 0
                      ? TextAlign.start
                      : s == DraftStep.review
                          ? TextAlign.end
                          : TextAlign.center,
                  style: AppTextStyles.labelSmall.copyWith(
                      color: s == step ? _brand : null,
                      fontWeight: s == step ? FontWeight.bold : null)),
            ),
        ]),
      ]),
    );
  }

  /// "٢. اختر الخط", with what was chosen in the step before as a reminder.
  Widget _stepTitle(DraftStep step, String title, {String? previous}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_numerals[step.index]}. $title',
              style: AppTextStyles.titleMedium.copyWith(color: _ink)),
          if (previous != null) ...[
            const SizedBox(height: 3),
            Text(previous,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
          ],
        ]),
      );

  // ── 1. Company ─────────────────────────────────────────────────────

  Widget _companyStep(SaleCatalog catalog, SubscriptionDraft draft) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _stepTitle(DraftStep.company, 'اختر شركة النقل'),
        for (final company in catalog.companies)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              key: Key('company-${company.id}'),
              borderRadius: BorderRadius.circular(18),
              onTap: () => _choose(draft.pickCompany(catalog, company.id), DraftStep.line),
              child: Ink(
                padding: const EdgeInsets.all(16),
                decoration: draft.companyId == company.id
                    ? BoxDecoration(
                        color: const Color(0xFFEAF4FB),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _brand, width: 1.6))
                    : BasakUi.card(radius: 18),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(color: BasakUi.softTeal, shape: BoxShape.circle),
                    child: const Icon(LucideIcons.building2, color: BasakUi.teal),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(company.name, style: AppTextStyles.titleMedium.copyWith(color: _ink)),
                      const SizedBox(height: 3),
                      Text(
                          company.lines.length == 1
                              ? 'خط واحد متاح لجامعتك'
                              : '${company.lines.length} خطوط متاحة لجامعتك',
                          style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
                    ]),
                  ),
                  const Icon(LucideIcons.chevronLeft, color: AppColors.textSecondary),
                ]),
              ),
            ),
          ),
      ]);

  // ── 2. Line ────────────────────────────────────────────────────────

  Widget _lineStep(SaleCatalog catalog, SubscriptionDraft draft) {
    final company = catalog.company(draft.companyId)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _stepTitle(DraftStep.line, 'اختر الخط', previous: company.name),
      for (final line in company.lines) _lineCard(catalog, draft, line),
    ]);
  }

  Widget _lineCard(SaleCatalog catalog, SubscriptionDraft draft, SaleLine line) {
    final selected = draft.lineId == line.id;
    final sells = line.options.isNotEmpty || (widget.allowDaily && line.dailyEnabled);
    final from = line.fromPrice;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        key: Key('line-${line.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: sells ? () => _choose(draft.pickLine(catalog, line.id), DraftStep.station) : null,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF4FB) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: selected ? _brand : const Color(0xFFE6EEF3), width: selected ? 1.6 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(selected ? LucideIcons.circleCheck : LucideIcons.busFront,
                  color: selected ? _brand : AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(line.name,
                      style: AppTextStyles.titleMedium.copyWith(color: _ink))),
              if (from != null) ...[
                const SizedBox(width: 8),
                Text('من ${_money(from)}',
                    style: AppTextStyles.labelSmall
                        .copyWith(color: _brand, fontWeight: FontWeight.w800)),
              ],
            ]),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(LucideIcons.graduationCap, size: 15, color: Color(0xFF3F51B5)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('إلى ${line.university ?? 'جامعتك'}',
                    style: AppTextStyles.labelSmall.copyWith(
                        color: const Color(0xFF3F51B5), fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
                line.stations.length == 1
                    ? 'محطة صعود واحدة: ${line.stations.first.name}'
                    : '${line.stations.length} محطات صعود: ${line.stations.map((s) => s.name).join(' · ')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (line.firstDeparture != null)
                BasakPill('أول ذهاب ${BasakUi.time12(line.firstDeparture)}',
                    background: const Color(0xFFE7F8F0),
                    foreground: const Color(0xFF15803D),
                    icon: LucideIcons.sunrise),
              if (line.lastReturn != null)
                BasakPill('آخر عودة ${BasakUi.time12(line.lastReturn)}',
                    background: const Color(0xFFFFF4E5),
                    foreground: const Color(0xFFB97812),
                    icon: LucideIcons.sunset),
            ]),
            if (!sells) ...[
              const SizedBox(height: 8),
              Text('الاشتراك في هذا الخط غير متاح الآن.',
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
            ],
          ]),
        ),
      ),
    );
  }

  // ── 3. Boarding station ────────────────────────────────────────────

  Widget _stationStep(SaleCatalog catalog, SubscriptionDraft draft) {
    final line = catalog.line(draft.lineId)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _stepTitle(DraftStep.station, 'اختر محطة الصعود', previous: line.name),
      if (line.stations.isEmpty)
        _message('لا توجد رحلات متاحة لجامعتك على هذا الخط.')
      else
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BasakUi.card(radius: 22),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < line.stations.length; i++)
              _stationRow(draft, line.stations[i],
                  first: i == 0, last: i == line.stations.length - 1),
          ]),
        ),
      const SizedBox(height: 8),
      Text('الموعد الظاهر هو وقت مرور الباص على المحطة. موعد كل يوم تختاره من الرئيسية.',
          style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
    ]);
  }

  /// A stop on the route rail. Under its name, one time per departure trip
  /// that stops there: a station has no single bus time.
  Widget _stationRow(SubscriptionDraft draft, SaleStation station,
      {required bool first, required bool last}) {
    final selected = draft.stationId == station.id;
    return InkWell(
      key: Key('station-${station.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => _choose(draft.pickStation(station.id), DraftStep.period),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 24,
            child: Column(children: [
              Expanded(child: Container(width: 2, color: first ? Colors.transparent : _rail)),
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? _green : Colors.white,
                  border: Border.all(color: _green, width: 2.5),
                ),
              ),
              Expanded(child: Container(width: 2, color: last ? Colors.transparent : _rail)),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: selected ? _greenSoft : const Color(0xFFF5F8FA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: selected ? _green : Colors.transparent, width: 1.4),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(station.name,
                        style: AppTextStyles.bodyLarge
                            .copyWith(color: BasakUi.ink, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(station.departures.map((d) => BasakUi.time12(d.time)).join(' · '),
                        style: AppTextStyles.labelSmall.copyWith(
                            color: const Color(0xFF15803D), fontWeight: FontWeight.w600)),
                  ]),
                ),
                Icon(selected ? LucideIcons.circleCheck : LucideIcons.circle,
                    size: 19, color: selected ? const Color(0xFF15803D) : const Color(0xFFB6C3CB)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── 4. Period ──────────────────────────────────────────────────────

  Widget _periodStep(SaleCatalog catalog, SubscriptionDraft draft) {
    final line = catalog.line(draft.lineId)!;
    final station = line.station(draft.stationId)!;
    final options = _ordered(line.options);
    final daily = widget.allowDaily && line.dailyEnabled;
    final first = line.option(options.where((o) => o.option == 'first').firstOrNull?.key);
    final second = line.option(options.where((o) => o.option == 'second').firstOrNull?.key);
    // What paying both semesters at once saves, when both single prices are on sale.
    final saving = (first == null || second == null) ? null : first.price + second.price;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _stepTitle(DraftStep.period, 'اختر فترة الاشتراك', previous: station.name),
      if (options.isEmpty && !daily)
        _message('لا توجد فترة متاحة للاشتراك الآن على هذا الخط.', retry: true)
      else ...[
        if (options.isNotEmpty)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _optionCard(draft, options[i], pairPrice: saving)),
              ],
            ]),
          ),
        if (daily) ...[
          const SizedBox(height: 10),
          InkWell(
            key: const Key('option-daily'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => _choose(draft.pickOption(SubscriptionDraft.dailyKey), DraftStep.review),
            child: Ink(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                  color: draft.isDaily ? const Color(0xFFEAF4FB) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: draft.isDaily ? _brand : const Color(0xFFE6EEF3),
                      width: draft.isDaily ? 1.5 : 1)),
              child: Row(children: [
                Expanded(
                  child: Text('يوم واحد · الدفع نقداً في الباص',
                      style: AppTextStyles.labelSmall.copyWith(fontWeight: FontWeight.bold)),
                ),
                Text(_money(line.dailyPrice),
                    style: AppTextStyles.titleMedium.copyWith(color: _brand)),
              ]),
            ),
          ),
        ],
      ],
    ]);
  }

  Widget _optionCard(SubscriptionDraft draft, SaleOption option, {double? pairPrice}) {
    final selected = draft.optionKey == option.key;
    final saved = option.option == 'both' && pairPrice != null ? pairPrice - option.price : 0.0;
    return InkWell(
      key: Key('option-${option.option}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => _choose(draft.pickOption(option.key), DraftStep.review),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF4FB) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? _brand : const Color(0xFFE6EEF3), width: selected ? 1.5 : 1)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(option.title,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSmall.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(_money(option.price),
                style: AppTextStyles.titleMedium.copyWith(color: _brand)),
          ),
          if (saved > 0 || option.isUpcoming) ...[
            const SizedBox(height: 4),
            Text(saved > 0 ? 'وفّر ${_money(saved)}' : 'الفترة القادمة',
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSmall.copyWith(
                    color: saved > 0 ? const Color(0xFF15803D) : const Color(0xFF3F51B5),
                    fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }

  // ── 5. Review ──────────────────────────────────────────────────────

  Widget _reviewStep(SaleCatalog catalog, SubscriptionDraft draft) {
    final company = catalog.company(draft.companyId)!;
    final line = catalog.line(draft.lineId)!;
    final station = line.station(draft.stationId)!;
    final option = draft.isDaily ? null : line.option(draft.optionKey);
    final amount = option?.price ?? line.dailyPrice;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _stepTitle(DraftStep.review, 'راجع اختياراتك', previous: option?.title ?? 'يوم واحد'),
      Container(
        padding: const EdgeInsets.fromLTRB(17, 8, 8, 17),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(color: Color(0x0B17384A), blurRadius: 15, offset: Offset(0, 5))
            ]),
        child: Column(children: [
          _reviewRow(LucideIcons.building2, 'شركة النقل', company.name, DraftStep.company),
          _reviewRow(LucideIcons.busFront, 'الخط', line.name, DraftStep.line),
          _reviewRow(LucideIcons.graduationCap, 'الجامعة', line.university ?? '—', null),
          _reviewRow(LucideIcons.mapPin, 'محطة الصعود', station.name, DraftStep.station),
          _reviewRow(LucideIcons.calendarDays, 'فترة الاشتراك',
              option?.title ?? 'يوم واحد (نقداً في الباص)', DraftStep.period),
          const SizedBox(height: 10),
          Container(
            margin: const EdgeInsetsDirectional.only(end: 9),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFF1F6FB), borderRadius: BorderRadius.circular(13)),
            child: Row(children: [
              Expanded(child: Text('المبلغ المطلوب', style: AppTextStyles.bodyMedium)),
              Text(_money(amount),
                  key: const Key('review-amount'),
                  style: AppTextStyles.titleLarge.copyWith(color: _brand)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 24),
      ElevatedButton(
        key: const Key('flow-confirm'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: _submitting ? null : () => _confirm(catalog),
        child: _submitting
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(draft.isDaily ? 'تأكيد اشتراك اليوم' : 'تأكيد والذهاب للدفع'),
      ),
      const SizedBox(height: 8),
      Text(
          draft.isDaily
              ? 'يُفعّل اشتراك اليوم مباشرة، وتدفع نقداً للمشرف في الباص.'
              : 'بعد التأكيد لا يمكن تغيير هذه الاختيارات.',
          textAlign: TextAlign.center,
          style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
    ]);
  }

  Widget _reviewRow(IconData icon, String label, String value, DraftStep? edit) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(icon, size: 17, color: _brand),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: Text(label,
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
          ),
          if (edit != null)
            TextButton(
              key: Key('review-edit-${edit.name}'),
              style: TextButton.styleFrom(
                  minimumSize: const Size(48, 40), padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: _submitting ? null : () => _go(edit),
              child: const Text('تعديل'),
            )
          else
            const SizedBox(width: 48, height: 40),
        ]),
      );
}
