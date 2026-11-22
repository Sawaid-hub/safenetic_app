import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Full-screen emergency alert that mimics earthquake/tornado warning UI.
///
/// Shows over everything (even lock screen) with pulsing red, alarm icon,
/// and continuous vibration until the user acknowledges.
class SosIncomingAlertScreen extends StatefulWidget {
  final String userName;
  final String alertType;
  final String? sosId;
  final String? userId;
  final String? latitude;
  final String? longitude;

  const SosIncomingAlertScreen({
    super.key,
    required this.userName,
    required this.alertType,
    this.sosId,
    this.userId,
    this.latitude,
    this.longitude,
  });

  @override
  State<SosIncomingAlertScreen> createState() => _SosIncomingAlertScreenState();
}

class _SosIncomingAlertScreenState extends State<SosIncomingAlertScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _iconController;
  late AnimationController _slideController;
  Timer? _vibrationTimer;

  @override
  void initState() {
    super.initState();

    // Lock screen to portrait
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    // Make status bar transparent
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    // Pulsing background
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Rotating/shaking alarm icon
    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat(reverse: true);

    // Slide-up entrance
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    // Start continuous vibration pattern using HapticFeedback
    _startVibration();
  }

  void _startVibration() {
    // Trigger heavy haptic feedback repeatedly to simulate alarm vibration
    HapticFeedback.heavyImpact();
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  void _stopVibration() {
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
  }

  @override
  void dispose() {
    _stopVibration();
    _pulseController.dispose();
    _iconController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  String get _alertTitle {
    switch (widget.alertType) {
      case 'fall':
        return '⚠️ FALL DETECTED';
      case 'noise':
        return '🔊 DISTRESS NOISE';
      case 'motion':
        return '📳 MOTION ANOMALY';
      default:
        return '🆘 EMERGENCY SOS';
    }
  }

  String get _alertDescription {
    switch (widget.alertType) {
      case 'fall':
        return '${widget.userName} may have fallen and needs help.';
      case 'noise':
        return 'Distress sounds detected from ${widget.userName}.';
      case 'motion':
        return 'Unusual motion pattern detected from ${widget.userName}.';
      default:
        return '${widget.userName} has triggered an emergency SOS alert.';
    }
  }

  IconData get _alertIcon {
    switch (widget.alertType) {
      case 'fall':
        return Icons.personal_injury_rounded;
      case 'noise':
        return Icons.record_voice_over_rounded;
      case 'motion':
        return Icons.directions_run_rounded;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  void _dismiss() {
    _stopVibration();
    Navigator.of(context).pop();
  }

  Future<void> _openMap() async {
    _stopVibration();
    
    if (widget.latitude != null && widget.longitude != null) {
      final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${widget.latitude},${widget.longitude}');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    }
    
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final pulseValue = _pulseController.value;
            return Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(
                      const Color(0xFFB71C1C),
                      const Color(0xFFD32F2F),
                      pulseValue,
                    )!,
                    Color.lerp(
                      const Color(0xFF1A0000),
                      const Color(0xFF3E0000),
                      pulseValue,
                    )!,
                  ],
                ),
              ),
              child: child,
            );
          },
          child: SafeArea(
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.3),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: _slideController,
                curve: Curves.easeOutCubic,
              )),
              child: FadeTransition(
                opacity: _slideController,
                child: Column(
                  children: [
                    const SizedBox(height: 16),

                    // Emergency header bar
                    _emergencyHeaderBar(),

                    const Spacer(flex: 2),

                    // Pulsing alarm icon
                    _alarmIcon(),

                    const SizedBox(height: 32),

                    // Alert title
                    Text(
                      _alertTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    // Alert description
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        _alertDescription,
                        style: TextStyle(
                          color: Colors.white.withAlpha(220),
                          fontSize: 17,
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Timestamp
                    Text(
                      _formattedTime(),
                      style: TextStyle(
                        color: Colors.white.withAlpha(150),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const Spacer(flex: 3),

                    // Action buttons
                    _actionButtons(),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emergencyHeaderBar() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final opacity = 0.6 + (_pulseController.value * 0.4);
        return Opacity(opacity: opacity, child: child);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withAlpha(40)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cell_tower_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(
              'EMERGENCY ALERT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 3.0,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.cell_tower_rounded, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _alarmIcon() {
    return AnimatedBuilder(
      animation: _iconController,
      builder: (context, _) {
        final shake = (_iconController.value - 0.5) * 0.15;
        return Transform.rotate(
          angle: shake,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              final scale = 1.0 + (_pulseController.value * 0.08);
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withAlpha(30),
                    border: Border.all(
                      color: Colors.white.withAlpha(60),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withAlpha(
                          (80 + _pulseController.value * 80).toInt(),
                        ),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Icon(
                    _alertIcon,
                    color: Colors.white,
                    size: 56,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _actionButtons() {
    final hasLocation =
        widget.latitude != null && widget.latitude!.isNotEmpty &&
        widget.longitude != null && widget.longitude!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // View Location button (if available)
          if (hasLocation) ...[
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _openMap,
                icon: const Icon(Icons.location_on_rounded, size: 22),
                label: const Text(
                  'VIEW LOCATION',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFB71C1C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                  shadowColor: Colors.black54,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Dismiss button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton(
              onPressed: _dismiss,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(
                  color: Colors.white.withAlpha(100),
                  width: 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'ACKNOWLEDGE',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formattedTime() {
    final now = DateTime.now();
    final hour = now.hour > 12 ? now.hour - 12 : now.hour;
    final amPm = now.hour >= 12 ? 'PM' : 'AM';
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute $amPm';
  }
}
