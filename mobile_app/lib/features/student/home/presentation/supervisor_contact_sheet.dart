import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';

/// The bus supervisor's contact: call now, chat on WhatsApp, save to the
/// phone's contacts, or copy the number. Calling and saving hand over to the
/// system (the dialer and the "new contact" screen), on iPhone and Android alike, so the app needs no
/// permission for either.
class SupervisorContactSheet extends StatelessWidget {
  final String name;
  final String phone;
  final String? lineName;
  final ImageProvider? photo;

  const SupervisorContactSheet(
      {super.key, required this.name, required this.phone, this.lineName, this.photo});

  static Future<void> show(BuildContext context,
          {required String name, required String phone, String? lineName, ImageProvider? photo}) =>
      BasakSheet.show<void>(
        context,
        builder: (_) => SupervisorContactSheet(name: name, phone: phone, lineName: lineName, photo: photo),
      );

  /// What is saved in the phone's contacts: "name (مشرف باص خط …)".
  static String contactName(String name, String? lineName) {
    final role = (lineName ?? '').trim().isEmpty ? 'مشرف الباص' : 'مشرف باص ${lineName!.trim()}';
    return name.trim().isEmpty ? role : '${name.trim()} - $role';
  }

  /// Digits (and a leading +) only: what the dialer expects.
  static String dialable(String phone) => phone.replaceAll(RegExp(r'[^0-9+]'), '');

  /// The number as WhatsApp wants it: country code first, digits only. An
  /// Egyptian mobile written locally (010…) gets Egypt's code.
  static String whatsappNumber(String phone) {
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.length == 11 && digits.startsWith('01')) digits = '2$digits';
    return digits;
  }

  /// The number as it is read: an Egyptian mobile in three groups
  /// ("010 1122 3344"), anything else as it was written.
  static String readable(String phone) {
    final digits = dialable(phone);
    return digits.length == 11 && digits.startsWith('01')
        ? '${digits.substring(0, 3)} ${digits.substring(3, 7)} ${digits.substring(7)}'
        : phone.trim();
  }

  /// "مشرف الباص · خط الزرقا".
  static String roleLabel(String? lineName) {
    final line = (lineName ?? '').trim();
    if (line.isEmpty) return 'مشرف الباص';
    return 'مشرف الباص · ${line.startsWith('خط ') ? line : 'خط $line'}';
  }

  /// Opens the dialer on [phone]. [context] must outlive a sheet closing.
  static Future<void> call(BuildContext context, String phone) async {
    try {
      final opened = await launchUrl(Uri(scheme: 'tel', path: dialable(phone)));
      if (!opened && context.mounted) _failed(context, 'تعذر فتح الاتصال على هذا الجهاز.');
    } catch (_) {
      if (context.mounted) _failed(context, 'تعذر فتح الاتصال على هذا الجهاز.');
    }
  }

  /// Opens the chat in WhatsApp when it is installed, otherwise its web page.
  static Future<void> whatsapp(BuildContext context, String phone) async {
    try {
      final opened = await launchUrl(Uri.parse('https://wa.me/${whatsappNumber(phone)}'),
          mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) _failed(context, 'تعذر فتح واتساب على هذا الجهاز.');
    } catch (_) {
      if (context.mounted) _failed(context, 'تعذر فتح واتساب على هذا الجهاز.');
    }
  }

  static void _failed(BuildContext context, String message) =>
      BasakToast.show(context, message, kind: BasakToastKind.failure);

  /// Closes the sheet and gives back a context that is still there after it:
  /// what follows (the dialer, a toast) belongs to the page under the sheet.
  BuildContext _close(BuildContext context) {
    final navigator = Navigator.of(context);
    final page = navigator.context;
    navigator.pop();
    return page;
  }

  Future<void> _save(BuildContext context) async {
    final page = _close(context);
    try {
      // The system's own "new contact" screen, already filled in.
      final id = await FlutterContacts.native.showCreator(
        contact: Contact(
          name: Name(first: contactName(name, lineName)),
          phones: [Phone(number: dialable(phone))],
        ),
      );
      if (id != null && page.mounted) BasakToast.show(page, 'تم حفظ جهة الاتصال.');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: dialable(phone)));
      if (page.mounted) {
        BasakToast.show(page, 'تعذر فتح جهات الاتصال. تم نسخ الرقم لتحفظه يدوياً.', kind: BasakToastKind.info);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Semantics(
      container: true,
      label: 'التواصل مع مشرف الباص',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Who it is, on one row.
          Row(
            children: [
              PhotoRing(name: name, image: photo, size: 56),
              const SizedBox(width: BasakSpace.s14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.sheetTitle),
                    Text(roleLabel(lineName),
                        style: text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400)),
                    Text(
                      readable(phone),
                      textDirection: TextDirection.ltr,
                      style: text.body.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: BasakSpace.s16),
          BasakButton(
            key: const Key('supervisor-call'),
            label: 'اتصال',
            icon: LucideIcons.phone,
            onPressed: () => call(_close(context), phone),
          ),
          const SizedBox(height: BasakSpace.s16),
          Row(
            children: [
              Expanded(
                child: ActionTile(
                  key: const Key('supervisor-whatsapp'),
                  icon: LucideIcons.messageCircle,
                  label: 'واتساب',
                  onTap: () => whatsapp(_close(context), phone),
                ),
              ),
              const SizedBox(width: BasakSpace.s8),
              Expanded(
                child: ActionTile(
                  key: const Key('supervisor-save'),
                  icon: LucideIcons.userRoundPlus,
                  label: 'حفظ الرقم',
                  onTap: () => _save(context),
                ),
              ),
              const SizedBox(width: BasakSpace.s8),
              Expanded(
                // The sheet stays: the tile itself says the number was copied.
                child: CopyTile(
                  key: const Key('supervisor-copy'),
                  label: 'نسخ الرقم',
                  value: dialable(phone),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
