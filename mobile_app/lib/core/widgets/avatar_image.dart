import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// Image provider for a signed storage URL. Signed URLs change on every load,
/// so the disk cache is keyed on the object path: the last downloaded photo
/// keeps showing when the device is offline.
ImageProvider avatarImage(String signedUrl) {
  final uri = Uri.tryParse(signedUrl);
  return CachedNetworkImageProvider(
    signedUrl,
    cacheKey: uri == null ? signedUrl : '${uri.host}${uri.path}',
  );
}
