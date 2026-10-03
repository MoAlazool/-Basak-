import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../providers/auth_provider.dart';
import 'forgot_password_screen.dart';
import '../../splash/splash_gate.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, required this.onSignup});
  final VoidCallback onSignup;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _storage = FlutterSecureStorage();
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _remember = false;
  bool _hidePassword = true;
  bool _supervisor = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRememberedPhone();
  }

  Future<void> _loadRememberedPhone() async {
    try {
      final saved = await _storage.read(key: 'basak.remembered_phone');
      if (!mounted || saved == null) return;
      setState(() {
        _phone.text = saved;
        _remember = true;
      });
    } catch (_) {
      // Keep sign-in usable on test platforms without secure-storage support.
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      if (_remember) {
        await _storage.write(
            key: 'basak.remembered_phone', value: _phone.text.trim());
      } else {
        await _storage.delete(key: 'basak.remembered_phone');
      }
      await ref.read(authStateProvider.notifier).signIn(
            identifier: _phone.text.trim(),
            password: _password.text,
          );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  String _message(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('invalid_credentials') ||
        message.contains('invalid login credentials') ||
        message.contains('email or password') ||
        message.contains('user not found') ||
        message.contains('invalid password')) {
      return 'رقم الهاتف أو كلمة المرور غير صحيحة.';
    }
    if (message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('connection refused') ||
        message.contains('clientexception')) {
      return 'تعذر الاتصال بالإنترنت. تحقق من الاتصال وحاول مرة أخرى.';
    }
    return 'تعذر تسجيل الدخول الآن. حاول مرة أخرى.';
  }

  Future<void> _openForgotPassword() async {
    final phone = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => ForgotPasswordScreen(initialPhone: _phone.text.trim()),
    ));
    if (phone != null && mounted) {
      setState(() {
        _phone.text = phone;
        _password.clear();
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authStateProvider).isLoading;
    return Scaffold(
      backgroundColor: splashBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  // The launch splash glides its logo onto this one.
                  Container(
                    key: basakLogoTargetKey,
                    width: 78,
                    height: 78,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Color(0x261F6F8B),
                            blurRadius: 16,
                            offset: Offset(0, 7)),
                      ],
                    ),
                    child: ClipOval(
                        child: Image.asset('assets/images/basak_icon.png',
                            fit: BoxFit.cover)),
                  ),
                  const SizedBox(height: 12),
                  const Text('باصك | Basak',
                      style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF17384A))),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                        color: const Color(0xFFE8F0F5),
                        borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      _roleTab('طالب', LucideIcons.graduationCap, !_supervisor,
                          () => setState(() => _supervisor = false)),
                      _roleTab(
                          'مشرف',
                          LucideIcons.briefcaseBusiness,
                          _supervisor,
                          () => setState(() => _supervisor = true)),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    elevation: 2,
                    shadowColor: const Color(0x141F6F8B),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22)),
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Form(
                        key: _formKey,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('رقم الهاتف المحمول',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF334B5A))),
                              const SizedBox(height: 7),
                              TextFormField(
                                controller: _phone,
                                keyboardType: _supervisor
                                    ? TextInputType.emailAddress
                                    : TextInputType.phone,
                                textDirection: TextDirection.ltr,
                                decoration: InputDecoration(
                                  hintText: _supervisor
                                      ? 'رقم الهاتف أو البريد الإلكتروني'
                                      : '010XXXXXXXX',
                                  prefixIcon:
                                      const Icon(LucideIcons.phone, size: 19),
                                  prefixText: _supervisor ? null : '+20  ',
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  filled: true,
                                  fillColor: const Color(0xFFFAFCFE),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return _supervisor
                                        ? 'أدخل رقم الهاتف أو البريد الإلكتروني'
                                        : 'رقم الهاتف مطلوب';
                                  }
                                  if (!_supervisor &&
                                      value
                                              .replaceAll(RegExp(r'\D'), '')
                                              .length <
                                          10) {
                                    return 'أدخل رقم هاتف مصري صحيح';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              const Text('كلمة المرور',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF334B5A))),
                              const SizedBox(height: 7),
                              TextFormField(
                                controller: _password,
                                obscureText: _hidePassword,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(
                                      LucideIcons.lockKeyhole,
                                      size: 19),
                                  suffixIcon: IconButton(
                                      onPressed: () => setState(
                                          () => _hidePassword = !_hidePassword),
                                      icon: Icon(
                                          _hidePassword
                                              ? LucideIcons.eye
                                              : LucideIcons.eyeOff,
                                          size: 19)),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  filled: true,
                                  fillColor: const Color(0xFFFAFCFE),
                                ),
                                validator: (value) =>
                                    value == null || value.isEmpty
                                        ? 'كلمة المرور مطلوبة'
                                        : null,
                              ),
                              if (!_supervisor)
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: TextButton(
                                    onPressed: loading ? null : _openForgotPassword,
                                    child: const Text('نسيت كلمة المرور؟'),
                                  ),
                                ),
                              const SizedBox(height: 5),
                              Material(
                                color: Colors.transparent,
                                child: CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _remember,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: const Text(
                                      'تذكر بيانات الدخول على هذا الجهاز',
                                      style: TextStyle(fontSize: 12)),
                                  onChanged: (value) => setState(
                                      () => _remember = value ?? false),
                                ),
                              ),
                              if (_error != null) ...[
                                Container(
                                    padding: const EdgeInsets.all(11),
                                    decoration: BoxDecoration(
                                        color: const Color(0xFFFFF1F0),
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: Text(_error!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Color(0xFFB42318),
                                            fontSize: 13))),
                                const SizedBox(height: 12),
                              ],
                              SizedBox(
                                height: 50,
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
                                  label: const Text('تسجيل الدخول',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF1F6F8B),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(15))),
                                ),
                              ),
                              if (!_supervisor) ...[
                                const SizedBox(height: 18),
                                const Text('ليس لديك حساب؟',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF718695))),
                                const SizedBox(height: 9),
                                OutlinedButton.icon(
                                  onPressed: widget.onSignup,
                                  icon: const Icon(LucideIcons.userRoundPlus,
                                      size: 18),
                                  label: const Text('إنشاء حساب جديد'),
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF1F6F8B),
                                      side: const BorderSide(
                                          color: Color(0xFF8DBAC9)),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(15)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 13)),
                                ),
                              ] else ...[
                                const SizedBox(height: 18),
                                const Text(
                                  'حسابات المشرفين ينشئها مسؤول النظام فقط.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 12, color: Color(0xFF718695)),
                                ),
                              ],
                            ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Dot(active: true),
                        SizedBox(width: 6),
                        _Dot(active: false),
                        SizedBox(width: 6),
                        _Dot(active: false),
                      ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleTab(
          String label, IconData icon, bool selected, VoidCallback onTap) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: selected ? const Color(0xFF1F6F8B) : Colors.transparent,
                borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon,
                  size: 17,
                  color: selected ? Colors.white : const Color(0xFF718695)),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF718695),
                      fontWeight: FontWeight.bold))
            ]),
          ),
        ),
      );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
      width: active ? 17 : 6,
      height: 6,
      decoration: BoxDecoration(
          color: active ? const Color(0xFF1F6F8B) : const Color(0xFFBED1DA),
          borderRadius: BorderRadius.circular(5)));
}
