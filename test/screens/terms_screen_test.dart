import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safenetic_app/screens/terms_screen.dart';

void main() {
  group('TermsScreen Widget Tests', () {
    testWidgets('TermsScreen renders all sections correctly', (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(
        const MaterialApp(
          home: TermsScreen(),
        ),
      );

      // Verify if the title is present
      expect(find.text('Privacy & Security'), findsOneWidget);

      // Verify the header text
      expect(find.text('SafeNetic'), findsOneWidget);
      expect(find.text('Your data is protected'), findsOneWidget);

      // Verify sections are present
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Data Collection'), findsOneWidget);
      
      final listFinder = find.byType(ListView);
      
      await tester.dragUntilVisible(
        find.text('Data Storage & Security'),
        listFinder,
        const Offset(0, -300),
      );
      expect(find.text('Data Storage & Security'), findsOneWidget);
      
      await tester.dragUntilVisible(
        find.text('User Rights'),
        listFinder,
        const Offset(0, -300),
      );
      expect(find.text('User Rights'), findsOneWidget);
      
      await tester.dragUntilVisible(
        find.text('Emergency Services'),
        listFinder,
        const Offset(0, -300),
      );
      expect(find.text('Emergency Services'), findsOneWidget);
      
      await tester.dragUntilVisible(
        find.text('Disclaimer'),
        listFinder,
        const Offset(0, -300),
      );
      expect(find.text('Disclaimer'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('Last updated: March 2026 • Version 1.0.0'),
        listFinder,
        const Offset(0, -300),
      );
      expect(find.text('Last updated: March 2026 • Version 1.0.0'), findsOneWidget);
    });
  });
}
