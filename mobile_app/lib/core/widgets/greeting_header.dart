import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../ui/ui.dart';
import 'avatar_image.dart';

/// Top of the student and supervisor home screens: photo, good morning /
/// good evening and the name on the start side; the notifications bell, with
/// the unread count, on the other.
class GreetingHeader extends StatelessWidget {
  final String name;

  /// Signed link to the photo; null shows the name's first letter.
  final String? photoUrl;
  final int unread;
  final VoidCallback onNotifications;

  const GreetingHeader({
    super.key,
    required this.name,
    required this.photoUrl,
    required this.unread,
    required this.onNotifications,
  });

  // Words that are half of a name: «عبد الرحمن», «أبو بكر» are one name, and
  // so are «نور الدين», «جاد الله».
  static const _joinsNext = {'عبد', 'ابو', 'أبو'};
  static const _joinsPrevious = {'الدين', 'الله', 'الإسلام', 'الاسلام'};

  /// The first two names of [fullName], for a greeting: «محمد عادل فؤاد
  /// العزول» → «محمد عادل». A name of one word stays as it is, spaces of any
  /// kind and number are tidied, and a two-word name is never cut in half
  /// («محمد عبد الرحمن علي» → «محمد عبد الرحمن»).
  ///
  /// For display only: the stored name is never changed, and every other
  /// screen (the card, receipts, the profile) shows it in full.
  static String firstTwoNames(String fullName) {
    final words = fullName
        // Direction marks and zero-width characters some keyboards add.
        .replaceAll(RegExp('[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final names = <String>[];
    for (var i = 0; i < words.length && names.length < 2; i++) {
      var name = words[i];
      if (_joinsNext.contains(name) && i + 1 < words.length) name = '$name ${words[++i]}';
      while (i + 1 < words.length && _joinsPrevious.contains(words[i + 1])) {
        name = '$name ${words[++i]}';
      }
      names.add(name);
    }
    return names.join(' ');
  }

  /// صباح الخير in the morning, مساء الخير the rest of the day.
  static String greetingFor(DateTime now) =>
      now.hour >= 5 && now.hour < 12 ? 'صباح الخير' : 'مساء الخير';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: BasakSpace.s4),
      child: Row(
        children: [
          PhotoRing(name: name, image: photoUrl == null ? null : avatarImage(photoUrl!)),
          const SizedBox(width: BasakSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(greetingFor(DateTime.now()),
                    style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400)),
                Semantics(
                  header: true,
                  child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.title),
                ),
              ],
            ),
          ),
          const SizedBox(width: BasakSpace.s12),
          BasakIconButton(
            icon: LucideIcons.bell,
            label: unread > 0 ? 'التنبيهات، $unread غير مقروءة' : 'التنبيهات',
            badge: unread,
            onPressed: onNotifications,
          ),
        ],
      ),
    );
  }
}
