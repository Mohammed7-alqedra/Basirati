import 'package:baseerte_ai/detection/yolo_detector.dart';
import 'package:baseerte_ai/depth/colab_depth_client.dart';
import 'package:baseerte_ai/ui/overlay_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Detection chair({double left = 0.1, double right = 0.4}) => Detection(
        classId: 56,
        label: 'chair',
        score: 0.9,
        left: left,
        top: 0.2,
        right: right,
        bottom: 0.7,
        isObstacle: true,
      );

  test('Uploaded YOLO detection retains direction and obstacle semantics', () {
    final c = chair();
    expect(c.label, 'chair');
    expect(c.direction, 'left');
    expect(c.isObstacle, isTrue);
    expect(YoloDetector.obstacleClasses.contains(56), isTrue);
  });

  test('Depth parses matching label and normalized box coordinates', () {
    final now = DateTime(2026, 11, 28);
    final results = parseDepthEstimates([
      {
        'label': 'chair',
        'left': 0.1,
        'top': 0.2,
        'right': 0.4,
        'bottom': 0.7,
        'calibrated_distance_m': 2.3,
      },
      {'label': 'bad', 'calibrated_distance_m': null},
    ], now);
    expect(results, hasLength(1));
    expect(estimateForObject(chair(), results, now)?.meters, 2.3);
    expect(
      estimateForObject(chair(left: 0.65, right: 0.95), results, now),
      isNull,
    );
    expect(
      estimateForObject(
          chair(), results, now.add(const Duration(seconds: 7))),
      isNull,
    );
  });

  testWidgets('Uploaded overlay painter works with phone detections',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomPaint(
          painter: OverlayPainter([chair()], const []),
          child: const SizedBox(width: 300, height: 400),
        ),
      ),
    ));
    expect(
      find.byWidgetPredicate((w) =>
          w is CustomPaint && w.painter is OverlayPainter),
      findsOneWidget,
    );
  });
}
