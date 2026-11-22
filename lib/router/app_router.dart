import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:safenetic_app/constants/app_routes.dart';
import 'package:safenetic_app/screens/home_screen.dart';
import 'package:safenetic_app/screens/login_screen.dart';
import 'package:safenetic_app/screens/signup_screen.dart';
import 'package:safenetic_app/screens/profile_screen.dart';
import 'package:safenetic_app/screens/settings_screen.dart';
import 'package:safenetic_app/screens/alert_sent_screen.dart';
import 'package:safenetic_app/screens/ml_test_screen.dart';
import 'package:safenetic_app/screens/onboarding_screen.dart';
import 'package:safenetic_app/screens/alert_history_screen.dart';
import 'package:safenetic_app/screens/terms_screen.dart';
import 'package:safenetic_app/screens/guardian_link_screen.dart';
import 'package:safenetic_app/services/guardian_fcm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

/// Cached onboarding state — loaded once at app startup.
bool _onboardingComplete = true; // default true to avoid flicker

/// Call this before runApp to initialize onboarding state.
Future<void> initOnboardingState() async {
  final prefs = await SharedPreferences.getInstance();
  _onboardingComplete = prefs.getBool('onboarding_complete') ?? false;
}

/// Call this when the user completes onboarding to update the router state.
void setOnboardingCompleteRoute() {
  _onboardingComplete = true;
}

class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
          (dynamic _) => notifyListeners(),
        );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final appRouter = GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: AppRoutes.home,
  refreshListenable:
      GoRouterRefreshStream(FirebaseAuth.instance.authStateChanges()),
  redirect: (context, state) {
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;
    final isLoggingIn = state.uri.toString() == AppRoutes.login ||
        state.uri.toString() == AppRoutes.register;

    if (!isLoggedIn && !isLoggingIn) {
      return AppRoutes.login;
    }

    if (isLoggedIn && isLoggingIn) {
      // After login, check onboarding
      if (!_onboardingComplete) return AppRoutes.onboarding;
      return AppRoutes.home;
    }

    // Logged in, going to home, but hasn't onboarded
    if (isLoggedIn &&
        !_onboardingComplete &&
        state.uri.toString() == AppRoutes.home) {
      return AppRoutes.onboarding;
    }

    return null;
  },
  routes: [
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: AppRoutes.register,
      builder: (context, state) => const SignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.profile,
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final name = extra?['name'] as String? ?? '';
        final phone = extra?['phone'] as String? ?? '';
        return CustomTransitionPage(
          key: state.pageKey,
          child: ProfileScreen(initialName: name, initialPhone: phone),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOut;
            var tween =
                Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(
              position: animation.drive(tween),
              child: child,
            );
          },
        );
      },
    ),
    GoRoute(
      path: AppRoutes.settings,
      pageBuilder: (context, state) {
        return CustomTransitionPage(
          key: state.pageKey,
          child: const SettingsScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOut;
            var tween =
                Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(
              position: animation.drive(tween),
              child: child,
            );
          },
        );
      },
    ),
    GoRoute(
      path: AppRoutes.alertSent,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return AlertSentScreen(
          sosDelaySeconds: extra['sosDelaySeconds'] as double,
          guardians: extra['guardians'] as List<Map<String, dynamic>>,
          alertType: extra['alertType'] as String? ?? 'manual',
          userName: extra['userName'] as String? ?? 'User',
          locationData: extra['locationData'] as dynamic,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.mlTest,
      builder: (context, state) => const MLTestScreen(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.alertHistory,
      builder: (context, state) => const AlertHistoryScreen(),
    ),
    GoRoute(
      path: AppRoutes.terms,
      builder: (context, state) => const TermsScreen(),
    ),
    GoRoute(
      path: AppRoutes.guardianLink,
      pageBuilder: (context, state) {
        return CustomTransitionPage(
          key: state.pageKey,
          child: const GuardianLinkScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOut;
            var tween =
                Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(
              position: animation.drive(tween),
              child: child,
            );
          },
        );
      },
    ),
  ],
);
