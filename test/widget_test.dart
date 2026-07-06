import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unigrid_app/widgets/glass_card.dart';

void main() {
  testWidgets('GlassCard displays its child and handles tap',
      (WidgetTester tester) async {
    bool tapped = false;

    // Build the GlassCard widget inside a MaterialApp scaffold
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlassCard(
            onTap: () {
              tapped = true;
            },
            child: const Text('Hello UniGrid'),
          ),
        ),
      ),
    );

    // Verify the child widget is rendered
    expect(find.text('Hello UniGrid'), findsOneWidget);

    // Tap on the GlassCard and verify callback is executed
    await tester.tap(find.text('Hello UniGrid'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
