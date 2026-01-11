import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

Uint8List optimizeImageBytes(
  Uint8List bytes, {
  int maxDimension = 1024,
  int quality = 70,
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return bytes;
  }

  img.Image processed = decoded;
  final maxSide = math.max(decoded.width, decoded.height);

  if (maxSide > maxDimension) {
    final scale = maxDimension / maxSide;
    final targetWidth = math.max(1, (decoded.width * scale).round());
    final targetHeight = math.max(1, (decoded.height * scale).round());
    processed = img.copyResize(
      decoded,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.cubic,
    );
  }

  final safeQuality = quality.clamp(10, 100).toInt();

  return Uint8List.fromList(
    img.encodeJpg(
      processed,
      quality: safeQuality,
    ),
  );
}
