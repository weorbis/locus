import 'package:flutter_test/flutter_test.dart';
import 'package:locus_example/main.dart';

void main() {
  testWidgets('shows app bar title', (tester) async {
    await tester.pumpWidget(const MotionRecognitionApp());
    expect(find.text('Locus'), findsOneWidget);
  });
}
