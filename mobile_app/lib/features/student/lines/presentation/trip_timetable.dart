import 'package:flutter/material.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/basak_ui.dart';

/// "Departure (n) | Return (n)" switch (the supervisor's Trips page).
class TripDirectionTabs extends StatelessWidget {
  final bool departure;
  final int departureCount;
  final int returnCount;
  final ValueChanged<bool> onChanged;

  const TripDirectionTabs({
    super.key,
    required this.departure,
    required this.departureCount,
    required this.returnCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, int count, bool active, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: active ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                boxShadow: active
                    ? const [BoxShadow(color: Color(0x1016384A), blurRadius: 10, offset: Offset(0, 3))]
                    : null,
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(label,
                    style: AppTextStyles.titleMedium
                        .copyWith(color: active ? BasakUi.teal : BasakUi.muted)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: active ? BasakUi.teal : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$count',
                      style: AppTextStyles.labelSmall.copyWith(
                          color: active ? Colors.white : BasakUi.muted, fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFE8F0F5), borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        tab('الذهاب', departureCount, departure, () => onChanged(true)),
        tab('العودة', returnCount, !departure, () => onChanged(false)),
      ]),
    );
  }
}
