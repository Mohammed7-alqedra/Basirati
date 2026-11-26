import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Bounding boxes are normalized to the exact upright JPEG sent to the API.
class DetectionOverlayItem {
  const DetectionOverlayItem({
    required this.bounds,
    required this.label,
    required this.distanceMeters,
    required this.danger,
  });

  final Rect bounds;
  final String label;
  final double? distanceMeters;
  final bool danger;
}

class DetectionPainter extends CustomPainter {
  const DetectionPainter({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<DetectionOverlayItem> detections;
  final int imageWidth;
  final int imageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (imageWidth <= 0 || imageHeight <= 0 || size.isEmpty) return;

    // CameraPreview and the overlay both use BoxFit.cover. Transform the
    // rectangle positions using the same centered crop.
    final scale = math.max(size.width / imageWidth, size.height / imageHeight);
    final dx = (size.width - imageWidth * scale) / 2;
    final dy = (size.height - imageHeight * scale) / 2;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final detection in detections) {
      final b = detection.bounds;
      final bounds = Rect.fromLTRB(
        dx + b.left.clamp(0.0, 1.0).toDouble() * imageWidth * scale,
        dy + b.top.clamp(0.0, 1.0).toDouble() * imageHeight * scale,
        dx + b.right.clamp(0.0, 1.0).toDouble() * imageWidth * scale,
        dy + b.bottom.clamp(0.0, 1.0).toDouble() * imageHeight * scale,
      );
      if (bounds.width <= 0 || bounds.height <= 0) continue;

      final color = detection.danger ? Colors.redAccent : Colors.lightGreenAccent;
      canvas.drawRect(
        bounds,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      final meters = detection.distanceMeters;
      final label = meters == null
          ? detection.label
          : '${detection.label} ${meters.toStringAsFixed(1)} m (test)';
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(20, size.width - 12));
      final textX = bounds.left.clamp(4.0, math.max(4.0, size.width - painter.width - 8)).toDouble();
      final textY = (bounds.top - painter.height - 7).clamp(4.0, math.max(4.0, size.height - painter.height - 8)).toDouble();
      final background = Rect.fromLTWH(
        textX - 3, textY - 2, painter.width + 6, painter.height + 4,
      );
      canvas.drawRect(background, Paint()..color = Colors.black.withAlpha(190));
      painter.paint(canvas, Offset(textX, textY));
      painter.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}
