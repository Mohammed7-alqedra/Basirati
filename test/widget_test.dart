import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baseerte_ai/main.dart';

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
            objects: ['chair - 2.30 m (test)'],
          ),
        ),
      ),
    );
    expect(find.text('Continuous preview'), findsOneWidget);
    expect(find.text('chair - 2.30 m (test)'), findsOneWidget);
    expect(find.text('Latest AI snapshot (experimental)'), findsOneWidget);
  });
}
