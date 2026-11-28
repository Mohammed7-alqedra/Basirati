import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Copy YUV420 frame planes before the camera plugin reuses their memory, then
/// encode an upright JPEG off the UI isolate for the Colab distance endpoint.
/// Rotation is identical to YoloDetector._fillInput so normalized boxes match.
Future<Uint8List> jpegFromCameraFrame(CameraImage frame, int rotation) {
  if (frame.planes.length != 3) {
    throw UnsupportedError('Depth upload requires Android YUV420 frames.');
  }
  final payload = <String, Object>{
    'width': frame.width,
    'height': frame.height,
    'rotation': rotation,
    'planes': frame.planes.map((plane) => <String, Object>{
          'bytes': Uint8List.fromList(plane.bytes),
          'rowStride': plane.bytesPerRow,
          'pixelStride': plane.bytesPerPixel ?? 1,
        }).toList(),
  };
  return compute(_encodeUprightJpeg, payload);
}

Uint8List _encodeUprightJpeg(Map<String, Object> payload) {
  final width = payload['width']! as int;
  final height = payload['height']! as int;
  final rotation = payload['rotation']! as int;
  final planes = (payload['planes']! as List).cast<Map<String, Object>>();
  final y = planes[0]['bytes']! as Uint8List;
  final u = planes[1]['bytes']! as Uint8List;
  final v = planes[2]['bytes']! as Uint8List;
  final yStride = planes[0]['rowStride']! as int;
  final uStride = planes[1]['rowStride']! as int;
  final vStride = planes[2]['rowStride']! as int;
  final uPixel = planes[1]['pixelStride']! as int;
  final vPixel = planes[2]['pixelStride']! as int;

  final rotated = rotation == 90 || rotation == 270;
  final uprightWidth = rotated ? height : width;
  final uprightHeight = rotated ? width : height;
  const maxDimension = 640;
  final scale = uprightWidth > uprightHeight
      ? maxDimension / uprightWidth
      : maxDimension / uprightHeight;
  final shrink = scale < 1 ? scale : 1.0;
  final outWidth = (uprightWidth * shrink).round().clamp(1, uprightWidth).toInt();
  final outHeight = (uprightHeight * shrink).round().clamp(1, uprightHeight).toInt();
  final rgb = img.Image(width: outWidth, height: outHeight, numChannels: 3);

  int bounded(double value) => value < 0 ? 0 : (value > 255 ? 255 : value.round());

  for (var row = 0; row < outHeight; row++) {
    final uprightY = row * uprightHeight ~/ outHeight;
    for (var col = 0; col < outWidth; col++) {
      final uprightX = col * uprightWidth ~/ outWidth;
      int sx;
      int sy;
      switch (rotation) {
        case 90:
          sx = uprightY;
          sy = height - 1 - uprightX;
          break;
        case 180:
          sx = width - 1 - uprightX;
          sy = height - 1 - uprightY;
          break;
        case 270:
          sx = width - 1 - uprightY;
          sy = uprightX;
          break;
        default:
          sx = uprightX;
          sy = uprightY;
      }
      final luma = y[sy * yStride + sx];
      final chromaU = u[(sy ~/ 2) * uStride + (sx ~/ 2) * uPixel] - 128;
      final chromaV = v[(sy ~/ 2) * vStride + (sx ~/ 2) * vPixel] - 128;
      rgb.setPixelRgb(
        col,
        row,
        bounded(luma + 1.402 * chromaV),
        bounded(luma - 0.344136 * chromaU - 0.714136 * chromaV),
        bounded(luma + 1.772 * chromaU),
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(rgb, quality: 75));
}
