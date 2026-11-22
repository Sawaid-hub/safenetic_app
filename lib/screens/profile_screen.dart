import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:safenetic_app/services/database_service.dart';
import 'package:safenetic_app/services/location_service.dart';
import 'package:safenetic_app/models/user_model.dart';
import 'package:safenetic_app/models/guardian_model.dart';
import 'package:safenetic_app/models/device_model.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:safenetic_app/constants/app_routes.dart';
import 'package:safenetic_app/constants/app_colors.dart';
import 'package:safenetic_app/constants/app_constants.dart';
import 'package:safenetic_app/constants/app_text_styles.dart';
import 'package:safenetic_app/widgets/profile/profile_menu_tile.dart';
import 'package:safenetic_app/widgets/profile/sign_out_row.dart';

class ProfileScreen extends StatefulWidget {
  final String initialName;
  final String initialPhone;

  const ProfileScreen({
    super.key,
    required this.initialName,
    required this.initialPhone,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  DatabaseService? _dbService;
  UserModel? _userData;
  String _locationText = 'Getting location...';
  int _guardianCount = 0;
  int _deviceCount = 0;
  bool _accountExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadLocation();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _dbService = DatabaseService(uid: user.uid);

    _dbService!.userData.listen((userData) {
      if (!mounted) return;
      setState(() => _userData = userData);
    });

    _dbService!.guardians.listen((guardians) {
      if (!mounted) return;
      setState(() => _guardianCount = guardians.length);
    });

    _dbService!.devices.listen((devices) {
      if (!mounted) return;
      setState(() => _deviceCount = devices.length);
    });
  }

  Future<void> _loadLocation() async {
    try {
      final locationService = LocationService();
      final loc = await locationService.getCurrentLocation();
      if (loc != null && mounted) {
        setState(() {
          _locationText =
              '${loc.latitude?.toStringAsFixed(3)}, ${loc.longitude?.toStringAsFixed(3)}';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _locationText = 'Location unavailable');
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
          'Are you sure you want to sign out? Fall detection and guardian alerts will stop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) context.go('/login');
    }
  }

  Future<void> _startQuickSOS() async {
    if (!mounted) return;
    final locationService = LocationService();
    final locationData = await locationService.getCurrentLocation();
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final dbService = DatabaseService(uid: user.uid);
    final guardians = await dbService.guardians.first;
    final guardianMaps = guardians.map((g) => g.toMap()).toList();

    if (!mounted) return;
    context.push(AppRoutes.alertSent, extra: {
      'sosDelaySeconds': 3.0,
      'guardians': guardianMaps,
      'alertType': 'manual',
      'userName': _userData?.name ?? 'User',
      'locationData': locationData,
    });
  }

  String _getInitials() {
    final name = _userData?.name ?? widget.initialName;
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  // ── Personal Info Edit Bottom Sheet ──
  void _openPersonalInfo() {
    final nameCtrl =
        TextEditingController(text: _userData?.name ?? widget.initialName);
    final phoneCtrl =
        TextEditingController(text: _userData?.phone ?? widget.initialPhone);
    final bloodCtrl = TextEditingController(text: _userData?.bloodType ?? '');
    final medicalCtrl =
        TextEditingController(text: _userData?.medicalConditions ?? '');
    final allergiesCtrl =
        TextEditingController(text: _userData?.allergies ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXLarge)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Edit Profile', style: AppTextStyles.h3),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textHint),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _editField('Full Name', nameCtrl, Icons.person_outline),
              const SizedBox(height: 12),
              _editField('Phone Number', phoneCtrl, Icons.phone_outlined,
                  keyboard: TextInputType.phone),
              const SizedBox(height: 12),
              _editField('Blood Type', bloodCtrl, Icons.bloodtype_outlined,
                  hint: 'e.g. O+, A-'),
              const SizedBox(height: 12),
              _editField('Medical Conditions', medicalCtrl,
                  Icons.monitor_heart_outlined,
                  hint: 'e.g. Diabetes, Asthma'),
              const SizedBox(height: 12),
              _editField(
                  'Allergies', allergiesCtrl, Icons.warning_amber_outlined,
                  hint: 'e.g. Penicillin, Peanuts'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusMedium)),
                  ),
                  onPressed: () async {
                    if (_dbService != null && _userData != null) {
                      await _dbService!.updateUserData(_userData!.copyWith(
                        name: nameCtrl.text.trim(),
                        phone: phoneCtrl.text.trim(),
                        bloodType: bloodCtrl.text.trim().isEmpty
                            ? null
                            : bloodCtrl.text.trim(),
                        medicalConditions: medicalCtrl.text.trim().isEmpty
                            ? null
                            : medicalCtrl.text.trim(),
                        allergies: allergiesCtrl.text.trim().isEmpty
                            ? null
                            : allergiesCtrl.text.trim(),
                      ));
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Profile saved'),
                          backgroundColor: AppColors.success,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusMedium)),
                        ),
                      );
                    }
                  },
                  child: const Text('Save Changes',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editField(String label, TextEditingController ctrl, IconData icon,
      {TextInputType keyboard = TextInputType.text, String? hint}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
    );
  }

  // ── Help & Support Dialog ──
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Help & Support'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _helpItem(Icons.email_outlined, 'Email', 'support@safenetic.app'),
            const SizedBox(height: 12),
            _helpItem(Icons.info_outline, 'Version', '1.0.0'),
            const SizedBox(height: 12),
            _helpItem(
                Icons.description_outlined,
                'About',
                'SafeNetic is a personal safety application that uses AI-powered '
                    'fall detection and guardian alerts to keep you safe.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _helpItem(IconData icon, String title, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: AppConstants.spacing12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.bodyMedium),
              const SizedBox(height: 2),
              Text(value, style: AppTextStyles.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  // ── Guardian Management Sheet ──
  void _showGuardiansSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXLarge)),
      ),
      builder: (ctx) => StreamBuilder<List<GuardianModel>>(
        stream: _dbService?.guardians,
        builder: (context, snapshot) {
          final guardians = snapshot.data ?? [];
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Trusted Guardians', style: AppTextStyles.h3),
                    IconButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showAddGuardianDialog();
                      },
                      icon: const Icon(Icons.person_add_rounded,
                          color: AppColors.success),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (guardians.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('No guardians added yet',
                          style: AppTextStyles.bodyMedium),
                    ),
                  )
                else
                  ...guardians.map((g) => ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.success,
                          child: Text(g.name[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(g.name, style: AppTextStyles.bodyLarge),
                        subtitle: Text('${g.phone}  •  ${g.relationship}',
                            style: AppTextStyles.bodySmall),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: AppColors.error, size: 20),
                          onPressed: () async {
                            await _dbService?.deleteGuardian(g.id);
                          },
                        ),
                      )),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAddGuardianDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final relationCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Guardian'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDialogField(nameCtrl, 'Name', Icons.person),
              const SizedBox(height: 12),
              _buildDialogField(phoneCtrl, 'Phone', Icons.phone,
                  keyboard: TextInputType.phone),
              const SizedBox(height: 12),
              _buildDialogField(relationCtrl, 'Relationship', Icons.favorite),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () async {
                  final status = await FlutterContacts.permissions.request(PermissionType.read);
                  if (status == PermissionStatus.granted) {
                    final contact = await FlutterContacts.native.showPicker(properties: {ContactProperty.phone});
                    if (contact != null) {
                      nameCtrl.text = contact.displayName ?? '';
                      if (contact.phones.isNotEmpty) {
                        phoneCtrl.text = contact.phones.first.number;
                      }
                    }
                  }
                },
                icon: const Icon(Icons.contacts, color: Color(0xFF4CAF50)),
                label: const Text('Pick from Contacts', style: TextStyle(color: Color(0xFF4CAF50))),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty && _dbService != null) {
                await _dbService!.addGuardian(GuardianModel(
                  id: '',
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  relationship: relationCtrl.text.trim().isEmpty
                      ? 'Contact'
                      : relationCtrl.text.trim(),
                ));
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child:
                const Text('Add', style: TextStyle(color: Color(0xFF4CAF50))),
          ),
        ],
      ),
    );
  }

  // ── Device Management Sheet ──
  void _showDevicesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2C2C2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StreamBuilder<List<DeviceModel>>(
        stream: _dbService?.devices,
        builder: (context, snapshot) {
          final devices = snapshot.data ?? [];
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Connected Devices',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    IconButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showAddDeviceDialog();
                      },
                      icon: const Icon(Icons.add_circle_outline,
                          color: Color(0xFFFF9800)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('No devices paired yet',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  ...devices.map((d) => ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFFF9800),
                          child: Icon(
                            d.type == 'Smart Watch'
                                ? Icons.watch
                                : d.type == 'Fitness Tracker'
                                    ? Icons.fitness_center
                                    : Icons.bluetooth,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        title: Text(d.name,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(d.type,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent, size: 20),
                          onPressed: () async {
                            await _dbService?.deleteDevice(d.id);
                          },
                        ),
                      )),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAddDeviceDialog() {
    final nameCtrl = TextEditingController();
    String selectedType = 'Smart Watch';
    final types = [
      'Smart Watch',
      'Fitness Tracker',
      'Bluetooth Tag',
      'Smartphone',
      'Other'
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2C2C2C),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title:
              const Text('Add Device', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogField(
                    nameCtrl, 'Device Name', Icons.devices_rounded),
                const SizedBox(height: AppConstants.spacing12),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  dropdownColor: AppColors.surfaceLight,
                  style: AppTextStyles.bodyMedium,
                  decoration: const InputDecoration(
                    labelText: 'Device Type',
                    prefixIcon:
                        Icon(Icons.category_rounded, color: AppColors.textHint),
                  ),
                  items: types
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => selectedType = val ?? selectedType),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (nameCtrl.text.isNotEmpty && _dbService != null) {
                  await _dbService!.addDevice(DeviceModel(
                    id: '',
                    name: nameCtrl.text.trim(),
                    type: selectedType,
                    isConnected: true,
                  ));
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogField(
      TextEditingController ctrl, String label, IconData icon,
      {TextInputType keyboard = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
    );
  }

  // ── Build ──
  @override
  Widget build(BuildContext context) {
    final userName = _userData?.name.isNotEmpty == true
        ? _userData!.name
        : widget.initialName.isNotEmpty
            ? widget.initialName
            : 'User';

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Column(
        children: [
          _buildGradientHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  _buildProfileCard(userName),
                  const SizedBox(height: 24),

                  // ── Account Settings (Expandable) ──
                  _buildExpandableAccountSettings(),
                  const SizedBox(height: 24),

                  // ── Preferences ──
                  _buildSectionLabel('Preferences'),
                  const SizedBox(height: 10),
                  ProfileMenuTile(
                    icon: Icons.notifications_outlined,
                    iconColor: const Color(0xFFFFB74D),
                    title: 'Emergency Alerts',
                    subtitle: 'View alert history',
                    onTap: () => context.push(AppRoutes.alertHistory),
                  ),
                  const SizedBox(height: 8),
                  ProfileMenuTile(
                    icon: Icons.shield_outlined,
                    iconColor: const Color(0xFFFF5252),
                    title: 'Privacy & Security',
                    subtitle: 'Terms and conditions',
                    onTap: () => context.push(AppRoutes.terms),
                  ),
                  const SizedBox(height: 8),
                  ProfileMenuTile(
                    icon: Icons.help_outline,
                    iconColor: const Color(0xFF90CAF9),
                    title: 'Help & Support',
                    onTap: _showHelpDialog,
                  ),
                  const SizedBox(height: 24),

                  SignOutRow(
                    onSignOut: _signOut,
                    onQuickSOS: _startQuickSOS,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Expandable Account Settings ──
  Widget _buildExpandableAccountSettings() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          // Header (tap to expand/collapse)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _accountExpanded = !_accountExpanded),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5252).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.settings,
                          color: Color(0xFFFF5252), size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Account Settings',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 15)),
                          Text('Manage profile, guardians & devices',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _accountExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.expand_more,
                          color: Colors.grey, size: 24),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Expandable items
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                const Divider(
                    color: Color(0xFF3D3D3D),
                    height: 1,
                    indent: 14,
                    endIndent: 14),
                _buildDropdownItem(
                  Icons.person_outline,
                  const Color(0xFFFF5252),
                  'Personal Information',
                  'Edit name, phone, medical info',
                  _openPersonalInfo,
                ),
                const Divider(
                    color: Color(0xFF3D3D3D),
                    height: 1,
                    indent: 56,
                    endIndent: 14),
                _buildDropdownItem(
                  Icons.people_outline,
                  const Color(0xFF4CAF50),
                  'Trusted Guardians',
                  '$_guardianCount contacts notified',
                  _showGuardiansSheet,
                ),
                const Divider(
                    color: Color(0xFF3D3D3D),
                    height: 1,
                    indent: 56,
                    endIndent: 14),
                _buildDropdownItem(
                  Icons.devices_other,
                  const Color(0xFFFF9800),
                  'Connected Devices',
                  '$_deviceCount paired',
                  _showDevicesSheet,
                ),
              ],
            ),
            crossFadeState: _accountExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownItem(IconData icon, Color color, String title,
      String subtitle, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                    Text(subtitle,
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ── Gradient Header ──
  Widget _buildGradientHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        bottom: 28,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF5252), Color(0xFFE53935), Color(0xFF1E1E1E)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => context.pop(),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 12),
          const Text(
            'SafeNetic',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your Personal Safety Net',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ── Profile Card ──
  Widget _buildProfileCard(String userName) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF3D3D3D),
                child: Text(
                  _getInitials(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(userName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            color: Color(0xFFFF5252), size: 14),
                        const SizedBox(width: 4),
                        Text(_locationText,
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_note, color: Colors.grey),
                onPressed: _openPersonalInfo,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF3D3D3D), height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatItem('$_guardianCount', 'Guardians'),
              _buildStatDivider(),
              _buildStatItem('Active', 'Status'),
              _buildStatDivider(),
              _buildStatItem('$_deviceCount', 'Devices'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 30, color: const Color(0xFF3D3D3D));
  }

  Widget _buildSectionLabel(String text) {
    return Text(text,
        style: TextStyle(
            color: Colors.grey[500],
            fontSize: 13,
            fontWeight: FontWeight.w500));
  }
}
