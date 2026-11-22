import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:safenetic_app/constants/app_colors.dart';
import 'package:safenetic_app/constants/app_constants.dart';
import 'package:safenetic_app/constants/app_text_styles.dart';
import 'package:safenetic_app/models/alert_model.dart';
import 'package:safenetic_app/services/notification_service.dart';
import 'package:safenetic_app/widgets/common_widgets.dart';

class AlertHistoryScreen extends StatelessWidget {
  const AlertHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alert History'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: StreamBuilder<List<AlertModel>>(
        stream: NotificationService.instance.getAlertHistory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (snapshot.hasError) {
            return const EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Could not load alerts',
              subtitle: 'Please check your connection and try again',
            );
          }

          final alerts = snapshot.data ?? [];

          if (alerts.isEmpty) {
            return const EmptyState(
              icon: Icons.verified_user_rounded,
              title: 'No Alerts Yet',
              subtitle: 'Your emergency alert history will appear here',
            );
          }

          return RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: AppColors.surfaceLight,
            onRefresh: () async {
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacing16,
                  vertical: AppConstants.spacing8),
              itemCount: alerts.length,
              itemBuilder: (_, i) => _buildAlertCard(alerts[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAlertCard(AlertModel alert) {
    final typeInfo = _getTypeInfo(alert.type);
    final timeAgo = _formatTimeAgo(alert.timestamp);
    final dateStr = _formatDate(alert.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacing12),
      padding: const EdgeInsets.all(AppConstants.spacing16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
        border: Border.all(
          color: typeInfo.color.withAlpha(30),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: typeInfo.color.withAlpha(25),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                ),
                child: Icon(typeInfo.icon, color: typeInfo.color, size: 20),
              ),
              const SizedBox(width: AppConstants.spacing12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(typeInfo.label, style: AppTextStyles.labelLarge),
                    const SizedBox(height: 2),
                    Text(timeAgo, style: AppTextStyles.caption),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(alert.status).withAlpha(25),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusCircular),
                ),
                child: Text(
                  alert.status.toUpperCase(),
                  style: TextStyle(
                    color: _getStatusColor(alert.status),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppConstants.spacing12),

          // Details
          Row(
            children: [
              const Icon(Icons.people_outline_rounded,
                  color: AppColors.textHint, size: 16),
              const SizedBox(width: 6),
              Text(
                '${alert.guardianNames.length} guardian${alert.guardianNames.length != 1 ? 's' : ''} notified',
                style: AppTextStyles.bodySmall,
              ),
              const Spacer(),
              const Icon(Icons.access_time_rounded,
                  color: AppColors.textHint, size: 14),
              const SizedBox(width: 4),
              Text(dateStr, style: AppTextStyles.caption),
            ],
          ),

          // Location
          if (alert.latitude != null && alert.longitude != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    color: AppColors.textHint, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${alert.latitude!.toStringAsFixed(4)}, ${alert.longitude!.toStringAsFixed(4)}',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  _AlertTypeInfo _getTypeInfo(String type) {
    switch (type) {
      case 'fall':
        return const _AlertTypeInfo(
          icon: Icons.accessibility_new_rounded,
          color: AppColors.warning,
          label: 'Fall Detected',
        );
      case 'distress':
        return const _AlertTypeInfo(
          icon: Icons.mic_outlined,
          color: Color(0xFFE91E63),
          label: 'Distress Sound',
        );
      default:
        return const _AlertTypeInfo(
          icon: Icons.sos_rounded,
          color: AppColors.primary,
          label: 'Manual SOS',
        );
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'sent':
        return AppColors.success;
      case 'cancelled':
        return AppColors.disabled;
      default:
        return AppColors.warning;
    }
  }

  String _formatTimeAgo(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  String _formatDate(DateTime timestamp) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '${months[timestamp.month - 1]} ${timestamp.day}, $h:$m';
  }
}

class _AlertTypeInfo {
  final IconData icon;
  final Color color;
  final String label;

  const _AlertTypeInfo({
    required this.icon,
    required this.color,
    required this.label,
  });
}
