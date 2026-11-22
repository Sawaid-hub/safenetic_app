import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safenetic_app/widgets/dashboard/status_card.dart';

void main() {
  testWidgets('StatusCard renders correctly with animations', (WidgetTester tester) async {
    // Create a dummy animation controller
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(seconds: 1),
    );
    final animation = Tween<double>(begin: 1.0, end: 1.1).animate(controller);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusCard(
            statusController: controller,
            statusScaleAnimation: animation,
          ),
        ),
      ),
    );

    // Verify it renders the expected text
    expect(find.text("You're Safe"), findsOneWidget);
    expect(find.text('All systems monitoring'), findsOneWidget);

    // Check for icons
    expect(find.byIcon(Icons.shield_rounded), findsOneWidget);

    // Cleanup
    controller.dispose();
  });
}
