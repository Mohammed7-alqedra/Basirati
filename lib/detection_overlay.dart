import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'on_device_detector.dart';

/// Overlays YOLO11 boxes on the still-photo camera preview. The rectangles
/// come from the phone's object detector; distances come from Google Colab.
class LiveCameraWithDetections extends StatelessWidget {
  const LiveCameraWithDetections({
    super.key,
    required this.preview,
    required this.previewAspectRatio,
    required this.detections,
  });

  final Widget preview;
  final double previewAspectRatio;
  final List<LocalDetection> detections;

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
              if (detections.isNotEmpty)
                IgnorePointer(
                  child: CustomPaint(
                    painter: LocalObjectPainter(detections),
                  ),
                ),
              const Positioned(
                left: 6,
                top: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black87),
                  child: Padding(
                    padding: EdgeInsets.all(5),
                    child: Text(
                      'YOLO11 on phone • distances from Colab',
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

/// Normalized object positions scaled directly to the displayed preview.
/// Because preview and still-photo crop/FOV can differ, alignment is approximate.
class LocalObjectPainter extends CustomPainter {
  const LocalObjectPainter(this.detections);

  final List<LocalDetection> detections;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Offset.zero & size;
    canvas.save();
    canvas.clipRect(screen);
    for (final detection in detections) {
      final b = detection.box;
      final rectangle = Rect.fromLTRB(
        b.left * size.width,
        b.top * size.height,
        b.right * size.width,
        b.bottom * size.height,
      );
      if (rectangle.intersect(screen).isEmpty) {
        continue;
      }

      final color = detection.isNear
          ? Colors.redAccent
          : Colors.lightGreenAccent;
      canvas.drawRect(
        rectangle,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      final text = TextPainter(
        text: TextSpan(
          text: detection.overlayLabel,
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
      final x = rectangle.left
          .clamp(6.0, math.max(6.0, size.width - text.width - 8))
          .toDouble();
      final y = (rectangle.top - text.height - 6)
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
  bool shouldRepaint(covariant LocalObjectPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
