
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:location/location.dart';
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:safenetic_app/constants/app_colors.dart';
import 'package:safenetic_app/constants/app_constants.dart';
import 'package:safenetic_app/constants/app_text_styles.dart';
import 'package:safenetic_app/constants/app_routes.dart';
import 'package:safenetic_app/router/app_router.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.shield_outlined,
      iconColor: AppColors.primary,
      title: 'Welcome to SafeNetic',
      subtitle:
          'Your personal safety companion — always watching, always ready.',
    ),
    _OnboardingPage(
      icon: Icons.sensors_rounded,
      iconColor: AppColors.accent,
      title: 'Smart Detection',
      subtitle:
          'Automatic fall detection using motion sensors and distress sound recognition through your microphone.',
    ),
    _OnboardingPage(
      icon: Icons.people_outline_rounded,
      iconColor: AppColors.info,
      title: 'Guardian Alerts',
      subtitle:
          'Add trusted contacts who get instantly notified with your live location during emergencies.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    try {
      final location = Location();
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) await location.requestService();

      var permission = await location.hasPermission();
      if (permission == PermissionStatus.denied) {
        await location.requestPermission();
      }

      final geoPermission = await geolocator.Geolocator.checkPermission();
      if (geoPermission == geolocator.LocationPermission.denied) {
        await geolocator.Geolocator.requestPermission();
      }

      // Request microphone permission for noise/distress detection
      final micStatus = await ph.Permission.microphone.status;
      if (!micStatus.isGranted) {
        await ph.Permission.microphone.request();
      }
    } catch (e) {
      if (kDebugMode) print('Permission request error: $e');
    }
  }

  Future<void> _completeOnboarding() async {
    HapticFeedback.mediumImpact();
    await _requestPermissions();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    setOnboardingCompleteRoute();
    if (mounted) context.go(AppRoutes.home);
  }

  void _nextPage() {
    HapticFeedback.selectionClick();
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: AppConstants.animMedium,
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1A1A2E),
                AppColors.background,
                Color(0xFF0D0D0D),
              ],
            ),
          ),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                children: [
                  // Skip button
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(AppConstants.spacing16),
                      child: AnimatedOpacity(
                        opacity:
                            _currentPage < _pages.length - 1 ? 1.0 : 0.0,
                        duration: AppConstants.animFast,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: _completeOnboarding,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(8),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Colors.white.withAlpha(12)),
                              ),
                              child: Text(
                                'Skip',
                                style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textHint, fontSize: 14),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Pages
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _pages.length,
                      onPageChanged: (i) =>
                          setState(() => _currentPage = i),
                      itemBuilder: (_, i) => _buildPage(_pages[i]),
                    ),
                  ),

                  // Dots + Button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
                    child: Column(
                      children: [
                        // Glass dot indicators
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _pages.length,
                            (i) => AnimatedContainer(
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOutCubic,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              width: _currentPage == i ? 32 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _currentPage == i
                                    ? AppColors.primary
                                    : Colors.white.withAlpha(20),
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: _currentPage == i
                                    ? [
                                        BoxShadow(
                                          color: AppColors.primary
                                              .withAlpha(60),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),

                        // CTA Button
                        AnimatedContainer(
                          duration: AppConstants.animFast,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                                AppConstants.radiusLarge),
                            gradient: AppColors.primaryGradient,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withAlpha(50),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusLarge),
                              onTap: _nextPage,
                              child: Container(
                                height: 56,
                                width: double.infinity,
                                alignment: Alignment.center,
                                child: AnimatedSwitcher(
                                  duration: AppConstants.animFast,
                                  child: Text(
                                    _currentPage < _pages.length - 1
                                        ? 'Continue'
                                        : 'Get Started',
                                    key: ValueKey(_currentPage),
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Glassmorphism icon ring with pulse
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: page.iconColor.withAlpha(12),
              border: Border.all(
                color: page.iconColor.withAlpha(30),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: page.iconColor.withAlpha(35),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Icon(page.icon, color: page.iconColor, size: 56),
          ),
          const SizedBox(height: 44),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: AppTextStyles.h1,
          ),
          const SizedBox(height: 18),
          Text(
            page.subtitle,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 15,
              height: 1.7,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _OnboardingPage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });
}
