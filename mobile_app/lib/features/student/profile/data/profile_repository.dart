import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/network_errors.dart';
import '../../../../core/network/perf_trace.dart';
import '../../../../core/network/supabase_service.dart';
import '../../../../core/storage/offline_cache.dart';
import '../../../../core/sync/own_changes.dart';

/// The requests behind the student's profile, one method each (see SubscriptionGateway).
abstract class ProfileGateway {
  String? get userId;
  Future<Map<String, dynamic>?> summaryRow(String userId);
  Future<dynamic> updateDetails(Map<String, dynamic> params);
  Future<void> uploadPhoto(String path, Uint8List jpeg);
  Future<dynamic> setPhoto(String path);
  Future<List<String>> listPhotos(String userId);
  Future<void> removePhotos(List<String> paths);
}

class SupabaseProfileGateway implements ProfileGateway {
  const SupabaseProfileGateway();

  SupabaseClient get _client => SupabaseService.client;
  static const _bucket = 'student-avatars';

  @override
  String? get userId => _client.auth.currentUser?.id;

  @override
  Future<Map<String, dynamic>?> summaryRow(String userId) {
    PerfTrace.count('profile.summary');
    return _client
        .from('students')
        // Everything the app shows of the student's own row, in one read: the
        // home screen and the profile, the card (qr_code_value) and whether a
        // new password must be chosen first (must_change_password). The whole
        // row is asked for, not a list of columns: a column this version knows
        // but the database does not have yet (specialisation) is then simply
        // absent from the answer, where naming it would fail the read.
        .select()
        .eq('id', userId)
        .maybeSingle();
  }

  @override
  Future<dynamic> updateDetails(Map<String, dynamic> params) {
    PerfTrace.count('profile.update');
    return _client.rpc('update_my_profile', params: params);
  }

  @override
  Future<void> uploadPhoto(String path, Uint8List jpeg) async {
    PerfTrace.count('profile.photo_upload');
    await _client.storage.from(_bucket).uploadBinary(path, jpeg,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
  }

  @override
  Future<dynamic> setPhoto(String path) {
    PerfTrace.count('profile.photo_set');
    return _client.rpc('set_my_profile_photo', params: {'p_path': path});
  }

  @override
  Future<List<String>> listPhotos(String userId) async {
    PerfTrace.count('profile.photo_list');
    final files = await _client.storage.from(_bucket).list(path: userId);
    return [for (final file in files) file.name];
  }

  @override
  Future<void> removePhotos(List<String> paths) async {
    PerfTrace.count('profile.photo_remove');
    await _client.storage.from(_bucket).remove(paths);
  }
}

final profileRepositoryProvider = Provider((ref) => ProfileRepository());

/// What a student may change about themselves: the photo, and the optional
/// email, college, specialisation and birth date. Name, phone and university
/// are fixed.
class ProfileRepository {
  final ProfileGateway _gateway;

  ProfileRepository({ProfileGateway? gateway}) : _gateway = gateway ?? const SupabaseProfileGateway();

  /// The student's own row, as shown on the home and account pages.
  Future<Map<String, dynamic>?> summaryRow(String userId) => _gateway.summaryRow(userId);

  /// Saves the optional details. An empty value clears the field.
  ///
  /// The specialisation is sent only when the student changed it
  /// ([specialisationChanged]), through the form of `update_my_profile` that
  /// takes it. A database that does not have that form yet answers "no such
  /// function": the other details are then saved the way they always were and
  /// the answer is false: everything but the specialisation was saved.
  ///
  /// The server's answer (the saved values) is written into what this phone
  /// holds, so the profile and the card (which is made from it) show it
  /// without being read again;
  /// the caller only invalidates their providers.
  Future<bool> updateDetails({
    String? email,
    String? college,
    DateTime? birthDate,
    String? specialisation,
    bool specialisationChanged = false,
  }) async {
    final echo = OwnChanges.begin('students');
    final details = <String, dynamic>{
      'p_email': email?.trim(),
      'p_college': college?.trim(),
      'p_birth_date': birthDate == null ? null : _isoDate(birthDate),
    };
    var withSpecialisation = specialisationChanged;
    try {
      Object? saved;
      if (withSpecialisation) {
        try {
          saved = await requireOnline(
              () => _gateway.updateDetails({...details, 'p_specialisation': specialisation?.trim()}));
        } catch (error) {
          if (!isMissingFunction(error)) rethrow;
          withSpecialisation = false;
        }
      }
      if (!withSpecialisation) saved = await requireOnline(() => _gateway.updateDetails(details));
      echo.done();
      final values = saved is Map
          ? Map<String, dynamic>.from(saved)
          : <String, dynamic>{
              'email': (email ?? '').trim().isEmpty ? null : email!.trim().toLowerCase(),
              'college': (college ?? '').trim().isEmpty ? 'غير محدد' : college!.trim(),
              'birth_date': birthDate == null ? null : _isoDate(birthDate),
              if (withSpecialisation)
                'specialisation': (specialisation ?? '').trim().isEmpty ? null : specialisation!.trim(),
            };
      await OfflineCache.applyLocal('profile.summary', (row) => row is Map ? {...row, ...values} : row);
      return withSpecialisation == specialisationChanged;
    } catch (error) {
      echo.failed();
      if (error is PostgrestException) throw Exception(error.message);
      rethrow;
    }
  }

  /// The server has no function of that name and arguments (PostgREST
  /// PGRST202, a 404): this database is older than this version of the app.
  static bool isMissingFunction(Object error) =>
      error is PostgrestException && (error.code == 'PGRST202' || error.code == '42883' || error.code == '404');

  /// Replaces the profile photo with [jpeg] (already framed and compressed).
  ///
  /// The new file is uploaded under a new name, the profile is pointed at it,
  /// and only then is every other file in the student's folder removed, so the
  /// old photo never stays behind and a failure half-way never leaves the
  /// profile without a photo.
  ///
  /// Returns the new photo's path as soon as the profile points at it: the
  /// saved copies on this phone already name it, and the old files are
  /// cleared away afterwards, without the student waiting for it.
  Future<String> changePhoto(Uint8List jpeg) async {
    final userId = _gateway.userId;
    if (userId == null) throw Exception('المستخدم غير مسجل.');
    final path = '$userId/avatar-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await requireOnline(() => _gateway.uploadPhoto(path, jpeg));
    final echo = OwnChanges.begin('students');
    try {
      await requireOnline(() => _gateway.setPhoto(path));
      echo.done();
    } catch (error) {
      echo.failed();
      // The profile still points at the old photo: take the new upload back.
      await _removeQuietly([path]);
      if (error is PostgrestException) throw Exception(error.message);
      rethrow;
    }
    await OfflineCache.applyLocal(
        'profile.summary', (row) => row is Map ? {...row, 'profile_image_url': path} : row);
    // After the caller has been answered: the screen is not kept waiting.
    unawaited(Future(() => removeOldPhotos(userId, keep: path)));
    return path;
  }

  /// Deletes every photo in the student's folder except [keep]. Best effort:
  /// anything left is removed the next time the photo changes.
  Future<void> removeOldPhotos(String userId, {required String keep}) async {
    try {
      final files = await _gateway.listPhotos(userId);
      final old = [
        for (final name in files)
          if ('$userId/$name' != keep) '$userId/$name',
      ];
      await _removeQuietly(old);
    } catch (_) {}
  }

  Future<void> _removeQuietly(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _gateway.removePhotos(paths);
    } catch (_) {}
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
