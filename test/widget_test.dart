import 'package:flutter_test/flutter_test.dart';
import 'package:pasti/main.dart';

void main() {
  testWidgets('renders web app shell', (tester) async {
    await tester.pumpWidget(const PastiApp());

    expect(find.byType(PastiApp), findsOneWidget);
  });
}
