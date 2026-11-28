import 'package:baseerte_ai/on_device_detector.dart';
import 'package:baseerte_ai/detection_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('YOLO output is parsed into normalized phone object boxes', () {
    final result = parseYoloBoxes([
      {
        'class': 'chair',
        'confidence': 0.89,
        'x1_norm': 0.1,
        'y1_norm': 0.2,
        'x2_norm': 0.5,
        'y2_norm': 0.8,
      },
      {
        'class': 'invalid',
        'confidence': 0.9,
        'x1_norm': 0.9,
        'y1_norm': 0.8,
        'x2_norm': 0.1,
        'y2_norm': 0.2,
      },
    ]);
    expect(result, hasLength(1));
    expect(result.first.name, 'chair');
    expect(result.first.box, const Rect.fromLTRB(0.1, 0.2, 0.5, 0.8));
    expect(result.first.toDepthRequest()['left'], 0.1);
    expect(result.first.distanceMeters, isNull);
  });

  test('Colab attaches distance without changing local YOLO bounding box', () {
    const phone = LocalDetection(
      name: 'chair',
      score: 0.89,
      box: Rect.fromLTRB(0.1, 0.2, 0.5, 0.8),
    );
    final results = attachDepthResults(
      [phone],
      [phone],
      [
        {
          'label': 'chair',
          'left': 0.1,
          'top': 0.2,
          'right': 0.5,
          'bottom': 0.8,
          'calibrated_distance_m': 2.3,
        },
      ],
      DateTime(2026, 11, 28),
    );
    expect(results.single.box, phone.box);
    expect(results.single.distanceMeters, 2.3);
    expect(results.single.overlayLabel, 'chair — 2.30 m');
  });

  test('Does not attribute wrong chair distance or stale measurements', () {
    final now = DateTime(2026, 11, 28);
    final oldChair = LocalDetection(
      name: 'chair',
      score: 0.8,
      box: const Rect.fromLTRB(0.0, 0.0, 0.3, 0.3),
    ).withDistance(2.5, now.subtract(const Duration(seconds: 12)));
    const otherChair = LocalDetection(
      name: 'chair',
      score: 0.9,
      box: Rect.fromLTRB(0.6, 0.6, 0.95, 0.95),
    );
    expect(
      keepRecentDistances([otherChair], [oldChair], now).first.distanceMeters,
      isNull,
    );
    expect(
      attachDepthResults(
        [otherChair],
        [oldChair],
        [
          {
            'label': 'chair',
            'left': 0.0,
            'top': 0.0,
            'right': 0.3,
            'bottom': 0.3,
            'calibrated_distance_m': 2.5,
          },
        ],
        now,
      ).first.distanceMeters,
      isNull,
    );
  });

  test('Distances update as an object becomes closer', () {
    const object = LocalDetection(
      name: 'chair',
      score: 0.85,
      box: Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
    );
    final earlier = object.withDistance(2.3, DateTime(2026, 11, 28));
    final closer = object.withDistance(1.7, DateTime(2026, 11, 28, 0, 0, 2));
    expect(earlier.overlayLabel, 'chair — 2.30 m');
    expect(closer.overlayLabel, 'chair — 1.70 m');
  });

  testWidgets('Phone boxes render above preview', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LiveCameraWithDetections(
            preview: Text('Continuous camera preview'),
            previewAspectRatio: 0.75,
            detections: [
              LocalDetection(
                name: 'chair',
                score: 0.85,
                box: Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Continuous camera preview'), findsOneWidget);
    expect(
      find.text('YOLO11 on phone • distances from Colab'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint &&
            widget.painter is LocalObjectPainter,
      ),
      findsOneWidget,
    );
  });
}
