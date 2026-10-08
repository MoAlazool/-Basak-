import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/whatsapp_icon.dart';

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

  static const _ink = Color(0xFF17384A);
  static const _teal = Color(0xFF1F6F8B);

  static Future<void> show(BuildContext context,
          {required String name, required String phone, String? lineName, ImageProvider? photo}) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.white,
        showDragHandle: true,
        // As tall as its content needs, on small phones too.
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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

  Future<void> _whatsapp(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    try {
      // Opens the chat in WhatsApp when it is installed, otherwise its web page.
      final opened = await launchUrl(Uri.parse('https://wa.me/${whatsappNumber(phone)}'),
          mode: LaunchMode.externalApplication);
      if (!opened) messenger.showSnackBar(const SnackBar(content: Text('تعذر فتح واتساب على هذا الجهاز.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('تعذر فتح واتساب على هذا الجهاز.')));
    }
  }

  void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _call(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    try {
      final opened = await launchUrl(Uri(scheme: 'tel', path: dialable(phone)));
      if (!opened) messenger.showSnackBar(const SnackBar(content: Text('تعذر فتح الاتصال على هذا الجهاز.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('تعذر فتح الاتصال على هذا الجهاز.')));
    }
  }

  Future<void> _save(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    try {
      // The system's own "new contact" screen, already filled in.
      final id = await FlutterContacts.native.showCreator(
        contact: Contact(
          name: Name(first: contactName(name, lineName)),
          phones: [Phone(number: dialable(phone))],
        ),
      );
      if (id != null) messenger.showSnackBar(const SnackBar(content: Text('تم حفظ جهة الاتصال.')));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: dialable(phone)));
      messenger.showSnackBar(
          const SnackBar(content: Text('تعذر فتح جهات الاتصال. تم نسخ الرقم لتحفظه يدوياً.')));
    }
  }

  /// One of the two main actions: an icon over a word, side by side.
  Widget _action(
          {required Key key,
          required Widget icon,
          required String label,
          required Color background,
          required Color foreground,
          required VoidCallback onTap}) =>
      Expanded(
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                icon,
                const SizedBox(height: 8),
                Text(label,
                    style: AppTextStyles.bodyLarge
                        .copyWith(color: foreground, fontWeight: FontWeight.w700, height: 1.2)),
              ]),
            ),
          ),
        ),
      );

  /// A quiet secondary action under the two main ones.
  Widget _link({required Key key, required IconData icon, required String label, required VoidCallback onTap}) =>
      Expanded(
        child: TextButton.icon(
          key: key,
          style: TextButton.styleFrom(
              foregroundColor: _teal, padding: const EdgeInsets.symmetric(vertical: 12)),
          onPressed: onTap,
          icon: Icon(icon, size: 17),
          label: Text(label, style: AppTextStyles.bodyMedium.copyWith(color: _teal, fontWeight: FontWeight.w600)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final role = (lineName ?? '').trim().isEmpty ? 'مشرف الحافلة' : 'مشرف حافلة خط ${lineName!.trim()}';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Who it is, on one row.
          Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFFE5F3FA),
              backgroundImage: photo,
              child: photo == null ? const Icon(LucideIcons.userRound, color: _teal, size: 26) : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: AppTextStyles.titleLarge.copyWith(color: _ink)),
                const SizedBox(height: 2),
                Text(role, style: AppTextStyles.bodyMedium),
                const SizedBox(height: 4),
                Text(phone,
                    textDirection: TextDirection.ltr,
                    style: AppTextStyles.bodyLarge
                        .copyWith(color: _ink, fontWeight: FontWeight.w600, letterSpacing: .4)),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            _action(
              key: const Key('supervisor-call'),
              icon: const Icon(LucideIcons.phone, size: 24, color: Colors.white),
              label: 'اتصال',
              background: _teal,
              foreground: Colors.white,
              onTap: () => _call(context),
            ),
            const SizedBox(width: 12),
            _action(
              key: const Key('supervisor-whatsapp'),
              icon: const WhatsAppIcon(size: 24),
              label: 'واتساب',
              background: const Color(0xFF25D366),
              foreground: Colors.white,
              onTap: () => _whatsapp(context),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _link(
              key: const Key('supervisor-save'),
              icon: LucideIcons.userRoundPlus,
              label: 'حفظ جهة الاتصال',
              onTap: () => _save(context),
            ),
            Container(width: 1, height: 22, color: const Color(0xFFE3EDF3)),
            _link(
              key: const Key('supervisor-copy'),
              icon: LucideIcons.copy,
              label: 'نسخ الرقم',
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: dialable(phone)));
                if (!context.mounted) return;
                Navigator.of(context).pop();
                _say(context, 'تم نسخ الرقم');
              },
            ),
          ]),
        ]),
      ),
    );
  }
}
