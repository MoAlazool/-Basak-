import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../data/auth_repository.dart';
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
  final _picker = ImagePicker();
  String? _universityId;
  String? _university;
  XFile? _photo;
  bool _acceptedTerms = false;
  bool _hidePassword = true;
  bool _hideConfirmation = true;
  String? _error;

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
    final image = await _picker.pickImage(
        source: source, imageQuality: 82, maxWidth: 1200);
    if (image != null && mounted) setState(() => _photo = image);
  }

  Future<void> _showUniversityPicker(List<Map<String, String>> universities) async {
    var query = '';
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = universities.where((university) =>
              university['name']!.contains(query.trim())).toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Container(
                height: MediaQuery.sizeOf(context).height * 0.72,
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FBFD),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(width: 42, height: 4,
                        decoration: BoxDecoration(color: const Color(0xFFD5E1E8), borderRadius: BorderRadius.circular(4))),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                      child: Row(children: [
                        const Expanded(child: Text('اختر الجامعة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF17384A)))),
                        IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close_rounded)),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: TextField(
                        autofocus: true,
                        textDirection: TextDirection.rtl,
                        onChanged: (value) => setSheetState(() => query = value),
                        decoration: InputDecoration(
                          hintText: 'ابحث عن جامعتك',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('لا توجد جامعة بهذا الاسم'))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final university = filtered[index];
                                final selected = university['id'] == _universityId;
                                return Material(
                                  color: selected ? const Color(0xFFE6F4FA) : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => Navigator.pop(sheetContext, university['id']),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      child: Row(children: [
                                        Icon(Icons.account_balance_rounded, color: selected ? const Color(0xFF1F6F8B) : const Color(0xFF78909C)),
                                        const SizedBox(width: 12),
                                        Expanded(child: Text(university['name']!, textAlign: TextAlign.right, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: const Color(0xFF17384A)))),
                                        if (selected) const Icon(Icons.check_circle_rounded, color: Color(0xFF1F6F8B)),
                                      ]),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (!mounted || selectedId == null) return;
    final selected = universities.where((university) => university['id'] == selectedId).firstOrNull;
    setState(() {
      _universityId = selectedId;
      _university = selected?['name'];
      _universityText.text = _university ?? '';
      _error = null;
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_photo == null) {
      setState(() => _error = 'اختر صورتك الشخصية لإكمال التسجيل.');
      return;
    }
    if (!_acceptedTerms) {
      setState(() => _error = 'وافق على الشروط وسياسة الخصوصية للمتابعة.');
      return;
    }
    setState(() => _error = null);
    try {
      await ref.read(authStateProvider.notifier).registerStudent(
            phone: _phone.text.trim(),
            fullName: _name.text.trim(),
            university: _university ?? '',
            college: 'غير محدد',
            password: _password.text,
            profileImageBytes:
                _photo == null ? null : await _photo!.readAsBytes(),
            profileImageExtension: _photo?.name.split('.').last,
          );
    } catch (error) {
      if (mounted) {
        setState(() => _error = error
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final universities = ref.watch(activeUniversitiesProvider);
    final loading = ref.watch(authStateProvider).isLoading;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9FC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.all(19),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border:
                          Border.all(color: const Color(0xFF6366F1), width: 2),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x101F6F8B),
                            blurRadius: 18,
                            offset: Offset(0, 5))
                      ]),
                  child: Form(
                    key: _formKey,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                    color: const Color(0xFF1F6F8B),
                                    borderRadius: BorderRadius.circular(13)),
                                child: const Icon(LucideIcons.busFront,
                                    color: Colors.white)),
                            const SizedBox(width: 11),
                            const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('BASAK',
                                      style: TextStyle(
                                          fontSize: 11,
                                          letterSpacing: 1.3,
                                          color: Color(0xFF718695))),
                                  Text('إنشاء حساب جديد',
                                      style: TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF17384A)))
                                ]),
                          ]),
                          const SizedBox(height: 18),
                          _label('الاسم بالكامل (ثلاثي أو رباعي)'),
                          _field(
                              controller: _name,
                              hint: 'مثال: أحمد محمد علي',
                              icon: LucideIcons.userRound,
                              validator: (value) =>
                                  (value?.trim().split(RegExp(r'\s+')).length ??
                                              0) <
                                          3
                                      ? 'أدخل الاسم ثلاثياً على الأقل.'
                                      : null),
                          const SizedBox(height: 13),
                          _label('الصورة الشخصية'),
                          Row(children: [
                            CircleAvatar(
                                radius: 30,
                                backgroundColor: const Color(0xFFEAF5FA),
                                backgroundImage: _photo == null
                                    ? null
                                    : FileImage(File(_photo!.path)),
                                child: _photo == null
                                    ? const Icon(LucideIcons.camera,
                                        color: Color(0xFF1F6F8B))
                                    : null),
                            const SizedBox(width: 10),
                            Expanded(
                                child: OutlinedButton.icon(
                                    onPressed: () => _showPhotoOptions(),
                                    icon: const Icon(LucideIcons.imagePlus,
                                        size: 17),
                                    label: Text(_photo == null
                                        ? 'اختيار صورة'
                                        : 'تغيير الصورة'))),
                          ]),
                          const SizedBox(height: 5),
                          const Text(
                              'بعد إنشاء الحساب لا يمكن تغيير الصورة إلا بحذف الحساب والاشتراك.',
                              style: TextStyle(
                                  fontSize: 10.5, color: Color(0xFFB54708))),
                          const SizedBox(height: 13),
                          _label('رقم الهاتف المسجل (تأكيد الحجوزات)'),
                          _field(
                              controller: _phone,
                              hint: '010XXXXXXXX',
                              icon: LucideIcons.phone,
                              keyboardType: TextInputType.phone,
                              prefix: '+20',
                              validator: (value) {
                                final digits =
                                    AuthRepository.normalizeEgyptianPhone(
                                        value ?? '');
                                return !RegExp(r'^01[0125][0-9]{8}$')
                                        .hasMatch(digits)
                                    ? 'أدخل رقم هاتف مصري صحيح.'
                                    : null;
                              }),
                          const SizedBox(height: 13),
                          _label('الجامعة'),
                          universities.when(
                            data: (values) => TextFormField(
                              controller: _universityText,
                              readOnly: true,
                              onTap: () => _showUniversityPicker(values),
                              textDirection: TextDirection.rtl,
                              decoration: _decoration(
                                icon: LucideIcons.building2,
                                hint: 'اختر جامعتك',
                              ).copyWith(
                                suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF1F6F8B)),
                              ),
                              validator: (_) => _universityId == null
                                  ? 'اختر الجامعة من القائمة.'
                                  : null,
                            ),
                            loading: () => const LinearProgressIndicator(),
                            error: (error, _) => _retryMessage(
                                'تعذر تحميل الجامعات',
                                () =>
                                    ref.invalidate(activeUniversitiesProvider)),
                          ),
                          const SizedBox(height: 13),
                          _label('كلمة المرور'),
                          _field(
                              controller: _password,
                              icon: LucideIcons.lockKeyhole,
                              obscure: _hidePassword,
                              suffix: IconButton(
                                  onPressed: () => setState(
                                      () => _hidePassword = !_hidePassword),
                                  icon: Icon(
                                      _hidePassword
                                          ? LucideIcons.eye
                                          : LucideIcons.eyeOff,
                                      size: 18)),
                              onChanged: (_) => setState(() {}),
                              validator: (value) => (value?.length ?? 0) < 8
                                  ? 'كلمة المرور يجب أن تكون 8 أحرف على الأقل.'
                                  : null),
                          const SizedBox(height: 5),
                          _strengthMeter,
                          const SizedBox(height: 11),
                          _label('تأكيد كلمة المرور'),
                          _field(
                              controller: _confirmation,
                              icon: LucideIcons.keyRound,
                              obscure: _hideConfirmation,
                              suffix: IconButton(
                                  onPressed: () => setState(() =>
                                      _hideConfirmation = !_hideConfirmation),
                                  icon: Icon(
                                      _hideConfirmation
                                          ? LucideIcons.eye
                                          : LucideIcons.eyeOff,
                                      size: 18)),
                              validator: (value) => value != _password.text
                                  ? 'كلمتا المرور غير متطابقتين.'
                                  : null),
                          const SizedBox(height: 8),
                          Material(
                            color: Colors.transparent,
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _acceptedTerms,
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (value) => setState(
                                  () => _acceptedTerms = value ?? false),
                              title: const Text(
                                  'أوافق على الشروط والأحكام وسياسة الخصوصية لمنظومة النقل الجامعي',
                                  style:
                                      TextStyle(fontSize: 11.5, height: 1.35)),
                            ),
                          ),
                          if (_error != null) ...[
                            Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFFFF1F0),
                                    borderRadius: BorderRadius.circular(12)),
                                child: Text(_error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Color(0xFFB42318),
                                        fontSize: 12))),
                            const SizedBox(height: 10),
                          ],
                          SizedBox(
                              height: 49,
                              child: ElevatedButton.icon(
                                  onPressed: loading ? null : _submit,
                                  icon: loading
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white))
                                      : const Icon(LucideIcons.arrowLeft,
                                          size: 18),
                                  label: const Text('إنشاء الحساب',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF1F6F8B),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(15))))),
                        ]),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(alignment: WrapAlignment.center, children: [
                  const Text('لديك حساب بالفعل؟ '),
                  GestureDetector(
                      onTap: widget.onLogin,
                      child: const Text('تسجيل الدخول',
                          style: TextStyle(
                              color: Color(0xFF1F6F8B),
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline))),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPhotoOptions() => showModalBottomSheet<void>(
        context: context,
        builder: (context) => SafeArea(
            child: Wrap(children: [
          ListTile(
              leading: const Icon(LucideIcons.image),
              title: const Text('اختيار من المعرض'),
              onTap: () {
                Navigator.pop(context);
                _choosePhoto(ImageSource.gallery);
              }),
          ListTile(
              leading: const Icon(LucideIcons.camera),
              title: const Text('التقاط صورة بالكاميرا'),
              onTap: () {
                Navigator.pop(context);
                _choosePhoto(ImageSource.camera);
              }),
        ])),
      );

  Widget get _strengthMeter {
    final score = _strength;
    final label = score < 2
        ? 'ضعيفة'
        : score < 4
            ? 'متوسطة'
            : 'قوية';
    final color = score < 2
        ? const Color(0xFFEF4444)
        : score < 4
            ? const Color(0xFFF59E0B)
            : const Color(0xFF16A34A);
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text('قوة كلمة المرور: $label',
          style: TextStyle(fontSize: 10.5, color: color)),
      const SizedBox(height: 4),
      Row(
        children: List.generate(
          4,
          (index) => Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(left: index == 3 ? 0 : 4),
              decoration: BoxDecoration(
                color: index < score ? color : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _label(String value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(value,
          textAlign: TextAlign.right,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334B5A))));

  InputDecoration _decoration({required IconData icon, required String hint}) =>
      InputDecoration(
          prefixIcon: Icon(icon, size: 18),
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          filled: true,
          fillColor: const Color(0xFFFAFCFE));

  Widget _field(
          {required TextEditingController controller,
          required IconData icon,
          String? hint,
          String? prefix,
          TextInputType? keyboardType,
          bool obscure = false,
          Widget? suffix,
          String? Function(String?)? validator,
          ValueChanged<String>? onChanged}) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscure,
        onChanged: onChanged,
        validator: validator,
        autovalidateMode:
            validator == null ? null : AutovalidateMode.onUserInteraction,
        textDirection: keyboardType == TextInputType.phone
            ? TextDirection.ltr
            : TextDirection.rtl,
        decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18),
            prefixText: prefix == null ? null : '$prefix  ',
            hintText: hint,
            suffixIcon: suffix,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: true,
            fillColor: const Color(0xFFFAFCFE)),
      );

  Widget _retryMessage(String message, VoidCallback retry) => Row(children: [
        Expanded(
            child: Text(message,
                style:
                    const TextStyle(color: Color(0xFFB42318), fontSize: 12))),
        TextButton(onPressed: retry, child: const Text('إعادة المحاولة'))
      ]);
}
