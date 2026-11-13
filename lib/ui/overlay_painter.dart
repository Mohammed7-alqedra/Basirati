import 'package:flutter/material.dart';

import '../detection/yolo_detector.dart';

class OverlayPainter extends CustomPainter {
  final List<Detection> detections;
  final String Function(Detection) textForDetection;
  final TextDirection textDirection;

  OverlayPainter(
    this.detections, {
    required this.textForDetection,
    required this.textDirection,
  });

  static final _obstaclePaint = Paint()
    ..color = const Color(0xFFFFB547)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;

  static final _infoPaint = Paint()
    ..color = const Color(0xFF4FD1C5)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;

  static final _labelBackground = Paint()
    ..color = const Color(0xCC0F1B3D);

  @override
  void paint(Canvas canvas, Size size) {
    for (final detection in detections) {
      final rect = Rect.fromLTRB(
        detection.left * size.width,
        detection.top * size.height,
        detection.right * size.width,
        detection.bottom * size.height,
      );

      canvas.drawRect(
        rect,
        detection.isObstacle ? _obstaclePaint : _infoPaint,
      );

      final text = TextPainter(
        text: TextSpan(
          text: textForDetection(detection),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        textDirection: textDirection,
      )..layout();

      final top = (rect.top - text.height - 6)
          .clamp(0.0, size.height)
          .toDouble();

      final labelWidth = text.width + 10;

      final left = (textDirection == TextDirection.rtl
              ? rect.right - labelWidth
              : rect.left)
          .clamp(0.0, size.width)
          .toDouble();

      canvas.drawRect(
        Rect.fromLTWH(
          left,
          top,
          labelWidth,
          text.height + 6,
        ),
        _labelBackground,
      );

      text.paint(
        canvas,
        Offset(left + 5, top + 3),
      );
    }
  }

  @override
  bool shouldRepaint(OverlayPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.textForDetection != textForDetection ||
        oldDelegate.textDirection != textDirection;
  }
}