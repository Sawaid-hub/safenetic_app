import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safenetic_app/screens/login_screen.dart';

void main() {
  group('LoginScreen Widget Tests', () {
    testWidgets('LoginScreen renders UI correctly', (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      // Give it time to finish animations
      await tester.pumpAndSettle();

      // Verify title is present
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Sign in to continue your safety journey'), findsOneWidget);

      // Verify form fields
      expect(find.byType(TextFormField), findsNWidgets(2)); // Email and Password
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);

      // Verify login button
      expect(find.text('LOGIN'), findsOneWidget);

      // Verify sign up link
      expect(find.text("Don't have an account?"), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
    });
  });
}
