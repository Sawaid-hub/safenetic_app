import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safenetic_app/constants/app_colors.dart';
import 'package:safenetic_app/constants/app_constants.dart';
import 'package:safenetic_app/constants/app_text_styles.dart';
import 'package:safenetic_app/services/database_service.dart';
import 'package:safenetic_app/services/ble_service.dart';
import 'package:safenetic_app/models/user_model.dart';
import 'package:safenetic_app/constants/app_routes.dart';
import 'package:safenetic_app/providers/settings_provider.dart';

class SettingsScreen extends StatefulWidget {
  final double initialSosDelay;
  const SettingsScreen({super.key, this.initialSosDelay = 10.0});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with TickerProviderStateMixin {
  User? _user;
  DatabaseService? _dbService;
  Stream<UserModel>? _userStream;
  String? _initError;

  final Battery _battery = Battery();
  int _batteryLevel = 100;
  BatteryState? _batteryState;
  StreamSubscription<BatteryState>? _batterySub;

  bool _fallDetection = true;
  bool _voiceCommands = true;
  double _sensitivity = 0.5;

  // Staggered animation controller
  late AnimationController _staggerController;

  // Section keys for hero-like scroll animations
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _init();
    // Start stagger animation after frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _staggerController.forward();
    });
  }

  void _init() {
    try {
      _user = FirebaseAuth.instance.currentUser;
      if (_user == null || _user!.uid.isEmpty) {
        _initError = 'Not logged in. Please sign in first.';
        return;
      }
      _dbService = DatabaseService(uid: _user!.uid);
      _userStream = _dbService!.userData;
      _initBattery();
      _loadPrefs();
    } catch (e) {
      _initError = e.toString();
      debugPrint('[Settings] init error: $e');
    }
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _fallDetection = p.getBool('ai_fall_detection_enabled') ?? true;
      _voiceCommands = p.getBool('voice_commands_enabled') ?? true;
      _sensitivity = p.getDouble('fall_sensitivity') ?? 0.5;
    });
  }

  Future<void> _savePref(String key, dynamic val) async {
    final p = await SharedPreferences.getInstance();
    if (val is bool) await p.setBool(key, val);
    if (val is double) await p.setDouble(key, val);
  }

  Future<void> _initBattery() async {
    try {
      _batteryLevel = await _battery.batteryLevel;
      if (mounted) setState(() {});
    } catch (_) {}
    try {
      _batterySub = _battery.onBatteryStateChanged.listen((s) {
        if (mounted) setState(() => _batteryState = s);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _batterySub?.cancel();
    _staggerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _updateUser(UserModel u, Map<String, dynamic> c) async {
    await _dbService?.updateUserData(u.copyWith(
      name: c['name'],
      phone: c['phone'],
      biometricEnabled: c['biometricEnabled'],
      notificationsEnabled: c['notificationsEnabled'],
      sosDelay: c['sosDelay']?.toDouble(),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_initError != null || _userStream == null) {
      return _scaffold(body: _errorBody());
    }

    return _scaffold(
      body: StreamBuilder<UserModel>(
        stream: _userStream,
        builder: (ctx, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Error: ${snap.error}',
                    style: const TextStyle(color: AppColors.error)),
              ),
            );
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final data = snap.data;
          if (data == null) {
            return const Center(
                child: Text('No data found',
                    style: TextStyle(color: Colors.white)));
          }
          return _body(data);
        },
      ),
    );
  }

  Widget _scaffold({required Widget body}) {
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
                title: const Text('Settings', style: AppTextStyles.h2),
                centerTitle: true,
                leading: _glassIconButton(
                  icon: Icons.arrow_back_rounded,
                  onPressed: () => context.pop(),
                ),
              ),
            ),
          ),
        ),
        body: body,
      ),
    );
  }

  Widget _errorBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text(
              _initError ?? 'Could not load settings.',
              style: const TextStyle(color: AppColors.error, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => setState(() {
                _initError = null;
                _init();
              }),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN BODY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _body(UserModel u) {
    final sections = <Widget>[
      const SizedBox(height: kToolbarHeight + 60),

      // Account
      _animatedSection(0, _label('Account')),
      _animatedSection(1, _profileCard(u)),
      const SizedBox(height: 28),

      // Safety & Security
      _animatedSection(2, _label('Safety & Security')),
      _animatedSection(3, _glassCard([
        _switchRow('Biometric Unlock', 'Use FaceID / Fingerprint',
            Icons.fingerprint_rounded, u.biometricEnabled, (v) {
          _updateUser(u, {'biometricEnabled': v});
        }),
        _glassDivider(),
        _sliderRow(
            'SOS Delay Timer',
            '${u.sosDelay.clamp(5.0, 30.0).toInt()}s',
            Icons.timer_outlined,
            u.sosDelay.clamp(5.0, 30.0), (v) {
          _updateUser(u, {'sosDelay': v});
        }, min: 5, max: 30),
        _glassDivider(),
        _tapRow('Manage Guardians', 'Manage on Home Screen',
            Icons.group_add_rounded, () => context.pop()),
        _glassDivider(),
        _tapRow('Guardian Push Link', 'Link devices for SOS push alerts',
            Icons.notifications_active_rounded, () => context.push(AppRoutes.guardianLink)),
      ])),
      const SizedBox(height: 28),

      // Detection
      _animatedSection(4, _label('Detection')),
      _animatedSection(5, _glassCard([
        _switchRow('AI Fall Detection', 'Auto-detect accidents via sensors',
            Icons.sensors_rounded, _fallDetection, (v) {
          setState(() => _fallDetection = v);
          _savePref('ai_fall_detection_enabled', v);
        }),
        _glassDivider(),
        Consumer<SettingsProvider>(
          builder: (ctx, settings, _) => _switchRow(
            'Noise Detection',
            'Detect distress sounds (crashes, screams)',
            Icons.graphic_eq_rounded,
            settings.noiseDetectionEnabled,
            (v) => settings.setNoiseDetectionEnabled(v),
          ),
        ),
        _glassDivider(),
        _switchRow('Voice Commands', 'Say "Cancel" to dismiss false alerts',
            Icons.mic_rounded, _voiceCommands, (v) {
          setState(() => _voiceCommands = v);
          _savePref('voice_commands_enabled', v);
        }),
        _glassDivider(),
        _tapRow(
          'ML Developer Studio',
          'Live inference test & raw sensor visualizations',
          Icons.developer_board_rounded,
          () => context.push(AppRoutes.mlTest),
        ),
        _glassDivider(),
        _sliderRow(
            'Sensitivity',
            _sensitivityLabel(_sensitivity.clamp(0.0, 1.0)),
            Icons.tune_rounded,
            _sensitivity.clamp(0.0, 1.0), (v) {
          setState(() => _sensitivity = v);
          _savePref('fall_sensitivity', v);
        }, min: 0, max: 1),
      ])),
      const SizedBox(height: 28),

      // General
      _animatedSection(6, _label('General')),
      _animatedSection(7, _glassCard([
        _switchRow('Push Notifications', 'Receive alerts from guardians',
            Icons.notifications_active_rounded, u.notificationsEnabled, (v) {
          _updateUser(u, {'notificationsEnabled': v});
        }),
        _glassDivider(),
        _tapRow('Background Location', 'Managed by OS permissions',
            Icons.location_on_rounded, null),
      ])),
      const SizedBox(height: 28),

      // Wearable
      _animatedSection(8, _label('Wearable Devices')),
      _animatedSection(9, _wearableCard()),
      const SizedBox(height: 28),

      // Battery
      _animatedSection(10, _label('Device Health')),
      _animatedSection(11, _batteryCard()),
      const SizedBox(height: 36),

      // Log out
      _animatedSection(12, _logoutButton()),
      const SizedBox(height: 40),
    ];

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      physics: const BouncingScrollPhysics(),
      children: sections,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANIMATION HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _animatedSection(int index, Widget child) {
    final start = (index * 0.06).clamp(0.0, 0.7);
    final end = (start + 0.3).clamp(0.0, 1.0);

    final slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _staggerController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    ));

    final fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: Curves.easeOut),
      ),
    );

    return SlideTransition(
      position: slideAnim,
      child: FadeTransition(opacity: fadeAnim, child: child),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GLASSMORPHISM COMPONENTS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _glassCard(List<Widget> children) {
    return Container(
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
          color: Colors.white.withAlpha(20),
          width: 1,
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _glassDivider() => Divider(
        height: 1,
        indent: 56,
        color: Colors.white.withAlpha(10),
      );

  Widget _glassIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
          onTap: () {
            HapticFeedback.lightImpact();
            onPressed();
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
              border: Border.all(color: Colors.white.withAlpha(15)),
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _glowingIcon(IconData ic, {Color? color}) {
    final c = color ?? AppColors.primary;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: c.withAlpha(25),
        borderRadius: BorderRadius.circular(AppConstants.radiusSmall + 2),
        border: Border.all(color: c.withAlpha(40)),
        boxShadow: [
          BoxShadow(
            color: c.withAlpha(20),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(ic, color: c, size: 18),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4),
        child: Text(t.toUpperCase(),
            style: AppTextStyles.overline.copyWith(
              color: AppColors.textHint,
              letterSpacing: 2.0,
              fontSize: 11,
            )),
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // SETTING ROWS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _switchRow(String title, String sub, IconData ic, bool val,
      ValueChanged<bool> onChanged) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!val);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _glowingIcon(ic,
                  color: val ? AppColors.primary : AppColors.textHint),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: AppTextStyles.bodyLarge),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: AppConstants.animFast,
                curve: Curves.easeInOut,
                child: Switch.adaptive(
                  value: val,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    onChanged(v);
                  },
                  activeThumbColor: AppColors.primary,
                  activeTrackColor: AppColors.primary.withAlpha(80),
                  inactiveThumbColor: AppColors.textHint,
                  inactiveTrackColor: AppColors.surfaceElevated,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sliderRow(String title, String valLabel, IconData ic, double val,
      ValueChanged<double> onChanged,
      {double min = 0, double max = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _glowingIcon(ic),
              const SizedBox(width: 14),
              Text(title, style: AppTextStyles.bodyLarge),
              const Spacer(),
              AnimatedSwitcher(
                duration: AppConstants.animFast,
                child: Container(
                  key: ValueKey(valLabel),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(20),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusSmall),
                    border:
                        Border.all(color: AppColors.primary.withAlpha(40)),
                  ),
                  child: Text(valLabel,
                      style: AppTextStyles.labelLarge
                          .copyWith(color: AppColors.primary, fontSize: 13)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: Colors.white.withAlpha(12),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withAlpha(30),
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: val,
              min: min,
              max: max,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tapRow(String title, String sub, IconData ic, VoidCallback? onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap != null
            ? () {
                HapticFeedback.lightImpact();
                onTap();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _glowingIcon(ic),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: AppTextStyles.bodyLarge),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (onTap != null)
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textHint, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROFILE CARD (Glassmorphism)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _profileCard(UserModel u) {
    final initials =
        (u.name.trim().isEmpty) ? '?' : u.name.trim()[0].toUpperCase();

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
        border: Border.all(color: Colors.white.withAlpha(20), width: 1),
      ),
      child: Row(
            children: [
              // Avatar with glow
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withAlpha(60),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(initials,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      u.name.isEmpty ? 'Set Name' : u.name,
                      style: AppTextStyles.h3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.success,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.success.withAlpha(80),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            u.phone.isEmpty ? 'Set Phone' : u.phone,
                            style: AppTextStyles.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _glassIconButton(
                icon: Icons.edit_rounded,
                onPressed: () async {
                  final result = await context
                      .push<Map<String, dynamic>>(AppRoutes.profile, extra: {
                    'name': u.name,
                    'phone': u.phone,
                  });
                  if (result != null) {
                    _updateUser(u, {
                      'name': result['name'],
                      'phone': result['phone'],
                    });
                  }
                },
              ),
            ],
          ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WEARABLE CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _wearableCard() {
    try {
      final ble = BleService.instance;
      final connected = ble.isConnected;
      final devName = ble.connectedDevice?.platformName;

      return _glassCard([
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _glowingIcon(Icons.watch_rounded,
                      color: connected ? AppColors.info : AppColors.textHint),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          connected
                              ? 'Connected: ${(devName != null && devName.isNotEmpty) ? devName : "Device"}'
                              : 'No wearable connected',
                          style: AppTextStyles.bodyLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (connected)
                          Text('Sensor data active',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.success)),
                      ],
                    ),
                  ),
                  if (connected)
                    _glassPill(
                      label: 'Disconnect',
                      color: AppColors.error,
                      onTap: () async {
                        await ble.disconnect();
                        if (mounted) setState(() {});
                      },
                    )
                  else
                    _glassPill(
                      label: 'Scan',
                      icon: Icons.bluetooth_searching_rounded,
                      color: AppColors.info,
                      onTap: _openScanSheet,
                    ),
                ],
              ),
            ],
          ),
        ),
      ]);
    } catch (_) {
      return _glassCard([
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _glowingIcon(Icons.bluetooth_disabled_rounded,
                  color: AppColors.error),
              const SizedBox(width: 14),
              const Text('BLE Initialization is offline',
                  style: TextStyle(color: AppColors.error, fontSize: 13)),
            ],
          ),
        ),
      ]);
    }
  }

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
                Icon(icon, color: color, size: 15),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: AppTextStyles.buttonSmall.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BATTERY CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _batteryCard() {
    final low = _batteryLevel < 20;
    final charging = _batteryState == BatteryState.charging ||
        _batteryState == BatteryState.full;
    final warn = low && !charging;

    return _glassCard([
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _glowingIcon(
                  charging
                      ? Icons.battery_charging_full_rounded
                      : warn
                          ? Icons.battery_alert_rounded
                          : Icons.battery_full_rounded,
                  color: warn ? AppColors.error : AppColors.success,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Battery: $_batteryLevel%',
                          style: AppTextStyles.bodyLarge
                              .copyWith(fontWeight: FontWeight.w600)),
                      Text(charging ? 'Charging' : 'Discharging',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Battery bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: AnimatedContainer(
                duration: AppConstants.animMedium,
                height: 6,
                child: LinearProgressIndicator(
                  value: _batteryLevel / 100,
                  backgroundColor: Colors.white.withAlpha(10),
                  valueColor: AlwaysStoppedAnimation(
                    warn
                        ? AppColors.error
                        : charging
                            ? AppColors.info
                            : AppColors.success,
                  ),
                ),
              ),
            ),
            if (warn) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withAlpha(15),
                  border: Border.all(color: AppColors.error.withAlpha(40)),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMedium),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: AppColors.error.withAlpha(200), size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Low battery may affect background fall detection.',
                        style: TextStyle(
                            color: AppColors.error, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOGOUT BUTTON
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _logoutButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        onTap: () async {
          HapticFeedback.heavyImpact();
          Navigator.of(context).popUntil((r) => r.isFirst);
          await FirebaseAuth.instance.signOut();
        },
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.error.withAlpha(12),
            borderRadius:
                BorderRadius.circular(AppConstants.radiusMedium),
            border: Border.all(color: AppColors.error.withAlpha(40)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded,
                  size: 20, color: AppColors.error),
              SizedBox(width: 10),
              Text('Log Out',
                  style: TextStyle(
                      color: AppColors.error,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BLE SCAN SHEET (Glassmorphism)
  // ═══════════════════════════════════════════════════════════════════════════

  void _openScanSheet() {
    try {
      final ble = BleService.instance;
      ble.startScan();

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppConstants.radiusXLarge)),
        ),
        builder: (ctx) {
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
            child: StreamBuilder<List<ScanResult>>(
                  stream: ble.scanResults,
                  builder: (context, snapshot) {
                    final devices = snapshot.data ?? [];
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Handle
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(30),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Scanning for Devices',
                                  style: AppTextStyles.h3),
                              _glassIconButton(
                                icon: Icons.close_rounded,
                                onPressed: () {
                                  ble.stopScan();
                                  Navigator.pop(ctx);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (devices.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 30),
                              child: Center(
                                child: Column(
                                  children: [
                                    SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: CircularProgressIndicator(
                                        color: AppColors.info,
                                        strokeWidth: 3,
                                        backgroundColor:
                                            Colors.white.withAlpha(10),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text('Looking for nearby devices...',
                                        style: AppTextStyles.bodyMedium),
                                  ],
                                ),
                              ),
                            )
                          else
                            ...devices.take(8).map((r) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withAlpha(8),
                                      borderRadius: BorderRadius.circular(
                                          AppConstants.radiusMedium),
                                      border: Border.all(
                                          color: Colors.white.withAlpha(10)),
                                    ),
                                    child: Row(
                                      children: [
                                        _glowingIcon(
                                            Icons.bluetooth_rounded,
                                            color: AppColors.info),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(r.device.platformName,
                                                  style:
                                                      AppTextStyles.bodyLarge),
                                              Text('Signal: ${r.rssi} dBm',
                                                  style:
                                                      AppTextStyles.bodySmall),
                                            ],
                                          ),
                                        ),
                                        _glassPill(
                                          label: 'Pair',
                                          color: AppColors.info,
                                          onTap: () async {
                                            final messenger =
                                                ScaffoldMessenger.of(context);
                                            await ble.stopScan();
                                            final ok =
                                                await ble.connect(r.device);
                                            if (ctx.mounted) {
                                              Navigator.pop(ctx);
                                            }
                                            if (mounted) {
                                              setState(() {});
                                              messenger.showSnackBar(SnackBar(
                                                content: Text(ok
                                                    ? 'Connected to ${r.device.platformName}'
                                                    : 'Failed to connect'),
                                                backgroundColor: ok
                                                    ? AppColors.success
                                                    : AppColors.error,
                                              ));
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                )),
                        ],
                      ),
                    );
                  },
                ),
          );
        },
      );
    } catch (e) {
      debugPrint('BLE Scan Exception: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  String _sensitivityLabel(double v) {
    if (v < 0.33) return 'Low';
    if (v < 0.66) return 'Medium';
    return 'High';
  }
}
