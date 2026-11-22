import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:safenetic_app/constants/app_colors.dart';
import 'package:safenetic_app/constants/app_constants.dart';
import 'package:safenetic_app/constants/app_text_styles.dart';

/// Premium SOS button with concentric pulsing rings,
/// glassmorphism glow, and haptic feedback.
class SosButton extends StatelessWidget {
  final Animation<double> sosScaleAnimation;
  final VoidCallback onTap;

  const SosButton({
    super.key,
    required this.sosScaleAnimation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sosScaleAnimation,
      builder: (context, child) {
        final pulse = sosScaleAnimation.value; // 1.0 → 1.1
        final normalized = (pulse - 1.0) / 0.1; // 0 → 1

        return SizedBox(
          width: AppConstants.sosButtonPulseRadius,
          height: AppConstants.sosButtonPulseRadius,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer pulse ring 3
              _pulseRing(
                size: AppConstants.sosButtonPulseRadius,
                opacity: (0.06 * normalized).clamp(0.0, 0.1),
              ),
              // Middle pulse ring 2
              _pulseRing(
                size: AppConstants.sosButtonPulseRadius * 0.85,
                opacity: (0.1 * normalized).clamp(0.0, 0.15),
              ),
              // Inner pulse ring 1
              _pulseRing(
                size: AppConstants.sosButtonPulseRadius * 0.7,
                opacity: (0.15 * normalized).clamp(0.0, 0.2),
              ),
              // Main button
              GestureDetector(
                onTap: () {
                  HapticFeedback.heavyImpact();
                  onTap();
                },
                child: Container(
                  width: AppConstants.sosButtonSize,
                  height: AppConstants.sosButtonSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.primaryDark,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withAlpha(
                            (80 + 40 * normalized).toInt()),
                        blurRadius: 24 + 8 * normalized,
                        spreadRadius: 4 + 4 * normalized,
                      ),
                      BoxShadow(
                        color: AppColors.primaryDark.withAlpha(40),
                        blurRadius: 40,
                        spreadRadius: 0,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.warning_rounded,
                          color: Colors.white, size: 38),
                      const SizedBox(height: 4),
                      Text('SOS',
                          style: AppTextStyles.h1.copyWith(
                            color: Colors.white,
                            fontSize: 26,
                            letterSpacing: 2,
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pulseRing({
    required double size,
    required double opacity,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.primary.withAlpha((opacity * 255).toInt()),
          width: 1.5,
        ),
      ),
    );
  }
}
