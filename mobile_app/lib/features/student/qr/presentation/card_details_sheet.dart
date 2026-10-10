import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../data/student_qr_repository.dart';
import 'card_facts.dart';

/// "كل التفاصيل": everything the card knows, read-only. It is the list a
/// supervisor gets after a scan, so both sides read the same facts.
class CardDetailsSheet extends StatelessWidget {
  final StudentPassDetails pass;
  final ImageProvider? photo;

  /// Today's ride, when this phone already knows it.
  final TodayRide? ride;

  const CardDetailsSheet({super.key, required this.pass, this.photo, this.ride});

  static Future<void> show(BuildContext context,
          {required StudentPassDetails pass, ImageProvider? photo, TodayRide? ride}) =>
      BasakSheet.show<void>(context, builder: (_) => CardDetailsSheet(pass: pass, photo: photo, ride: ride));

  /// Unicode's left-to-right isolate and its end: for a run that must keep
  /// its order inside an Arabic line.
  static final _ltr = String.fromCharCode(0x2066);
  static final _end = String.fromCharCode(0x2069);

  static String _or(String? value) => (value ?? '').trim().isEmpty ? '—' : value!.trim();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final standing = CardStanding.of(pass);
    final name = _or(pass.fullName);
    final year = pass.academicYear;
    // The years read left to right inside the Arabic line.
    final period = [
      if ((pass.periodName ?? '').isNotEmpty) pass.periodName!,
      if (year != null) '$_ltr$year / ${year + 1}$_end',
    ].join(' · ');
    final today = ride;

    Widget group(String title, List<InfoRow> rows) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text(title, style: text.label.copyWith(color: colors.ink2))),
            const SizedBox(height: BasakSpace.s8),
            InfoRows(sunken: true, rows: rows),
          ],
        );

    return Column(
      key: const Key('card-details'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: BasakSpace.s4, top: BasakSpace.s4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PhotoRing(image: photo, name: name, size: 68, ring: standing.ring(colors)),
              const SizedBox(width: BasakSpace.s14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.sheetTitle),
                    ),
                    const SizedBox(height: BasakSpace.s4),
                    StatusChip(standing.status, label: standing.chipLabel),
                  ],
                ),
              ),
              BasakIconButton(
                key: const Key('card-details-close'),
                icon: LucideIcons.x,
                label: 'إغلاق',
                onCard: true,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        const SizedBox(height: BasakSpace.s16),
        group('بيانات الطالب', [
          InfoRow(label: 'الجامعة', value: _or(pass.university)),
          InfoRow(label: 'الكلية', value: _or(pass.college)),
          if ((pass.phone ?? '').trim().isNotEmpty)
            InfoRow(label: 'الهاتف', value: cardPhone(pass.phone!.trim()), ltrValue: true),
        ]),
        if (standing != CardStanding.none) ...[
          const SizedBox(height: BasakSpace.s16),
          group('الاشتراك', [
            InfoRow(label: 'الخط', value: _or(pass.lineName)),
            InfoRow(label: 'محطة الصعود', value: _or(pass.stationName)),
            InfoRow(label: 'الشركة', value: _or(pass.companyName)),
            InfoRow(label: 'الفترة', value: _or(period)),
            InfoRow(label: 'الصلاحية', value: _or(CardDates.range(pass.startDate, pass.endDate))),
          ]),
        ],
        if (standing.isActive && today != null && today.isRiding) ...[
          const SizedBox(height: BasakSpace.s16),
          group(today.title, [
            InfoRow(label: 'الذهاب', value: _or(today.going)),
            InfoRow(label: 'العودة', value: _or(today.returning(pass))),
          ]),
        ],
      ],
    );
  }
}
