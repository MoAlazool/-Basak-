import 'package:flutter/material.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../theme/app_text_styles.dart';
import 'avatar_image.dart';

/// Top of the student and supervisor home screens: photo, good morning /
/// good evening and the name on the start side; the notifications bell, with
/// the unread count, on the other.
class GreetingHeader extends StatelessWidget {
  final String name;

  /// Signed link to the photo; null shows a person icon.
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

  static const _ink = Color(0xFF17384A);
  static const _teal = Color(0xFF00658D);
  static const _line = Color(0xFFE3EDF3);

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
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Color(0x1A16384A), blurRadius: 12, offset: Offset(0, 4))
              ],
            ),
            child: CircleAvatar(
              radius: 25,
              backgroundColor: const Color(0xFFE4F2F9),
              backgroundImage: photoUrl == null ? null : avatarImage(photoUrl!),
              child: photoUrl == null
                  ? const Icon(LucideIcons.userRound, color: _teal, size: 23)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greetingFor(DateTime.now()),
                    style: AppTextStyles.bodyMedium.copyWith(color: _teal)),
                const SizedBox(height: 2),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.displayMedium.copyWith(color: _ink, fontSize: 21)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            button: true,
            label: unread > 0 ? 'الإشعارات، $unread غير مقروءة' : 'الإشعارات',
            child: Stack(clipBehavior: Clip.none, children: [
              Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: _line),
                ),
                child: InkWell(
                  customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onTap: onNotifications,
                  child: const SizedBox(
                    width: 50,
                    height: 50,
                    child: Icon(LucideIcons.bell, color: _ink, size: 22),
                  ),
                ),
              ),
              if (unread > 0)
                PositionedDirectional(
                  top: -5,
                  end: -5,
                  child: IgnorePointer(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 22),
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5484D),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(unread > 9 ? '+9' : '$unread',
                          style: AppTextStyles.labelSmall.copyWith(
                              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11)),
                    ),
                  ),
                ),
            ]),
          ),
        ],
      );
}
