import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Dimensions of the JPEG returned by the existing Maya notebook API.
///
/// We read only a small header prefix, never decode or display the JPEG.
/// The notebook draws boxes onto an image with exactly these dimensions.
Size? jpegSizeFromBase64(String base64Jpeg) {
  if (base64Jpeg.length < 16) return null;
  final limit = math.min(base64Jpeg.length, 32768);
  final aligned = limit - (limit % 4);
  if (aligned < 16) return null;

  try {
    return jpegSizeFromBytes(base64Decode(base64Jpeg.substring(0, aligned)));
  } on FormatException {
    return null;
  }
}

Size? jpegSizeFromBytes(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) {
    return null;
  }
  var offset = 2;
  while (offset + 3 < bytes.length) {
    if (bytes[offset] != 0xff) return null;
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset >= bytes.length) return null;
    final marker = bytes[offset++];

    if (marker == 0xd9 || marker == 0xda) break;
    if (marker == 0x00 || marker == 0x01 ||
        (marker >= 0xd0 && marker <= 0xd7)) {
      continue;
    }

    if (offset + 2 > bytes.length) return null;
    final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
    if (segmentLength < 2 || offset + segmentLength > bytes.length) return null;

    const frameMarkers = <int>{
      0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7,
      0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf,
    };
    if (frameMarkers.contains(marker)) {
      if (segmentLength < 7) return null;
      final h = (bytes[offset + 3] << 8) | bytes[offset + 4];
      final w = (bytes[offset + 5] << 8) | bytes[offset + 6];
      if (w <= 0 || h <= 0) return null;
      return Size(w.toDouble(), h.toDouble());
    }
    offset += segmentLength;
  }
  return null;
}

/// One object box from a completed camera snapshot.
class ObjectDetection {
  const ObjectDetection({
    required this.rect,
    required this.label,
    required this.danger,
  });

  /// Pixel coordinates in the processed JPEG, NOT preview coordinates.
  final Rect rect;
  final String label;
  final bool danger;
}

/// Parse the existing Update 8 API response without changing its AI models.
List<ObjectDetection> detectionsFromApi(Object? value) {
  if (value is! List) return const [];
  final detections = <ObjectDetection>[];
  for (final item in value) {
    if (item is! Map) continue;
    final box = item['bbox'];
    if (box is! List || box.length != 4 ||
        box.any((v) => v is! num)) continue;

    final left = (box[0] as num).toDouble();
    final top = (box[1] as num).toDouble();
    final right = (box[2] as num).toDouble();
    final bottom = (box[3] as num).toDouble();
    if (![left, top, right, bottom].every((v) => v.isFinite) ||
        right <= left || bottom <= top) continue;

    final object = item['object']?.toString() ?? 'Object';
    final distance = item['calibrated_distance_m'];
    final text = distance is num && distance.isFinite
        ? '$object — ${distance.toStringAsFixed(2)} m'
        : object;

    detections.add(ObjectDetection(
      rect: Rect.fromLTRB(left, top, right, bottom),
      label: text,
      danger: item['danger_zone'] == true,
    ));
  }
  return detections;
}

/// Map image coordinates onto a centered, cover-fitted camera preview.
///
/// The preview and still photo can have different aspect ratios; a centered
/// crop is used as an approximation of the camera plugin's preview framing.
Rect mapSnapshotBoxToPreview({
  required Rect rect,
  required Size photoSize,
  required Size previewSize,
  int sensorOrientation = 90,
}) {
  if (photoSize.isEmpty || previewSize.isEmpty) return Rect.zero;
  var imageWidth = photoSize.width;
  var imageHeight = photoSize.height;
  var b = rect;

  // Some devices return a landscape-oriented still while CameraPreview is
  // portrait. Use the Android sensor orientation only in that case.
  if (imageWidth > imageHeight && previewSize.height > previewSize.width) {
    if (sensorOrientation == 270) {
      b = Rect.fromLTRB(
        b.top, imageWidth - b.right, b.bottom, imageWidth - b.left,
      );
    } else {
      b = Rect.fromLTRB(
        imageHeight - b.bottom, b.left, imageHeight - b.top, b.right,
      );
    }
    final previousWidth = imageWidth;
    imageWidth = imageHeight;
    imageHeight = previousWidth;
  }

  final scale = math.max(
    previewSize.width / imageWidth,
    previewSize.height / imageHeight,
  );
  final xOffset = (previewSize.width - imageWidth * scale) / 2;
  final yOffset = (previewSize.height - imageHeight * scale) / 2;
  return Rect.fromLTRB(
    xOffset + b.left * scale,
    yOffset + b.top * scale,
    xOffset + b.right * scale,
    yOffset + b.bottom * scale,
  );
}

/// The camera stays live; only boxes and labels are painted over the preview.
class LiveCameraWithDetections extends StatelessWidget {
  const LiveCameraWithDetections({
    super.key,
    required this.preview,
    required this.previewAspectRatio,
    required this.detections,
    required this.photoSize,
    this.sensorOrientation = 90,
  });

  final Widget preview;
  final double previewAspectRatio;
  final List<ObjectDetection> detections;
  final Size? photoSize;
  final int sensorOrientation;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: previewAspectRatio,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              preview,
              if (photoSize != null && detections.isNotEmpty)
                IgnorePointer(
                  child: CustomPaint(
                    painter: ObjectDetectionPainter(
                      detections: detections,
                      photoSize: photoSize!,
                      sensorOrientation: sensorOrientation,
                    ),
                  ),
                ),
              if (detections.isNotEmpty)
                const Positioned(
                  left: 6,
                  top: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black87),
                    child: Padding(
                      padding: EdgeInsets.all(5),
                      child: Text(
                        'AI snapshot • boxes may lag',
                        style: TextStyle(fontSize: 11, color: Colors.white),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ObjectDetectionPainter extends CustomPainter {
  const ObjectDetectionPainter({
    required this.detections,
    required this.photoSize,
    required this.sensorOrientation,
  });

  final List<ObjectDetection> detections;
  final Size photoSize;
  final int sensorOrientation;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final detection in detections) {
      final area = mapSnapshotBoxToPreview(
        rect: detection.rect,
        photoSize: photoSize,
        previewSize: size,
        sensorOrientation: sensorOrientation,
      );
      final visible = area.intersect(Offset.zero & size);
      if (visible.isEmpty) continue;
      final color = detection.danger ? Colors.redAccent : Colors.lightGreenAccent;
      canvas.drawRect(
        area,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );

      final text = TextPainter(
        text: TextSpan(
          text: detection.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(60.0, size.width - 16));
      final x = area.left.clamp(6.0, math.max(6.0, size.width - text.width - 8)).toDouble();
      final y = (area.top - text.height - 6)
          .clamp(6.0, math.max(6.0, size.height - text.height - 8))
          .toDouble();
      canvas.drawRect(
        Rect.fromLTWH(x - 3, y - 2, text.width + 6, text.height + 4),
        Paint()..color = Colors.black87,
      );
      text.paint(canvas, Offset(x, y));
      text.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ObjectDetectionPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.photoSize != photoSize ||
        oldDelegate.sensorOrientation != sensorOrientation;
  }
}
