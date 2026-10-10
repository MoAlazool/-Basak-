import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../student/home/presentation/supervisor_contact_sheet.dart';

/// One rider of a trip: whether they boarded, their stop, what they confirmed
/// today, their university and phone, and three ways to reach them.
class RiderSheet extends StatelessWidget {
  final String name;
  final String phone;

  /// "لم يصعد", "صعد 7:15 ص", "لم يؤكّد اليوم"; null on a day that has not come.
  final String? state;
  final BasakTone stateTone;

  /// "شرباص · 7:15 ص".
  final String? stop;

  /// "ذهاب 7:00 ص", or "لم يؤكّد".
  final String? confirmation;

  /// What [confirmation] is about: "تأكيد اليوم", "تأكيد الغد".
  final String confirmationLabel;
  final String? university;

  const RiderSheet({
    super.key,
    required this.name,
    required this.phone,
    this.state,
    this.stateTone = BasakTone.warning,
    this.stop,
    this.confirmation,
    this.confirmationLabel = 'تأكيد اليوم',
    this.university,
  });

  static Future<void> show(
    BuildContext context, {
    required String name,
    required String phone,
    String? state,
    BasakTone stateTone = BasakTone.warning,
    String? stop,
    String? confirmation,
    String confirmationLabel = 'تأكيد اليوم',
    String? university,
  }) =>
      BasakSheet.show<void>(
        context,
        builder: (_) => RiderSheet(
          name: name,
          phone: phone,
          state: state,
          stateTone: stateTone,
          stop: stop,
          confirmation: confirmation,
          confirmationLabel: confirmationLabel,
          university: university,
        ),
      );

  /// Closes the sheet and gives back a context that outlives it: the dialer
  /// and the toast belong to the page under the sheet.
  BuildContext _close(BuildContext context) {
    final navigator = Navigator.of(context);
    final page = navigator.context;
    navigator.pop();
    return page;
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = SupervisorContactSheet.dialable(phone).isNotEmpty;
    return Semantics(
      container: true,
      label: 'بيانات الراكب',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PhotoRing(name: name, size: 56),
              const SizedBox(width: BasakSpace.s14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.sheetTitle),
                    if (state != null) ...[
                      const SizedBox(height: BasakSpace.s4),
                      BasakTag(state!, key: const Key('rider-state'), tone: stateTone),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: BasakSpace.s16),
          InfoRows(
            sunken: true,
            rows: [
              if (stop != null) InfoRow(label: 'المحطة', value: stop),
              if (confirmation != null) InfoRow(label: confirmationLabel, value: confirmation),
              if ((university ?? '').isNotEmpty) InfoRow(label: 'الجامعة', value: university),
              InfoRow(
                label: 'الهاتف',
                value: hasPhone ? SupervisorContactSheet.readable(phone) : 'لم يُضف بعد',
                ltrValue: hasPhone,
              ),
            ],
          ),
          const SizedBox(height: BasakSpace.s16),
          BasakButton(
            key: const Key('rider-call'),
            label: 'اتصال',
            icon: LucideIcons.phone,
            onPressed: hasPhone ? () => SupervisorContactSheet.call(_close(context), phone) : null,
          ),
          const SizedBox(height: BasakSpace.s8),
          Row(
            children: [
              Expanded(
                child: BasakButton(
                  key: const Key('rider-whatsapp'),
                  label: 'واتساب',
                  icon: LucideIcons.messageCircle,
                  variant: BasakButtonVariant.secondary,
                  size: BasakButtonSize.medium,
                  onPressed: hasPhone ? () => SupervisorContactSheet.whatsapp(_close(context), phone) : null,
                ),
              ),
              const SizedBox(width: BasakSpace.s8),
              Expanded(
                // The sheet stays: the button itself says the number was copied.
                child: CopyButton(
                  key: const Key('rider-copy'),
                  label: 'نسخ الرقم',
                  value: hasPhone ? SupervisorContactSheet.dialable(phone) : null,
                  size: BasakButtonSize.medium,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
