import 'package:flutter/material.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/basak_ui.dart';
import '../models/line_model.dart';

/// The line's meeting points in route order; the student taps the one they
/// board at. No times here: the line card shows them, and the student picks
/// the departure and return times day by day on the home screen.
class StationPicker extends StatelessWidget {
  final List<StationModel> stations;
  final String? selectedStationId;
  final ValueChanged<StationModel> onSelect;

  const StationPicker({
    super.key,
    required this.stations,
    required this.onSelect,
    this.selectedStationId,
  });

  static const _green = Color(0xFF22C55E);
  static const _greenSoft = Color(0xFFE7F8F0);
  static const _rail = Color(0xFFBBF7D0);

  @override
  Widget build(BuildContext context) {
    if (stations.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BasakUi.card(),
        child: Text('لا توجد رحلات متاحة لجامعتك على هذا الخط.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: BasakUi.muted)),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BasakUi.card(radius: 22),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < stations.length; i++)
          _station(stations[i], first: i == 0, last: i == stations.length - 1),
      ]),
    );
  }

  Widget _station(StationModel station, {required bool first, required bool last}) {
    final selected = station.id == selectedStationId;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => onSelect(station),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Route rail
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                decoration: BoxDecoration(
                  color: selected ? _greenSoft : const Color(0xFFF5F8FA),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: selected ? _green : Colors.transparent, width: 1.4),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(station.name,
                        style: AppTextStyles.bodyLarge
                            .copyWith(color: BasakUi.ink, fontWeight: FontWeight.w700)),
                  ),
                  Icon(selected ? LucideIcons.circleCheck : LucideIcons.circle,
                      size: 19, color: selected ? const Color(0xFF15803D) : const Color(0xFFB6C3CB)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
