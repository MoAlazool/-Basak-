import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/network_errors.dart';
import '../../../../core/network/supabase_service.dart';

/// What a student may change about themselves: the photo, and the optional
/// email, college and birth date. Name, phone and university are fixed.
class ProfileRepository {
  SupabaseClient get _client => SupabaseService.client;

  static const _bucket = 'student-avatars';

  /// Saves the optional details. An empty value clears the field.
  Future<void> updateDetails({String? email, String? college, DateTime? birthDate}) async {
    try {
      await requireOnline(() => _client.rpc('update_my_profile', params: {
            'p_email': email?.trim(),
            'p_college': college?.trim(),
            'p_birth_date': birthDate == null ? null : _isoDate(birthDate),
          }));
    } on PostgrestException catch (error) {
      throw Exception(error.message);
    }
  }

  /// Replaces the profile photo with [jpeg] (already framed and compressed).
  ///
  /// The new file is uploaded under a new name, the profile is pointed at it,
  /// and only then is every other file in the student's folder removed, so the
  /// old photo never stays behind and a failure half-way never leaves the
  /// profile without a photo.
  Future<void> changePhoto(Uint8List jpeg) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('المستخدم غير مسجل.');
    final path = '${user.id}/avatar-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await requireOnline(() => _client.storage.from(_bucket).uploadBinary(path, jpeg,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false)));
    try {
      await requireOnline(() => _client.rpc('set_my_profile_photo', params: {'p_path': path}));
    } catch (error) {
      // The profile still points at the old photo: take the new upload back.
      await _removeQuietly([path]);
      if (error is PostgrestException) throw Exception(error.message);
      rethrow;
    }
    await removeOldPhotos(user.id, keep: path);
  }

  /// Deletes every photo in the student's folder except [keep]. Best effort:
  /// anything left is removed the next time the photo changes.
  Future<void> removeOldPhotos(String userId, {required String keep}) async {
    try {
      final files = await _client.storage.from(_bucket).list(path: userId);
      final old = [
        for (final file in files)
          if ('$userId/${file.name}' != keep) '$userId/${file.name}',
      ];
      await _removeQuietly(old);
    } catch (_) {}
  }

  Future<void> _removeQuietly(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _client.storage.from(_bucket).remove(paths);
    } catch (_) {}
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
