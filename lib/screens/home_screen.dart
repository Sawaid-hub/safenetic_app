import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as loc;
import 'package:provider/provider.dart';
import 'package:safenetic_app/providers/settings_provider.dart';
import 'package:safenetic_app/services/database_service.dart';
import 'package:safenetic_app/services/ml_service.dart';
import 'package:safenetic_app/models/user_model.dart';
import 'package:safenetic_app/models/guardian_model.dart';
import 'package:safenetic_app/models/device_model.dart';
import 'package:safenetic_app/constants/app_routes.dart';
import 'package:safenetic_app/services/location_service.dart';
import 'package:safenetic_app/services/ble_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:safenetic_app/constants/app_colors.dart';
import 'package:safenetic_app/constants/app_constants.dart';
import 'package:safenetic_app/constants/app_text_styles.dart';
import 'package:safenetic_app/widgets/dashboard/status_card.dart';
import 'package:safenetic_app/widgets/dashboard/sos_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  User? user;
  late DatabaseService _dbService;

  // Local state for SOS logic (updated via streams)
  List<GuardianModel> _latestGuardians = [];
  double _sosDelay = 10.0;
  UserModel? _currentUserData;

  // Animations
  late AnimationController _sosController;
  late AnimationController _statusController;
  late AnimationController _staggerController;
  late Animation<double> _sosScaleAnimation;
  late Animation<double> _statusScaleAnimation;

  StreamSubscription? _userDataSubscription;

  // Fall Detection
  final MLService _mlService = MLService();
  final bool _isFallDetectionEnabled = true;
  bool _isFallDetected = false;
  Timer? _fallAlertTimer;
  int _fallCountdown = 10;

  // BLE wearable
  StreamSubscription? _bleSubscription;

  // Live location
  loc.LocationData? _currentLocation;
  StreamSubscription<loc.LocationData>? _locationSubscription;
  GoogleMapController? _mapController;
  String _locationAddress = 'Getting location...';

  // Dark map style
  static const String _darkMapStyle = '''[
    {"elementType":"geometry","stylers":[{"color":"#242f3e"}]},
    {"elementType":"labels.text.stroke","stylers":[{"color":"#242f3e"}]},
    {"elementType":"labels.text.fill","stylers":[{"color":"#746855"}]},
    {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},
    {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},
    {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#263c3f"}]},
    {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#6b9a76"}]},
    {"featureType":"road","elementType":"geometry","stylers":[{"color":"#38414e"}]},
    {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#212a37"}]},
    {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca5b3"}]},
    {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#746855"}]},
    {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1f2835"}]},
    {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#f3d19c"}]},
    {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2f3948"}]},
    {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},
    {"featureType":"water","elementType":"geometry","stylers":[{"color":"#17263c"}]},
    {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#515c6d"}]},
    {"featureType":"water","elementType":"labels.text.stroke","stylers":[{"color":"#17263c"}]}
  ]''';

  @override
  void initState() {
    super.initState();
    user = FirebaseAuth.instance.currentUser;

    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    if (user == null) {
      _initDummyAnimations();
      return;
    }

    _dbService = DatabaseService(uid: user!.uid);

    _userDataSubscription = _dbService.userData.listen((userData) {
      if (mounted) {
        setState(() {
          _currentUserData = userData;
          _sosDelay = userData.sosDelay;
        });
      }
    });

    _initAnimations();
    _initFallDetection();
    _subscribeBleWearable();
    _startLocationUpdates();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _staggerController.forward();
    });
  }

  Future<void> _startLocationUpdates() async {
    try {
      final locationService = LocationService();
      final hasPermission = await locationService.checkLocationPermission();
      if (!hasPermission) {
        if (mounted) {
          setState(() => _locationAddress = 'Location denied');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is required for emergency alerts.'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Get initial location
      final initial = await locationService.getCurrentLocation();
      if (initial != null && mounted) {
        setState(() {
          _currentLocation = initial;
          _locationAddress =
              '${initial.latitude?.toStringAsFixed(4)}, ${initial.longitude?.toStringAsFixed(4)}';
        });
      }

      // Listen for updates
      final location = loc.Location();
      location.changeSettings(
        accuracy: loc.LocationAccuracy.high,
        interval: 5000,
        distanceFilter: 10,
      );
      _locationSubscription = location.onLocationChanged.listen((locData) {
        if (mounted) {
          setState(() {
            _currentLocation = locData;
            _locationAddress =
                '${locData.latitude?.toStringAsFixed(4)}, ${locData.longitude?.toStringAsFixed(4)}';
          });
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(
              LatLng(locData.latitude ?? 0, locData.longitude ?? 0),
            ),
          );
        }
      });
    } catch (e) {
      debugPrint('Location updates error: $e');
    }
  }

  void _subscribeBleWearable() {
    _bleSubscription = BleService.instance.sensorData.listen((data) {
      if (data['type'] == 'accelerometer') {
        _mlService.injectExternalAccelerometer(
          (data['x'] as num).toDouble(),
          (data['y'] as num).toDouble(),
          (data['z'] as num).toDouble(),
        );
      }
    });
  }

  Future<void> _initFallDetection() async {
    try {
      await _mlService.initialize();
      
      // Listen for background emergencies sent to the main isolate
      FlutterBackgroundService().on('onEmergencyEvent').listen((event) {
        if (mounted && event != null) {
          final type = event['type'] as String?;
          final confidence = event['confidence'] as double?;
          
          if (type == 'motion' && !_isFallDetected) {
            _onFallDetected(confidence ?? 0.85);
          } else if (type == 'noise' && !_isFallDetected) {
            _onDistressDetected(confidence ?? 0.90);
          }
        }
      });

      if (_isFallDetectionEnabled && mounted) {
        final noiseEnabled = context.read<SettingsProvider>().noiseDetectionEnabled;
        _mlService.startMonitoring(
          noiseEnabled: noiseEnabled,
          onMotion: (isAnomaly, confidence) {
            if (isAnomaly && !_isFallDetected && mounted) {
              _onFallDetected(confidence);
            }
          },
          onNoise: (isDistress, confidence) {
            if (isDistress && !_isFallDetected && mounted) {
              _onDistressDetected(confidence);
            }
          },
        );
      }
    } catch (e) {
      debugPrint('Fall detection init error: $e');
    }
  }

  void _onFallDetected(double confidence) {
    if (_isFallDetected) return;
    setState(() {
      _isFallDetected = true;
      _fallCountdown = _sosDelay.toInt();
    });
    _showFallDetectedDialog();
  }

  void _onDistressDetected(double confidence) {
    if (_isFallDetected) return;
    setState(() {
      _isFallDetected = true;
      _fallCountdown = _sosDelay.toInt();
    });
    _showFallDetectedDialog(alertType: 'distress');
  }

  void _showFallDetectedDialog({String alertType = 'fall'}) {
    final isFall = alertType == 'fall';
    final title = isFall ? 'Fall Detected!' : 'Distress Sound Detected!';
    final description = isFall
        ? 'A fall was detected. Emergency alert will be sent automatically.'
        : 'A distress sound was detected. Emergency alert will be sent automatically.';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          _fallAlertTimer?.cancel();
          _fallAlertTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (!mounted) {
              timer.cancel();
              return;
            }
            if (_fallCountdown <= 1) {
              timer.cancel();
              Navigator.of(dialogContext).pop();
              _triggerAutoSOS(alertType: alertType);
            } else {
              setDialogState(() => _fallCountdown--);
              setState(() {});
            }
          });

          return AlertDialog(
            backgroundColor: const Color(0xFF2C2C2C),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.warning_rounded,
                    color: Colors.redAccent, size: 32),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(title,
                        style: const TextStyle(color: Colors.white))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(description, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 24),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: CircularProgressIndicator(
                        value: _fallCountdown / _sosDelay,
                        strokeWidth: 8,
                        backgroundColor: Colors.grey[800],
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.redAccent),
                      ),
                    ),
                    Text('$_fallCountdown',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Tap "I\'m OK" to cancel',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    _cancelFallAlert();
                    Navigator.of(dialogContext).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('I\'m OK - Cancel Alert',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _cancelFallAlert() {
    _fallAlertTimer?.cancel();
    _fallAlertTimer = null;
    setState(() {
      _isFallDetected = false;
      _fallCountdown = _sosDelay.toInt();
    });
  }

  void _triggerAutoSOS({String alertType = 'fall'}) {
    _fallAlertTimer?.cancel();
    setState(() => _isFallDetected = false);
    _startSosSequence(alertType: alertType);
  }

  void _initDummyAnimations() {
    _sosController = AnimationController(vsync: this);
    _statusController = AnimationController(vsync: this);
    _sosScaleAnimation = const AlwaysStoppedAnimation(1.0);
    _statusScaleAnimation = const AlwaysStoppedAnimation(1.0);
  }

  void _initAnimations() {
    _sosController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _sosScaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _sosController, curve: Curves.easeInOut),
    );

    _statusController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _statusScaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _statusController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    try {
      _sosController.dispose();
      _statusController.dispose();
      _staggerController.dispose();
    } catch (e) {
      // Ignore errors if disposing dummy animations
    }
    _fallAlertTimer?.cancel();
    _mlService.dispose();
    _userDataSubscription?.cancel();
    _bleSubscription?.cancel();
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _openSettings() async {
    if (user == null) return;
    context.push(AppRoutes.settings);
  }

  Future<void> _openProfile() async {
    if (user == null || _currentUserData == null) return;
    final result =
        await context.push<Map<String, dynamic>>(AppRoutes.profile, extra: {
      'name': _currentUserData!.name,
      'phone': _currentUserData!.phone,
    });

    if (result != null) {
      await _dbService.updateUserData(_currentUserData!.copyWith(
        name: result['name'],
        phone: result['phone'],
      ));
    }
  }

  Future<void> _shareLocationViaWhatsApp() async {
    double lat;
    double lng;

    if (_currentLocation != null) {
      lat = _currentLocation!.latitude ?? 0;
      lng = _currentLocation!.longitude ?? 0;
    } else {
      // Fallback: try quick fetch
      final locationService = LocationService();
      final loc = await locationService.getCurrentLocation();
      if (loc == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location unavailable')),
        );
        return;
      }
      lat = loc.latitude ?? 0;
      lng = loc.longitude ?? 0;
    }

    final mapsLink = 'https://maps.google.com/?q=$lat,$lng';
    final message =
        Uri.encodeComponent('My live location via SafeNetic:\n$mapsLink');

    if (_latestGuardians.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No guardians to share with')),
      );
      return;
    }

    // Show guardian picker
    if (!mounted) return;
    final guardian = await showModalBottomSheet<GuardianModel>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _glassBottomSheet(
        title: 'Share Location With',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _latestGuardians.map((g) => _glassListTile(
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF25D366).withAlpha(25),
                border: Border.all(color: const Color(0xFF25D366).withAlpha(60)),
              ),
              child: Center(
                child: Text(g.name[0].toUpperCase(),
                    style: const TextStyle(
                        color: Color(0xFF25D366),
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ),
            ),
            title: g.name,
            subtitle: g.phone,
            trailing: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.send, color: Color(0xFF25D366), size: 18),
            ),
            onTap: () => Navigator.pop(ctx, g),
          )).toList(),
        ),
      ),
    );

    if (guardian == null || !mounted) return;

    // Clean phone number (remove non-digits except +)
    String phone = guardian.phone.replaceAll(RegExp(r'[^\d+]'), '');
    
    // First, if it starts with '00', treat it as '+'
    if (phone.startsWith('00')) {
      phone = '+${phone.substring(2)}';
    }
    
    // If no country code, assume Pakistan (+92)
    if (!phone.startsWith('+')) {
      if (phone.startsWith('0')) {
        phone = '+92${phone.substring(1)}';
      } else if (phone.startsWith('92') && phone.length == 12) {
        phone = '+$phone';
      } else {
        phone = '+92$phone';
      }
    }
    
    // Send location via SMS (silent text)
    // Remove '+' for SMS format
    phone = phone.replaceAll('+', '');

    final smsUrl = Uri.parse('sms:$phone?body=$message');
    if (await canLaunchUrl(smsUrl)) {
      await launchUrl(smsUrl, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open SMS app')),
        );
      }
    }
  }

  Future<void> _startSosSequence({String alertType = 'manual'}) async {
    if (!mounted) return;

    final guardianMaps = _latestGuardians.map((g) => g.toMap()).toList();

    context.push(AppRoutes.alertSent, extra: {
      'sosDelaySeconds': _sosDelay,
      'guardians': guardianMaps,
      'alertType': alertType,
      'userName': _currentUserData?.name ?? 'User',
      'locationData': _currentLocation != null
          ? loc.LocationData.fromMap({
              'latitude': _currentLocation!.latitude,
              'longitude': _currentLocation!.longitude,
            })
          : null,
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGGERED ANIMATION HELPER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _staggered(int index, Widget child) {
    final start = (index * 0.07).clamp(0.0, 0.65);
    final end = (start + 0.35).clamp(0.0, 1.0);

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.12),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      )),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(
            parent: _staggerController,
            curve: Interval(start, end, curve: Curves.easeOut),
          ),
        ),
        child: child,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GLASSMORPHISM COMPONENTS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _glassCard({required Widget child, Color? accentColor}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withAlpha(15),
            Colors.white.withAlpha(8),
          ],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
        border: Border.all(
          color: (accentColor ?? Colors.white).withAlpha(20),
          width: 1,
        ),
      ),
      child: child,
    );
  }

  Widget _glowingIcon(IconData ic, {Color? color}) {
    final c = color ?? AppColors.primary;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: c.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withAlpha(40)),
        boxShadow: [
          BoxShadow(color: c.withAlpha(20), blurRadius: 12, spreadRadius: 1),
        ],
      ),
      child: Icon(ic, color: c, size: 18),
    );
  }

  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4),
        child: Text(t.toUpperCase(),
            style: AppTextStyles.overline.copyWith(
              color: AppColors.textHint,
              letterSpacing: 2.0,
              fontSize: 11,
            )),
      );

  Widget _glassPill({
    required String label,
    IconData? icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withAlpha(50)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: color, size: 14),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: AppTextStyles.buttonSmall.copyWith(
                      color: color, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(10),
            borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
            border: Border.all(color: Colors.white.withAlpha(15)),
          ),
          child: Icon(icon, color: AppColors.textPrimary, size: 20),
        ),
      ),
    );
  }

  Widget _glassBottomSheet({required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.surfaceLight,
            AppColors.surface,
          ],
        ),
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXLarge)),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(title, style: AppTextStyles.h3),
            const SizedBox(height: 16),
            child,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _glassListTile({
    required Widget leading,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
              border: Border.all(color: Colors.white.withAlpha(10)),
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: AppTextStyles.bodyLarge),
                      Text(subtitle, style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body:
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: AppBar(
                backgroundColor: AppColors.background.withAlpha(180),
                elevation: 0,
                leading: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _glassIconButton(
                    icon: Icons.person_rounded,
                    onPressed: _openProfile,
                  ),
                ),
                centerTitle: true,
                title: const Text('SafeNetic', style: AppTextStyles.h2),
                actions: [
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: _glassIconButton(
                      icon: Icons.settings_outlined,
                      onPressed: _openSettings,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: kToolbarHeight + MediaQuery.of(context).padding.top + 16),

              // Status Card
              _staggered(0, StatusCard(
                statusController: _statusController,
                statusScaleAnimation: _statusScaleAnimation,
              )),
              const SizedBox(height: 32),

              // SOS Button
              _staggered(1, Center(
                child: SosButton(
                  sosScaleAnimation: _sosScaleAnimation,
                  onTap: _startSosSequence,
                ),
              )),
              _staggered(2, const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Press for immediate emergency alert',
                    style: AppTextStyles.bodySmall,
                  ),
                ),
              )),
              const SizedBox(height: 32),

              // Guardians Section
              _staggered(3, _sectionLabel('Guardians')),
              _staggered(4, _buildGuardiansSection()),
              const SizedBox(height: 28),

              // Live Location
              _staggered(5, _sectionLabel('Live Location')),
              _staggered(6, _buildLiveLocationSection()),
              const SizedBox(height: 28),

              // Connected Devices
              _staggered(7, _sectionLabel('Connected Devices')),
              _staggered(8, _buildDevicesSection()),
              const SizedBox(height: 20),

              // Bottom Tip
              _staggered(9, _buildBottomTip()),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GUARDIANS SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGuardiansSection() {
    return StreamBuilder<List<GuardianModel>>(
      stream: _dbService.guardians,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text("Error loading guardians",
              style: TextStyle(color: Colors.red));
        }

        if (snapshot.hasData) _latestGuardians = snapshot.data!;
        final guardians = snapshot.data ?? [];

        return _glassCard(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _glowingIcon(Icons.shield_rounded),
                      const SizedBox(width: 12),
                      const Text("Trusted Contacts", style: AppTextStyles.h3),
                    ],
                  ),
                  _glassPill(
                    label: 'Add',
                    icon: Icons.add_rounded,
                    color: AppColors.primary,
                    onTap: () => _showGuardianDialog(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (guardians.isEmpty)
                _emptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'No trusted contacts configured',
                  subtitle: 'Add people who should be notified during an emergency.',
                )
              else
                ...guardians.map((g) => _buildGuardianTile(g)),
            ],
          ),
        );
      },
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppColors.textHint.withAlpha(80)),
          const SizedBox(height: 10),
          Text(title, style: AppTextStyles.bodyMedium),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildGuardianTile(GuardianModel guardian) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          onTap: () => _showGuardianDialog(existing: guardian),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(6),
              borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
              border: Border.all(color: Colors.white.withAlpha(8)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withAlpha(20),
                    border: Border.all(
                        color: AppColors.primary.withAlpha(40), width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      guardian.name.isNotEmpty
                          ? guardian.name[0].toUpperCase()
                          : '?',
                      style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(guardian.name, style: AppTextStyles.bodyLarge),
                      Text('${guardian.relationship} • ${guardian.phone}',
                          style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _dbService.deleteGuardian(guardian.id);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.error.withAlpha(15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: AppColors.error, size: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIVE LOCATION SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLiveLocationSection() {
    final lat = _currentLocation?.latitude ?? 33.6844;
    final lng = _currentLocation?.longitude ?? 73.0479;

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _glowingIcon(Icons.location_on_rounded, color: AppColors.info),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_locationAddress,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textPrimary)),
                    const Text('Live tracking active',
                        style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          RepaintBoundary(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withAlpha(10)),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                ),
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(lat, lng),
                    zoom: 15,
                  ),
                  style: _darkMapStyle,
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                  markers: {
                    Marker(
                      markerId: const MarkerId('me'),
                      position: LatLng(lat, lng),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueAzure),
                    ),
                  },
                  myLocationEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: false,
                  scrollGesturesEnabled: false,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  zoomGesturesEnabled: false,
                  liteModeEnabled: false,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _glassPill(
                label: 'Refresh',
                icon: Icons.refresh_rounded,
                color: AppColors.success,
                onTap: () async {
                  final locationService = LocationService();
                  final loc = await locationService.getCurrentLocation();
                  if (loc != null && mounted) {
                    setState(() {
                      _currentLocation = loc;
                      _locationAddress =
                          '${loc.latitude?.toStringAsFixed(4)}, ${loc.longitude?.toStringAsFixed(4)}';
                    });
                    _mapController?.animateCamera(
                      CameraUpdate.newLatLng(
                        LatLng(loc.latitude ?? 0, loc.longitude ?? 0),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(width: 12),
              _glassPill(
                label: 'Share via WhatsApp',
                icon: Icons.share_rounded,
                color: const Color(0xFF25D366),
                onTap: _shareLocationViaWhatsApp,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONNECTED DEVICES SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDevicesSection() {
    return StreamBuilder<List<DeviceModel>>(
      stream: _dbService.devices,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox();
        final devices = snapshot.data ?? [];

        return _glassCard(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _glowingIcon(Icons.watch_rounded, color: AppColors.info),
                      const SizedBox(width: 12),
                      const Text("Devices", style: AppTextStyles.h3),
                    ],
                  ),
                  _glassPill(
                    label: 'Pair',
                    icon: Icons.bluetooth_searching_rounded,
                    color: AppColors.info,
                    onTap: () => _showDeviceDialog(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (devices.isEmpty)
                _emptyState(
                  icon: Icons.bluetooth_disabled_rounded,
                  title: 'No wearable devices connected',
                  subtitle: 'Pair a smartwatch for enhanced fall detection.',
                )
              else
                ...devices.map((d) => _buildDeviceTile(d)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDeviceTile(DeviceModel device) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(6),
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          border: Border.all(color: Colors.white.withAlpha(8)),
        ),
        child: Row(
          children: [
            _glowingIcon(Icons.bluetooth_connected_rounded,
                color: AppColors.info),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.name, style: AppTextStyles.bodyLarge),
                  Row(
                    children: [
                      Text(device.type, style: AppTextStyles.bodySmall),
                      const SizedBox(width: 8),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.success.withAlpha(80),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text("Connected",
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.success)),
                    ],
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _dbService.deleteDevice(device.id);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.error.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close_rounded,
                    color: AppColors.error, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTTOM TIP
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomTip() {
    return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacing16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.success.withAlpha(12),
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
            border: Border.all(color: AppColors.success.withAlpha(30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.success.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.check_circle_rounded,
                    color: AppColors.success.withAlpha(200), size: 18),
              ),
              const SizedBox(width: AppConstants.spacing12),
              Expanded(
                child: Text(
                  'Keep your phone charged and GPS enabled for the most accurate protection.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.success, fontSize: 12),
                ),
              ),
            ],
          ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DIALOGS (preserved, styled)
  // ═══════════════════════════════════════════════════════════════════════════

  void _showGuardianDialog({GuardianModel? existing}) {
    final nameController = TextEditingController(text: existing?.name ?? "");
    final phoneController = TextEditingController(text: existing?.phone ?? "");
    final relationController =
        TextEditingController(text: existing?.relationship ?? "");

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(existing == null ? "Add Guardian" : "Edit Guardian"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                    controller: nameController,
                    label: "Name",
                    icon: Icons.person),
                const SizedBox(height: 15),
                _buildDialogTextField(
                    controller: phoneController,
                    label: "Phone",
                    icon: Icons.phone,
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 15),
                _buildDialogTextField(
                    controller: relationController,
                    label: "Relationship",
                    icon: Icons.favorite),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty && user != null) {
                  final newGuardian = GuardianModel(
                    id: existing?.id ?? '',
                    name: nameController.text,
                    phone: phoneController.text,
                    relationship: relationController.text.isEmpty
                        ? "Contact"
                        : relationController.text,
                  );
                  await _dbService.addGuardian(newGuardian);
                  if (context.mounted) context.pop();
                }
              },
              child: Text(existing == null ? "Add" : "Save"),
            ),
          ],
        );
      },
    );
  }

  void _showDeviceDialog({DeviceModel? existing}) {
    final nameController = TextEditingController(text: existing?.name ?? "");
    String? selectedType = existing?.type;
    final List<String> deviceTypes = [
      "Smart Watch",
      "Fitness Tracker",
      "Bluetooth Tag",
      "Smartphone",
      "Other"
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(existing == null ? "Add Device" : "Edit Device"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDialogTextField(
                        controller: nameController,
                        label: "Device Name",
                        icon: Icons.devices),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: selectedType,
                      dropdownColor: AppColors.surfaceLight,
                      style: AppTextStyles.bodyMedium,
                      decoration: const InputDecoration(
                        labelText: "Device Type",
                        prefixIcon: Icon(Icons.category_rounded),
                      ),
                      items: deviceTypes
                          .map((type) =>
                              DropdownMenuItem(value: type, child: Text(type)))
                          .toList(),
                      onChanged: (val) =>
                          setStateDialog(() => selectedType = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () async {
                    if (nameController.text.isNotEmpty &&
                        selectedType != null &&
                        user != null) {
                      final newDevice = DeviceModel(
                        id: existing?.id ?? '',
                        name: nameController.text,
                        type: selectedType!,
                        isConnected: true,
                      );
                      await _dbService.addDevice(newDevice);
                      if (context.mounted) context.pop();
                    }
                  },
                  child: Text(existing == null ? "Add" : "Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDialogTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
    );
  }
}
