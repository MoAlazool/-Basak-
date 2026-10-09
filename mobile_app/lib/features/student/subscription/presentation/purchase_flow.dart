import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/network_errors.dart';
import '../../../../core/sync/own_changes.dart';
import '../../../../core/sync/session.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/basak_ui.dart' show BasakUi;
import '../../../../core/widgets/skeleton.dart';
import '../../home/presentation/student_home_screen.dart';
import '../../qr/presentation/student_qr_screen.dart';
import '../models/sale_catalog.dart';
import '../models/subscription_draft.dart';
import '../models/subscription_model.dart';
import 'confirm_sheet.dart';
import 'station_sheet.dart';
import 'subscription_screen.dart';

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

/// "8,000 ج.م"
String formatMoney(double value) {
  final digits = value.toStringAsFixed(0);
  final grouped = digits.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return '$grouped ج.م';
}

/// The number of an amount without its currency ("8,000"), where the
/// currency is drawn apart from it.
String _amount(double value) => formatMoney(value).replaceFirst(RegExp(r'\s*ج\.م$'), '');

/// Periods in the order a student thinks of them, not by date.
const _optionOrder = ['first', 'second', 'both', 'summer'];
List<SaleOption> _ordered(List<SaleOption> options) => [...options]
  ..sort((a, b) => _optionOrder.indexOf(a.option).compareTo(_optionOrder.indexOf(b.option)));

/// "20 سبتمبر 2026"
String _day(String iso, {bool year = true}) {
  final date = DateTime.tryParse(iso);
  if (date == null) return iso;
  return '${date.day} ${BasakUi.arabicMonths[date.month - 1]}${year ? ' ${date.year}' : ''}';
}

/// "من 20 سبتمبر 2026 إلى 14 يناير 2027"; the year is said once when both
/// days share it.
String _range(SaleOption option) {
  final from = DateTime.tryParse(option.startDate);
  final to = DateTime.tryParse(option.endDate);
  return 'من ${_day(option.startDate, year: from?.year != to?.year)} إلى ${_day(option.endDate)}';
}

/// "4 خطوط إلى جامعتك"
String _linesLabel(int count) => switch (count) {
      1 => 'خط واحد إلى جامعتك',
      2 => 'خطّان إلى جامعتك',
      <= 10 => '$count خطوط إلى جامعتك',
      _ => '$count خطاً إلى جامعتك',
    };

/// The university without the word "جامعة", as the pass names it.
String _shortUniversity(String? name) {
  final short = (name ?? '').trim().replaceFirst(RegExp(r'^(جامعة|جامعه)\s+'), '');
  return short.isEmpty ? 'جامعتك' : short;
}

/// The subscribe builder: one screen, "اشتراك جديد — إلى جامعة …".
///
/// Company → line and boarding station (one gesture, through the station
/// sheet) → period → review (a sheet). The open step shows its options on the
/// ground, a chosen one collapses to a row with "تغيير", a future one is
/// sunken. The student changes any choice freely: the choices are a
/// [SubscriptionDraft] held here, a later choice that still applies is kept,
/// and nothing is written until "تأكيد والانتقال للدفع" on the review.
///
/// Given a bounded height it is a whole page with its own scroll: above the
/// tabs ([PurchaseFlowPage], with a way out) the review button is docked at
/// the bottom; as a tab's own page (no [onCancel]) the button follows the
/// content and the page leaves room for the tab bar. Inside a scrolling
/// parent it lays itself out as a column.
class PurchaseFlow extends ConsumerStatefulWidget {
  /// Choices to start from (e.g. the line and station of the running
  /// subscription when paying the next period). A complete set opens the
  /// review at once.
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

  /// The step whose options are on screen: company, line (which settles the
  /// station too) or period (whose review is a sheet).
  late DraftStep _step = _section(widget.initial.firstOpenStep);
  bool _submitting = false;

  /// A complete set of choices to start from goes straight to the review, once.
  late bool _reviewOffered = widget.initial.firstOpenStep != DraftStep.review;

  /// The catalog as last shown (null: the flow has not been on screen yet).
  AsyncValue<SaleCatalog>? _shown;

  /// The builder's row a draft step belongs to.
  static DraftStep _section(DraftStep step) => switch (step) {
        DraftStep.station => DraftStep.line,
        DraftStep.review => DraftStep.period,
        _ => step,
      };

  bool _sells(SaleLine line) =>
      line.stations.any((s) => s.departures.isNotEmpty) &&
      (line.options.isNotEmpty || (widget.allowDaily && line.dailyEnabled));

  /// The period of a line that sells exactly one thing: nothing to choose.
  String? _onlyOption(SaleLine line) =>
      line.options.length == 1 && !(widget.allowDaily && line.dailyEnabled) ? line.options.single.key : null;

  void _go(DraftStep step) {
    if (_draft.canOpen(step) && !_submitting) setState(() => _step = step);
  }

  /// Takes a choice and opens what is still missing after it.
  void _choose(SubscriptionDraft next) => setState(() {
        _draft = next;
        _step = _section(next.firstOpenStep);
      });

  bool _canStepBack(SaleCatalog catalog, DraftStep step) =>
      step == DraftStep.period || (step == DraftStep.line && catalog.companies.length > 1);

  /// One step back; from the first one, out of the flow.
  void _back(SaleCatalog catalog, SubscriptionDraft draft, DraftStep step) {
    if (_submitting) return;
    if (step == DraftStep.period && draft.isDaily) {
      // Back from the cash day to the periods.
      setState(() => _draft =
          SubscriptionDraft(companyId: draft.companyId, lineId: draft.lineId, stationId: draft.stationId));
    } else if (_canStepBack(catalog, step)) {
      setState(() => _step = step == DraftStep.period ? DraftStep.line : DraftStep.company);
    } else {
      widget.onCancel?.call();
    }
  }

  /// Line and station in one gesture: the stop chosen in the sheet settles both.
  Future<void> _pickLine(SaleCatalog catalog, SubscriptionDraft draft, SaleLine line) async {
    final onLine = draft.pickLine(catalog, line.id);
    final stationId = await StationSheet.show(context, line: line, selected: onLine.stationId);
    if (stationId == null || !mounted) return;
    _choose(onLine.pickStation(stationId));
  }

  Future<void> _review(SaleCatalog catalog, SubscriptionDraft draft) async {
    final request = SubscriptionRequest.from(draft, catalog);
    final company = catalog.company(draft.companyId);
    final line = catalog.line(draft.lineId);
    final station = line?.station(draft.stationId);
    final option = line?.option(draft.optionKey);
    if (request == null || company == null || line == null || station == null || option == null || _submitting) {
      return;
    }
    final create = ref.read(subscriptionCreatorProvider);
    SubscriptionModel? created;
    Object? failure;
    var asked = false;
    final answered = Completer<void>();
    await ConfirmSheet.show(
      context,
      station: station.name,
      university: _shortUniversity(line.university ?? catalog.universityName),
      line: line.name,
      company: company.name,
      period: option.title,
      validUntil: option.endDate.isEmpty ? null : _day(option.endDate),
      amount: option.price,
      onConfirm: () async {
        asked = true;
        if (mounted) setState(() => _submitting = true);
        try {
          created = await create(request);
        } catch (e) {
          failure = e;
        } finally {
          answered.complete();
        }
      },
    );
    // Closed without confirming: the choices stay as they are.
    if (!asked) return;
    await answered.future;
    _finish(created, failure);
  }

  /// A cash day has nothing to review or pay here: it is confirmed in place.
  Future<void> _confirmDaily(SaleCatalog catalog, SubscriptionDraft draft) async {
    final request = SubscriptionRequest.from(draft, catalog);
    if (request == null || _submitting) return;
    setState(() => _submitting = true);
    SubscriptionModel? created;
    Object? failure;
    try {
      created = await ref.read(subscriptionCreatorProvider)(request);
    } catch (e) {
      failure = e;
    }
    _finish(created, failure);
  }

  void _finish(SubscriptionModel? created, Object? failure) {
    if (!mounted) return;
    setState(() => _submitting = false);
    if (created != null) {
      widget.onCreated(created);
      return;
    }
    // The offer may have changed since it was shown: read it again.
    ref.invalidate(saleCatalogProvider);
    if (failure != null) BasakToast.show(context, errorMessage(failure), kind: BasakToastKind.failure);
  }

  // Its own Material, so its text and controls read the same whether the
  // host is a route's Scaffold or a tab's bare page.
  @override
  Widget build(BuildContext context) => Material(type: MaterialType.transparency, child: _content());

  Widget _content() {
    // Watched only while on screen: behind another tab nothing is read, and a
    // change that marks the catalog stale waits until the flow is shown again.
    if (widget.visible) _shown = ref.watch(saleCatalogProvider);
    final catalogAsync = _shown;
    if (catalogAsync == null) return _waiting(const PurchaseFlowSkeleton());
    return catalogAsync.when(
      loading: () => _waiting(const PurchaseFlowSkeleton()),
      error: (e, _) => _waiting(Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(null),
          InlineError(
            message: 'تعذر تحميل الشركات والخطوط: ${errorMessage(e)}',
            onRetry: () => ref.invalidate(saleCatalogProvider),
          ),
        ],
      )),
      data: (catalog) {
        // Whatever was chosen and is no longer offered is dropped.
        var draft = _draft.reconciled(catalog);
        // One company leaves nothing to choose: it starts chosen and collapsed.
        final soleCompany = catalog.companies.length == 1;
        if (draft.companyId == null && soleCompany) {
          draft = draft.pickCompany(catalog, catalog.companies.single.id);
        }
        // So does the one period of a line that sells nothing else.
        final chosenLine = catalog.line(draft.lineId);
        if (chosenLine != null && draft.stationId != null && draft.optionKey == null) {
          final only = _onlyOption(chosenLine);
          if (only != null) draft = draft.pickOption(only);
        }
        var step = draft.canOpen(_step) ? _step : _section(draft.firstOpenStep);
        if (step == DraftStep.company && soleCompany) step = _section(draft.firstOpenStep);
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
        if (!_reviewOffered && widget.visible) {
          _reviewOffered = true;
          if (draft.firstOpenStep == DraftStep.review && !draft.isDaily) {
            final complete = draft;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _review(catalog, complete);
            });
          }
        }
        final Widget page;
        if (catalog.companies.isEmpty) {
          page = _empty(catalog);
        } else if (step == DraftStep.period && draft.isDaily) {
          page = _dailyPage(catalog, draft);
        } else {
          page = _builder(catalog, draft, step);
        }
        return PopScope(
          canPop: widget.onCancel == null && !(catalog.companies.isNotEmpty && _canStepBack(catalog, step)),
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back(catalog, draft, step);
          },
          child: page,
        );
      },
    );
  }

  // ── Frame ──────────────────────────────────────────────────────────

  /// A whole page when the height is bounded, a column inside a scrolling
  /// parent otherwise. [dock] holds the route's one primary button.
  Widget _frame({Widget? header, required List<Widget> children, Widget? dock}) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.hasBoundedHeight) {
            // With no way out the builder is a tab's own page (a student who
            // never subscribed): the tab bar floats over its end, so the
            // button follows the content instead of sitting in a dock.
            final tab = widget.onCancel == null;
            return BasakPage(
              header: header,
              spacing: 0,
              bottomInset: tab ? BasakPage.tabBarClearance : BasakSpace.s24,
              dock: dock == null || tab ? null : BasakDock(child: dock),
              children: [
                ...children,
                if (dock != null && tab) ...[const SizedBox(height: BasakSpace.s20), dock],
              ],
            );
          }
          return MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (header != null) ...[header, const SizedBox(height: BasakSpace.s16)],
                ...children,
                if (dock != null) ...[const SizedBox(height: BasakSpace.s20), dock],
              ],
            ),
          );
        },
      );

  /// Before the catalog is there (or when it could not be read): the way out
  /// still works.
  Widget _waiting(Widget child) => PopScope(
        canPop: widget.onCancel == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) widget.onCancel?.call();
        },
        child: _frame(header: _close(), children: [child]),
      );

  /// The round close button of the builder.
  Widget? _close() => widget.onCancel == null
      ? null
      : Align(
          alignment: AlignmentDirectional.centerStart,
          child: BasakIconButton(
            key: const Key('flow-back'),
            icon: LucideIcons.x,
            label: 'إغلاق',
            onPressed: _submitting ? null : widget.onCancel,
          ),
        );

  /// A back button with the page's name beside it: the pages that are not
  /// the builder itself (the cash day, an empty catalogue).
  Widget _backHeader(VoidCallback? onBack) => Builder(builder: (context) {
        final rtl = Directionality.of(context) == TextDirection.rtl;
        return Row(
          children: [
            if (onBack != null) ...[
              BasakIconButton(
                key: const Key('flow-back'),
                icon: rtl ? LucideIcons.arrowRight : LucideIcons.arrowLeft,
                label: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: _submitting ? null : onBack,
              ),
              const SizedBox(width: BasakSpace.s12),
            ],
            Expanded(
              child: Semantics(
                header: true,
                child: Text('اشتراك جديد',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.sheetTitle),
              ),
            ),
          ],
        );
      });

  /// "اشتراك جديد" and where it goes. The university is context, not a step.
  Widget _title(String? university) => Builder(
        builder: (context) => Padding(
          padding: const EdgeInsetsDirectional.only(top: BasakSpace.s4, bottom: BasakSpace.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(header: true, child: Text('اشتراك جديد', style: context.text.display)),
              const SizedBox(height: BasakSpace.s4),
              Text('إلى ${university ?? 'جامعتك'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.body.copyWith(color: context.colors.ink2)),
            ],
          ),
        ),
      );

  static const _gap = SizedBox(height: BasakSpace.s10);

  // ── The builder ────────────────────────────────────────────────────

  Widget _builder(SaleCatalog catalog, SubscriptionDraft draft, DraftStep step) {
    final company = catalog.company(draft.companyId);
    final line = company == null ? null : catalog.line(draft.lineId);
    final station = line?.station(draft.stationId);
    final option = line?.option(draft.optionKey);
    final ready = step == DraftStep.period && option != null;

    return _frame(
      header: _close(),
      dock: ready
          ? BasakButton(
              key: const Key('flow-review'),
              label: 'مراجعة الاشتراك',
              onPressed: _submitting ? null : () => _review(catalog, draft),
            )
          : null,
      children: [
        _title(catalog.universityName),

        // 1 · Company
        if (step == DraftStep.company)
          _companies(catalog, draft)
        else
          BuilderRow(
            key: const Key('flow-row-company'),
            state: BuilderRowState.chosen,
            step: 1,
            title: 'شركة النقل',
            value: company?.name,
            onChange: catalog.companies.length > 1 ? () => _go(DraftStep.company) : null,
          ),
        _gap,

        // 2 · Line and station
        if (step == DraftStep.line && company != null)
          _lines(catalog, draft, company)
        else if (line != null && station != null)
          BuilderRow(
            key: const Key('flow-row-line'),
            state: BuilderRowState.chosen,
            step: 2,
            title: 'الخط والمحطة',
            value: '${line.name} · ${station.name}',
            onChange: () => _go(DraftStep.line),
          )
        else
          const BuilderRow(state: BuilderRowState.locked, step: 2, title: 'الخط والمحطة'),
        _gap,

        // 3 · Period
        if (step == DraftStep.period && line != null)
          _periods(draft, line)
        else if (line != null && station != null && draft.optionKey != null)
          BuilderRow(
            key: const Key('flow-row-period'),
            state: BuilderRowState.chosen,
            step: 3,
            title: 'الفترة',
            value: option == null
                ? 'يوم واحد · ${formatMoney(line.dailyPrice)}'
                : '${option.title} · ${formatMoney(option.price)}',
            onChange: () => _go(DraftStep.period),
          )
        else
          const BuilderRow(state: BuilderRowState.locked, step: 3, title: 'الفترة'),
      ],
    );
  }

  Widget _companies(SaleCatalog catalog, SubscriptionDraft draft) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: BasakSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BuilderStepHead(step: 1, title: 'شركة النقل'),
            for (final company in catalog.companies) ...[
              _gap,
              CompanyRow(
                key: Key('company-${company.id}'),
                name: company.name,
                caption: _linesLabel(company.lines.length),
                onTap: () => _choose(draft.pickCompany(catalog, company.id)),
              ),
            ],
          ],
        ),
      );

  /// The company's lines as cards that compare by eye. A line that cannot be
  /// bought now sinks to the end and is not tappable.
  Widget _lines(SaleCatalog catalog, SubscriptionDraft draft, SaleCompany company) {
    final onSale = company.lines.where(_sells).toList();
    final closed = company.lines.where((l) => !_sells(l)).toList();
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: BasakSpace.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BuilderStepHead(step: 2, title: 'الخط والمحطة'),
          if (company.lines.isEmpty) ...[
            _gap,
            InlineError(
              message: 'لا توجد رحلات متاحة لجامعتك على هذا الخط.',
              retryLabel: 'تحديث',
              onRetry: () => ref.invalidate(saleCatalogProvider),
            ),
          ],
          for (final line in onSale) ...[
            _gap,
            LineCard(
              key: Key('line-${line.id}'),
              name: line.name,
              stops: StationSheet.stopsLabel(line.stations.length),
              fromPrice: _amount(line.fromPrice ?? line.dailyPrice),
              firstDeparture: BasakUi.time12(line.firstDeparture),
              lastReturn: BasakUi.time12(line.lastReturn),
              tag: widget.allowDaily && line.dailyEnabled ? 'يومي متاح' : null,
              onTap: _submitting ? null : () => _pickLine(catalog, draft, line),
            ),
          ],
          for (final line in closed) ...[
            _gap,
            line.stations.any((s) => s.departures.isNotEmpty)
                ? LineCard.unavailable(
                    key: Key('line-${line.id}'),
                    name: line.name,
                    stops: StationSheet.stopsLabel(line.stations.length),
                    reason: 'الاشتراك مغلق حالياً',
                  )
                : LineCard.unavailable(
                    key: Key('line-${line.id}'),
                    name: line.name,
                    stops: '',
                    reason: 'لا توجد رحلات متاحة لجامعتك على هذا الخط.',
                  ),
          ],
        ],
      ),
    );
  }

  /// What paying both semesters at once saves, when both single prices are
  /// on sale too.
  double _saving(SaleLine line, SaleOption option) {
    if (option.option != 'both') return 0;
    final first = line.options.where((o) => o.option == 'first').firstOrNull;
    final second = line.options.where((o) => o.option == 'second').firstOrNull;
    if (first == null || second == null) return 0;
    return first.price + second.price - option.price;
  }

  /// The one tag a period carries: what the bundle saves, or that the period
  /// has not started yet.
  (String, BasakTone)? _periodTag(SaleLine line, SaleOption option) {
    final saved = _saving(line, option);
    if (saved > 0) return ('وفّر ${_amount(saved)}', BasakTone.success);
    if (option.isUpcoming) return ('الفترة القادمة', BasakTone.info);
    return null;
  }

  /// One period fills the row, two share it, three sit in one row, four make
  /// a 2 × 2 grid. The cash day is a quiet row under them.
  Widget _periods(SubscriptionDraft draft, SaleLine line) {
    final options = _ordered(line.options);
    final daily = widget.allowDaily && line.dailyEnabled;
    final chosen = line.option(draft.optionKey);
    return Builder(
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BuilderStepHead(step: 3, title: 'الفترة'),
          const SizedBox(height: BasakSpace.s14),
          if (options.isEmpty && !daily)
            InlineError(
              message: 'لا توجد فترة متاحة للاشتراك الآن على هذا الخط.',
              retryLabel: 'تحديث',
              onRetry: () => ref.invalidate(saleCatalogProvider),
            ),
          if (options.isNotEmpty)
            Semantics(
              container: true,
              label: 'فترة الاشتراك',
              child: ChoiceGrid(
                columns: options.length == 4 ? 2 : null,
                children: [
                  for (final option in options)
                    PeriodTile(
                      key: Key('option-${option.option}'),
                      label: option.title,
                      amount: _amount(option.price),
                      selected: draft.optionKey == option.key,
                      tag: _periodTag(line, option)?.$1,
                      tagTone: _periodTag(line, option)?.$2 ?? BasakTone.success,
                      onTap: _submitting ? null : () => _choose(draft.pickOption(option.key)),
                    ),
                ],
              ),
            ),
          if (chosen != null) ...[
            const SizedBox(height: BasakSpace.s14),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s4),
              child: Text(_range(chosen),
                  key: const Key('option-dates'),
                  style: context.text.label.copyWith(color: context.colors.ink2, fontWeight: FontWeight.w400)),
            ),
          ],
          if (daily) ...[
            if (options.isNotEmpty) const SizedBox(height: BasakSpace.s14),
            QuietPriceRow(
              key: const Key('option-daily'),
              label: options.isEmpty ? 'يوم واحد، نقداً في الباص' : 'أو يوم واحد، نقداً في الباص',
              value: formatMoney(line.dailyPrice),
              onTap: _submitting ? null : () => _choose(draft.pickOption(SubscriptionDraft.dailyKey)),
            ),
          ],
        ],
      ),
    );
  }

  // ── The cash day ───────────────────────────────────────────────────

  /// The one-day cash subscription, chosen: what was picked, the periods as
  /// a list with the day among them, what a cash day means, and its own
  /// confirmation. Nothing is paid or uploaded for it.
  Widget _dailyPage(SaleCatalog catalog, SubscriptionDraft draft) {
    final company = catalog.company(draft.companyId)!;
    final line = catalog.line(draft.lineId)!;
    final station = line.station(draft.stationId)!;
    return _frame(
      header: _backHeader(() => _back(catalog, draft, DraftStep.period)),
      dock: BasakButton(
        key: const Key('flow-confirm'),
        label: 'تأكيد اشتراك اليوم',
        loading: _submitting,
        onPressed: () => _confirmDaily(catalog, draft),
      ),
      children: [
        const SizedBox(height: BasakSpace.s4),
        InfoRows(rows: [
          InfoRow(label: 'الشركة', value: company.name),
          InfoRow(label: 'الخط والمحطة', value: '${line.name} · ${station.name}'),
        ]),
        const SizedBox(height: BasakSpace.s16),
        Builder(
          builder: (context) => Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s4),
            child: Text('الفترة', style: context.text.label.copyWith(color: context.colors.ink2)),
          ),
        ),
        const SizedBox(height: BasakSpace.s16),
        for (final option in _ordered(line.options)) ...[
          PeriodRow(
            key: Key('option-${option.option}'),
            title: option.title,
            caption: 'حتى ${_day(option.endDate)}',
            amount: _amount(option.price),
            tag: _periodTag(line, option)?.$1,
            tagTone: _periodTag(line, option)?.$2 ?? BasakTone.success,
            selected: false,
            onTap: _submitting ? null : () => _choose(draft.pickOption(option.key)),
          ),
          const SizedBox(height: BasakSpace.s8),
        ],
        PeriodRow(
          key: const Key('option-daily'),
          title: 'يوم واحد',
          caption: 'اليوم فقط · الدفع نقداً في الباص',
          amount: _amount(line.dailyPrice),
          tag: 'نقداً',
          tagTone: BasakTone.warning,
          selected: true,
          onTap: () {},
        ),
        const SizedBox(height: BasakSpace.s16),
        const BasakCard(
          radius: BasakRadius.control,
          padding: EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s14),
          child: InfoNote(
            'اشتراك اليوم يظهر فقط لمن ليس له اشتراك مفتوح. لا يحتاج تحويلاً ولا إيصالاً: تدفع للمشرف عند الصعود.',
            icon: LucideIcons.banknote,
          ),
        ),
      ],
    );
  }

  // ── Nothing on sale ────────────────────────────────────────────────

  /// No company runs a line to the student's university yet.
  Widget _empty(SaleCatalog catalog) {
    final state = EmptyState(
      page: true,
      icon: LucideIcons.bus,
      title: 'لا توجد خطوط لجامعتك بعد',
      message: 'لا توجد حالياً شركات أو خطوط متاحة '
          '${catalog.universityName == null ? 'لجامعتك' : 'ل${catalog.universityName}'}. تظهر هنا فور إضافتها.',
      actionLabel: 'تحديث',
      actionIcon: LucideIcons.refreshCw,
      onAction: () => ref.invalidate(saleCatalogProvider),
    );
    final header = _backHeader(widget.onCancel);
    return LayoutBuilder(builder: (context, constraints) {
      if (!constraints.hasBoundedHeight) {
        return _frame(header: header, children: [
          const SizedBox(height: BasakSpace.s40),
          state,
          const SizedBox(height: BasakSpace.s40),
        ]);
      }
      return MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: ColoredBox(
          color: context.colors.ground,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      BasakSpace.gutter, BasakSpace.s12, BasakSpace.gutter, BasakSpace.s24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      Expanded(child: Center(child: SingleChildScrollView(child: state))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// The builder as a route of its own, above the tabs: the boards draw it
/// without the tab bar, closed by the round button at its top.
class PurchaseFlowPage extends StatelessWidget {
  final SubscriptionDraft initial;
  final bool allowDaily;

  const PurchaseFlowPage({super.key, this.initial = const SubscriptionDraft(), this.allowDaily = true});

  /// Opens the builder; completes with the subscription it created, or null
  /// when the student left without one.
  static Future<SubscriptionModel?> open(BuildContext context,
          {SubscriptionDraft initial = const SubscriptionDraft(), bool allowDaily = true}) =>
      Navigator.of(context).push<SubscriptionModel>(MaterialPageRoute(
        builder: (_) => PurchaseFlowPage(initial: initial, allowDaily: allowDaily),
      ));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.colors.ground,
        body: PurchaseFlow(
          initial: initial,
          allowDaily: allowDaily,
          onCancel: () => Navigator.of(context).pop(),
          onCreated: (created) => Navigator.of(context).pop(created),
        ),
      );
}
