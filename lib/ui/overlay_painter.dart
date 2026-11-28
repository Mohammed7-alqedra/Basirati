import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../detection/yolo_detector.dart';
import '../depth/colab_depth_client.dart';

/// The ZIP's yellow/teal YOLO boxes; add Colab distances when fresh and matched.
class OverlayPainter extends CustomPainter {
  OverlayPainter(this.detections, this.estimates);

  final List<Detection> detections;
  final List<DepthEstimate> estimates;

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
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final now = DateTime.now();
    for (final d in detections) {
      final rect = Rect.fromLTRB(
        d.left.clamp(0.0, 1.0) * size.width,
        d.top.clamp(0.0, 1.0) * size.height,
        d.right.clamp(0.0, 1.0) * size.width,
        d.bottom.clamp(0.0, 1.0) * size.height,
      );
      if (rect.isEmpty) {
        continue;
      }
      canvas.drawRect(rect, d.isObstacle ? _obstaclePaint : _infoPaint);

      final estimate = estimateForObject(d, estimates, now);
      final distance = estimate == null
          ? 'measuring…'
          : '${estimate.meters.toStringAsFixed(2)} m';
      final label = '${d.label} ${(d.score * 100).round()}% · '
          '${d.direction} · $distance';
      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(50.0, size.width - 18));
      final x = rect.left.clamp(0.0, math.max(0.0, size.width - text.width - 10)).toDouble();
      final top = (rect.top - text.height - 6)
          .clamp(0.0, math.max(0.0, size.height - text.height - 6))
          .toDouble();
      canvas.drawRect(
        Rect.fromLTWH(x, top, text.width + 10, text.height + 6),
        _labelBackground,
      );
      text.paint(canvas, Offset(x + 5, top + 3));
      text.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant OverlayPainter oldDelegate) =>
      oldDelegate.detections != detections || oldDelegate.estimates != estimates;
}
