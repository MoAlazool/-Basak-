import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/basak_ui.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../data/supervisor_repository.dart';
import '../../models/supervisor_models.dart';

const _departureColor = BasakUi.teal;
const _returnColor = Color(0xFFF2A93B);

/// Tab 3 — the supervisor's monthly activity, computed server-side from the
/// real scan log (supervisor_scan_events) and students' ride confirmations.
class SupervisorMonthlyScreen extends ConsumerStatefulWidget {
  const SupervisorMonthlyScreen({super.key});

  @override
  ConsumerState<SupervisorMonthlyScreen> createState() => _SupervisorMonthlyScreenState();
}

class _SupervisorMonthlyScreenState extends ConsumerState<SupervisorMonthlyScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  void _shift(int months) => setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(supervisorMonthlySummaryProvider(_month));
    return GlassScaffold(
      body: BasakPage(
        onRefresh: () async {
          ref.invalidate(supervisorMonthlySummaryProvider(_month));
          await ref.read(supervisorMonthlySummaryProvider(_month).future);
        },
        children: [
          const BasakPageHeader(
            title: 'الملخص الشهري',
            subtitle: 'نشاطك في المسح وتسجيل الصعود',
          ),
          const SizedBox(height: 16),
          _monthSwitcher(),
          const SizedBox(height: 14),
          summary.when(
            loading: () => const BasakLoadingCard(height: 360),
            error: (_, __) => BasakMessageCard(
              icon: LucideIcons.wifiOff,
              title: 'تعذر تحميل الملخص',
              message: 'تحقق من الاتصال بالإنترنت ثم أعد المحاولة.',
              actionLabel: 'إعادة المحاولة',
              onAction: () => ref.invalidate(supervisorMonthlySummaryProvider(_month)),
            ),
            data: _content,
          ),
        ],
      ),
    );
  }

  Widget _monthSwitcher() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BasakUi.card(radius: 18),
        child: Row(children: [
          IconButton(
            tooltip: 'الشهر السابق',
            onPressed: () => _shift(-1),
            icon: const Icon(LucideIcons.chevronRight, color: BasakUi.teal),
          ),
          Expanded(
            child: Text('${BasakUi.arabicMonths[_month.month - 1]} ${_month.year}',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleMedium.copyWith(color: BasakUi.ink)),
          ),
          IconButton(
            tooltip: 'الشهر التالي',
            onPressed: _isCurrentMonth ? null : () => _shift(1),
            icon: Icon(LucideIcons.chevronLeft,
                color: _isCurrentMonth ? BasakUi.muted.withOpacity(.4) : BasakUi.teal),
          ),
        ]),
      );

  Widget _content(SupervisorMonthlySummary s) {
    if (s.scans == 0 && s.confirmedRides == 0) {
      return BasakMessageCard(
        icon: LucideIcons.calendarX2,
        title: 'لا يوجد نشاط في هذا الشهر',
        message: _isCurrentMonth
            ? 'ابدأ بمسح بطاقات الطلاب من تبويب "مسح QR" وستظهر الإحصائيات هنا.'
            : 'لم تُسجل عمليات مسح خلال هذا الشهر.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heroCard(s),
        const SizedBox(height: 14),
        BasakStatGrid(tiles: [
          BasakStatTile(
              icon: LucideIcons.userCheck, value: '${s.uniqueStudents}', label: 'طالب مختلف صعد'),
          BasakStatTile(
              icon: LucideIcons.scanLine,
              value: '${s.scans}',
              label: 'عملية مسح QR',
              color: const Color(0xFF6366F1)),
          BasakStatTile(
              icon: LucideIcons.calendarDays,
              value: '${s.activeDays}',
              label: 'يوم عمل مسجل',
              color: const Color(0xFF07865A)),
          BasakStatTile(
              icon: LucideIcons.calendarCheck2,
              value: '${s.confirmedRides}',
              label: 'ركوب أكده الطلاب في التطبيق',
              color: _returnColor),
        ]),
        const BasakSectionTitle('الحضور اليومي'),
        _dailyChart(s),
        const BasakSectionTitle('نتائج عمليات المسح'),
        _scanBreakdown(s),
        if (s.stations.isNotEmpty) ...[
          const BasakSectionTitle('أكثر المحطات صعوداً'),
          _stations(s),
        ],
      ],
    );
  }

  Widget _heroCard(SupervisorMonthlySummary s) {
    final rate = s.attendanceRate;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: BasakUi.heroGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(color: Color(0x3020698C), blurRadius: 20, offset: Offset(0, 10))
        ],
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('إجمالي تسجيلات الصعود',
                style: AppTextStyles.labelSmall.copyWith(color: Colors.white70)),
            const SizedBox(height: 4),
            Text('${s.checkins}',
                style: AppTextStyles.displayMedium.copyWith(color: Colors.white, fontSize: 38)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              BasakPill('ذهاب ${s.departureCheckins}',
                  background: Colors.white.withOpacity(.14), foreground: Colors.white),
              BasakPill('عودة ${s.returnCheckins}',
                  background: Colors.white.withOpacity(.14), foreground: Colors.white),
            ]),
          ]),
        ),
        SizedBox(
          width: 92,
          height: 92,
          child: Stack(fit: StackFit.expand, children: [
            CircularProgressIndicator(
              value: rate ?? 0,
              strokeWidth: 9,
              backgroundColor: Colors.white.withOpacity(.16),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF40D0A2)),
            ),
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(rate == null ? '—' : '${(rate * 100).round()}%',
                    style: AppTextStyles.titleLarge.copyWith(color: Colors.white)),
                Text('نسبة الحضور',
                    style: AppTextStyles.labelSmall.copyWith(color: Colors.white70, fontSize: 9)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _dailyChart(SupervisorMonthlySummary s) {
    final days = s.days;
    final peak = days.fold<int>(1, (max, d) {
      final value = [d.checkins, d.confirmed].reduce((a, b) => a > b ? a : b);
      return value > max ? value : max;
    });
    const chartHeight = 140.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BasakUi.card(),
      child: Column(children: [
        SizedBox(
          height: chartHeight + 22,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            reverse: true, // newest day closest to the reader's start (RTL)
            itemCount: days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, index) {
              final day = days[days.length - 1 - index];
              double h(int v) => v == 0 ? 0 : (v / peak) * chartHeight;
              return Tooltip(
                message:
                    '${day.date.day}/${day.date.month}: ذهاب ${day.departure} · عودة ${day.returning} · مؤكد ${day.confirmed}',
                child: SizedBox(
                  width: 18,
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    SizedBox(
                      height: chartHeight,
                      child: Stack(alignment: Alignment.bottomCenter, children: [
                        // confirmed rides as a faint target bar
                        Container(
                          width: 18,
                          height: h(day.confirmed),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3EEF3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          Container(
                            width: 12,
                            height: h(day.returning),
                            decoration: const BoxDecoration(
                              color: _returnColor,
                              borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
                            ),
                          ),
                          Container(
                            width: 12,
                            height: h(day.departure),
                            decoration: BoxDecoration(
                              color: _departureColor,
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(day.returning == 0 ? 5 : 0),
                                  bottom: const Radius.circular(5)),
                            ),
                          ),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 6),
                    Text('${day.date.day}',
                        style: AppTextStyles.labelSmall.copyWith(
                            color: BasakUi.muted, fontSize: 9.5)),
                  ]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 6, alignment: WrapAlignment.center, children: [
          _legend(_departureColor, 'صعود الذهاب'),
          _legend(_returnColor, 'صعود العودة'),
          _legend(const Color(0xFFE3EEF3), 'ركوب مؤكد في التطبيق'),
        ]),
      ]),
    );
  }

  Widget _legend(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(label, style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted)),
      ]);

  Widget _scanBreakdown(SupervisorMonthlySummary s) {
    final rows = [
      (LucideIcons.circleCheck, 'تسجيل صعود ناجح', s.checkins, const Color(0xFF07865A)),
      (LucideIcons.badgeCheck, 'مسح مكرر (مسجل مسبقاً)', s.duplicateScans, BasakUi.teal),
      (LucideIcons.shieldAlert, 'مسح مرفوض', s.rejectedScans, AppColors.error),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BasakUi.card(),
      child: Column(children: [
        for (final (icon, label, value, color) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(label,
                      style: AppTextStyles.bodyMedium.copyWith(color: BasakUi.ink))),
              SizedBox(
                width: 90,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: s.scans == 0 ? 0 : value / s.scans,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFEFF5F8),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 34,
                child: Text('$value',
                    textAlign: TextAlign.end,
                    style: AppTextStyles.bodyLarge
                        .copyWith(color: BasakUi.ink, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _stations(SupervisorMonthlySummary s) {
    final top = s.stations.take(6).toList();
    final peak = top.first.checkins;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BasakUi.card(),
      child: Column(children: [
        for (final station in top)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('${station.station} · ${station.line}',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: BasakUi.ink, fontWeight: FontWeight.w700)),
                ),
                Text('${station.checkins}',
                    style: AppTextStyles.bodyLarge
                        .copyWith(color: BasakUi.teal, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: peak == 0 ? 0 : station.checkins / peak,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFEFF5F8),
                  valueColor: const AlwaysStoppedAnimation(BasakUi.teal),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}
