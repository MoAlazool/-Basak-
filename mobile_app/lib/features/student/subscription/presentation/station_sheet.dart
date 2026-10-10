import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/basak_ui.dart';
import '../models/sale_catalog.dart';

/// "من أين تركب؟": the stops of one line in route order, on the rail.
///
/// Choosing a line and its boarding stop is one gesture: the builder opens
/// this sheet over the line card, and the stop chosen here settles both. A
/// closed row shows only when the first bus passes; the selected one opens in
/// place to list every pass time. Search appears above six stops.
abstract final class StationSheet {
  /// Above this many stops the sheet offers a search box.
  static const searchAbove = 6;

  /// The id of the chosen stop, or null when the sheet is closed without one.
  static Future<String?> show(BuildContext context, {required SaleLine line, String? selected}) =>
      BasakSheet.showFrame<String>(
        context,
        builder: (context) => _StationPicker(line: line, selected: selected),
      );

  /// "7 محطات".
  static String stopsLabel(int count) => switch (count) {
        1 => 'محطة واحدة',
        2 => 'محطتان',
        <= 10 => '$count محطات',
        _ => '$count محطة',
      };

  static String _tripsLabel(int count) => switch (count) {
        1 => 'رحلة واحدة',
        2 => 'رحلتان',
        <= 10 => '$count رحلات',
        _ => '$count رحلة',
      };

  static bool _morning(TripStop stop) => (int.tryParse(stop.time.split(':').first) ?? 0) < 12;

  /// "خط الزرقا · 7 محطات · 5 رحلات صباحاً".
  static String summary(SaleLine line) {
    final stops = line.stations.expand((s) => s.departures).toList();
    final trips = stops.map((d) => d.tripId).toSet().length;
    final name = line.name.trim().startsWith('خط') ? line.name.trim() : 'خط ${line.name.trim()}';
    return [
      name,
      stopsLabel(line.stations.length),
      if (trips > 0) '${_tripsLabel(trips)}${stops.every(_morning) ? ' صباحاً' : ''}',
    ].join(' · ');
  }

  /// "6:38 · 7:23 · 8:08 ص": every pass time, the half of the day said once
  /// when they share it.
  static String passes(SaleStation station) {
    final times = station.departures.map((d) => BasakUi.time12(d.time)).toList();
    final parts = times.map((t) => t.split(' ')).toList();
    final shared = parts.every((p) => p.length == 2 && p[1] == parts.first[1]);
    return shared && times.length > 1 ? '${parts.map((p) => p[0]).join(' · ')} ${parts.first[1]}' : times.join(' · ');
  }

  /// Letters that are typed either way count as the same one.
  static String _fold(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي');
}

class _StationPicker extends StatefulWidget {
  final SaleLine line;
  final String? selected;

  const _StationPicker({required this.line, this.selected});

  @override
  State<_StationPicker> createState() => _StationPickerState();
}

class _StationPickerState extends State<_StationPicker> {
  final _search = TextEditingController();
  String _query = '';
  late String? _picked = _initial();

  String? _initial() {
    final stations = widget.line.stations.where((s) => s.departures.isNotEmpty).toList();
    final kept = stations.where((s) => s.id == widget.selected).firstOrNull;
    // A line with one stop leaves nothing to choose.
    return kept?.id ?? (stations.length == 1 ? stations.single.id : null);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final query = StationSheet._fold(_query);
    final shown = query.isEmpty
        ? line.stations
        : line.stations.where((s) => StationSheet._fold(s.name).contains(query)).toList();
    final picked = line.station(_picked);

    return BasakSheetFrame(
      title: 'من أين تركب؟',
      subtitle: StationSheet.summary(line),
      largeTitle: true,
      header: line.stations.length > StationSheet.searchAbove
          ? BasakSearchField(
              key: const Key('station-search'),
              controller: _search,
              hint: 'ابحث عن محطة',
              onChanged: (value) => setState(() => _query = value),
            )
          : null,
      primary: BasakButton(
        key: const Key('station-confirm'),
        label: picked == null ? 'اختيار' : 'اختيار ${picked.name}',
        onPressed: picked == null ? null : () => Navigator.of(context).pop(picked.id),
      ),
      child: shown.isEmpty
          ? const EmptyState(icon: LucideIcons.search, title: 'لا توجد محطة بهذا الاسم')
          : Semantics(
              container: true,
              label: 'المحطات بترتيب المسار',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < shown.length; i++)
                    StationRow(
                      key: Key('station-${shown[i].id}'),
                      name: shown[i].name,
                      firstPass: shown[i].departures.isEmpty
                          ? 'لا توجد رحلات'
                          : 'من ${BasakUi.time12(shown[i].departures.first.time)}',
                      passesCaption:
                          shown[i].departures.every(StationSheet._morning) ? 'يمرّ الباص صباحاً' : 'يمرّ الباص',
                      allPasses: StationSheet.passes(shown[i]),
                      selected: shown[i].id == _picked,
                      isFirst: i == 0,
                      isLast: i == shown.length - 1,
                      // A stop no trip passes cannot be boarded from.
                      onTap: shown[i].departures.isEmpty ? null : () => setState(() => _picked = shown[i].id),
                    ),
                ],
              ),
            ),
    );
  }
}
