import 'package:flutter_test/flutter_test.dart';
import 'package:baseerte_ai/main.dart';

void main() {
  testWidgets('Hosted AI server connection screen appears', (tester) async {
    await tester.pumpWidget(const BasiratiApp());
    expect(find.text('AI server URL'), findsOneWidget);
    expect(find.text('Server access key (for testing)'), findsOneWidget);
    expect(find.text('Connect to server'), findsOneWidget);
  });
}
