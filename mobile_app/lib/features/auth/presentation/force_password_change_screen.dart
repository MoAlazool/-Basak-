import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/network/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/basak_ui.dart';
import '../providers/auth_provider.dart';

/// True when the Super Admin reset this student's password and the student has
/// not chosen a new one yet (students.must_change_password, set server-side).
final mustChangePasswordProvider = FutureProvider.autoDispose<bool>((ref) async {
  final user = ref.watch(authStateProvider).user;
  if (user == null) return false;
  try {
    final row = await SupabaseService.client
        .from('students')
        .select('must_change_password')
        .eq('id', user.id)
        .maybeSingle();
    return row?['must_change_password'] as bool? ?? false;
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
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_password.text.length < 8) {
      setState(() => _error = 'كلمة المرور الجديدة يجب ألا تقل عن 8 أحرف.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين.');
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await SupabaseService.client.functions
          .invoke('student-change-password', body: {'newPassword': _password.text});
      final data = response.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      _password.clear();
      _confirm.clear();
      ref.invalidate(mustChangePasswordProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم تغيير كلمة المرور. استخدمها في المرات القادمة.'),
          backgroundColor: AppColors.success,
        ));
      }
    } on FunctionException catch (e) {
      final details = e.details;
      setState(() => _error = details is Map && details['error'] is String
          ? details['error'] as String
          : 'تعذر تغيير كلمة المرور. حاول مرة أخرى.');
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          prefixIcon: const Icon(LucideIcons.lock),
          suffixIcon: IconButton(
            icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        );
    return Scaffold(
      backgroundColor: BasakUi.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BasakUi.card(radius: 24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(color: Color(0xFFFFF4E5), shape: BoxShape.circle),
                    child: const Icon(LucideIcons.keyRound, color: Color(0xFFB97812), size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text('اختر كلمة مرور جديدة',
                      style: AppTextStyles.titleLarge.copyWith(color: BasakUi.ink)),
                  const SizedBox(height: 6),
                  Text('تم تعيين كلمة مرور مؤقتة لحسابك من الإدارة. لحماية حسابك اختر كلمة مرور جديدة قبل المتابعة.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(color: BasakUi.muted)),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: deco('كلمة المرور الجديدة (8 أحرف على الأقل)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: _obscure,
                    decoration: deco('تأكيد كلمة المرور'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BasakUi.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('حفظ كلمة المرور والمتابعة'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.read(authStateProvider.notifier).signOut(),
                    child: const Text('تسجيل الخروج'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
