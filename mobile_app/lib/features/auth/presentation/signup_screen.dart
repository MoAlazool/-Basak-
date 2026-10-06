import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../core/widgets/photo_adjust_screen.dart';
import '../data/auth_repository.dart';
import 'auth_form_styles.dart';
import 'university_picker_sheet.dart';
import '../providers/auth_provider.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key, required this.onLogin});
  final VoidCallback onLogin;

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _universityText = TextEditingController();
  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmationFocus = FocusNode();
  final _photoKey = GlobalKey();
  final _errorKey = GlobalKey();
  String? _universityId;
  String? _university;
  /// The profile photo exactly as the student framed it; uploaded with the account.
  Uint8List? _photo;
  bool _acceptedTerms = false;
  bool _hidePassword = true;
  bool _hideConfirmation = true;
  String? _error;
  bool _photoMissing = false;

  int get _strength {
    final value = _password.text;
    var score = 0;
    if (value.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(value) && RegExp(r'[a-z]').hasMatch(value)) {
      score++;
    }
    if (RegExp(r'\d').hasMatch(value)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;
    return score;
  }

  Future<void> _choosePhoto(ImageSource source) async {
    // Cancelling at any step keeps the photo chosen before, if any.
    final framed = await ProfilePhoto.pickAndAdjust(context, source);
    if (framed != null && mounted) {
      HapticFeedback.selectionClick();
      setState(() {
        _photo = framed;
        _photoMissing = false;
        _error = null;
      });
    }
  }

  Future<void> _showUniversityPicker(List<Map<String, String>> universities) async {
    FocusScope.of(context).unfocus();
    final selectedId = await UniversityPickerSheet.show(context,
        universities: universities, selectedId: _universityId);

    if (!mounted || selectedId == null) return;
    final selected = universities.where((university) => university['id'] == selectedId).firstOrNull;
    setState(() {
      _universityId = selectedId;
      _university = selected?['name'];
      _universityText.text = _university ?? '';
      _error = null;
    });
  }

  /// Scrolls to what needs attention, so a problem is never off-screen.
  void _reveal(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (target != null && mounted) {
        Scrollable.ensureVisible(target,
            alignment: 0.2, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _fail(String message, {GlobalKey? reveal}) {
    HapticFeedback.mediumImpact();
    setState(() => _error = message);
    _reveal(reveal ?? _errorKey);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final fieldsValid = _formKey.currentState!.validate();
    if (_photo == null) {
      setState(() => _photoMissing = true);
      return _fail('أضف صورتك الشخصية لإكمال التسجيل.', reveal: _photoKey);
    }
    if (!fieldsValid) {
      return _fail('راجع البيانات المظللة بالأحمر.', reveal: _photoKey);
    }
    if (!_acceptedTerms) {
      return _fail('وافق على الشروط وسياسة الخصوصية للمتابعة.');
    }
    setState(() => _error = null);
    try {
      await ref.read(authStateProvider.notifier).registerStudent(
            phone: _phone.text.trim(),
            fullName: _name.text.trim(),
            university: _university ?? '',
            college: 'غير محدد',
            password: _password.text,
            profileImageBytes: _photo,
            profileImageExtension: 'jpg',
          );
    } catch (error) {
      if (mounted) {
        _fail(error
            .toString()
            .replaceAll('Exception: ', '')
            .replaceAll('AuthException: ', ''));
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmation.dispose();
    _universityText.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    _confirmationFocus.dispose();
    super.dispose();
  }

  static const _teal = Color(0xFF1F6F8B);
  static const _ink = Color(0xFF17384A);
  static const _muted = Color(0xFF6B8494);
  static const _danger = Color(0xFFB42318);

  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final universities = ref.watch(activeUniversitiesProvider);
    final loading = ref.watch(authStateProvider).isLoading;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9FC),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: IconButton(
                        onPressed: loading ? null : widget.onLogin,
                        tooltip: 'رجوع لتسجيل الدخول',
                        // Flutter mirrors these arrows itself in a right-to-left screen.
                        icon: Icon(_isIOS ? Icons.arrow_back_ios_new_rounded : Icons.arrow_back_rounded,
                            size: _isIOS ? 20 : 24,
                            color: _ink),
                      ),
                    ),
                    const Text('إنشاء حساب جديد',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _ink)),
                    const SizedBox(height: 4),
                    const Text('ثلاث خطوات بسيطة: صورتك، بياناتك، وكلمة المرور.',
                        style: TextStyle(fontSize: 14, height: 1.5, color: _muted)),
                    const SizedBox(height: 20),

                    // ---- 1. Photo
                    _section(
                      key: _photoKey,
                      step: '١',
                      title: 'الصورة الشخصية',
                      child: Column(children: [
                        Semantics(
                          button: true,
                          label: _photo == null ? 'إضافة الصورة الشخصية' : 'تغيير الصورة الشخصية',
                          child: GestureDetector(
                            onTap: loading ? null : _showPhotoOptions,
                            child: Stack(clipBehavior: Clip.none, children: [
                              Container(
                                width: 104,
                                height: 104,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFEAF5FA),
                                  border: Border.all(
                                      color: _photoMissing ? _danger : const Color(0xFFCFE3EE), width: 2),
                                  image: _photo == null
                                      ? null
                                      : DecorationImage(image: MemoryImage(_photo!), fit: BoxFit.cover),
                                ),
                                child: _photo == null
                                    ? const Icon(LucideIcons.userRound, size: 44, color: Color(0xFF8FB3CC))
                                    : null,
                              ),
                              PositionedDirectional(
                                bottom: -2,
                                end: -2,
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: _teal,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 3),
                                  ),
                                  child: Icon(_photo == null ? LucideIcons.camera : LucideIcons.pencil,
                                      size: 16, color: Colors.white),
                                ),
                              ),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: loading ? null : _showPhotoOptions,
                          style: TextButton.styleFrom(foregroundColor: _teal),
                          child: Text(_photo == null ? 'إضافة صورة' : 'تغيير الصورة',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                        Text(
                          _photoMissing
                              ? 'الصورة مطلوبة: تظهر على بطاقتك ليتعرّف عليك المشرف.'
                              : 'صورة واضحة لوجهك. تظهر على بطاقتك ولا يمكن تغييرها بعد إنشاء الحساب.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12.5, height: 1.5, color: _photoMissing ? _danger : _muted),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),

                    // ---- 2. Details
                    _section(
                      step: '٢',
                      title: 'بياناتك',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _label('الاسم بالكامل'),
                        _field(
                          controller: _name,
                          focusNode: _nameFocus,
                          hint: 'مثال: أحمد محمد علي',
                          helper: 'ثلاثي أو رباعي كما في بطاقتك الجامعية.',
                          icon: LucideIcons.userRound,
                          keyboardType: TextInputType.name,
                          capitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          action: TextInputAction.next,
                          onSubmitted: (_) => _phoneFocus.requestFocus(),
                          validator: (value) =>
                              (value?.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).length ?? 0) < 3
                                  ? 'اكتب الاسم ثلاثياً على الأقل.'
                                  : null,
                        ),
                        const SizedBox(height: 16),
                        _label('رقم الهاتف'),
                        _field(
                          controller: _phone,
                          focusNode: _phoneFocus,
                          hint: '01XXXXXXXXX',
                          helper: 'تسجّل به الدخول ونؤكد به حجوزاتك.',
                          icon: LucideIcons.phone,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          formatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9+٠-٩]')),
                            LengthLimitingTextInputFormatter(14),
                          ],
                          ltr: true,
                          action: TextInputAction.done,
                          onSubmitted: (_) => FocusScope.of(context).unfocus(),
                          validator: (value) {
                            final digits = AuthRepository.normalizeEgyptianPhone(value ?? '');
                            return !RegExp(r'^01[0125][0-9]{8}$').hasMatch(digits)
                                ? 'اكتب رقم هاتف مصري صحيح من 11 رقماً.'
                                : null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _label('الجامعة'),
                        universities.when(
                          data: (values) => TextFormField(
                            controller: _universityText,
                            readOnly: true,
                            onTap: () => _showUniversityPicker(values),
                            style: const TextStyle(fontSize: 16, color: _ink),
                            decoration: _decoration(icon: LucideIcons.building2, hint: 'اختر جامعتك').copyWith(
                              suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded, color: _teal),
                            ),
                            validator: (_) => _universityId == null ? 'اختر الجامعة من القائمة.' : null,
                          ),
                          loading: () => const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: LinearProgressIndicator(minHeight: 3),
                          ),
                          error: (error, _) => _retryMessage(
                              'تعذر تحميل الجامعات', () => ref.invalidate(activeUniversitiesProvider)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),

                    // ---- 3. Password
                    _section(
                      step: '٣',
                      title: 'كلمة المرور',
                      child: AutofillGroup(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _label('كلمة المرور'),
                          _field(
                            controller: _password,
                            focusNode: _passwordFocus,
                            hint: '8 أحرف على الأقل',
                            icon: LucideIcons.lockKeyhole,
                            obscure: _hidePassword,
                            ltr: true,
                            autofillHints: const [AutofillHints.newPassword],
                            action: TextInputAction.next,
                            onSubmitted: (_) => _confirmationFocus.requestFocus(),
                            suffix: _visibilityToggle(
                                _hidePassword, () => setState(() => _hidePassword = !_hidePassword)),
                            onChanged: (_) => setState(() {}),
                            validator: (value) =>
                                (value?.length ?? 0) < 8 ? 'كلمة المرور 8 أحرف على الأقل.' : null,
                          ),
                          // Judging an empty field as "weak" only scolds the student.
                          if (_password.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _strengthMeter,
                          ],
                          const SizedBox(height: 16),
                          _label('تأكيد كلمة المرور'),
                          _field(
                            controller: _confirmation,
                            focusNode: _confirmationFocus,
                            hint: 'أعد كتابة كلمة المرور',
                            icon: LucideIcons.keyRound,
                            obscure: _hideConfirmation,
                            ltr: true,
                            autofillHints: const [AutofillHints.newPassword],
                            action: TextInputAction.done,
                            onSubmitted: (_) => FocusScope.of(context).unfocus(),
                            suffix: _visibilityToggle(_hideConfirmation,
                                () => setState(() => _hideConfirmation = !_hideConfirmation)),
                            validator: (value) =>
                                value != _password.text ? 'كلمتا المرور غير متطابقتين.' : null,
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // The whole row is the tap target, not just the small box.
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: loading ? null : () => setState(() => _acceptedTerms = !_acceptedTerms),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: Checkbox.adaptive(
                              value: _acceptedTerms,
                              activeColor: _teal,
                              onChanged: loading
                                  ? null
                                  : (value) => setState(() => _acceptedTerms = value ?? false),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('أوافق على الشروط والأحكام وسياسة الخصوصية لمنظومة النقل الجامعي.',
                                style: TextStyle(fontSize: 13.5, height: 1.5, color: Color(0xFF334B5A))),
                          ),
                        ]),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 6),
                      AuthStyles.errorBanner(_error!, key: _errorKey),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _teal,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF8FB3C2),
                          disabledForegroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: loading
                            ? const Row(mainAxisSize: MainAxisSize.min, children: [
                                SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                SizedBox(width: 10),
                                Text('جاري إنشاء الحساب...',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              ])
                            : const Text('إنشاء الحساب',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: loading ? null : widget.onLogin,
                      style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      child: const Text.rich(TextSpan(
                        style: TextStyle(fontSize: 14.5, color: _muted),
                        children: [
                          TextSpan(text: 'لديك حساب بالفعل؟ '),
                          TextSpan(
                              text: 'تسجيل الدخول',
                              style: TextStyle(color: _teal, fontWeight: FontWeight.w800)),
                        ],
                      )),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Camera or gallery, in the form each platform's users expect.
  Future<void> _showPhotoOptions() async {
    FocusScope.of(context).unfocus();
    final Future<ImageSource?> choice = _isIOS
        ? showCupertinoModalPopup<ImageSource>(
            context: context,
            builder: (sheet) => CupertinoActionSheet(
              title: const Text('الصورة الشخصية'),
              actions: [
                CupertinoActionSheetAction(
                    onPressed: () => Navigator.pop(sheet, ImageSource.camera),
                    child: const Text('التقاط صورة بالكاميرا')),
                CupertinoActionSheetAction(
                    onPressed: () => Navigator.pop(sheet, ImageSource.gallery),
                    child: const Text('اختيار من الصور')),
              ],
              cancelButton: CupertinoActionSheetAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.pop(sheet),
                  child: const Text('إلغاء')),
            ),
          )
        : showModalBottomSheet<ImageSource>(
            context: context,
            showDragHandle: true,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            builder: (sheet) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(
                      minTileHeight: 56,
                      leading: const Icon(LucideIcons.camera, color: _teal),
                      title: const Text('التقاط صورة بالكاميرا'),
                      onTap: () => Navigator.pop(sheet, ImageSource.camera)),
                  ListTile(
                      minTileHeight: 56,
                      leading: const Icon(LucideIcons.image, color: _teal),
                      title: const Text('اختيار من المعرض'),
                      onTap: () => Navigator.pop(sheet, ImageSource.gallery)),
                ]),
              ),
            ),
          );
    final source = await choice;
    if (source != null && mounted) await _choosePhoto(source);
  }

  Widget _visibilityToggle(bool hidden, VoidCallback onPressed) => IconButton(
        onPressed: onPressed,
        tooltip: hidden ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
        icon: Icon(hidden ? LucideIcons.eye : LucideIcons.eyeOff, size: 20, color: _muted),
      );

  Widget get _strengthMeter {
    final score = _strength;
    final label = score < 2 ? 'ضعيفة' : score < 4 ? 'متوسطة' : 'قوية';
    final color = score < 2
        ? const Color(0xFFDC2626)
        : score < 4
            ? const Color(0xFFD97706)
            : const Color(0xFF15803D);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        children: List.generate(
          4,
          (index) => Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 5,
              margin: EdgeInsetsDirectional.only(end: index == 3 ? 0 : 5),
              decoration: BoxDecoration(
                color: index < score ? color : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
          score < 4
              ? 'قوة كلمة المرور: $label. أضف حروفاً كبيرة وصغيرة وأرقاماً ورمزاً لتقويتها.'
              : 'قوة كلمة المرور: $label',
          style: TextStyle(fontSize: 12.5, height: 1.4, color: color)),
    ]);
  }

  Widget _section({Key? key, required String step, required String title, required Widget child}) =>
      Container(
        key: key,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x0F1F6F8B), blurRadius: 16, offset: Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Color(0xFFE3F2FA), shape: BoxShape.circle),
              child: Text(step,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _teal)),
            ),
            const SizedBox(width: 9),
            Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: _ink)),
          ]),
          const SizedBox(height: 16),
          child,
        ]),
      );

  Widget _label(String value) => Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(value,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF334B5A))));

  InputDecoration _decoration({required IconData icon, String? hint, String? helper, Widget? suffix}) =>
      AuthStyles.field(icon: icon, hint: hint, helper: helper, suffix: suffix);

  Widget _field({
    required TextEditingController controller,
    required IconData icon,
    FocusNode? focusNode,
    String? hint,
    String? helper,
    TextInputType? keyboardType,
    TextCapitalization capitalization = TextCapitalization.none,
    List<String>? autofillHints,
    List<TextInputFormatter>? formatters,
    TextInputAction? action,
    ValueChanged<String>? onSubmitted,
    bool obscure = false,
    bool ltr = false,
    Widget? suffix,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) =>
      TextFormField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        textCapitalization: capitalization,
        autofillHints: autofillHints,
        inputFormatters: formatters,
        textInputAction: action,
        onFieldSubmitted: onSubmitted,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: !obscure,
        onChanged: onChanged,
        validator: validator,
        autovalidateMode: validator == null ? null : AutovalidateMode.onUserInteraction,
        // Numbers and passwords read left to right even in an Arabic form.
        textDirection: ltr ? TextDirection.ltr : null,
        textAlign: ltr ? TextAlign.left : TextAlign.start,
        style: const TextStyle(fontSize: 16, color: _ink),
        decoration: _decoration(icon: icon, hint: hint, helper: helper, suffix: suffix),
      );

  Widget _retryMessage(String message, VoidCallback retry) => Row(children: [
        Expanded(child: Text(message, style: const TextStyle(color: _danger, fontSize: 13))),
        TextButton(onPressed: retry, child: const Text('إعادة المحاولة'))
      ]);
}
