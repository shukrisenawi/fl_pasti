import 'package:flutter_test/flutter_test.dart';
import 'package:pasti/main.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('renders web app shell', (tester) async {
    await tester.pumpWidget(const PastiApp(homeOverride: SizedBox.shrink()));

    expect(find.byType(PastiApp), findsOneWidget);
    expect(find.byType(SizedBox), findsOneWidget);
  });
}
