import 'dart:convert';
import 'dart:typed_data';

import 'package:baseerte_ai/detection_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Reads JPEG dimensions without decoding the full image', () {
    // A synthetic JPEG header with a 640x480 baseline frame.
    final header = Uint8List.fromList([
      0xff, 0xd8,
      0xff, 0xe0, 0x00, 0x04, 0x11, 0x22,
      0xff, 0xc0, 0x00, 0x11, 0x08, 0x01, 0xe0, 0x02, 0x80, 0x03,
      0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
    ]);
    expect(jpegSizeFromBytes(header), const Size(640, 480));
    expect(jpegSizeFromBase64(base64Encode(header)), const Size(640, 480));
    expect(jpegSizeFromBytes(Uint8List.fromList([0, 1, 2, 3])), isNull);
  });

  test('Parses bounding boxes from Maya Update 8 JSON', () {
    final boxes = detectionsFromApi([
      {
        'object': 'chair',
        'bbox': [100, 200, 300, 400],
        'calibrated_distance_m': 2.3,
        'danger_zone': false,
      },
      {'object': 'invalid', 'bbox': [3, 2, 1, 0]},
    ]);
    expect(boxes, hasLength(1));
    expect(boxes.single.label, 'chair — 2.30 m');
    expect(boxes.single.rect, const Rect.fromLTRB(100, 200, 300, 400));
  });

  test('Fresh detection snapshots update the displayed distance', () {
    final earlier = detectionsFromApi([
      {
        'object': 'chair',
        'bbox': [100, 200, 300, 400],
        'calibrated_distance_m': 2.3,
        'danger_zone': false,
      },
    ]);
    final closer = detectionsFromApi([
      {
        'object': 'chair',
        'bbox': [110, 210, 310, 410],
        'calibrated_distance_m': 1.7,
        'danger_zone': false,
      },
    ]);
    expect(earlier.single.label, 'chair — 2.30 m');
    expect(closer.single.label, 'chair — 1.70 m');
    expect(closer.single.rect, isNot(earlier.single.rect));
    expect(detectionsFromApi([]), isEmpty);
  });

  test('Maps photo box onto live preview with unchanged aspect ratio', () {
    final mapped = mapSnapshotBoxToPreview(
      rect: const Rect.fromLTRB(100, 200, 300, 400),
      photoSize: const Size(480, 640),
      previewSize: const Size(240, 320),
    );
    expect(mapped, const Rect.fromLTRB(50, 100, 150, 200));
  });

  test('Landscape camera photo can rotate for a portrait preview', () {
    final mapped = mapSnapshotBoxToPreview(
      rect: const Rect.fromLTRB(100, 70, 200, 140),
      photoSize: const Size(640, 480),
      previewSize: const Size(240, 320),
      sensorOrientation: 90,
    );
    expect(mapped.isEmpty, isFalse);
    expect(mapped.left, greaterThanOrEqualTo(-240));
    expect(mapped.top, greaterThanOrEqualTo(-320));
  });

  testWidgets('Live camera continues below object bounding boxes',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            width: 300,
            child: LiveCameraWithDetections(
              preview: const Text('Continuous preview'),
              previewAspectRatio: 0.75,
              photoSize: const Size(480, 640),
              detections: const [
                ObjectDetection(
                  rect: Rect.fromLTRB(100, 200, 300, 400),
                  label: 'chair — 2.30 m',
                  danger: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Continuous preview'), findsOneWidget);
    expect(find.text('AI snapshot • boxes may lag'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) =>
          widget is CustomPaint && widget.painter is ObjectDetectionPainter),
      findsOneWidget,
    );
  });
}
