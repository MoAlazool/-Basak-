import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../providers/auth_provider.dart';

/// Student "Forgot password".
/// 1. The student enters their phone number -> a reset request reaches their
///    bus company in the admin dashboard.
/// 2. The company admin verifies the student by phone and gives them a
///    6-digit one-time code (valid 30 minutes, 5 tries).
/// 3. The student enters the code and a new password, then signs in with it.
/// Pops with the phone number once the password has been changed.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialPhone = ''});
  final String initialPhone;

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  static const _teal = Color(0xFF1F6F8B);
  final _phoneForm = GlobalKey<FormState>();
  final _resetForm = GlobalKey<FormState>();
  late final _phone = TextEditingController(text: widget.initialPhone);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _codeStep = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String _clean(Object error) => error.toString().replaceFirst('Exception: ', '');

  Future<void> _request() async {
    FocusScope.of(context).unfocus();
    if (!_phoneForm.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(authRepositoryProvider).requestPasswordReset(_phone.text);
      if (mounted) setState(() => _codeStep = true);
    } catch (error) {
      if (mounted) setState(() => _error = _clean(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    FocusScope.of(context).unfocus();
    if (!_resetForm.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(authRepositoryProvider).resetPasswordWithCode(
            phone: _phone.text,
            code: _code.text,
            newPassword: _password.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم تغيير كلمة المرور. سجّل الدخول بكلمة المرور الجديدة.'),
        backgroundColor: Color(0xFF07865A),
      ));
      Navigator.of(context).pop(_phone.text.trim());
    } catch (error) {
      if (mounted) setState(() => _error = _clean(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _field(String hint, IconData icon, {Widget? suffix, String? prefix}) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 19),
        prefixText: prefix,
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
        fillColor: const Color(0xFFFAFCFE),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9FC),
      appBar: AppBar(
        title: const Text('استعادة كلمة المرور'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF17384A),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: _codeStep ? _codeForm() : _phoneFormView(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneFormView() => Form(
        key: _phoneForm,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(LucideIcons.keyRound, size: 40, color: _teal),
          const SizedBox(height: 12),
          const Text('أدخل رقم الهاتف المسجل في حسابك',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF17384A))),
          const SizedBox(height: 6),
          const Text(
              'سيصل طلبك إلى إدارة شركة النقل الخاصة بك. بعد التحقق من هويتك ستعطيك رمزاً من 6 أرقام لتعيين كلمة مرور جديدة.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF718695))),
          const SizedBox(height: 18),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: _field('010XXXXXXXX', LucideIcons.phone, prefix: '+20  '),
            validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10
                ? 'أدخل رقم هاتف مصري صحيح'
                : null,
          ),
          ..._errorBox(),
          const SizedBox(height: 16),
          _primary('إرسال طلب الاستعادة', _request),
          TextButton(
            onPressed: _busy ? null : () => setState(() { _codeStep = true; _error = null; }),
            child: const Text('لديّ رمز بالفعل'),
          ),
        ]),
      );

  Widget _codeForm() => Form(
        key: _resetForm,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFE7F8F0), borderRadius: BorderRadius.circular(14)),
            child: const Text(
                'تم إرسال طلبك. تواصل مع إدارة شركة النقل للحصول على رمز الاستعادة، ثم أدخله هنا مع كلمة المرور الجديدة. الرمز صالح لمدة 30 دقيقة.',
                style: TextStyle(fontSize: 13, color: Color(0xFF07865A))),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: _field('010XXXXXXXX', LucideIcons.phone, prefix: '+20  '),
            validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10
                ? 'أدخل رقم هاتف مصري صحيح'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _code,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            maxLength: 6,
            decoration: _field('رمز الاستعادة (6 أرقام)', LucideIcons.hash),
            validator: (v) => RegExp(r'^\d{6}$').hasMatch((v ?? '').trim())
                ? null
                : 'أدخل الرمز المكون من 6 أرقام',
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: _password,
            obscureText: _hide,
            decoration: _field('كلمة المرور الجديدة', LucideIcons.lockKeyhole,
                suffix: IconButton(
                  onPressed: () => setState(() => _hide = !_hide),
                  icon: Icon(_hide ? LucideIcons.eye : LucideIcons.eyeOff, size: 19),
                )),
            validator: (v) => (v ?? '').length < 8 ? 'كلمة المرور 8 أحرف على الأقل' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirm,
            obscureText: _hide,
            decoration: _field('تأكيد كلمة المرور', LucideIcons.lockKeyhole),
            validator: (v) => v != _password.text ? 'كلمتا المرور غير متطابقتين' : null,
          ),
          ..._errorBox(),
          const SizedBox(height: 16),
          _primary('تعيين كلمة المرور', _reset),
          TextButton(
            onPressed: _busy ? null : _request,
            child: const Text('إعادة إرسال الطلب'),
          ),
        ]),
      );

  List<Widget> _errorBox() => _error == null
      ? const []
      : [
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0), borderRadius: BorderRadius.circular(12)),
            child: Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFB42318), fontSize: 13)),
          ),
        ];

  Widget _primary(String label, VoidCallback onPressed) => SizedBox(
        height: 50,
        child: ElevatedButton(
          onPressed: _busy ? null : onPressed,
          style: ElevatedButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
}
