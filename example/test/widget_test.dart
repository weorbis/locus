import 'package:flutter_test/flutter_test.dart';
import 'package:locus_example/main.dart';

void main() {
  testWidgets('boots harness and shows app bar title', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LocusExampleApp());
    // The app shows a boot splash while the recorder + mock backend come up
    // asynchronously; settle past that into the main scaffold before
    // asserting on the app-bar chrome.
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Locus'), findsOneWidget);
  });
}
