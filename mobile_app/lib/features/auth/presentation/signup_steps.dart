import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/core/ui/ui.dart';

import '../data/auth_repository.dart';
import 'password_strength.dart';

/// The four steps of the sign-up, as the rail names them, each with the
/// question it asks and one line of why.
const signupSteps = <({String rail, String title, String why})>[
  (
    rail: 'بياناتك',
    title: 'من أنت؟',
    why: 'اسمك كما في بطاقتك الجامعية، ورقم هاتفك هو اسم دخولك.',
  ),
  (
    rail: 'دراستك',
    title: 'أين تدرس؟',
    why: 'جامعتك تحدّد الخطوط والشركات التي تظهر لك.',
  ),
  (
    rail: 'صورتك',
    title: 'صورة واضحة لوجهك',
    why: 'تظهر على بطاقتك، والمشرف يطابقها عند الصعود.',
  ),
  (
    rail: 'كلمة المرور',
    title: 'كلمة مرور',
    why: '8 أحرف على الأقل. اختر شيئاً لا تستخدمه في مكان آخر.',
  ),
];

Widget _blocks(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: BasakSpace.s18),
          children[i],
        ],
      ],
    );

/// Step 1 · the name and the phone number.
class SignupDetailsStep extends StatelessWidget {
  final TextEditingController name;
  final TextEditingController phone;
  final FocusNode phoneFocus;
  final String? nameError;
  final String? phoneError;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onPhoneChanged;
  final VoidCallback onDone;

  const SignupDetailsStep({
    super.key,
    required this.name,
    required this.phone,
    required this.phoneFocus,
    this.nameError,
    this.phoneError,
    required this.onNameChanged,
    required this.onPhoneChanged,
    required this.onDone,
  });

  static const nameMessage = 'اكتب الاسم ثلاثياً على الأقل.';
  static const phoneMessage = 'اكتب رقم هاتف مصري صحيح من 11 رقماً.';

  static String? validateName(String value) =>
      value.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).length < 3 ? nameMessage : null;

  static String? validatePhone(String value) =>
      RegExp(r'^01[0125][0-9]{8}$').hasMatch(AuthRepository.normalizeEgyptianPhone(value)) ? null : phoneMessage;

  @override
  Widget build(BuildContext context) => GroupedFields(children: [
        GroupedField(
          key: const Key('signup-name'),
          label: 'الاسم بالكامل',
          hint: 'مثال: أحمد محمد علي',
          controller: name,
          error: nameError,
          keyboardType: TextInputType.name,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          onChanged: onNameChanged,
          onSubmitted: (_) => phoneFocus.requestFocus(),
        ),
        GroupedField(
          key: const Key('signup-phone'),
          label: 'رقم الهاتف',
          hint: '01XXXXXXXXX',
          controller: phone,
          focusNode: phoneFocus,
          error: phoneError,
          ltr: true,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+٠-٩]')),
            LengthLimitingTextInputFormatter(14),
          ],
          onChanged: onPhoneChanged,
          onSubmitted: (_) => onDone(),
        ),
      ]);
}

/// Step 2 · the university and the college, each from its sheet, and the
/// specialisation for whoever wants to give it.
class SignupStudyStep extends StatelessWidget {
  final AsyncValue<List<Map<String, String>>> universities;
  final String? university;
  final String? college;
  final TextEditingController specialisation;
  final String? universityError;
  final String? collegeError;
  final ValueChanged<List<Map<String, String>>> onPickUniversity;
  final VoidCallback onPickCollege;
  final VoidCallback onRetryUniversities;

  const SignupStudyStep({
    super.key,
    required this.universities,
    required this.university,
    required this.college,
    required this.specialisation,
    this.universityError,
    this.collegeError,
    required this.onPickUniversity,
    required this.onPickCollege,
    required this.onRetryUniversities,
  });

  static const universityMessage = 'اختر الجامعة من القائمة.';
  static const collegeMessage = 'اختر كليتك.';

  @override
  Widget build(BuildContext context) {
    final loaded = universities.valueOrNull;
    return _blocks([
      GroupedFields(children: [
        GroupedValue(
          key: const Key('signup-university'),
          label: 'الجامعة',
          value: university,
          placeholder: loaded != null
              ? 'اختر جامعتك'
              : (universities.hasError ? 'تعذر تحميل الجامعات' : 'جارٍ تحميل الجامعات…'),
          error: universityError,
          opensSheet: true,
          onTap: loaded == null ? null : () => onPickUniversity(loaded),
        ),
        GroupedValue(
          key: const Key('signup-college'),
          label: 'الكلية',
          value: college,
          placeholder: 'اختر كليتك',
          error: collegeError,
          opensSheet: true,
          onTap: onPickCollege,
        ),
        GroupedField(
          key: const Key('signup-specialisation'),
          label: 'التخصص (اختياري)',
          hint: 'مثال: هندسة مدنية',
          controller: specialisation,
          maxLength: AuthRepository.specialisationMaxLength,
          textInputAction: TextInputAction.done,
        ),
      ]),
      if (loaded == null && universities.hasError)
        InlineError(message: 'تعذر تحميل الجامعات', onRetry: onRetryUniversities),
      const InfoNote('لا يمكن تغيير الجامعة بعد التسجيل.'),
    ]);
  }
}

/// Step 3 · the photo: a dashed circle until there is one, and the two
/// places a photo comes from.
class SignupPhotoStep extends StatelessWidget {
  final Uint8List? photo;
  final VoidCallback? onCamera;
  final VoidCallback? onGallery;

  /// A tap on the circle itself: asks where the photo comes from.
  final VoidCallback? onTapPhoto;

  const SignupPhotoStep({super.key, required this.photo, this.onCamera, this.onGallery, this.onTapPhoto});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(top: BasakSpace.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhotoDrop(
              key: const Key('signup-photo'),
              image: photo == null ? null : MemoryImage(photo!),
              onTap: onTapPhoto,
            ),
            const SizedBox(height: BasakSpace.s16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: BasakSpace.s8,
              runSpacing: BasakSpace.s8,
              children: [
                BasakButton(
                  key: const Key('signup-photo-camera'),
                  label: 'الكاميرا',
                  icon: LucideIcons.camera,
                  onPressed: onCamera,
                  variant: BasakButtonVariant.surface,
                  size: BasakButtonSize.medium,
                  expand: false,
                ),
                BasakButton(
                  key: const Key('signup-photo-gallery'),
                  label: 'من الصور',
                  icon: LucideIcons.image,
                  onPressed: onGallery,
                  variant: BasakButtonVariant.surface,
                  size: BasakButtonSize.medium,
                  expand: false,
                ),
              ],
            ),
          ],
        ),
      );
}

/// Step 4 · the password, typed twice, how strong it is, and the terms.
class SignupPasswordStep extends StatelessWidget {
  final TextEditingController password;
  final TextEditingController confirmation;
  final FocusNode confirmationFocus;
  final bool hidePassword;
  final bool hideConfirmation;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirmation;
  final String? passwordError;
  final String? confirmationError;
  final ValueChanged<String> onPasswordChanged;
  final ValueChanged<String> onConfirmationChanged;
  final bool acceptedTerms;
  final ValueChanged<bool>? onAcceptedTerms;
  final String? termsError;
  final VoidCallback onDone;

  const SignupPasswordStep({
    super.key,
    required this.password,
    required this.confirmation,
    required this.confirmationFocus,
    required this.hidePassword,
    required this.hideConfirmation,
    required this.onTogglePassword,
    required this.onToggleConfirmation,
    this.passwordError,
    this.confirmationError,
    required this.onPasswordChanged,
    required this.onConfirmationChanged,
    required this.acceptedTerms,
    required this.onAcceptedTerms,
    this.termsError,
    required this.onDone,
  });

  static const termsMessage = 'وافق على الشروط وسياسة الخصوصية للمتابعة.';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strength = passwordStrength(password.text);
    final plain = context.text.bodySmall.copyWith(color: colors.ink2);
    final strong = plain.copyWith(color: colors.teal, fontWeight: FontWeight.w600);

    return _blocks([
      AutofillGroup(
        child: GroupedFields(children: [
          GroupedField(
            key: const Key('signup-password'),
            label: 'كلمة المرور',
            hint: '8 أحرف على الأقل',
            controller: password,
            error: passwordError,
            ltr: true,
            obscureText: hidePassword,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            trailing: PasswordEye(hidden: hidePassword, onTap: onTogglePassword),
            onChanged: onPasswordChanged,
            onSubmitted: (_) => confirmationFocus.requestFocus(),
          ),
          GroupedField(
            key: const Key('signup-confirmation'),
            label: 'تأكيد كلمة المرور',
            hint: 'أعد كتابتها',
            controller: confirmation,
            focusNode: confirmationFocus,
            error: confirmationError,
            ltr: true,
            obscureText: hideConfirmation,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            trailing: PasswordEye(hidden: hideConfirmation, onTap: onToggleConfirmation),
            onChanged: onConfirmationChanged,
            onSubmitted: (_) => onDone(),
          ),
        ]),
      ),
      // Judging an empty field as "weak" only scolds the student.
      if (password.text.isNotEmpty) StrengthMeter(level: strength.level, label: strength.label),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckRow(
            key: const Key('signup-terms'),
            value: acceptedTerms,
            onChanged: onAcceptedTerms,
            child: Text.rich(
              TextSpan(style: plain, children: [
                const TextSpan(text: 'أوافق على '),
                TextSpan(text: 'الشروط', style: strong),
                const TextSpan(text: ' و'),
                TextSpan(text: 'سياسة الخصوصية', style: strong),
                const TextSpan(text: '.'),
              ]),
            ),
          ),
          if (termsError != null) FieldNote(termsError!),
        ],
      ),
    ]);
  }
}
