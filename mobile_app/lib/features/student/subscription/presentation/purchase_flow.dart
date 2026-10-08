import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/sync/session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/basak_ui.dart';
import '../../home/presentation/student_home_screen.dart';
import '../models/sale_catalog.dart';
import '../models/subscription_draft.dart';
import '../models/subscription_model.dart';

/// Companies, lines, stations and the options on sale for the signed-in
/// student. Kept for the session; refreshed by SyncHub when a line or its
/// prices change, on app resume and by pull to refresh.
final saleCatalogProvider = FutureProvider<SaleCatalog>((ref) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(subscriptionRepoProvider).getSaleCatalog();
});

/// Creates the subscription on the server. The only write of the whole flow:
/// it runs once, when the student confirms the review.
final subscriptionCreatorProvider =
    Provider<Future<SubscriptionModel> Function(SubscriptionRequest)>((ref) {
  final repo = ref.watch(subscriptionRepoProvider);
  return (request) => repo.createSubscription(
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
});

const _ink = Color(0xFF17384A);
const _brand = Color(0xFF00658D);
const _stepNames = ['الشركة', 'الخط', 'المحطة', 'الفترة', 'المراجعة'];

String _money(double value) => '${value.toStringAsFixed(0)} ج.م';

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

  /// Leaves the flow without subscribing (shown when there is somewhere to
  /// go back to).
  final VoidCallback? onCancel;
  final ValueChanged<SubscriptionModel> onCreated;

  const PurchaseFlow({
    super.key,
    this.initial = const SubscriptionDraft(),
    this.allowDaily = true,
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
    final catalogAsync = ref.watch(saleCatalogProvider);
    return catalogAsync.when(
      loading: () => const Padding(
          padding: EdgeInsets.only(top: 80),
          child: Center(child: CircularProgressIndicator())),
      error: (e, _) => _message('تعذر تحميل الشركات والخطوط: ${errorMessage(e)}'),
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _progress(draft, step),
            const SizedBox(height: 14),
            if (step != DraftStep.company || widget.onCancel != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('flow-back'),
                  onPressed: _submitting ? null : _back,
                  icon: const Icon(LucideIcons.arrowRight, size: 18),
                  label: Text(step == DraftStep.company ? 'العودة إلى اشتراكاتي' : 'رجوع'),
                ),
              ),
            if (catalog.companies.isEmpty)
              _message(
                  'لا توجد حالياً شركات أو خطوط متاحة لجامعتك'
                  '${catalog.universityName == null ? '' : ' (${catalog.universityName})'}.',
                  retry: true)
            else
              switch (step) {
                DraftStep.company => _companyStep(catalog, draft),
                DraftStep.line => _lineStep(catalog, draft),
                DraftStep.station => _stationStep(catalog, draft),
                DraftStep.period => _periodStep(catalog, draft),
                DraftStep.review => _reviewStep(catalog, draft),
              },
          ]),
        );
      },
    );
  }

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

  /// The five steps; a step already reachable can be tapped to jump to it.
  Widget _progress(SubscriptionDraft draft, DraftStep step) => Container(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(.94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE3EDF3))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final s in DraftStep.values)
            Expanded(
              child: InkWell(
                key: Key('flow-step-${s.name}'),
                borderRadius: BorderRadius.circular(12),
                onTap: draft.canOpen(s) && !_submitting ? () => _go(s) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: s.index <= step.index ? _brand : const Color(0xFFE7EEF4),
                      child: s.index < step.index
                          ? const Icon(LucideIcons.check, size: 15, color: Colors.white)
                          : Text('${s.index + 1}',
                              style: AppTextStyles.labelSmall.copyWith(
                                  color: s == step ? Colors.white : AppColors.textSecondary,
                                  fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 5),
                    Text(_stepNames[s.index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelSmall.copyWith(
                            color: s == step ? _brand : AppColors.textSecondary,
                            fontWeight: s == step ? FontWeight.bold : FontWeight.normal)),
                  ]),
                ),
              ),
            ),
        ]),
      );

  Widget _heading(String title, [String? hint]) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTextStyles.titleLarge.copyWith(color: _ink)),
          if (hint != null) ...[
            const SizedBox(height: 3),
            Text(hint, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
          ],
        ]),
      );

  Widget _choiceCard(
          {required Key key,
          required bool selected,
          required VoidCallback? onTap,
          required Widget child}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFEAF4FB) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: selected ? _brand : const Color(0xFFE6EEF3), width: selected ? 1.6 : 1),
            ),
            child: child,
          ),
        ),
      );

  Widget _next(String label, VoidCallback? onPressed) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ElevatedButton(
          key: const Key('flow-next'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _brand,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: onPressed,
          child: Text(label),
        ),
      );

  // ── 1. Company ─────────────────────────────────────────────────────

  Widget _companyStep(SaleCatalog catalog, SubscriptionDraft draft) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading('اختر شركة النقل',
            catalog.universityName == null ? null : 'الشركات التي تخدم ${catalog.universityName}'),
        for (final company in catalog.companies)
          _choiceCard(
            key: Key('company-${company.id}'),
            selected: draft.companyId == company.id,
            onTap: () => _choose(draft.pickCompany(catalog, company.id), DraftStep.line),
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
      ]);

  // ── 2. Line ────────────────────────────────────────────────────────

  Widget _lineStep(SaleCatalog catalog, SubscriptionDraft draft) {
    final company = catalog.company(draft.companyId)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading('اختر الخط', company.name),
      for (final line in company.lines) _lineCard(catalog, draft, line),
    ]);
  }

  Widget _lineCard(SaleCatalog catalog, SubscriptionDraft draft, SaleLine line) {
    final selected = draft.lineId == line.id;
    final sells = line.options.isNotEmpty || (widget.allowDaily && line.dailyEnabled);
    final from = line.fromPrice;
    return _choiceCard(
      key: Key('line-${line.id}'),
      selected: selected,
      onTap: sells ? () => _choose(draft.pickLine(catalog, line.id), DraftStep.station) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(selected ? LucideIcons.circleCheck : LucideIcons.busFront,
              color: selected ? _brand : AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
              child: Text(line.name, style: AppTextStyles.titleMedium.copyWith(color: _ink))),
          if (from != null)
            Text('من ${_money(from)}',
                style: AppTextStyles.labelSmall
                    .copyWith(color: _brand, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 6),
        Text('إلى ${line.university ?? 'جامعتك'}',
            style: AppTextStyles.bodyMedium
                .copyWith(color: const Color(0xFF3F51B5), fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          BasakPill(line.stations.length == 1 ? 'محطة واحدة' : '${line.stations.length} محطات',
              icon: LucideIcons.mapPin),
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
    );
  }

  // ── 3. Boarding station ────────────────────────────────────────────

  Widget _stationStep(SaleCatalog catalog, SubscriptionDraft draft) {
    final line = catalog.line(draft.lineId)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading('اختر محطة الصعود',
          'المحطة التي ستركب منها على خط ${line.name}. موعد كل يوم تختاره من الرئيسية.'),
      if (line.stations.isEmpty)
        _message('لا توجد رحلات متاحة لجامعتك على هذا الخط.')
      else
        for (final station in line.stations) _stationCard(draft, station),
      _next('التالي', draft.stationId == null ? null : () => _go(DraftStep.period)),
    ]);
  }

  Widget _stationCard(SubscriptionDraft draft, SaleStation station) {
    final selected = draft.stationId == station.id;
    String list(Iterable<String> times) => times.map(BasakUi.time12).join(' · ');
    return _choiceCard(
      key: Key('station-${station.id}'),
      selected: selected,
      onTap: () => setState(() => _draft = draft.pickStation(station.id)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(selected ? LucideIcons.circleCheck : LucideIcons.mapPin,
              size: 20, color: selected ? _brand : AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
              child: Text(station.name, style: AppTextStyles.titleMedium.copyWith(color: _ink))),
        ]),
        // One time per trip that stops here: a station has no single bus time.
        if (selected) ...[
          const SizedBox(height: 10),
          _timesRow(
              LucideIcons.sunrise,
              station.departures.length == 1 ? 'موعد المرور للذهاب' : 'مواعيد المرور للذهاب',
              list(station.departures.map((d) => d.time)),
              const Color(0xFF15803D)),
          if (station.returns.isNotEmpty) ...[
            const SizedBox(height: 6),
            _timesRow(
                LucideIcons.sunset,
                station.returns.length == 1 ? 'العودة تتحرك من الجامعة' : 'رحلات العودة تتحرك من الجامعة',
                list(station.returns.map((r) => r.start)),
                const Color(0xFFB97812)),
          ],
        ],
      ]),
    );
  }

  Widget _timesRow(IconData icon, String label, String times, Color color) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: '$label: ',
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
            TextSpan(
                text: times,
                style: AppTextStyles.bodyMedium.copyWith(color: color, fontWeight: FontWeight.w700)),
          ])),
        ),
      ]);

  // ── 4. Period ──────────────────────────────────────────────────────

  Widget _periodStep(SaleCatalog catalog, SubscriptionDraft draft) {
    final line = catalog.line(draft.lineId)!;
    final daily = widget.allowDaily && line.dailyEnabled;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading('اختر فترة الاشتراك'),
      if (line.options.isEmpty && !daily)
        _message('لا توجد فترة متاحة للاشتراك الآن على هذا الخط.', retry: true)
      else ...[
        // The periods the company sells now, side by side.
        if (line.options.isNotEmpty)
          LayoutBuilder(builder: (context, box) {
            final perRow = line.options.length > 3 ? 2 : line.options.length;
            final width = (box.maxWidth - 10 * (perRow - 1)) / perRow;
            return Wrap(spacing: 10, runSpacing: 10, children: [
              for (final option in line.options)
                SizedBox(width: width, child: _optionCard(draft, option)),
            ]);
          }),
        if (daily) ...[
          const SizedBox(height: 10),
          _choiceCard(
            key: const Key('option-daily'),
            selected: draft.isDaily,
            onTap: () => setState(() => _draft = draft.pickOption(SubscriptionDraft.dailyKey)),
            child: Row(children: [
              Icon(draft.isDaily ? LucideIcons.circleCheck : LucideIcons.wallet,
                  size: 20, color: draft.isDaily ? _brand : AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('يوم واحد', style: AppTextStyles.titleMedium.copyWith(color: _ink)),
                  Text('الدفع نقداً في الباص',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
                ]),
              ),
              Text(_money(line.dailyPrice),
                  style: AppTextStyles.titleMedium.copyWith(color: _brand)),
            ]),
          ),
        ],
      ],
      _next('التالي', draft.optionKey == null ? null : () => _go(DraftStep.review)),
    ]);
  }

  Widget _optionCard(SubscriptionDraft draft, SaleOption option) {
    final selected = draft.optionKey == option.key;
    return InkWell(
      key: Key('option-${option.option}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _draft = draft.pickOption(option.key)),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF4FB) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? _brand : const Color(0xFFE6EEF3), width: selected ? 1.6 : 1)),
        child: Column(children: [
          Text(option.title,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: _ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(_money(option.price),
              style: AppTextStyles.titleMedium.copyWith(color: _brand)),
          if (option.isUpcoming) ...[
            const SizedBox(height: 6),
            Text('الفترة القادمة',
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSmall
                    .copyWith(color: const Color(0xFF3F51B5), fontWeight: FontWeight.w600)),
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
      _heading('راجع اختياراتك', 'يمكنك تعديل أي اختيار قبل التأكيد.'),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 14),
        decoration: BasakUi.card(),
        child: Column(children: [
          _reviewRow(LucideIcons.building2, 'شركة النقل', company.name, DraftStep.company),
          _reviewRow(LucideIcons.busFront, 'الخط', line.name, DraftStep.line),
          _reviewRow(LucideIcons.graduationCap, 'الجامعة', line.university ?? '—', null),
          _reviewRow(LucideIcons.mapPin, 'محطة الصعود', station.name, DraftStep.station),
          _reviewRow(LucideIcons.calendarDays, 'الفترة',
              option?.title ?? 'يوم واحد (نقداً في الباص)', DraftStep.period),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsetsDirectional.only(end: 8),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
                color: const Color(0xFFF1F6FB), borderRadius: BorderRadius.circular(13)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text('المبلغ', style: AppTextStyles.bodyMedium)),
              Text(_money(amount),
                  key: const Key('review-amount'),
                  style: AppTextStyles.titleLarge.copyWith(color: _brand)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Text(
          draft.isDaily
              ? 'بعد التأكيد يُفعّل اشتراك اليوم مباشرة وتدفع نقداً للمشرف في الباص.'
              : 'بعد التأكيد يُنشأ طلب الاشتراك وتنتقل للدفع، ولا يمكن تغيير هذه الاختيارات بعدها.',
          style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: ElevatedButton(
          key: const Key('flow-confirm'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _brand,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: _submitting ? null : () => _confirm(catalog),
          child: _submitting
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Text(draft.isDaily ? 'تأكيد اشتراك اليوم' : 'تأكيد والانتقال للدفع'),
        ),
      ),
    ]);
  }

  Widget _reviewRow(IconData icon, String label, String value, DraftStep? edit) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 18, color: _brand),
          const SizedBox(width: 9),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
              Text(value,
                  style: AppTextStyles.bodyMedium.copyWith(color: _ink, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (edit != null)
            TextButton(
              key: Key('review-edit-${edit.name}'),
              onPressed: _submitting ? null : () => _go(edit),
              child: const Text('تعديل'),
            )
          else
            const SizedBox(height: 48),
        ]),
      );
}
