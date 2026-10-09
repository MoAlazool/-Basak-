import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:basak_mobile/core/ui/ui.dart';

import '../data/auth_repository.dart';
import '../providers/auth_provider.dart';
import 'forgot_password_screen.dart';

/// Sign-in: the student's, or, with [supervisor], the supervisor's own
/// screen. The two differ in their words and in what the first field takes;
/// the role itself always comes from the server after signing in.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    required this.onSignup,
    this.onBack,
    this.onOtherRole,
    this.supervisor = false,
  });

  /// "طالب جديد؟ إنشاء حساب".
  final VoidCallback onSignup;

  /// Back to the welcome screen.
  final VoidCallback? onBack;

  /// "دخول المشرفين" on the student's screen, "دخول الطلاب" on the supervisor's.
  final VoidCallback? onOtherRole;

  final bool supervisor;

  /// What a refused sign-in says, under the password field.
  static const wrongCredentialsMessage = 'رقم الهاتف أو كلمة المرور غير صحيحة.';

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _storage = FlutterSecureStorage();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _remember = false;
  bool _hidePassword = true;
  String? _phoneError;
  String? _passwordError;

  /// A failure that is no field's fault (no connection).
  String? _failure;

  bool get _supervisor => widget.supervisor;

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

  bool _validate() {
    final id = _phone.text.trim();
    String? phoneError;
    if (id.isEmpty) {
      phoneError = _supervisor ? 'اكتب رقم الهاتف أو البريد الإلكتروني.' : 'اكتب رقم الهاتف.';
    } else if (!_supervisor && AuthRepository.normalizeEgyptianPhone(id).length < 10) {
      phoneError = 'اكتب رقم هاتف مصري صحيح.';
    }
    final passwordError = _password.text.isEmpty ? 'اكتب كلمة المرور.' : null;
    setState(() {
      _phoneError = phoneError;
      _passwordError = passwordError;
      _failure = null;
    });
    return phoneError == null && passwordError == null;
  }

  /// Only the identifier is kept; the password never is.
  Future<void> _saveRemembered() async {
    try {
      if (_remember) {
        await _storage.write(key: 'basak.remembered_phone', value: _phone.text.trim());
      } else {
        await _storage.delete(key: 'basak.remembered_phone');
      }
    } catch (_) {
      // Remembering the number is a convenience; signing in goes on without it.
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_validate()) return;
    // Kept beside the sign-in, never in its way.
    unawaited(_saveRemembered());
    try {
      await ref.read(authStateProvider.notifier).signIn(
            identifier: _phone.text.trim(),
            password: _password.text,
          );
    } catch (error) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final message = _message(error);
      setState(() {
        if (message == LoginScreen.wrongCredentialsMessage) {
          _passwordError = message;
        } else {
          _failure = message;
        }
      });
    }
  }

  String _message(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('invalid_credentials') ||
        message.contains('invalid login credentials') ||
        message.contains('email or password') ||
        message.contains('user not found') ||
        message.contains('invalid password')) {
      return LoginScreen.wrongCredentialsMessage;
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
        _phoneError = null;
        _passwordError = null;
        _failure = null;
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final loading = ref.watch(authStateProvider).isLoading;

    final remember = CheckRow(
      key: const Key('login-remember'),
      quiet: true,
      value: _remember,
      onChanged: loading ? null : (value) => setState(() => _remember = value),
      child: Text('تذكّر رقمي', style: text.bodySmall.copyWith(color: colors.ink2)),
    );

    return EntryPage(
      onBack: widget.onBack == null
          ? null
          : () {
              if (!loading) widget.onBack!();
            },
      trailing: const BrandLockup(),
      title: _supervisor ? 'دخول المشرف' : 'أهلاً بعودتك',
      subtitle: _supervisor ? 'تابع رحلات خطوطك وسجّل صعود الطلاب.' : 'سجّل دخولك وكمّل رحلتك.',
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_supervisor ? 'طالب؟' : 'طالب جديد؟', style: text.bodySmall.copyWith(color: colors.ink2)),
            const SizedBox(width: BasakSpace.s6),
            EntryLink(
              key: Key(_supervisor ? 'login-students' : 'login-signup'),
              label: _supervisor ? 'دخول الطلاب' : 'إنشاء حساب',
              inline: true,
              strong: true,
              onTap: loading ? null : (_supervisor ? widget.onOtherRole : widget.onSignup),
            ),
          ],
        ),
        if (!_supervisor)
          Center(
            child: EntryLink(
              key: const Key('login-supervisors'),
              label: 'دخول المشرفين',
              tone: EntryLinkTone.quiet,
              inline: true,
              onTap: loading ? null : widget.onOtherRole,
            ),
          ),
      ],
      children: [
        // Lets the phone's password manager offer and save the login.
        AutofillGroup(
          child: GroupedFields(children: [
            GroupedField(
              key: const Key('login-identifier'),
              label: _supervisor ? 'رقم الهاتف أو البريد الإلكتروني' : 'رقم الهاتف',
              hint: '01XXXXXXXXX',
              controller: _phone,
              error: _phoneError,
              ltr: true,
              keyboardType: _supervisor ? TextInputType.emailAddress : TextInputType.phone,
              textInputAction: TextInputAction.next,
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
              onChanged: (_) {
                if (_phoneError != null) setState(() => _phoneError = null);
              },
              onSubmitted: (_) => _passwordFocus.requestFocus(),
            ),
            GroupedField(
              key: const Key('login-password'),
              label: 'كلمة المرور',
              hint: 'كلمة المرور',
              controller: _password,
              focusNode: _passwordFocus,
              error: _passwordError,
              ltr: true,
              obscureText: _hidePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              trailing: PasswordEye(
                  hidden: _hidePassword, onTap: () => setState(() => _hidePassword = !_hidePassword)),
              onChanged: (_) {
                if (_passwordError != null) setState(() => _passwordError = null);
              },
              onSubmitted: (_) => loading ? null : _submit(),
            ),
          ]),
        ),
        if (_supervisor) ...[
          Align(alignment: AlignmentDirectional.centerStart, child: remember),
          const InfoNote('حسابات المشرفين ينشئها مسؤول النظام فقط. لتغيير كلمة المرور تواصل مع إدارة شركتك.'),
        ] else
          // Side by side; one under the other where the screen is too narrow.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              EntryLink(
                key: const Key('login-forgot'),
                label: 'نسيت كلمة المرور؟',
                inline: true,
                onTap: loading ? null : _openForgotPassword,
              ),
              remember,
            ],
          ),
        if (_failure != null) InlineError(message: _failure!),
        // The square biometric button takes its place beside this one.
        Row(
          children: [
            Expanded(
              child: BasakButton(
                key: const Key('login-submit'),
                label: 'دخول',
                loading: loading,
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
