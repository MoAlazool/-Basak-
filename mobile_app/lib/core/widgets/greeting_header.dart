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
