import 'package:flutter_test/flutter_test.dart';
import 'package:baseerte_ai/main.dart';

void main() {
  testWidgets('Notebook connection screen is available', (tester) async {
    await tester.pumpWidget(const BasiratiApp());
    expect(find.text('Notebook server URL'), findsOneWidget);
    expect(find.text('Connect to notebook'), findsOneWidget);
  });
}
