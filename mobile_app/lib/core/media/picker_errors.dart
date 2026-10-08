import 'package:flutter/services.dart';

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
