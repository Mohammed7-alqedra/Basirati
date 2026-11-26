import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Copy the camera's native planes before they are reused by the camera plugin.
class FramePlaneSnapshot {
  const FramePlaneSnapshot(this.bytes, this.bytesPerRow, this.bytesPerPixel);

  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
}

enum FramePixelFormat { yuv420, nv21, bgra8888 }

class CameraFrameSnapshot {
  const CameraFrameSnapshot({
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.pixelFormat,
    required this.planes,
  });

  final int width;
  final int height;
  /// Clockwise rotation needed to align an Android rear-camera frame upright.
  final int rotationDegrees;
  final FramePixelFormat pixelFormat;
  final List<FramePlaneSnapshot> planes;
}

class EncodedCameraFrame {
  const EncodedCameraFrame(this.jpeg, this.width, this.height);

  final Uint8List jpeg;
  final int width;
  final int height;
}

/// Conversion and JPEG compression run in another isolate, NOT on Flutter's UI
/// thread. Frames are capped at 640 pixels along their longest edge.
Future<EncodedCameraFrame> encodeCameraFrameAsync(CameraFrameSnapshot frame) {
  return compute(encodeCameraFrame, frame);
}

EncodedCameraFrame encodeCameraFrame(CameraFrameSnapshot frame) {
  if (frame.width <= 0 || frame.height <= 0 || frame.planes.isEmpty) {
    throw const FormatException('Invalid camera frame dimensions or planes');
  }
  if (frame.rotationDegrees % 90 != 0) {
    throw const FormatException('Unsupported camera rotation');
  }

  final scale = (frame.width > frame.height ? frame.width : frame.height) / 640.0;
  final scaledWidth = (frame.width / (scale > 1 ? scale : 1)).round();
  final scaledHeight = (frame.height / (scale > 1 ? scale : 1)).round();
  final rotation = ((frame.rotationDegrees % 360) + 360) % 360;
  final swap = rotation == 90 || rotation == 270;
  final outputWidth = swap ? scaledHeight : scaledWidth;
  final outputHeight = swap ? scaledWidth : scaledHeight;
  final output = img.Image(
    width: outputWidth,
    height: outputHeight,
    numChannels: 3,
  );

  for (var y = 0; y < outputHeight; y++) {
    for (var x = 0; x < outputWidth; x++) {
      late final int scaledX;
      late final int scaledY;
      switch (rotation) {
        case 90:
          scaledX = y;
          scaledY = scaledHeight - 1 - x;
          break;
        case 180:
          scaledX = scaledWidth - 1 - x;
          scaledY = scaledHeight - 1 - y;
          break;
        case 270:
          scaledX = scaledWidth - 1 - y;
          scaledY = x;
          break;
        default:
          scaledX = x;
          scaledY = y;
          break;
      }

      final sourceX = (scaledX * frame.width ~/ scaledWidth).clamp(0, frame.width - 1).toInt();
      final sourceY = (scaledY * frame.height ~/ scaledHeight).clamp(0, frame.height - 1).toInt();

      if (frame.pixelFormat == FramePixelFormat.bgra8888) {
        final plane = frame.planes.first;
        final index = sourceY * plane.bytesPerRow + sourceX * 4;
        if (index + 2 >= plane.bytes.length) {
          throw const FormatException('Invalid BGRA plane size');
        }
        output.setPixelRgb(
          x, y,
          plane.bytes[index + 2],
          plane.bytes[index + 1],
          plane.bytes[index],
        );
        continue;
      }

      final yPlane = frame.planes.first;
      final yIndex = sourceY * yPlane.bytesPerRow +
          sourceX * yPlane.bytesPerPixel;
      if (yIndex >= yPlane.bytes.length) {
        throw const FormatException('Invalid Y plane stride');
      }
      final yy = yPlane.bytes[yIndex];
      late final int uu;
      late final int vv;

      if (frame.pixelFormat == FramePixelFormat.nv21 ||
          frame.planes.length == 1) {
        final uvIndex = yPlane.bytesPerRow * frame.height +
            (sourceY ~/ 2) * yPlane.bytesPerRow +
            (sourceX ~/ 2) * 2;
        if (uvIndex + 1 >= yPlane.bytes.length) {
          throw const FormatException('Invalid NV21 chroma plane');
        }
        vv = yPlane.bytes[uvIndex];
        uu = yPlane.bytes[uvIndex + 1];
      } else if (frame.planes.length >= 3) {
        final u = frame.planes[1];
        final v = frame.planes[2];
        final uIndex = (sourceY ~/ 2) * u.bytesPerRow +
            (sourceX ~/ 2) * u.bytesPerPixel;
        final vIndex = (sourceY ~/ 2) * v.bytesPerRow +
            (sourceX ~/ 2) * v.bytesPerPixel;
        if (uIndex >= u.bytes.length || vIndex >= v.bytes.length) {
          throw const FormatException('Invalid YUV chroma plane stride');
        }
        uu = u.bytes[uIndex];
        vv = v.bytes[vIndex];
      } else {
        throw const FormatException('Unsupported YUV plane layout');
      }

      final c = (yy - 16).clamp(0, 255);
      final d = uu - 128;
      final e = vv - 128;
      final red = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
      final green = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
      final blue = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);
      output.setPixelRgb(x, y, red, green, blue);
    }
  }

  return EncodedCameraFrame(
    img.encodeJpg(output, quality: 65, chroma: img.JpegChroma.yuv420),
    outputWidth,
    outputHeight,
  );
}
