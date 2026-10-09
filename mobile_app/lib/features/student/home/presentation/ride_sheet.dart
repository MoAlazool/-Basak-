import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// What the student answered in the ride sheet.
class RideChoice {
  final bool riding;

  /// The departure time chosen (as the line saves it). Null when not riding.
  final String? departure;

  /// The return time chosen; null: "لن أعود بالباص".
  final String? returnTime;

  const RideChoice.riding({required String this.departure, this.returnTime}) : riding = true;

  const RideChoice.notRiding()
      : riding = false,
        departure = null,
        returnTime = null;

  bool get returning => returnTime != null;
}

/// "نعم، سأركب": the departure time and the way back, each a grid that takes
/// any number of times. "لن أعود بالباص" is the last option of the way back,
/// and the only one when the line has no return trips. "تأكيد الركوب" stays
/// pinned under the times however many there are.
abstract final class RideSheet {
  static Future<RideChoice?> show(
    BuildContext context, {
    /// "رحلة الغد".
    required String title,

    /// "الاثنين 12 أكتوبر · من كوبري السرو".
    required String subtitle,

    /// "لن أركب غداً".
    required String declineLabel,
    required List<String> departures,
    required List<String> returns,
    required String Function(String time) departureLabel,
    required String Function(String time) returnLabel,

    /// What is chosen when the sheet opens: the saved ride, or the first times.
    String? departure,
    String? returnTime,
    bool returning = true,
  }) {
    final chosen = ValueNotifier<({String? departure, String? returnTime})>((
      departure: departures.contains(departure) ? departure : departures.firstOrNull,
      returnTime: !returning || returns.isEmpty
          ? null
          : (returns.contains(returnTime) ? returnTime : returns.first),
    ));
    return BasakSheet.show<RideChoice>(
      context,
      title: title,
      subtitle: subtitle,
      largeTitle: true,
      builder: (context) => ValueListenableBuilder(
        valueListenable: chosen,
        builder: (context, value, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: BasakSpace.s4),
            const _GroupHead('الذهاب', 'موعد مرور الباص على محطتك'),
            const SizedBox(height: BasakSpace.s10),
            Semantics(
              container: true,
              label: 'موعد الذهاب',
              child: TimeGrid(children: [
                for (final time in departures)
                  TimeTile(
                    key: Key('ride-departure-$time'),
                    label: departureLabel(time),
                    selected: time == value.departure,
                    // Read at the tap, not at the last build: two quick taps both count.
                    onTap: () => chosen.value = (departure: time, returnTime: chosen.value.returnTime),
                  ),
              ]),
            ),
            const SizedBox(height: BasakSpace.s18),
            const _GroupHead('العودة', 'موعد تحرّك الباص من الجامعة'),
            const SizedBox(height: BasakSpace.s10),
            Semantics(
              container: true,
              label: 'موعد العودة',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (returns.isNotEmpty) ...[
                    TimeGrid(children: [
                      for (final time in returns)
                        TimeTile(
                          key: Key('ride-return-$time'),
                          label: returnLabel(time),
                          selected: time == value.returnTime,
                          onTap: () => chosen.value = (departure: chosen.value.departure, returnTime: time),
                        ),
                    ]),
                    const SizedBox(height: BasakSpace.s8),
                  ],
                  TimeTile(
                    key: const Key('ride-return-none'),
                    label: 'لن أعود بالباص',
                    wide: true,
                    selected: value.returnTime == null,
                    onTap: () => chosen.value = (departure: chosen.value.departure, returnTime: null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: BasakSpace.s4),
          ],
        ),
      ),
      primary: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder(
            valueListenable: chosen,
            builder: (context, value, _) => BasakButton(
              key: const Key('ride-confirm'),
              label: 'تأكيد الركوب',
              onPressed: value.departure == null
                  ? null
                  : () => Navigator.of(context)
                      .pop(RideChoice.riding(departure: value.departure!, returnTime: value.returnTime)),
            ),
          ),
          const SizedBox(height: BasakSpace.s2),
          SheetLink(
            key: const Key('ride-decline'),
            label: declineLabel,
            onTap: () => Navigator.of(context).pop(const RideChoice.notRiding()),
          ),
        ],
      ),
    );
  }
}

class _GroupHead extends StatelessWidget {
  final String title;
  final String hint;

  const _GroupHead(this.title, this.hint);

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title, style: context.text.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: BasakSpace.s12),
          Expanded(
            child: Text(
              hint,
              textAlign: TextAlign.end,
              style: context.text.caption.copyWith(color: context.colors.ink3),
            ),
          ),
        ],
      );
}
