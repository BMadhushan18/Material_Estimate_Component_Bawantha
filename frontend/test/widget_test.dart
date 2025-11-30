// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:material_estimate/main.dart';

void main() {
  testWidgets('Voice UI smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the Voice button and speech display exist.
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Say something...'), findsOneWidget);
  });
}
