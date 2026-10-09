import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:basak_mobile/core/ui/ui.dart';

import '../../../core/network/supabase_service.dart';
import '../../../core/storage/offline_cache.dart';
import '../providers/auth_provider.dart';
import 'password_strength.dart';

/// True when the Super Admin reset this student's password and the student has
/// not chosen a new one yet (students.must_change_password, set server-side).
///
/// It is part of the student's own row, which the home screen reads anyway
/// (studentProfileSummaryProvider): asking for it costs no request of its own.
final mustChangePasswordProvider = FutureProvider.autoDispose<bool>((ref) async {
  final userId = ref.watch(authStateProvider.select((s) => s.user?.id));
  if (userId == null) return false;
  try {
    final row = await ref.watch(studentProfileSummaryProvider(userId).future);
    final mustChange = row?['must_change_password'] as bool? ?? false;
    if (mustChange) {
      // The row may be the copy saved last time, with the server already
      // asked behind it. While this screen stands in for the app nothing
      // else shows what the server answered (SyncScope is not up), so it is
      // taken here: a password already changed elsewhere lets the student in.
      void onFresh() => ref.invalidate(studentProfileSummaryProvider(userId));
      OfflineCache.refreshed.addListener(onFresh);
      ref.onDispose(() => OfflineCache.refreshed.removeListener(onFresh));
    }
    return mustChange;
  } catch (_) {
    return false; // offline: never lock a student out of their bus pass
  }
});

/// Shown instead of the app after an admin-assisted reset. The new password is
/// set through the student-change-password Edge Function, which also clears the
/// flag; the app itself cannot clear it.
class ForcePasswordChangeScreen extends ConsumerStatefulWidget {
  const ForcePasswordChangeScreen({super.key});

  @override
  ConsumerState<ForcePasswordChangeScreen> createState() => _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState extends ConsumerState<ForcePasswordChangeScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _confirmFocus = FocusNode();
  bool _busy = false;
  bool _obscure = true;
  String? _passwordError;
  String? _confirmError;

  /// What the server answered, when it is no single field's fault.
  String? _failure;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // One change at a time, however fast the button is tapped.
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final passwordError = _password.text.length < passwordMinLength ? passwordTooShortMessage : null;
    final confirmError = _password.text != _confirm.text ? passwordMismatchMessage : null;
    setState(() {
      _passwordError = passwordError;
      _confirmError = passwordError == null ? confirmError : null;
      _failure = null;
    });
    if (passwordError != null || confirmError != null) return;

    setState(() => _busy = true);
    try {
      final response = await SupabaseService.client.functions
          .invoke('student-change-password', body: {'newPassword': _password.text});
      final data = response.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      _password.clear();
      _confirm.clear();
      // The function cleared the flag: this phone shows that from its own
      // copy of the student's row, without reading it again.
      final userId = ref.read(authStateProvider).user?.id;
      final applied = await OfflineCache.applyLocal(
          'profile.summary', (row) => row is Map ? {...row, 'must_change_password': false} : row);
      if (!mounted) return;
      if (userId != null) ref.invalidate(studentProfileSummaryProvider(userId));
      if (!applied) ref.invalidate(mustChangePasswordProvider);
      if (mounted) BasakToast.show(context, 'تم تغيير كلمة المرور. استخدمها في المرات القادمة.');
    } on FunctionException catch (e) {
      if (!mounted) return;
      final details = e.details;
      setState(() => _failure = details is Map && details['error'] is String
          ? details['error'] as String
          : 'تعذر تغيير كلمة المرور. حاول مرة أخرى.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _failure = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => EntryPage(
        // No way back: the app opens once a password is chosen.
        trailing: const BrandLockup(),
        title: 'اختر كلمة مرور جديدة',
        subtitle: 'أعادت الإدارة تعيين كلمة مرورك. اختر واحدة جديدة لتكمل.',
        actions: [
          BasakButton(
            key: const Key('force-password-save'),
            label: 'حفظ كلمة المرور والمتابعة',
            loading: _busy,
            onPressed: _submit,
          ),
          EntryLink(
            key: const Key('force-password-sign-out'),
            label: 'تسجيل الخروج',
            tone: EntryLinkTone.danger,
            onTap: _busy ? null : () => ref.read(authStateProvider.notifier).signOut(),
          ),
        ],
        children: [
          AutofillGroup(
            child: GroupedFields(children: [
              GroupedField(
                key: const Key('force-password-new'),
                label: 'كلمة المرور الجديدة',
                hint: '8 أحرف على الأقل',
                controller: _password,
                error: _passwordError,
                ltr: true,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                trailing: PasswordEye(hidden: _obscure, onTap: () => setState(() => _obscure = !_obscure)),
                onChanged: (_) {
                  if (_passwordError != null) setState(() => _passwordError = null);
                },
                onSubmitted: (_) => _confirmFocus.requestFocus(),
              ),
              GroupedField(
                key: const Key('force-password-confirm'),
                label: 'تأكيد كلمة المرور',
                hint: 'أعد كتابتها',
                controller: _confirm,
                focusNode: _confirmFocus,
                error: _confirmError,
                ltr: true,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) {
                  if (_confirmError != null) setState(() => _confirmError = null);
                },
                onSubmitted: (_) => _submit(),
              ),
            ]),
          ),
          if (_failure != null) InlineError(message: _failure!),
        ],
      );
}
