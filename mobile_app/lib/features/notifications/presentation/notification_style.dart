import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/ui/ui.dart';
import '../data/notifications_repository.dart';

/// The icon and tone a notification is drawn with, from its type; a type this
/// version does not know takes the look of its category. [color] and
/// [background] are the tone's own two colours.
typedef NotificationStyle = ({IconData icon, BasakTone tone, Color color, Color background});

NotificationStyle notificationStyle(String type, NotificationCategory category) {
  final (IconData icon, BasakTone tone) = switch (type) {
    'subscription.payment_received' => (LucideIcons.receiptText, BasakTone.neutral),
    'subscription.approved' => (LucideIcons.check, BasakTone.success),
    'subscription.rejected' => (LucideIcons.circleX, BasakTone.danger),
    'subscription.expiring' => (LucideIcons.hourglass, BasakTone.warning),
    'subscription.expired' => (LucideIcons.calendarX2, BasakTone.danger),
    'transport.delay' => (LucideIcons.clockAlert, BasakTone.warning),
    'transport.arrived' => (LucideIcons.mapPin, BasakTone.success),
    'transport.departed' => (LucideIcons.bus, BasakTone.success),
    'transport.cancelled' => (LucideIcons.ban, BasakTone.danger),
    'transport.return_departing' => (LucideIcons.school, BasakTone.success),
    'announcement.supervisor' => (LucideIcons.megaphone, BasakTone.info),
    _ => switch (category) {
        NotificationCategory.subscription => (LucideIcons.receiptText, BasakTone.neutral),
        NotificationCategory.transport => (LucideIcons.bus, BasakTone.success),
        NotificationCategory.reminder => (LucideIcons.clock3, BasakTone.neutral),
        NotificationCategory.announcement => (LucideIcons.bell, BasakTone.info),
      },
  };
  const colors = BasakColors.light;
  return (icon: icon, tone: tone, color: tone.foreground(colors), background: tone.tint(colors));
}

/// The name of a category, as the preferences and the system channels show it.
String notificationCategoryLabel(NotificationCategory category) => switch (category) {
      NotificationCategory.subscription => 'الاشتراك والدفع',
      NotificationCategory.transport => 'حركة الباص',
      NotificationCategory.announcement => 'إعلانات الشركة والمشرف',
      NotificationCategory.reminder => 'تذكير تأكيد الرحلة',
    };
