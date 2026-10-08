import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// Image provider for a signed storage URL. Signed URLs change on every load,
/// so the disk cache is keyed on the object path: the last downloaded photo
/// keeps showing when the device is offline.
ImageProvider avatarImage(String signedUrl) {
  final uri = Uri.tryParse(signedUrl);
  return _SignedPhoto(
    signedUrl,
    cacheKey: uri == null ? signedUrl : '${uri.host}${uri.path}',
  );
}

/// The same photo under a newer link is a different request to the widget.
///
/// The disk cache is keyed on the photo's path, so a newer link normally costs
/// nothing. But a link saved from an earlier run may have expired with no copy
/// on disk (after a reinstall, the saved data survives and the image cache does
/// not): that first attempt fails. Were the two links "equal", the widget would
/// keep its failed attempt and never try the fresh link that arrives next.
class _SignedPhoto extends CachedNetworkImageProvider {
  const _SignedPhoto(super.url, {super.cacheKey});

  @override
  bool operator ==(Object other) => other is _SignedPhoto && other.url == url && other.cacheKey == cacheKey;

  @override
  int get hashCode => Object.hash(url, cacheKey);
}
