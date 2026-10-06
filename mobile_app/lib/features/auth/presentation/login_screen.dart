import 'package:flutter/material.dart';
import '../data/auth_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../providers/auth_provider.dart';
import 'auth_form_styles.dart';
import 'forgot_password_screen.dart';
import '../../splash/splash_gate.dart';
import '../../../core/widgets/app_version_label.dart';

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
  final _passwordFocus = FocusNode();
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
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() => _error = _message(error));
      }
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
    _passwordFocus.dispose();
    super.dispose();
  }

  void _selectRole(bool supervisor) {
    if (_supervisor == supervisor) return;
    HapticFeedback.selectionClick();
    setState(() {
      _supervisor = supervisor;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authStateProvider).isLoading;
    return Scaffold(
      backgroundColor: splashBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
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
                        BoxShadow(color: Color(0x261F6F8B), blurRadius: 16, offset: Offset(0, 7)),
                      ],
                    ),
                    child: ClipOval(
                        child: Image.asset('assets/images/basak_icon.webp',
                            fit: BoxFit.cover)),
                  ),
                  const SizedBox(height: 12),
                  const Text('باصك | Basak',
                      style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: AuthStyles.ink)),
                  const SizedBox(height: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      _supervisor ? 'ادخل بحساب المشرف لمتابعة رحلات خطوطك.' : 'أهلاً بك. ادخل لمتابعة اشتراكك ورحلاتك.',
                      key: ValueKey(_supervisor),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, height: 1.5, color: AuthStyles.muted),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                        color: const Color(0xFFE4EEF4), borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      _roleTab('طالب', LucideIcons.graduationCap, !_supervisor, () => _selectRole(false)),
                      _roleTab('مشرف', LucideIcons.briefcaseBusiness, _supervisor, () => _selectRole(true)),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(color: Color(0x141F6F8B), blurRadius: 18, offset: Offset(0, 6)),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      // Lets the phone's password manager offer and save the login.
                      child: AutofillGroup(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(_supervisor ? 'رقم الهاتف أو البريد الإلكتروني' : 'رقم الهاتف',
                              style: AuthStyles.labelStyle),
                          const SizedBox(height: 7),
                          TextFormField(
                            controller: _phone,
                            keyboardType: _supervisor ? TextInputType.emailAddress : TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autofillHints: [
                              AutofillHints.username,
                              _supervisor ? AutofillHints.email : AutofillHints.telephoneNumber,
                            ],
                            inputFormatters: _supervisor
                                ? null
                                : [
                                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+٠-٩]')),
                                    LengthLimitingTextInputFormatter(14),
                                  ],
                            onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.left,
                            style: AuthStyles.inputStyle,
                            decoration: AuthStyles.field(
                              icon: _supervisor ? LucideIcons.userRound : LucideIcons.phone,
                              hint: _supervisor ? '01XXXXXXXXX أو name@example.com' : '01XXXXXXXXX',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return _supervisor ? 'اكتب رقم الهاتف أو البريد الإلكتروني.' : 'اكتب رقم الهاتف.';
                              }
                              if (!_supervisor && AuthRepository.normalizeEgyptianPhone(value).length < 10) {
                                return 'اكتب رقم هاتف مصري صحيح.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          const Text('كلمة المرور', style: AuthStyles.labelStyle),
                          const SizedBox(height: 7),
                          TextFormField(
                            controller: _password,
                            focusNode: _passwordFocus,
                            obscureText: _hidePassword,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => loading ? null : _submit(),
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.left,
                            style: AuthStyles.inputStyle,
                            decoration: AuthStyles.field(
                              icon: LucideIcons.lockKeyhole,
                              suffix: IconButton(
                                onPressed: () => setState(() => _hidePassword = !_hidePassword),
                                tooltip: _hidePassword ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
                                icon: Icon(_hidePassword ? LucideIcons.eye : LucideIcons.eyeOff,
                                    size: 20, color: AuthStyles.muted),
                              ),
                            ),
                            validator: (value) => value == null || value.isEmpty ? 'اكتب كلمة المرور.' : null,
                          ),
                          const SizedBox(height: 6),
                          Row(children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: loading ? null : () => setState(() => _remember = !_remember),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Row(children: [
                                    SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: Checkbox.adaptive(
                                        value: _remember,
                                        activeColor: AuthStyles.teal,
                                        onChanged: loading
                                            ? null
                                            : (value) => setState(() => _remember = value ?? false),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Only the identifier is kept; the password never is.
                                    const Flexible(
                                      child: Text('تذكّر رقمي',
                                          style: TextStyle(fontSize: 13.5, color: AuthStyles.label)),
                                    ),
                                  ]),
                                ),
                              ),
                            ),
                            if (!_supervisor)
                              TextButton(
                                onPressed: loading ? null : _openForgotPassword,
                                style: TextButton.styleFrom(
                                    foregroundColor: AuthStyles.teal, minimumSize: const Size(48, 44)),
                                child: const Text('نسيت كلمة المرور؟',
                                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                              ),
                          ]),
                          if (_error != null) ...[
                            const SizedBox(height: 4),
                            AuthStyles.errorBanner(_error!),
                          ],
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: loading ? null : _submit,
                            style: AuthStyles.primaryButton(),
                            child: loading
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                                : const Text('تسجيل الدخول'),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_supervisor) ...[
                    const Text('ليس لديك حساب؟', style: TextStyle(fontSize: 13.5, color: AuthStyles.muted)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: loading ? null : widget.onSignup,
                      icon: const Icon(LucideIcons.userRoundPlus, size: 18),
                      label: const Text('إنشاء حساب جديد'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AuthStyles.teal,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF8DBAC9)),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ] else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFE9F3F8), borderRadius: BorderRadius.circular(14)),
                      child: const Row(children: [
                        Icon(LucideIcons.info, size: 18, color: AuthStyles.teal),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('حسابات المشرفين ينشئها مسؤول النظام فقط.',
                              style: TextStyle(fontSize: 13, height: 1.45, color: AuthStyles.label)),
                        ),
                      ]),
                    ),
                  const SizedBox(height: 24),
                  const AppVersionLabel(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleTab(String label, IconData icon, bool selected, VoidCallback onTap) => Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              height: 46,
              decoration: BoxDecoration(
                color: selected ? AuthStyles.teal : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: selected
                    ? const [BoxShadow(color: Color(0x331F6F8B), blurRadius: 8, offset: Offset(0, 3))]
                    : null,
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 18, color: selected ? Colors.white : AuthStyles.muted),
                const SizedBox(width: 7),
                Text(label,
                    style: TextStyle(
                        fontSize: 15,
                        color: selected ? Colors.white : AuthStyles.muted,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      );
}
