import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import 'purchase_flow.dart' show formatMoney;

/// "راجع اشتراكك": the last look before the subscription is created.
///
/// The route on its rail, the period and how long it is valid, the amount
/// once, and the one fact that cannot be undone. Its button is the only write
/// of the whole flow.
abstract final class ConfirmSheet {
  /// Shows the review. [onConfirm] creates the subscription; the sheet shows
  /// its progress on the button and closes when it ends, whatever the answer
  /// (the builder says what went wrong). Returns true once [onConfirm] ran.
  static Future<bool?> show(
    BuildContext context, {
    required String station,
    required String university,
    required String line,
    required String company,
    required String period,
    String? validUntil,
    required double amount,
    required Future<void> Function() onConfirm,
  }) =>
      BasakSheet.showFrame<bool>(
        context,
        builder: (context) => _ConfirmBody(
          station: station,
          university: university,
          line: line,
          company: company,
          period: period,
          validUntil: validUntil,
          amount: amount,
          onConfirm: onConfirm,
        ),
      );
}

class _ConfirmBody extends StatefulWidget {
  final String station;
  final String university;
  final String line;
  final String company;
  final String period;
  final String? validUntil;
  final double amount;
  final Future<void> Function() onConfirm;

  const _ConfirmBody({
    required this.station,
    required this.university,
    required this.line,
    required this.company,
    required this.period,
    required this.validUntil,
    required this.amount,
    required this.onConfirm,
  });

  @override
  State<_ConfirmBody> createState() => _ConfirmBodyState();
}

class _ConfirmBodyState extends State<_ConfirmBody> {
  bool _sending = false;

  Future<void> _confirm() async {
    if (_sending) return;
    setState(() => _sending = true);
    await widget.onConfirm();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lineName = widget.line.trim().startsWith('خط') ? widget.line.trim() : 'خط ${widget.line.trim()}';

    return PopScope(
      // The request is on its way: the answer closes the sheet.
      canPop: !_sending,
      child: BasakSheetFrame(
        title: 'راجع اشتراكك',
        largeTitle: true,
        primary: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BasakButton(
              key: const Key('flow-confirm'),
              label: 'تأكيد والانتقال للدفع',
              loading: _sending,
              onPressed: _confirm,
            ),
            const SizedBox(height: BasakSpace.s2),
            SheetLink(
              key: const Key('review-back'),
              label: 'رجوع للتعديل',
              onTap: _sending ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BasakCard(
              color: colors.ground,
              child: RouteRail(
                from: widget.station,
                to: widget.university,
                toCaption: '$lineName · ${widget.company}',
              ),
            ),
            const SizedBox(height: BasakSpace.s10),
            ReviewRow(label: 'الفترة', value: widget.period),
            if (widget.validUntil != null) ReviewRow(label: 'صالح حتى', value: widget.validUntil!),
            ReviewAmount(money: formatMoney(widget.amount), moneyKey: const Key('review-amount')),
            const SizedBox(height: BasakSpace.s8),
            const NoticeCard(
              icon: LucideIcons.info,
              message: 'بعد التأكيد لا يمكن تغيير الخط أو المحطة.',
            ),
          ],
        ),
      ),
    );
  }
}
