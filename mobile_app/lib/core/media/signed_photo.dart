import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'signed_url_cache.dart';

/// A private storage photo, e.g. (bucket: 'supervisor-avatars', path: 'SUPERVISOR_ID/1.jpg').
typedef StoragePhoto = ({String bucket, String path});

/// A short-lived link to a private photo, or null when there is none. The link
/// is signed once and shared (see [SignedUrlCache]); offline it is the photo's
/// plain address, which still shows the copy the image cache kept on disk.
final signedPhotoProvider =
    FutureProvider.autoDispose.family<String?, StoragePhoto>((ref, photo) async {
  if (photo.path.isEmpty) return null;
  return SignedUrlCache.urlOrOffline(photo.bucket, photo.path);
});

/// [signedPhotoProvider] for a student's own photo ([path] may be null).
StoragePhoto? studentPhoto(String? path) =>
    path == null || path.isEmpty ? null : (bucket: 'student-avatars', path: path);
