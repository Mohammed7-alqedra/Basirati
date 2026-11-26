import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baseerte_ai/main.dart';
import 'package:baseerte_ai/detection_overlay.dart';

void main() {
  testWidgets('Maya Update 8 notebook connection screen is available',
      (tester) async {
    await tester.pumpWidget(const BasiratiApp());
    expect(find.text('Basirati AI - Maya Update 8'), findsOneWidget);
    expect(find.text('Notebook server URL'), findsOneWidget);
    expect(find.text('Connect to notebook'), findsOneWidget);
  });

  testWidgets('Live camera preview remains while labels are shown',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LiveCameraWithDetections(
            preview: Text('Continuous preview'),
            previewAspectRatio: 0.75,
            photoSize: Size(480, 640),
            detections: [
              ObjectDetection(
                rect: Rect.fromLTRB(100, 200, 300, 400),
                label: 'chair — 2.30 m',
                danger: false,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Continuous preview'), findsOneWidget);
    expect(find.text('AI snapshot • boxes may lag'), findsOneWidget);
  });
}
