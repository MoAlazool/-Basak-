import 'package:flutter/material.dart';

import 'tokens.dart';

/// The six states of a subscription, with the one label each has everywhere:
/// Home, the subscription tab, the card and the inbox.
enum BasakStatus {
  active('نشط'),
  pendingReview('قيد المراجعة'),
  pendingPayment('بانتظار الدفع'),
  rejected('إيصال مرفوض'),
  upcoming('يبدأ قريباً'),
  expired('منتهٍ');

  final String label;
  const BasakStatus(this.label);
}

/// A tone: the text-safe colour and the tint it sits on.
enum BasakTone { success, warning, danger, info, neutral }

extension BasakToneColors on BasakTone {
  Color foreground(BasakColors c) => switch (this) {
        BasakTone.success => c.success,
        BasakTone.warning => c.warning,
        BasakTone.danger => c.danger,
        BasakTone.info => c.teal,
        BasakTone.neutral => c.ink2,
      };

  Color tint(BasakColors c) => switch (this) {
        BasakTone.success => c.successTint,
        BasakTone.warning => c.warningTint,
        BasakTone.danger => c.dangerTint,
        BasakTone.info => c.tealTint,
        BasakTone.neutral => c.sunken,
      };
}

extension BasakStatusTone on BasakStatus {
  BasakTone get tone => switch (this) {
        BasakStatus.active => BasakTone.success,
        BasakStatus.pendingReview => BasakTone.warning,
        BasakStatus.pendingPayment => BasakTone.info,
        BasakStatus.rejected => BasakTone.danger,
        BasakStatus.upcoming => BasakTone.info,
        BasakStatus.expired => BasakTone.neutral,
      };
}

/// The only way a status is drawn: a dot, the fixed label, the status colour.
class StatusChip extends StatelessWidget {
  final BasakStatus status;

  /// On the ink pass: a raised ink chip with a mint dot.
  final bool onInk;

  /// Where the status needs its noun: the card says "اشتراك نشط", and
  /// "لا يوجد اشتراك" when there is nothing to name. The colour stays the status's.
  final String? label;

  const StatusChip(this.status, {super.key, this.onInk = false, this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = onInk ? colors.onInk : status.tone.foreground(colors);
    final dot = onInk ? (status == BasakStatus.active ? colors.mint : colors.openDot) : foreground;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.s10, 5, BasakSpace.s12, 5),
      decoration: BoxDecoration(
        color: onInk ? colors.inkRaised : status.tone.tint(colors),
        borderRadius: BasakRadius.all(BasakRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: BasakSpace.s8),
          Flexible(
            child: Text(label ?? status.label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.label.copyWith(color: foreground)),
          ),
        ],
      ),
    );
  }
}

/// A read-only label, at most one per card: "وفّر 1,000 ج.م", "يومي متاح".
class BasakTag extends StatelessWidget {
  final String label;
  final BasakTone tone;

  const BasakTag(this.label, {super.key, this.tone = BasakTone.neutral});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s10, vertical: 3),
      decoration: BoxDecoration(color: tone.tint(colors), borderRadius: BasakRadius.all(BasakRadius.tag)),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.text.caption.copyWith(color: tone.foreground(colors), fontWeight: FontWeight.w500),
      ),
    );
  }
}
