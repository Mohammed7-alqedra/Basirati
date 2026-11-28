import 'package:baseerte_ai/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Update 10 supports Colab depth and phone-only detection',
      (tester) async {
    await tester.pumpWidget(const BasiratiApp());
    expect(find.text('Baseerte AI — Update 10'), findsOneWidget);
    expect(find.text('Update 10 Colab depth URL (optional)'), findsOneWidget);
    expect(find.text('Start camera'), findsOneWidget);
  });
}
