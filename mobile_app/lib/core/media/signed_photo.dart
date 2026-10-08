import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/supabase_service.dart';

/// A private storage photo, e.g. (bucket: 'supervisor-avatars', path: 'SUPERVISOR_ID/1.jpg').
typedef StoragePhoto = ({String bucket, String path});

/// A short-lived link to a private photo, or null when there is none or it
/// cannot be signed (offline: the image cache keeps showing the last copy).
final signedPhotoProvider =
    FutureProvider.autoDispose.family<String?, StoragePhoto>((ref, photo) async {
  if (photo.path.isEmpty) return null;
  try {
    return await SupabaseService.client.storage.from(photo.bucket).createSignedUrl(photo.path, 3600);
  } catch (_) {
    return null;
  }
});
