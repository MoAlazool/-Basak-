import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../data/notifications_repository.dart';

/// The icon and colours a notification is drawn with, from its type; a type
/// this version does not know takes the look of its category.
typedef NotificationStyle = ({IconData icon, Color color, Color background});

const _teal = (Color(0xFF00658D), Color(0xFFE5F3FA));
const _green = (Color(0xFF07865A), Color(0xFFE7F8F0));
const _amber = (Color(0xFFB97812), Color(0xFFFDF3DC));
const _red = (Color(0xFFD23B40), Color(0xFFFDE8E8));

NotificationStyle notificationStyle(String type, NotificationCategory category) {
  final (icon, (color, background)) = switch (type) {
    'subscription.payment_received' => (LucideIcons.fileCheck2, _teal),
    'subscription.approved' => (LucideIcons.circleCheck, _green),
    'subscription.rejected' => (LucideIcons.circleX, _red),
    'subscription.expiring' => (LucideIcons.hourglass, _amber),
    'subscription.expired' => (LucideIcons.calendarX2, _red),
    'transport.delay' => (LucideIcons.clockAlert, _amber),
    'transport.arrived' => (LucideIcons.mapPin, _green),
    'transport.departed' => (LucideIcons.busFront, _green),
    'transport.cancelled' => (LucideIcons.ban, _red),
    'transport.return_departing' => (LucideIcons.school, _green),
    'announcement.supervisor' => (LucideIcons.megaphone, _green),
    _ => switch (category) {
        NotificationCategory.subscription => (LucideIcons.receiptText, _teal),
        NotificationCategory.transport => (LucideIcons.busFront, _green),
        NotificationCategory.reminder => (LucideIcons.calendarClock, _teal),
        NotificationCategory.announcement => (LucideIcons.bell, _teal),
      },
  };
  return (icon: icon, color: color, background: background);
}

/// The name of a category, as the preferences and the system channels show it.
String notificationCategoryLabel(NotificationCategory category) => switch (category) {
      NotificationCategory.subscription => 'الاشتراك والدفع',
      NotificationCategory.transport => 'حركة الباص',
      NotificationCategory.announcement => 'إعلانات الشركة والمشرف',
      NotificationCategory.reminder => 'تذكير تأكيد الرحلة',
    };
