import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../providers/auth_provider.dart';

class LoginRegisterScreen extends ConsumerStatefulWidget {
  const LoginRegisterScreen({super.key});

  @override
  ConsumerState<LoginRegisterScreen> createState() => _LoginRegisterScreenState();
}

class _LoginRegisterScreenState extends ConsumerState<LoginRegisterScreen> {
  bool _isLogin = true;

  // Controllers
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _universityController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  String? _errorMessage;

  Future<void> _submit() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    try {
      if (_isLogin) {
        await ref.read(authStateProvider.notifier).signIn(
              identifier: phone,
              password: password,
            );
      } else {
        await ref.read(authStateProvider.notifier).registerStudent(
              phone: phone,
              fullName: _fullNameController.text.trim(),
              university: _universityController.text.trim(),
              password: password,
            );
      }
    } catch (e) {
      final cleanMsg = e.toString()
          .replaceAll('Exception: ', '')
          .replaceAll('AuthException: ', '');
      if (mounted) {
        setState(() => _errorMessage = cleanMsg);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(cleanMsg),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return GlassScaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App Logo / Title
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  shape: BoxShape.circle,
                  boxShadow: AppColors.softShadow,
                ),
                child: const Icon(LucideIcons.bus, size: 44, color: AppColors.babyBlueDark),
              ),
              const SizedBox(height: 12),
              Text('باصك - Basak', style: AppTextStyles.displayLarge),
              Text('نظام اشتراكات باصات الجامعة', style: AppTextStyles.bodyMedium),
              const SizedBox(height: 28),

              // Glass Auth Card
              GlassContainer(
                blur: 18,
                opacity: 0.82,
                borderRadius: 28,
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Mode Switcher (Login vs Register)
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _isLogin = true;
                                _errorMessage = null;
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _isLogin ? AppColors.babyBlueUltraLight : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    'تسجيل الدخول',
                                    style: AppTextStyles.titleMedium.copyWith(
                                      color: _isLogin ? AppColors.babyBlueDark : AppColors.textSecondary,
                                      fontWeight: _isLogin ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _isLogin = false;
                                _errorMessage = null;
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: !_isLogin ? AppColors.babyBlueUltraLight : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    'طالب جديد',
                                    style: AppTextStyles.titleMedium.copyWith(
                                      color: !_isLogin ? AppColors.babyBlueDark : AppColors.textSecondary,
                                      fontWeight: !_isLogin ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Full Name (Only for Registration)
                      if (!_isLogin) ...[
                        TextFormField(
                          controller: _fullNameController,
                          decoration: const InputDecoration(
                            labelText: 'الاسم الرباعي',
                            prefixIcon: Icon(LucideIcons.user, size: 20),
                            hintText: 'محمد أحمد علي محمود',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().split(RegExp(r'\s+')).length < 4) {
                              return 'يرجى إدخال الاسم رباعياً كاملاً.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // University
                        TextFormField(
                          controller: _universityController,
                          decoration: const InputDecoration(
                            labelText: 'الجامعة',
                            prefixIcon: Icon(LucideIcons.graduationCap, size: 20),
                            hintText: 'جامعة القاهرة / عين شمس / ...',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'الجامعة مطلوبة' : null,
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Phone Number
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: _isLogin ? 'رقم الهاتف أو البريد الإلكتروني' : 'رقم الهاتف',
                          prefixIcon: const Icon(LucideIcons.phone, size: 20),
                          hintText: '01xxxxxxxxx',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'رقم الهاتف مطلوب' : null,
                      ),
                      const SizedBox(height: 14),

                      // Password
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور',
                          prefixIcon: const Icon(LucideIcons.lock, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye, size: 20),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) => (v == null || v.length < 6) ? 'كلمة المرور 6 أحرف على الأقل' : null,
                      ),
                      const SizedBox(height: 16),

                      // Error message banner
                      if (_errorMessage != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.error.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.alertCircle, color: AppColors.error, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.error,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Submit Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.babyBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: authState.isLoading ? null : _submit,
                        child: authState.isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                              )
                            : Text(_isLogin ? 'دخول' : 'إنشاء الحساب وبدء الاشتراك'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
