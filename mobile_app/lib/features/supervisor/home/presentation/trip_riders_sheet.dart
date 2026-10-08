import 'package:flutter/material.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/basak_ui.dart';
import '../../models/supervisor_models.dart';

/// One trip time from Home's "الطلاب حسب موعد الرحلة": who rides it by the time
/// each student chose that day. Going → riders per boarding station in travel
/// order; Return → riders per university. A group opens to its students.
class TripRidersSheet extends StatefulWidget {
  final SupervisorTripTime trip;

  /// اليوم / غداً / the date.
  final String dayLabel;

  const TripRidersSheet({super.key, required this.trip, required this.dayLabel});

  static Future<void> show(BuildContext context,
          {required SupervisorTripTime trip, required String dayLabel}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => TripRidersSheet(trip: trip, dayLabel: dayLabel),
      );

  @override
  State<TripRidersSheet> createState() => _TripRidersSheetState();
}

class _TripRidersSheetState extends State<TripRidersSheet> {
  static const _green = Color(0xFF07865A);
  static const _amber = Color(0xFFB97812);
  static const _line = Color(0xFFEAF0F4);

  final Set<String> _open = {};

  SupervisorTripTime get _trip => widget.trip;
  Color get _color => _trip.isReturn ? _amber : _green;
  Color get _soft => _trip.isReturn ? const Color(0xFFFFF4E5) : const Color(0xFFE7F8F0);

  void _toggle(String key) =>
      setState(() => _open.contains(key) ? _open.remove(key) : _open.add(key));

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFD5DFE6), borderRadius: BorderRadius.circular(4)),
              ),
            ),
            _header(),
            const Divider(height: 1, color: _line),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
                children: !_trip.hasBreakdown
                    ? [
                        const BasakMessageCard(
                          icon: LucideIcons.info,
                          title: 'التفاصيل غير متاحة',
                          message: 'تعذر عرض توزيع الطلاب لهذا الموعد. اسحب الصفحة الرئيسية لتحديثها ثم أعد المحاولة.',
                        ),
                      ]
                    : _trip.isReturn
                        ? _byUniversity()
                        : _byStation(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final subtitle = _trip.subtitle;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 8, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          BasakPill(_trip.isReturn ? 'العودة' : 'الذهاب',
              background: _soft,
              foreground: _color,
              icon: _trip.isReturn ? LucideIcons.sunset : LucideIcons.sunrise),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.dayLabel,
                style: AppTextStyles.labelSmall
                    .copyWith(color: BasakUi.muted, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: 'إغلاق',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(LucideIcons.x, size: 20, color: BasakUi.muted),
          ),
        ]),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Tall line: the descender of "م" would touch the line below.
                Text(BasakUi.time12(_trip.time),
                    style: AppTextStyles.displayMedium.copyWith(color: BasakUi.ink, fontSize: 32, height: 1.55)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: BasakUi.ink, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(LucideIcons.busFront, size: 14, color: BasakUi.muted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(_trip.lineName,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted)),
                  ),
                ]),
              ]),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(18)),
              child: Column(children: [
                Text('${_trip.students}',
                    style: AppTextStyles.displayMedium.copyWith(color: _color, fontSize: 24, height: 1.1)),
                Text(_trip.isReturn ? 'طالب عائد' : 'طالب ذاهب',
                    style: AppTextStyles.labelSmall.copyWith(color: _color, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _title(String title, String trailing) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(
              child: Text(title, style: AppTextStyles.titleMedium.copyWith(color: BasakUi.ink))),
          Text(trailing, style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted)),
        ]),
      );

  List<Widget> _byStation() {
    final stations = _trip.stations;
    return [
      _title('الطلاب حسب محطة الركوب', '${stations.length} محطة'),
      for (var i = 0; i < stations.length; i++)
        _group(
          key: 's:${stations[i].id}',
          leading: Text('${i + 1}',
              style: AppTextStyles.labelSmall.copyWith(color: BasakUi.teal, fontWeight: FontWeight.w800)),
          leadingBackground: BasakUi.softTeal,
          title: stations[i].name,
          subtitle: stations[i].stopTime == null
              ? 'الرحلة لا تقف هنا'
              : BasakUi.time12(stations[i].stopTime),
          count: stations[i].students,
          riders: _trip.ridersAt(stations[i].id),
          riderNote: (_) => null,
        ),
    ];
  }

  List<Widget> _byUniversity() {
    final universities = _trip.universities;
    return [
      _title('الطلاب حسب الجامعة', '${universities.length} جامعة'),
      for (final university in universities)
        _group(
          key: 'u:${university.name}',
          leading: const Icon(LucideIcons.graduationCap, size: 16, color: Color(0xFF4F46E5)),
          leadingBackground: const Color(0xFFEEF0FF),
          title: university.name,
          subtitle: null,
          count: university.students,
          riders: _trip.ridersOf(university.name),
          riderNote: (r) => r.station == null ? null : 'ينزل في ${r.station}',
        ),
    ];
  }

  /// A station or university with its count; opens to its riders. Empty groups
  /// are dimmed and stay closed.
  Widget _group({
    required String key,
    required Widget leading,
    required Color leadingBackground,
    required String title,
    required String? subtitle,
    required int count,
    required List<TripTimeRider> riders,
    required String? Function(TripTimeRider) riderNote,
  }) {
    final expandable = riders.isNotEmpty;
    final open = expandable && _open.contains(key);
    return Opacity(
      opacity: count == 0 ? .5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: open ? Colors.white : const Color(0xFFF7FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: open ? _color.withOpacity(.35) : _line),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: expandable ? () => _toggle(key) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: leadingBackground, shape: BoxShape.circle),
                    child: leading,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title,
                          style: AppTextStyles.bodyLarge
                              .copyWith(color: BasakUi.ink, fontWeight: FontWeight.w700)),
                      if (subtitle != null)
                        Text(subtitle, style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  BasakPill('$count',
                      background: count == 0 ? const Color(0xFFEFF3F6) : _soft,
                      foreground: count == 0 ? BasakUi.muted : _color,
                      icon: LucideIcons.users),
                  SizedBox(
                    width: 26,
                    child: expandable
                        ? Icon(open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                            size: 18, color: BasakUi.muted)
                        : null,
                  ),
                ]),
              ),
            ),
            if (open)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(children: [for (final r in riders) _rider(r, riderNote(r))]),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _rider(TripTimeRider r, String? note) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: const Color(0xFFF4F8FA), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(LucideIcons.user, size: 16, color: BasakUi.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.fullName,
                  style: AppTextStyles.bodyMedium.copyWith(color: BasakUi.ink, fontWeight: FontWeight.w700)),
              if (r.phone.isNotEmpty)
                Text(r.phone,
                    textDirection: TextDirection.ltr,
                    style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted)),
              if (note != null)
                Text(note,
                    style: AppTextStyles.labelSmall
                        .copyWith(color: BasakUi.teal, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      );
}
