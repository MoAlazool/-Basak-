import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/theme/app_text_styles.dart';

/// The bus supervisor's contact: call now, save to the phone's contacts, or
/// copy the number. Calling and saving hand over to the system (the dialer and
/// the "new contact" screen), on iPhone and Android alike, so the app needs no
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: const Color(0xFFE5F3FA),
            backgroundImage: photo,
            child: photo == null ? const Icon(LucideIcons.userRound, color: _teal, size: 28) : null,
          ),
          const SizedBox(height: 10),
          Text(name, textAlign: TextAlign.center, style: AppTextStyles.titleLarge.copyWith(color: _ink)),
          const SizedBox(height: 2),
          Text((lineName ?? '').trim().isEmpty ? 'مشرف الحافلة' : 'مشرف حافلة خط ${lineName!.trim()}',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium),
          const SizedBox(height: 6),
          Text(phone,
              textDirection: TextDirection.ltr,
              style: AppTextStyles.titleMedium.copyWith(color: _teal, letterSpacing: .5)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const Key('supervisor-call'),
              onPressed: () => _call(context),
              icon: const Icon(LucideIcons.phone, size: 18),
              label: const Text('اتصال'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('supervisor-save'),
              onPressed: () => _save(context),
              icon: const Icon(LucideIcons.userRoundPlus, size: 18),
              label: const Text('حفظ في جهات الاتصال'),
            ),
          ),
          TextButton.icon(
            key: const Key('supervisor-copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: dialable(phone)));
              if (!context.mounted) return;
              Navigator.of(context).pop();
              _say(context, 'تم نسخ الرقم');
            },
            icon: const Icon(LucideIcons.copy, size: 16),
            label: const Text('نسخ الرقم'),
          ),
        ]),
      ),
    );
  }
}
