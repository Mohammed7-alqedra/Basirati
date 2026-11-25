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
}
