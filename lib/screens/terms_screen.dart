import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:safenetic_app/constants/app_colors.dart';
import 'package:safenetic_app/constants/app_constants.dart';
import 'package:safenetic_app/constants/app_text_styles.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy & Security'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppConstants.spacing20),
        children: [
          // ── Header Card ──
          Container(
            padding: const EdgeInsets.all(AppConstants.spacing20),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withAlpha(40),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_rounded, color: Colors.white, size: 36),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SafeNetic',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text('Your data is protected',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacing24),

          _buildSection(
            Icons.description_outlined,
            'Terms of Service',
            'By using SafeNetic, you agree to the following terms and conditions. '
                'SafeNetic is a personal safety application designed to detect falls '
                'and alert designated guardians in case of emergencies.',
          ),
          _buildSection(
            Icons.data_usage_rounded,
            'Data Collection',
            '• Location data: Used to share your position with guardians during emergencies.\n'
                '• Sensor data: Accelerometer and gyroscope readings are processed locally on your device for fall detection.\n'
                '• Contact information: Guardian names and phone numbers are stored securely in Firebase.\n'
                '• Medical information: Blood type, medical conditions, and allergies are shared only with your guardians during emergencies.',
          ),
          _buildSection(
            Icons.lock_outline_rounded,
            'Data Storage & Security',
            '• All personal data is encrypted and stored on Google Firebase servers.\n'
                '• Sensor data for fall detection is processed on-device and never transmitted to external servers.\n'
                '• Your location is only shared during active emergency alerts.\n'
                '• We do not sell or share your data with third parties.',
          ),
          _buildSection(
            Icons.people_outline_rounded,
            'User Rights',
            '• You can delete your account and all associated data at any time.\n'
                '• You can manage your guardians and revoke access at any time.\n'
                '• You can disable fall detection and background monitoring in Settings.\n'
                '• You have full control over which permissions the app uses.',
          ),
          _buildSection(
            Icons.emergency_outlined,
            'Emergency Services',
            'SafeNetic is not a replacement for professional emergency services. '
                'Always call local emergency numbers (e.g., 911, 112, 1122) in case '
                'of a life-threatening situation. The app is designed to supplement, '
                'not replace, existing safety measures.',
          ),
          _buildSection(
            Icons.info_outline_rounded,
            'Disclaimer',
            'SafeNetic uses AI-powered fall detection which may not detect all '
                'incidents or may occasionally trigger false alerts. The accuracy '
                'depends on device sensors and environmental conditions. We are not '
                'liable for any damages arising from missed detections or false alerts.',
          ),

          const SizedBox(height: AppConstants.spacing16),
          const Center(
            child: Text(
              'Last updated: March 2026 • Version 1.0.0',
              style: AppTextStyles.caption,
            ),
          ),
          const SizedBox(height: AppConstants.spacing32),
        ],
      ),
    );
  }

  static Widget _buildSection(IconData icon, String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacing16),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacing16),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Text(title, style: AppTextStyles.h3),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              content,
              style: AppTextStyles.bodyMedium.copyWith(height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
