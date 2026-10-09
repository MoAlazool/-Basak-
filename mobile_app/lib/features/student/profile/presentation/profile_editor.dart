import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/media/picker_errors.dart';
import '../../../../core/media/signed_photo.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/avatar_image.dart';
import '../../../../core/widgets/photo_adjust_screen.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../qr/presentation/student_qr_screen.dart';
import '../data/profile_repository.dart';
export '../data/profile_repository.dart' show profileRepositoryProvider;


const _months = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// "14 مارس 2005"
String birthDateLabel(DateTime date) => '${date.day} ${_months[date.month - 1]} ${date.year}';

bool isValidEmail(String value) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());

/// The student's own profile on the account page: the photo they can change,
/// what is fixed (name, phone, university), and what they may add or edit
/// (email, college, birth date; all optional).
class ProfileSection extends ConsumerStatefulWidget {
  final String userId;
  final Map<String, dynamic>? profile;
  final String fallbackName;
  final String fallbackPhone;

  const ProfileSection(
      {super.key, required this.userId, required this.profile, required this.fallbackName, required this.fallbackPhone});

  @override
  ConsumerState<ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<ProfileSection> {
  bool _changingPhoto = false;

  /// The photo just chosen on this phone: shown at once, from memory, for as
  /// long as the profile points at it ([_newPhotoPath]; null while it uploads).
  MemoryImage? _newPhoto;
  String? _newPhotoPath;

  static const _ink = Color(0xFF17384A);
  static const _teal = Color(0xFF00658D);

  /// The repository already wrote the change into what this phone holds, so
  /// these re-reads are answered from memory (no request).
  void _refresh() {
    ref.invalidate(studentProfileSummaryProvider(widget.userId));
    // The card and the QR screen show the same photo and college.
    ref.invalidate(studentQrProvider);
  }

  void _say(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: error ? AppColors.error : AppColors.success));
  }

  Future<void> _changePhoto() async {
    // One photo at a time: a second tap while one is on its way does nothing.
    if (_changingPhoto) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(LucideIcons.camera, color: _teal),
            title: Text('التقاط صورة', style: AppTextStyles.bodyLarge),
            onTap: () => Navigator.of(sheet).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(LucideIcons.image, color: _teal),
            title: Text('اختيار من الصور', style: AppTextStyles.bodyLarge),
            onTap: () => Navigator.of(sheet).pop(ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
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
      _say(isNetworkFailure(e) ? errorMessage(e) : pickerErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _changingPhoto = false);
    }
  }

  Future<void> _edit() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _DetailsForm(profile: widget.profile),
    );
    if (saved == true) {
      _refresh();
      _say('تم حفظ بياناتك.');
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
    final birth = DateTime.tryParse(p?['birth_date'] as String? ?? '');
    final hasCollege = college.isNotEmpty && college != 'غير محدد';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Photo, name and phone.
      Center(
        child: Stack(clipBehavior: Clip.none, children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: const Color(0xFFE2F2F9),
            backgroundImage: photo,
            child: photo == null ? const Icon(LucideIcons.user, size: 40, color: _teal) : null,
          ),
          if (_changingPhoto)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0x99FFFFFF), shape: BoxShape.circle),
                child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator(strokeWidth: 3)),
              ),
            ),
          Positioned(
            bottom: -2,
            left: -2,
            child: Material(
              color: _teal,
              shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 2.5)),
              child: InkWell(
                key: const Key('profile-change-photo'),
                customBorder: const CircleBorder(),
                onTap: _changingPhoto ? null : _changePhoto,
                child: const Padding(
                    padding: EdgeInsets.all(8), child: Icon(LucideIcons.camera, size: 16, color: Colors.white)),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Text(p?['full_name'] as String? ?? widget.fallbackName,
          textAlign: TextAlign.center, style: AppTextStyles.titleLarge.copyWith(color: _ink)),
      const SizedBox(height: 2),
      Text(p?['phone'] as String? ?? widget.fallbackPhone,
          textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: AppTextStyles.bodyMedium),
      const SizedBox(height: 18),

      // Fixed details.
      _row(LucideIcons.graduationCap, 'الجامعة', p?['university'] as String? ?? '—', locked: true),
      const Divider(height: 22),

      // What the student may add or change.
      _row(LucideIcons.school, 'الكلية', hasCollege ? college : null),
      const SizedBox(height: 12),
      _row(LucideIcons.send, 'البريد الإلكتروني', email.isEmpty ? null : email, ltr: true),
      const SizedBox(height: 12),
      _row(LucideIcons.calendarDays, 'تاريخ الميلاد', birth == null ? null : birthDateLabel(birth)),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        key: const Key('profile-edit'),
        onPressed: _edit,
        icon: const Icon(LucideIcons.pencil, size: 16),
        label: const Text('تعديل بياناتي'),
      ),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(LucideIcons.lock, size: 13, color: AppColors.textSecondary)),
        const SizedBox(width: 6),
        Expanded(
          child: Text('الاسم ورقم الهاتف والجامعة ثابتة. لتصحيح أي منها تواصل مع إدارة شركة النقل.',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
        ),
      ]),
    ]);
  }

  /// "label   value"; an empty optional value reads "لم يُضف بعد".
  Widget _row(IconData icon, String label, String? value, {bool locked = false, bool ltr = false}) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 3), child: Icon(icon, size: 16, color: _teal)),
        const SizedBox(width: 8),
        SizedBox(
          width: 112,
          child: Text(label, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary, height: 1.7)),
        ),
        Expanded(
          child: Text(value ?? 'لم يُضف بعد',
              textAlign: TextAlign.right,
              textDirection: ltr && value != null ? TextDirection.ltr : null,
              style: value == null
                  ? AppTextStyles.bodyMedium.copyWith(color: const Color(0xFFA3B1BC))
                  : AppTextStyles.bodyMedium.copyWith(color: _ink, fontWeight: FontWeight.w600)),
        ),
        if (locked)
          const Padding(
              padding: EdgeInsets.only(top: 4, right: 6),
              child: Icon(LucideIcons.lock, size: 13, color: Color(0xFFA3B1BC))),
      ]);
}

/// Email, college and birth date. All optional: an empty field clears it.
class _DetailsForm extends ConsumerStatefulWidget {
  final Map<String, dynamic>? profile;
  const _DetailsForm({required this.profile});

  @override
  ConsumerState<_DetailsForm> createState() => _DetailsFormState();
}

class _DetailsFormState extends ConsumerState<_DetailsForm> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: (widget.profile?['email'] as String?) ?? '');
  late final _college = TextEditingController(
      text: (widget.profile?['college'] as String?) == 'غير محدد' ? '' : (widget.profile?['college'] as String?) ?? '');
  late DateTime? _birth = DateTime.tryParse(widget.profile?['birth_date'] as String? ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _college.dispose();
    super.dispose();
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
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateDetails(email: _email.text, college: _college.text, birthDate: _birth);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  InputDecoration _decoration(String label, IconData icon, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Stays above the keyboard.
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('تعديل بياناتي', style: AppTextStyles.titleLarge),
            const SizedBox(height: 4),
            Text('كل الحقول اختيارية. اترك الحقل فارغاً لحذفه.', style: AppTextStyles.bodyMedium),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('profile-college'),
              controller: _college,
              maxLength: 80,
              textInputAction: TextInputAction.next,
              decoration: _decoration('الكلية', LucideIcons.school, hint: 'مثال: كلية الهندسة').copyWith(counterText: ''),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('profile-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              maxLength: 120,
              decoration: _decoration('البريد الإلكتروني', LucideIcons.send, hint: 'name@example.com').copyWith(counterText: ''),
              validator: (value) =>
                  (value ?? '').trim().isEmpty || isValidEmail(value!) ? null : 'اكتب بريداً إلكترونياً صحيحاً.',
            ),
            const SizedBox(height: 12),
            InkWell(
              key: const Key('profile-birth'),
              borderRadius: BorderRadius.circular(14),
              onTap: _pickBirth,
              child: InputDecorator(
                decoration: _decoration('تاريخ الميلاد', LucideIcons.calendarDays).copyWith(
                  suffixIcon: _birth == null
                      ? null
                      : IconButton(
                          tooltip: 'حذف',
                          icon: const Icon(LucideIcons.x, size: 16),
                          onPressed: () => setState(() => _birth = null)),
                ),
                child: Text(_birth == null ? 'اختر التاريخ' : birthDateLabel(_birth!),
                    style: _birth == null
                        ? AppTextStyles.bodyLarge.copyWith(color: const Color(0xFFA3B1BC))
                        : AppTextStyles.bodyLarge),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('profile-save'),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('حفظ'),
            ),
          ]),
        ),
      ),
    );
  }
}
