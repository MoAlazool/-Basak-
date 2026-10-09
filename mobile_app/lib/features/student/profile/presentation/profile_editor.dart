import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/media/picker_errors.dart';
import '../../../../core/media/signed_photo.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/avatar_image.dart';
import '../../../../core/widgets/basak_ui.dart';
import '../../../../core/widgets/photo_adjust_screen.dart';
import '../../../auth/presentation/college_picker_sheet.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../home/presentation/supervisor_contact_sheet.dart';
import '../../qr/presentation/student_qr_screen.dart';
import '../data/profile_repository.dart';
export '../data/profile_repository.dart' show profileRepositoryProvider;

/// "14 مارس 2005"
String birthDateLabel(DateTime date) => '${date.day} ${BasakUi.arabicMonths[date.month - 1]} ${date.year}';

bool isValidEmail(String value) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());

/// What the server stores for a college nobody chose.
const _noCollege = 'غير محدد';

/// The student's own profile on the account page: who they are, with the
/// photo they can change, and «بياناتي»: what is fixed (the university) and
/// what they may add or edit (college, specialisation, email) behind one
/// «تعديل».
class ProfileSection extends ConsumerStatefulWidget {
  final String userId;
  final Map<String, dynamic>? profile;
  final String fallbackName;
  final String fallbackPhone;

  const ProfileSection(
      {super.key, required this.userId, required this.profile, required this.fallbackName, required this.fallbackPhone});

  /// An optional detail the student has not given.
  static const notAdded = 'لم يُضف بعد';

  /// Said when everything was saved but the specialisation, which this
  /// database cannot hold yet.
  static const specialisationLater = 'حُفظت بياناتك، لكن التخصص لم يُحفظ بعد.';

  @override
  ConsumerState<ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<ProfileSection> {
  bool _changingPhoto = false;

  /// The photo just chosen on this phone: shown at once, from memory, for as
  /// long as the profile points at it ([_newPhotoPath]; null while it uploads).
  MemoryImage? _newPhoto;
  String? _newPhotoPath;

  /// The repository already wrote the change into what this phone holds, so
  /// these re-reads are answered from memory (no request).
  void _refresh() {
    ref.invalidate(studentProfileSummaryProvider(widget.userId));
    // The card and the QR screen show the same photo and college.
    ref.invalidate(studentQrProvider);
  }

  void _say(String message, {BasakToastKind kind = BasakToastKind.success}) {
    if (mounted) BasakToast.show(context, message, kind: kind);
  }

  Future<void> _changePhoto() async {
    // One photo at a time: a second tap while one is on its way does nothing.
    if (_changingPhoto) return;
    final source = await PhotoSourceSheet.show(context);
    if (source == null || !mounted) return;
    try {
      // Framed in a circle and compressed before anything is uploaded.
      final photo = await ProfilePhoto.pickAndAdjust(context, source);
      if (photo == null || !mounted || _changingPhoto) return;
      setState(() {
        _changingPhoto = true;
        _newPhoto = MemoryImage(photo);
        _newPhotoPath = null;
      });
      try {
        _newPhotoPath = await ref.read(profileRepositoryProvider).changePhoto(photo);
      } catch (_) {
        if (mounted) setState(() => _newPhoto = null);
        rethrow;
      }
      _refresh();
      _say('تم تغيير الصورة الشخصية.');
    } catch (e) {
      _say(isNetworkFailure(e) ? errorMessage(e) : pickerErrorMessage(e), kind: BasakToastKind.failure);
    } finally {
      if (mounted) setState(() => _changingPhoto = false);
    }
  }

  Future<void> _edit() async {
    final saved = await BasakSheet.showFrame<ProfileSaved>(
      context,
      builder: (_) => _DetailsForm(profile: widget.profile),
    );
    if (saved == null) return;
    _refresh();
    switch (saved) {
      case ProfileSaved.all:
        _say('تم حفظ بياناتك.');
      case ProfileSaved.withoutSpecialisation:
        _say(ProfileSection.specialisationLater, kind: BasakToastKind.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final stored = studentPhoto(p?['profile_image_url'] as String?);
    final photoUrl = stored == null ? null : ref.watch(signedPhotoProvider(stored)).valueOrNull;
    // Changed again elsewhere since: the stored photo is the newer one.
    final mine = _newPhoto != null && (_changingPhoto || _newPhotoPath == stored?.path);
    final ImageProvider? photo = mine ? _newPhoto : (photoUrl == null ? null : avatarImage(photoUrl));
    final email = (p?['email'] as String?)?.trim() ?? '';
    final college = (p?['college'] as String?)?.trim() ?? '';
    // Absent on a database that has no such column yet: read as "not added".
    final specialisation = (p?['specialisation'] as String?)?.trim() ?? '';
    final hasCollege = college.isNotEmpty && college != _noCollege;
    final phone = p?['phone'] as String? ?? widget.fallbackPhone;

    SettingRow optional(String label, String value, {bool ltr = false}) => SettingRow(
          label: label,
          value: value.isEmpty ? ProfileSection.notAdded : value,
          muted: value.isEmpty,
          ltrValue: ltr && value.isNotEmpty,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IdentityCard(
          name: p?['full_name'] as String? ?? widget.fallbackName,
          phone: SupervisorContactSheet.readable(phone),
          photo: photo,
          busy: _changingPhoto,
          photoKey: const Key('profile-change-photo'),
          onChangePhoto: _changePhoto,
        ),
        // The group's «تعديل» reaches up into this gap.
        const SizedBox(height: BasakSpace.betweenCards - GroupSection.overhang),
        GroupSection(
          title: 'بياناتي',
          actionLabel: 'تعديل',
          actionKey: const Key('profile-edit'),
          onAction: _edit,
          child: SettingRows(rows: [
            // Fixed: only the company's dashboard can correct it.
            SettingRow(label: 'الجامعة', value: p?['university'] as String? ?? '—', locked: true),
            optional('الكلية', hasCollege ? college : ''),
            optional('التخصص', specialisation),
            optional('البريد الإلكتروني', email, ltr: true),
          ]),
        ),
      ],
    );
  }
}

/// How saving «تعديل بياناتي» ended.
enum ProfileSaved {
  all,

  /// Everything but the specialisation: this database cannot hold it yet.
  withoutSpecialisation,
}

/// College, specialisation, email and birth date. All optional but the
/// college: an empty field clears it.
class _DetailsForm extends ConsumerStatefulWidget {
  final Map<String, dynamic>? profile;
  const _DetailsForm({required this.profile});

  @override
  ConsumerState<_DetailsForm> createState() => _DetailsFormState();
}

class _DetailsFormState extends ConsumerState<_DetailsForm> {
  String _text(String key) => (widget.profile?[key] as String?)?.trim() ?? '';

  late final _email = TextEditingController(text: _text('email'));
  late final String _specialisationWas = _text('specialisation');
  late final _specialisation = TextEditingController(text: _specialisationWas);
  late String _college = _text('college') == _noCollege ? '' : _text('college');
  late DateTime? _birth = DateTime.tryParse(widget.profile?['birth_date'] as String? ?? '');
  bool _saving = false;
  String? _emailError;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _specialisation.dispose();
    super.dispose();
  }

  Future<void> _pickCollege() async {
    final picked = await CollegePickerSheet.show(context, selected: _college.isEmpty ? null : _college);
    if (picked != null && mounted) setState(() => _college = picked);
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(now.year - 19, 1, 1),
      firstDate: DateTime(1940),
      lastDate: DateTime(now.year - 12, now.month, now.day),
      helpText: 'تاريخ الميلاد',
      initialEntryMode: DatePickerEntryMode.calendar,
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) setState(() => _birth = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    final emailOk = _email.text.trim().isEmpty || isValidEmail(_email.text);
    setState(() {
      _emailError = emailOk ? null : 'اكتب بريداً إلكترونياً صحيحاً.';
      _error = null;
      _saving = emailOk;
    });
    if (!emailOk) return;
    try {
      final all = await ref.read(profileRepositoryProvider).updateDetails(
            email: _email.text,
            college: _college,
            birthDate: _birth,
            specialisation: _specialisation.text,
            // Untouched: the save goes the way it always did.
            specialisationChanged: _specialisation.text.trim() != _specialisationWas,
          );
      if (mounted) Navigator.of(context).pop(all ? ProfileSaved.all : ProfileSaved.withoutSpecialisation);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return BasakSheetFrame(
      title: 'تعديل بياناتي',
      largeTitle: true,
      primary: BasakButton(key: const Key('profile-save'), label: 'حفظ', loading: _saving, onPressed: _save),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetValueField(
            key: const Key('profile-college'),
            label: 'الكلية',
            value: _college.isEmpty ? null : _college,
            placeholder: ProfileSection.notAdded,
            icon: LucideIcons.chevronDown,
            onTap: _pickCollege,
          ),
          const SizedBox(height: BasakSpace.s16),
          SheetField(
            key: const Key('profile-specialisation'),
            label: 'التخصص',
            controller: _specialisation,
            hint: 'اختياري',
            maxLength: 80,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: BasakSpace.s16),
          SheetField(
            key: const Key('profile-email'),
            label: 'البريد الإلكتروني',
            controller: _email,
            hint: 'name@example.com',
            error: _emailError,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            ltr: true,
            maxLength: 120,
          ),
          const SizedBox(height: BasakSpace.s16),
          SheetValueField(
            key: const Key('profile-birth'),
            label: 'تاريخ الميلاد',
            value: _birth == null ? null : birthDateLabel(_birth!),
            placeholder: 'اختر التاريخ',
            icon: LucideIcons.calendar,
            onTap: _pickBirth,
            onClear: () => setState(() => _birth = null),
          ),
          const SizedBox(height: BasakSpace.s16),
          Text('الاسم والهاتف والجامعة لا تتغيّر من هنا.',
              style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400)),
          if (_error != null) ...[
            const SizedBox(height: BasakSpace.s10),
            Text(_error!, style: text.bodySmall.copyWith(color: colors.danger)),
          ],
          const SizedBox(height: BasakSpace.s4),
        ],
      ),
    );
  }
}
