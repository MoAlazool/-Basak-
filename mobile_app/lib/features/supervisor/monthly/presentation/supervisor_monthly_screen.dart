import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/basak_ui.dart' show BasakUi;
import '../../../../core/widgets/skeleton.dart';
import '../../data/supervisor_repository.dart';
import '../../models/supervisor_models.dart';
import '../../supervisor_copy.dart';

/// «ملخص الشهر», a page under the account tab: the supervisor's scanning
/// month, computed on the server from the real scan log
/// (`supervisor_scan_events`) and the rides students confirmed.
class SupervisorMonthlyScreen extends ConsumerStatefulWidget {
  /// The month shown first; the current one unless a test says otherwise.
  final DateTime? month;

  const SupervisorMonthlyScreen({super.key, this.month});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const SupervisorMonthlyScreen()));

  @override
  ConsumerState<SupervisorMonthlyScreen> createState() => _SupervisorMonthlyScreenState();
}

class _SupervisorMonthlyScreenState extends ConsumerState<SupervisorMonthlyScreen> {
  late DateTime _month = DateTime((widget.month ?? DateTime.now()).year, (widget.month ?? DateTime.now()).month);

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  void _shift(int months) => setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(supervisorMonthlySummaryProvider(_month));
    final value = summary.valueOrNull;
    return Scaffold(
      backgroundColor: context.colors.ground,
      body: BasakPage(
        header: const BasakBackHeader(title: 'ملخص الشهر', inlineTitle: true),
        onRefresh: () async {
          ref.invalidate(supervisorMonthlySummaryProvider(_month));
          try {
            await ref.read(supervisorMonthlySummaryProvider(_month).future);
          } catch (_) {
            // Said by the page itself.
          }
        },
        children: [
          // The switcher stays usable whatever the month holds.
          MonthSwitcher(
            label: '${BasakUi.arabicMonths[_month.month - 1]} ${_month.year}',
            onPrevious: () => _shift(-1),
            onNext: _isCurrentMonth ? null : () => _shift(1),
          ),
          if (value != null)
            ..._content(value)
          else if (summary.hasError)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: BasakSpace.s24),
              child: EmptyState(
                icon: LucideIcons.wifiOff,
                title: 'تعذّر تحميل الملخص',
                message: 'تحقّق من الاتصال بالإنترنت ثم أعد المحاولة.',
                actionLabel: 'إعادة المحاولة',
                onAction: () => ref.invalidate(supervisorMonthlySummaryProvider(_month)),
              ),
            )
          else
            const MonthlySkeleton(),
        ],
      ),
    );
  }

  List<Widget> _content(SupervisorMonthlySummary s) {
    if (s.scans == 0 && s.confirmedRides == 0) {
      return [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: BasakSpace.s24),
          child: EmptyState(
            key: const Key('monthly-empty'),
            page: true,
            icon: LucideIcons.calendarX2,
            title: 'لا يوجد نشاط في هذا الشهر',
            message: _isCurrentMonth
                ? 'ابدأ بمسح رموز الطلاب من تبويب «مسح» وستظهر الأرقام هنا.'
                : 'لم تُسجَّل عمليات مسح خلال هذا الشهر.',
          ),
        ),
      ];
    }
    final rate = s.attendanceRate;
    final today = DateTime.now();
    final days = [
      for (final d in s.days)
        if (d.checkins > 0)
          DayBar(
            label: '${d.date.day}',
            lower: d.departure,
            upper: d.returning,
            emphasised: DateUtils.isSameDay(d.date, today),
          ),
    ];
    final stops = s.stations.take(6).toList();
    final severalLines = stops.map((stop) => stop.line).toSet().length > 1;
    final busiest = stops.isEmpty ? 0 : stops.first.checkins;
    String n(int value) => SupervisorCopy.grouped(value);

    Widget meters(List<Meter> rows) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: context.colors.hairline),
              rows[i],
            ],
          ],
        );

    Widget tiles(StatTile first, StatTile second) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: first),
              const SizedBox(width: BasakSpace.s8),
              Expanded(child: second),
            ],
          ),
        );

    return [
      MonthHero(
        label: 'تسجيلات الصعود',
        total: n(s.checkins),
        rate: rate == null ? null : '${(rate * 100).round()}%',
        rateCaption: 'من الركوب المؤكَّد',
        split: [('ذهاب', n(s.departureCheckins)), ('عودة', n(s.returnCheckins))],
      ),
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tiles(
            StatTile(
              value: n(s.uniqueStudents),
              label: SupervisorCopy.noun(s.uniqueStudents,
                  one: 'طالب مختلف',
                  two: 'طالبان مختلفان',
                  few: 'طلاب مختلفين',
                  many: 'طالباً مختلفاً',
                  hundred: 'طالب مختلف'),
            ),
            StatTile(
              value: n(s.activeDays),
              label: SupervisorCopy.noun(s.activeDays,
                  one: 'يوم عمل', two: 'يوما عمل', few: 'أيام عمل', many: 'يوم عمل', hundred: 'يوم عمل'),
            ),
          ),
          const SizedBox(height: BasakSpace.s8),
          tiles(
            StatTile(
              value: n(s.scans),
              label: SupervisorCopy.noun(s.scans,
                  one: 'عملية مسح',
                  two: 'عمليتا مسح',
                  few: 'عمليات مسح',
                  many: 'عملية مسح',
                  hundred: 'عملية مسح'),
            ),
            StatTile(
              value: n(s.confirmedRides),
              label: SupervisorCopy.noun(s.confirmedRides,
                  one: 'ركوب مؤكَّد',
                  two: 'ركوبان مؤكَّدان',
                  few: 'مرات ركوب مؤكَّد',
                  many: 'ركوباً مؤكَّداً',
                  hundred: 'ركوب مؤكَّد'),
            ),
          ),
        ],
      ),
      if (days.isNotEmpty)
        TitledCard(
          title: 'الصعود اليومي',
          trailing: DayBars.legend(context, lower: 'ذهاب', upper: 'عودة'),
          child: DayBars(
            days: days,
            semanticLabel: 'الصعود في كل يوم عمل من ${BasakUi.arabicMonths[_month.month - 1]}',
          ),
        ),
      TitledCard(
        title: 'نتائج المسح',
        child: meters([
          Meter(
            label: 'صعود مسجَّل',
            value: n(s.checkins),
            share: s.scans == 0 ? 0 : s.checkins / s.scans,
            tone: BasakTone.success,
          ),
          Meter(
            label: 'مسح مكرَّر',
            value: n(s.duplicateScans),
            share: s.scans == 0 ? 0 : s.duplicateScans / s.scans,
          ),
          Meter(
            label: 'مسح مرفوض',
            value: n(s.rejectedScans),
            share: s.scans == 0 ? 0 : s.rejectedScans / s.scans,
            tone: BasakTone.danger,
          ),
        ]),
      ),
      if (stops.isNotEmpty)
        TitledCard(
          title: 'أكثر المحطات صعوداً',
          child: meters([
            for (final stop in stops)
              Meter(
                // With several lines a stop's name alone may not tell it apart.
                label: severalLines && stop.line.isNotEmpty ? '${stop.station} · ${stop.line}' : stop.station,
                value: n(stop.checkins),
                share: busiest == 0 ? 0 : stop.checkins / busiest,
              ),
          ]),
        ),
    ];
  }
}
