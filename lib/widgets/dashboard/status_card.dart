import 'package:flutter/material.dart';

import 'package:safenetic_app/constants/app_colors.dart';
import 'package:safenetic_app/constants/app_constants.dart';
import 'package:safenetic_app/constants/app_text_styles.dart';

/// Glassmorphism status card with animated shield icon
/// and pulsing glow effect.
class StatusCard extends StatelessWidget {
  final Animation<double> statusScaleAnimation;
  final AnimationController statusController;

  const StatusCard({
    super.key,
    required this.statusScaleAnimation,
    required this.statusController,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: statusController,
      builder: (context, child) {
        final glowOpacity = (statusScaleAnimation.value - 1.0).abs() * 0.3;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withAlpha(40),
                AppColors.primaryDark.withAlpha(20),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppConstants.radiusXLarge),
            border: Border.all(
              color: AppColors.primary.withAlpha(50),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withAlpha((glowOpacity * 80).toInt()),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: [
              // Animated shield with glow
              Transform.scale(
                scale: statusScaleAnimation.value * 0.12 + 0.88,
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withAlpha(80),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.shield_rounded,
                      color: Colors.white, size: 34),
                ),
              ),
              const SizedBox(height: AppConstants.spacing16),
              Text(
                "You're Safe",
                style: AppTextStyles.h2.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.success,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.success.withAlpha(100),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'All systems monitoring',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: Colors.white.withAlpha(180)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
