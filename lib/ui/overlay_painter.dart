import 'package:flutter/material.dart';

import '../detection/yolo_detector.dart';

/// Draws detection boxes on top of the camera preview.
/// For team testing only: blind users rely on voice and vibration.
/// Yellow = obstacle, teal = info object.
class OverlayPainter extends CustomPainter {
  final List<Detection> detections;

  OverlayPainter(this.detections);

  static final _obstaclePaint = Paint()
    ..color = const Color(0xFFFFB547)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  static final _infoPaint = Paint()
    ..color = const Color(0xFF4FD1C5)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  static final _labelBackground = Paint()..color = const Color(0xCC0F1B3D);

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in detections) {
      final rect = Rect.fromLTRB(
        d.left * size.width,
        d.top * size.height,
        d.right * size.width,
        d.bottom * size.height,
      );
      canvas.drawRect(rect, d.isObstacle ? _obstaclePaint : _infoPaint);

      final text = TextPainter(
        text: TextSpan(
          text: '${d.label} ${(d.score * 100).round()}% · ${d.direction}',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final top = (rect.top - text.height - 6).clamp(0.0, size.height);
      canvas.drawRect(
        Rect.fromLTWH(rect.left, top, text.width + 10, text.height + 6),
        _labelBackground,
      );
      text.paint(canvas, Offset(rect.left + 5, top + 3));
    }
  }

  @override
  bool shouldRepaint(OverlayPainter oldDelegate) =>
      oldDelegate.detections != detections;
}
