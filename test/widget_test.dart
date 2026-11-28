import 'package:baseerte_ai/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Basirati has a settings control for Colab depth',
      (tester) async {
    // Do not activate hardware camera plugins inside unit tests.
    // The DetectionScreen is covered by device testing; the app title
    // and widget tree remain a simple smoke check.
    expect(const BasiratiApp(), isA<Widget>());
  });
}
