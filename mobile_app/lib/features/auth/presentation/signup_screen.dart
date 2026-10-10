import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:basak_mobile/core/ui/ui.dart';

import '../../../core/media/picker_errors.dart';
import '../../../core/widgets/photo_adjust_screen.dart';
import '../biometrics/biometric_sign_in.dart';
import '../data/auth_repository.dart';
import '../providers/auth_provider.dart';
import 'college_picker_sheet.dart';
import 'password_strength.dart';
import 'signup_steps.dart';
import 'university_picker_sheet.dart';

/// The sign-up: four steps over one registration, the route rail as its
/// progress. Each step checks its own fields before the next opens; the
/// account is created once, at the end.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key, required this.onBack, this.pickPhoto});

  /// Leaves the sign-up from its first step.
  final VoidCallback onBack;

  /// How a photo is picked and framed ([ProfilePhoto.pickAndAdjust]); replaced in tests.
  final Future<Uint8List?> Function(BuildContext context, ImageSource source)? pickPhoto;

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _specialisation = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _phoneFocus = FocusNode();
  final _confirmationFocus = FocusNode();

  int _step = 0;
  String? _universityId;
  String? _university;
  String? _college;

  /// The profile photo exactly as the student framed it; uploaded with the account.
  Uint8List? _photo;
  bool _acceptedTerms = false;
  bool _hidePassword = true;
  bool _hideConfirmation = true;

  String? _nameError;
  String? _phoneError;
  String? _universityError;
  String? _collegeError;
  String? _passwordError;
  String? _confirmationError;
  String? _termsError;

  /// What the server answered, when it is no single field's fault.
  String? _failure;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _specialisation.dispose();
    _password.dispose();
    _confirmation.dispose();
    _phoneFocus.dispose();
    _confirmationFocus.dispose();
    super.dispose();
  }

  bool get _loading => ref.read(authStateProvider).isLoading;

  void _back() {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    if (_step == 0) return widget.onBack();
    setState(() {
      _step--;
      _failure = null;
    });
  }

  /// Checks the step on screen; on a problem the field says it, in place.
  bool _validStep() {
    switch (_step) {
      case 0:
        final nameError = SignupDetailsStep.validateName(_name.text);
        final phoneError = SignupDetailsStep.validatePhone(_phone.text);
        setState(() {
          _nameError = nameError;
          _phoneError = phoneError;
        });
        return nameError == null && phoneError == null;
      case 1:
        final universityError = _universityId == null ? SignupStudyStep.universityMessage : null;
        final collegeError = (_college ?? '').trim().isEmpty ? SignupStudyStep.collegeMessage : null;
        setState(() {
          _universityError = universityError;
          _collegeError = collegeError;
        });
        return universityError == null && collegeError == null;
      case 2:
        return _photo != null;
      default:
        final passwordError = _password.text.length < passwordMinLength ? passwordTooShortMessage : null;
        final confirmationError = _confirmation.text != _password.text ? passwordMismatchMessage : null;
        final termsError = _acceptedTerms ? null : SignupPasswordStep.termsMessage;
        setState(() {
          _passwordError = passwordError;
          _confirmationError = confirmationError;
          _termsError = termsError;
        });
        return passwordError == null && confirmationError == null && termsError == null;
    }
  }

  void _next() {
    FocusScope.of(context).unfocus();
    if (!_validStep()) {
      HapticFeedback.mediumImpact();
      return;
    }
    if (_step == signupSteps.length - 1) {
      _submit();
    } else {
      setState(() {
        _step++;
        _failure = null;
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _failure = null);
    // Taken now: once the account exists, this screen is gone.
    final offerPending = ref.read(biometricOfferPendingProvider.notifier);
    try {
      await ref.read(authStateProvider.notifier).registerStudent(
            phone: _phone.text.trim(),
            fullName: _name.text.trim(),
            university: _university ?? '',
            college: _college ?? '',
            specialisation: _specialisation.text.trim(),
            password: _password.text,
            profileImageBytes: _photo,
            profileImageExtension: 'jpg',
          );
      // A new account, made with its password: the app may now offer the
      // faster way in, as it does after a sign-in.
      offerPending.state = true;
    } catch (error) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final message =
          error.toString().replaceAll('Exception: ', '').replaceAll('AuthException: ', '');
      setState(() {
        if (message == AuthRepository.phoneAlreadyRegisteredMessage) {
          // The phone field says it, on the step that holds it.
          _step = 0;
          _phoneError = message;
        } else {
          _failure = message;
        }
      });
    }
  }

  Future<void> _pickUniversity(List<Map<String, String>> universities) async {
    FocusScope.of(context).unfocus();
    final selectedId =
        await UniversityPickerSheet.show(context, universities: universities, selectedId: _universityId);
    if (!mounted || selectedId == null) return;
    final selected = universities.where((university) => university['id'] == selectedId).firstOrNull;
    setState(() {
      _universityId = selectedId;
      _university = selected?['name'];
      _universityError = null;
    });
  }

  Future<void> _pickCollege() async {
    FocusScope.of(context).unfocus();
    final college = await CollegePickerSheet.show(context, selected: _college);
    if (!mounted || college == null) return;
    setState(() {
      _college = college;
      _collegeError = null;
    });
  }

  Future<void> _choosePhoto(ImageSource source) async {
    // Cancelling at any step keeps the photo chosen before, if any.
    final Uint8List? framed;
    try {
      framed = await (widget.pickPhoto ?? ProfilePhoto.pickAndAdjust)(context, source);
    } on PlatformException catch (e) {
      if (mounted) showPickerError(context, e);
      return;
    }
    if (framed != null && mounted) {
      HapticFeedback.selectionClick();
      setState(() => _photo = framed);
    }
  }

  Future<void> _askPhotoSource() async {
    final source = await PhotoSourceSheet.show(context);
    if (source != null && mounted) await _choosePhoto(source);
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authStateProvider).isLoading;
    final step = signupSteps[_step];
    final last = _step == signupSteps.length - 1;

    final Widget body = switch (_step) {
      0 => SignupDetailsStep(
          name: _name,
          phone: _phone,
          phoneFocus: _phoneFocus,
          nameError: _nameError,
          phoneError: _phoneError,
          onNameChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
          onPhoneChanged: (_) {
            if (_phoneError != null) setState(() => _phoneError = null);
          },
          onDone: _next,
        ),
      1 => SignupStudyStep(
          universities: ref.watch(activeUniversitiesProvider),
          university: _university,
          college: _college,
          specialisation: _specialisation,
          universityError: _universityError,
          collegeError: _collegeError,
          onPickUniversity: _pickUniversity,
          onPickCollege: _pickCollege,
          onRetryUniversities: () => ref.invalidate(activeUniversitiesProvider),
        ),
      2 => SignupPhotoStep(
          photo: _photo,
          onCamera: () => _choosePhoto(ImageSource.camera),
          onGallery: () => _choosePhoto(ImageSource.gallery),
          onTapPhoto: _askPhotoSource,
        ),
      _ => SignupPasswordStep(
          password: _password,
          confirmation: _confirmation,
          confirmationFocus: _confirmationFocus,
          hidePassword: _hidePassword,
          hideConfirmation: _hideConfirmation,
          onTogglePassword: () => setState(() => _hidePassword = !_hidePassword),
          onToggleConfirmation: () => setState(() => _hideConfirmation = !_hideConfirmation),
          passwordError: _passwordError,
          confirmationError: _confirmationError,
          onPasswordChanged: (_) => setState(() => _passwordError = null),
          onConfirmationChanged: (_) {
            if (_confirmationError != null) setState(() => _confirmationError = null);
          },
          acceptedTerms: _acceptedTerms,
          onAcceptedTerms: loading
              ? null
              : (value) => setState(() {
                    _acceptedTerms = value;
                    _termsError = null;
                  }),
          termsError: _termsError,
          onDone: _next,
        ),
    };

    return PopScope(
      // Back walks the steps before it leaves the sign-up.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: EntryPage(
        onBack: _back,
        trailing: Text('إنشاء حساب', style: context.text.body.copyWith(fontWeight: FontWeight.w600)),
        rail: StepRail(steps: [for (final s in signupSteps) s.rail], current: _step),
        step: true,
        title: step.title,
        subtitle: step.why,
        actions: [
          BasakButton(
            key: Key(last ? 'signup-submit' : 'signup-next'),
            label: last ? 'إنشاء الحساب' : 'التالي',
            loading: loading,
            // The photo is the one step with nothing to correct: it waits.
            onPressed: _step == 2 && _photo == null ? null : _next,
          ),
        ],
        children: [
          KeyedSubtree(key: ValueKey('signup-step-$_step'), child: body),
          if (_failure != null) InlineError(message: _failure!),
        ],
      ),
    );
  }
}
