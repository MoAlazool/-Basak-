import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:basak_mobile/core/ui/ui.dart';

import '../data/auth_repository.dart';
import '../providers/auth_provider.dart';
import 'password_strength.dart';

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
  late final _phone = TextEditingController(text: widget.initialPhone);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _confirmFocus = FocusNode();
  bool _codeStep = false;
  bool _busy = false;
  bool _hide = true;
  String? _phoneError;
  String? _codeError;
  String? _passwordError;
  String? _confirmError;

  /// What the server answered, when it is no single field's fault.
  String? _failure;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  String _clean(Object error) => error.toString().replaceFirst('Exception: ', '');

  String get _codeDigits => AuthRepository.toLatinDigits(_code.text.trim());

  bool _validPhone() {
    final valid = RegExp(r'^01[0125][0-9]{8}$').hasMatch(AuthRepository.normalizeEgyptianPhone(_phone.text));
    setState(() {
      _phoneError = valid ? null : 'اكتب رقم هاتف مصري صحيح من 11 رقماً.';
      _failure = null;
    });
    return valid;
  }

  Future<void> _request() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_validPhone()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).requestPasswordReset(_phone.text);
      if (mounted) setState(() => _codeStep = true);
    } catch (error) {
      if (mounted) setState(() => _failure = _clean(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _haveCode() {
    FocusScope.of(context).unfocus();
    if (_validPhone()) setState(() => _codeStep = true);
  }

  Future<void> _reset() async {
    FocusScope.of(context).unfocus();
    if (_busy) return;
    final codeError = RegExp(r'^\d{6}$').hasMatch(_codeDigits) ? null : 'أدخل الرمز المكون من 6 أرقام.';
    final passwordError = _password.text.length < passwordMinLength ? passwordTooShortMessage : null;
    final confirmError = _confirm.text != _password.text ? passwordMismatchMessage : null;
    setState(() {
      _codeError = codeError;
      _passwordError = passwordError;
      _confirmError = confirmError;
      _failure = null;
    });
    if (codeError != null || passwordError != null || confirmError != null) return;

    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).resetPasswordWithCode(
            phone: _phone.text,
            code: _codeDigits,
            newPassword: _password.text,
          );
      if (!mounted) return;
      BasakToast.show(context, 'تم تغيير كلمة المرور. سجّل الدخول بكلمة المرور الجديدة.');
      Navigator.of(context).pop(_phone.text.trim());
    } catch (error) {
      if (mounted) setState(() => _failure = _clean(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    if (_busy) return;
    if (_codeStep) {
      setState(() {
        _codeStep = false;
        _failure = null;
      });
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        // Back leaves the code step for the phone step before it leaves the screen.
        canPop: !_codeStep,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: _codeStep ? _codePage() : _phonePage(),
      );

  Widget _phonePage() => EntryPage(
        key: const ValueKey('forgot-request'),
        onBack: _back,
        title: 'استعادة كلمة المرور',
        subtitle: 'اكتب رقم هاتفك، ونرسل طلباً لإدارة شركتك لتعطيك رمز الاستعادة.',
        actions: [
          BasakButton(
            key: const Key('forgot-send'),
            label: 'إرسال طلب الاستعادة',
            loading: _busy,
            onPressed: _request,
          ),
          EntryLink(key: const Key('forgot-have-code'), label: 'لديّ رمز بالفعل', onTap: _busy ? null : _haveCode),
        ],
        children: [
          GroupedFields(children: [
            GroupedField(
              key: const Key('forgot-phone'),
              label: 'رقم الهاتف',
              hint: '01XXXXXXXXX',
              controller: _phone,
              error: _phoneError,
              ltr: true,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+٠-٩]')),
                LengthLimitingTextInputFormatter(14),
              ],
              onChanged: (_) {
                if (_phoneError != null) setState(() => _phoneError = null);
              },
              onSubmitted: (_) => _request(),
            ),
          ]),
          const InfoNote('الرمز لا يصل برسالة نصية. تأخذه من إدارة الشركة، وهو صالح 30 دقيقة.'),
          if (_failure != null) InlineError(message: _failure!),
        ],
      );

  Widget _codePage() {
    final strength = passwordStrength(_password.text);
    final ready = _codeDigits.length == 6 && _password.text.isNotEmpty && _confirm.text.isNotEmpty;
    return EntryPage(
      key: const ValueKey('forgot-reset'),
      onBack: _back,
      title: 'أدخل الرمز',
      subtitle: 'ستة أرقام من إدارة الشركة، صالحة 30 دقيقة من لحظة إصدارها.',
      actions: [
        BasakButton(
          key: const Key('forgot-reset-submit'),
          label: 'تعيين كلمة المرور',
          loading: _busy,
          onPressed: ready ? _reset : null,
        ),
        EntryLink(key: const Key('forgot-resend'), label: 'إعادة إرسال الطلب', onTap: _busy ? null : _request),
      ],
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            CodeField(
              key: const Key('forgot-code'),
              controller: _code,
              hasError: _codeError != null,
              semanticLabel: 'رمز الاستعادة',
              onChanged: (_) => setState(() => _codeError = null),
            ),
            if (_codeError != null) ...[
              const SizedBox(height: BasakSpace.s6),
              FieldNote(_codeError!),
            ],
          ],
        ),
        AutofillGroup(
          child: GroupedFields(children: [
            GroupedField(
              key: const Key('forgot-password'),
              label: 'كلمة المرور الجديدة',
              hint: '8 أحرف على الأقل',
              controller: _password,
              error: _passwordError,
              ltr: true,
              obscureText: _hide,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              trailing: PasswordEye(hidden: _hide, onTap: () => setState(() => _hide = !_hide)),
              onChanged: (_) => setState(() => _passwordError = null),
              onSubmitted: (_) => _confirmFocus.requestFocus(),
            ),
            GroupedField(
              key: const Key('forgot-confirm'),
              label: 'تأكيد كلمة المرور',
              hint: 'أعد كتابتها',
              controller: _confirm,
              focusNode: _confirmFocus,
              error: _confirmError,
              ltr: true,
              obscureText: _hide,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => setState(() => _confirmError = null),
            ),
          ]),
        ),
        // Judging an empty field as "weak" only scolds the student.
        if (_password.text.isNotEmpty) StrengthMeter(level: strength.level, label: strength.label),
        if (_failure != null) InlineError(message: _failure!),
      ],
    );
  }
}
