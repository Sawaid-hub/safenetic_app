import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:safenetic_app/constants/app_colors.dart';
import 'package:safenetic_app/constants/app_constants.dart';
import 'package:safenetic_app/constants/app_text_styles.dart';
import 'package:safenetic_app/services/guardian_fcm_service.dart';
import 'package:safenetic_app/services/guardian_invite_service.dart';

/// Screen where a guardian can link their device to a protected user,
/// or a user can share their ID so guardians can register.
class GuardianLinkScreen extends StatefulWidget {
  const GuardianLinkScreen({super.key});

  @override
  State<GuardianLinkScreen> createState() => _GuardianLinkScreenState();
}

class _GuardianLinkScreenState extends State<GuardianLinkScreen>
    with TickerProviderStateMixin {
  final _codeController = TextEditingController();
  late AnimationController _staggerController;

  bool _isLinking = false;
  String? _statusMessage;
  bool _isSuccess = false;
  bool _isCreatingInvite = false;

  // Current user's own ID is only used to read their guardian count.
  String? _myUserId;
  String? _inviteCode;
  int _linkedGuardianCount = 0;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _myUserId = FirebaseAuth.instance.currentUser?.uid;
    _loadGuardianCount();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _staggerController.forward();
    });
  }

  Future<void> _loadGuardianCount() async {
    if (_myUserId == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_myUserId)
          .collection('guardian_tokens')
          .get();
      if (mounted) setState(() => _linkedGuardianCount = snap.docs.length);
    } catch (_) {}
  }

  @override
  void dispose() {
    _codeController.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  Future<void> _linkAsGuardian() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _statusMessage = 'Enter the invitation code shared by the person you protect.';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isLinking = true;
      _statusMessage = null;
    });

    try {
      // The server consumes the expiring, single-use invite and registers this
      // device. Raw user IDs cannot authorize a guardian relationship.
      await GuardianFcmService.instance.registerAsGuardian(code);

      setState(() {
        _statusMessage = 'Linked successfully. You will receive SOS alerts.';
        _isSuccess = true;
        _isLinking = false;
      });

      HapticFeedback.mediumImpact();
    } catch (_) {
      setState(() {
        _statusMessage = 'Could not use that invite. It may be expired or already used.';
        _isSuccess = false;
        _isLinking = false;
      });
    }
  }

  Future<void> _createInvite() async {
    if (_isCreatingInvite || _myUserId == null) return;
    setState(() {
      _isCreatingInvite = true;
      _statusMessage = null;
    });
    try {
      final data = await GuardianInviteService.instance.createInvite();
      if (!mounted) return;
      setState(() {
        _inviteCode = data['inviteCode'] as String?;
        _statusMessage = 'Invite created. Share the code with your guardian; it expires in 24 hours.';
        _isSuccess = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Could not create an invite right now. Please try again.';
        _isSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _isCreatingInvite = false);
    }
  }

  void _copyInviteCode() {
    final inviteCode = _inviteCode;
    if (inviteCode == null) return;
    Clipboard.setData(ClipboardData(text: inviteCode));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Guardian invite copied'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
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
                title: const Text('Guardian Link', style: AppTextStyles.h2),
                centerTitle: true,
                leading: _glassIconButton(
                  icon: Icons.arrow_back_rounded,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          physics: const BouncingScrollPhysics(),
          children: [
            const SizedBox(height: kToolbarHeight + 60),

            // Section 1: Share an owner-approved invite
            _animatedSection(0, _label('GUARDIAN INVITE')),
            _animatedSection(1, _shareIdCard()),
            const SizedBox(height: 28),

            // Section 2: Link as guardian
            _animatedSection(2, _label('LINK AS GUARDIAN')),
            _animatedSection(3, _linkCard()),
            const SizedBox(height: 28),

            // Section 3: How it works
            _animatedSection(4, _label('HOW IT WORKS')),
            _animatedSection(5, _howItWorksCard()),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARE MY ID CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _shareIdCard() {
    return _glassCard([
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _glowingIcon(Icons.shield_rounded, color: AppColors.info),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Invite a guardian',
                          style: AppTextStyles.bodyLarge),
                      SizedBox(height: 2),
                      Text(
                        'Create a one-time code for the person who should receive your SOS alerts',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Invitation code + create/copy button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusMedium),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.vpn_key_rounded,
                      color: AppColors.textHint, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _inviteCode ?? 'Create a secure invite code',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _glassPill(
                    label: _inviteCode == null ? 'Create' : 'Copy',
                    icon: _inviteCode == null
                        ? Icons.add_link_rounded
                        : Icons.copy_rounded,
                    color: AppColors.info,
                    onTap: _inviteCode == null ? _createInvite : _copyInviteCode,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Linked guardian count
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.success.withAlpha(15),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusSmall),
                border: Border.all(color: AppColors.success.withAlpha(40)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people_rounded,
                      color: AppColors.success, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '$_linkedGuardianCount guardian(s) linked to your account',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LINK AS GUARDIAN CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _linkCard() {
    return _glassCard([
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _glowingIcon(Icons.link_rounded, color: AppColors.warning),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Become a guardian', style: AppTextStyles.bodyLarge),
                      SizedBox(height: 2),
                      Text(
                        'Enter the one-time invitation code they shared with you',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Input field
            TextField(
              controller: _codeController,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Paste invitation code here...',
                hintStyle: const TextStyle(
                    color: AppColors.textHint, fontSize: 13),
                prefixIcon: const Icon(Icons.person_search_rounded,
                    color: AppColors.textHint, size: 20),
                filled: true,
                fillColor: AppColors.surfaceElevated,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMedium),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMedium),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMedium),
                  borderSide:
                      const BorderSide(color: AppColors.warning, width: 1.5),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 14),

            // Link button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLinking ? null : _linkAsGuardian,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  disabledBackgroundColor: AppColors.warning.withAlpha(80),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMedium),
                  ),
                  elevation: 0,
                ),
                child: _isLinking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.link_rounded,
                              color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Link as Guardian',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            // Status message
            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _isSuccess
                      ? AppColors.success.withAlpha(15)
                      : AppColors.error.withAlpha(15),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusSmall),
                  border: Border.all(
                    color: _isSuccess
                        ? AppColors.success.withAlpha(40)
                        : AppColors.error.withAlpha(40),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isSuccess
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      color:
                          _isSuccess ? AppColors.success : AppColors.error,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          color: _isSuccess
                              ? AppColors.success
                              : AppColors.error,
                          fontSize: 12,
                        ),
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
  // HOW IT WORKS CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _howItWorksCard() {
    return _glassCard([
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _stepRow(
              '1',
              'Create an invitation',
              'Generate a one-time code and share it with the person you trust.',
              Icons.share_rounded,
              AppColors.info,
            ),
            const SizedBox(height: 14),
            _stepRow(
              '2',
              'Guardian accepts it',
              'They enter the code in the "Link as Guardian" section. The code expires after 24 hours and can be used once.',
              Icons.link_rounded,
              AppColors.warning,
            ),
            const SizedBox(height: 14),
            _stepRow(
              '3',
              'SOS alerts arrive instantly',
              'When an SOS is triggered (manual or automatic), a high-priority notification pops up on the guardian\'s phone — even if the app is closed.',
              Icons.notifications_active_rounded,
              AppColors.primary,
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _stepRow(String number, String title, String desc, IconData icon,
      Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withAlpha(25),
            border: Border.all(color: color.withAlpha(60)),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.bodyLarge),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GLASSMORPHISM COMPONENTS (matches settings_screen.dart style)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _animatedSection(int index, Widget child) {
    final start = (index * 0.08).clamp(0.0, 0.7);
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
        border: Border.all(color: Colors.white.withAlpha(20), width: 1),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

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

  Widget _glassPill({
    required String label,
    IconData? icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                const SizedBox(width: 4),
              ],
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
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
}
