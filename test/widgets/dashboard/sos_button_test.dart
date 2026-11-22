import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safenetic_app/widgets/dashboard/sos_button.dart';

void main() {
  testWidgets('SosButton renders correctly and responds to tap', (WidgetTester tester) async {
    // Create a dummy animation controller
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(seconds: 1),
    );
    final animation = Tween<double>(begin: 1.0, end: 1.1).animate(controller);

    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SosButton(
              sosScaleAnimation: animation,
              onTap: () {
                tapped = true;
              },
            ),
          ),
        ),
      ),
    );

    // Verify it renders the SOS text
    expect(find.text('SOS'), findsOneWidget);

    // Tap the button
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();

    expect(tapped, isTrue);

    // Cleanup
    controller.dispose();
  });
}
