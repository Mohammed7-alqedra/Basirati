import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:baseerte_ai/main.dart';
import 'package:baseerte_ai/offline_maya_pipeline.dart';

void main() {
  testWidgets('Bundled model start screen is available', (tester) async {
    await tester.pumpWidget(const BasiratiApp());
    expect(find.text('Start camera and AI'), findsOneWidget);
    expect(find.text('Basirati - Offline Models'), findsOneWidget);
  });

  test('Depth median uses the center of a bounding box', () {
    final pixels = Float32List.fromList(List<double>.filled(100, 2.0));
    for (var x = 0; x < 10; x++) {
      pixels[x] = 99.0;
      pixels[9 * 10 + x] = 99.0;
    }

    final depth = OfflineMayaPipeline.medianDepthInsideBox(
      pixels, 10, 10, const Rect.fromLTWH(0, 0, 1, 1),
      imageWidth: 10, imageHeight: 10,
      cropX: 0, cropY: 0, cropSize: 10,
    );
    expect(depth, 2.0);
  });

  test('Depth median is absent for invalid boxes', () {
    final pixels = Float32List.fromList(List<double>.filled(100, 1.0));
    final depth = OfflineMayaPipeline.medianDepthInsideBox(
      pixels, 10, 10, Rect.zero,
      imageWidth: 10, imageHeight: 10,
      cropX: 0, cropY: 0, cropSize: 10,
    );
    expect(depth, isNull);
  });

  test('Notebook calibration constants are preserved', () {
    expect(OfflineMayaPipeline.scaleFactor, 1.05);
    expect(OfflineMayaPipeline.offset, -0.10);
    expect(OfflineMayaPipeline.boxInset, 0.20);
  });
}
