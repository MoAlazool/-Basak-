import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/notifications/push/notification_platform.dart';
import '../ui/feedback.dart';

/// What to tell the student when image_picker can't open the camera or the
/// photos, instead of failing silently. The codes are image_picker's.
String pickerErrorMessage(Object error) {
  final code = error is PlatformException ? error.code : '';
  return switch (code) {
    'camera_access_denied' =>
      'لا يوجد إذن لاستخدام الكاميرا. اسمح لتطبيق باصك باستخدام الكاميرا من إعدادات الهاتف ثم أعد المحاولة.',
    'photo_access_denied' =>
      'لا يوجد إذن للوصول إلى الصور. اسمح لتطبيق باصك بالوصول إلى الصور من إعدادات الهاتف ثم أعد المحاولة.',
    'no_available_camera' => 'لا توجد كاميرا متاحة على هذا الجهاز. اختر صورة من المعرض.',
    _ => 'تعذر فتح الكاميرا أو الصور. أعد المحاولة.',
  };
}

/// A refused permission is fixed in the phone's settings, nowhere else.
bool pickerErrorIsPermission(Object error) =>
    error is PlatformException && (error.code == 'camera_access_denied' || error.code == 'photo_access_denied');

/// Says [pickerErrorMessage] in a toast; after a refused permission the toast
/// also offers «فتح الإعدادات», which opens this app's page in the settings.
void showPickerError(BuildContext context, Object error) => BasakToast.show(
      context,
      pickerErrorMessage(error),
      kind: BasakToastKind.failure,
      actionLabel: pickerErrorIsPermission(error) ? 'فتح الإعدادات' : null,
      onAction: pickerErrorIsPermission(error) ? NotificationPlatform.openAppSettings : null,
    );
