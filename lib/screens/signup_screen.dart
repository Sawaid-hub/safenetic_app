
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safenetic_app/constants/app_colors.dart';
import 'package:safenetic_app/constants/app_constants.dart';
import 'package:safenetic_app/constants/app_text_styles.dart';
import 'package:safenetic_app/models/user_model.dart';
import 'package:safenetic_app/services/database_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  late AnimationController _staggerController;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _staggerController.forward();
    });
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = cred.user;
      if (user != null) {
        await user.updateDisplayName(_nameController.text.trim());

        final profile = UserModel(
          uid: user.uid,
          email: _emailController.text.trim(),
          name: _nameController.text.trim(),
          phone: '',
          sosDelay: AppConstants.defaultSosDelay,
          biometricEnabled: true,
          notificationsEnabled: true,
        );
        await DatabaseService(uid: user.uid).updateUserData(profile);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Account created successfully!'),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          ),
          margin: const EdgeInsets.all(AppConstants.spacing16),
        ),
      );

      if (context.mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(e.toString())),
            ],
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          ),
          margin: const EdgeInsets.all(AppConstants.spacing16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _staggered(int index, Widget child) {
    final start = (index * 0.07).clamp(0.0, 0.55);
    final end = (start + 0.4).clamp(0.0, 1.0);
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.15),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      )),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
          parent: _staggerController,
          curve: Interval(start, end, curve: Curves.easeOut),
        )),
        child: child,
      ),
    );
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              physics: const BouncingScrollPhysics(),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),

                    // Back Button
                    _staggered(0, Align(
                      alignment: Alignment.centerLeft,
                      child: _glassBackButton(),
                    )),
                    const SizedBox(height: 24),

                    // Logo
                    _staggered(1, _buildLogo()),
                    const SizedBox(height: 28),

                    // Title
                    _staggered(2, const Text(
                      'Create Account',
                      style: AppTextStyles.h1,
                      textAlign: TextAlign.center,
                    )),
                    const SizedBox(height: 8),
                    _staggered(3, Text(
                      'Join SafeNetic to stay protected',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    )),
                    const SizedBox(height: 32),

                    // Glass form card
                    _staggered(4, _buildFormCard()),
                    const SizedBox(height: 28),

                    // Sign Up Button
                    _staggered(5, _buildSignUpButton()),
                    const SizedBox(height: 20),

                    // Login Link
                    _staggered(6, Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Already have an account?',
                          style: AppTextStyles.bodyMedium,
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'Login',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    )),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _glassBackButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.pop(context);
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(10),
            borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
            border: Border.all(color: Colors.white.withAlpha(15)),
          ),
          child: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary, size: 20),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Center(
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.emergencyGradient,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withAlpha(60),
              blurRadius: 28,
              spreadRadius: 5,
            ),
          ],
        ),
        child: const Icon(
          Icons.person_add_rounded,
          size: 38,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withAlpha(15),
            Colors.white.withAlpha(6),
          ],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXLarge),
        border: Border.all(color: Colors.white.withAlpha(18), width: 1),
      ),
      child: Column(
            children: [
              _buildGlassField(
                controller: _nameController,
                label: 'Full Name',
                hint: 'John Doe',
                icon: Icons.person_outline_rounded,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter your name';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildGlassField(
                controller: _emailController,
                label: 'Email',
                hint: 'you@example.com',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter your email';
                  if (!v.contains('@')) return 'Invalid email';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildGlassField(
                controller: _passwordController,
                label: 'Password',
                hint: '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: AppColors.textHint,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter a password';
                  if (v.length < 6) return 'At least 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildGlassField(
                controller: _confirmPasswordController,
                label: 'Confirm Password',
                hint: '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscureConfirmPassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: AppColors.textHint,
                    size: 20,
                  ),
                  onPressed: () => setState(() =>
                      _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Confirm password';
                  if (v != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
            ],
          ),
    );
  }

  Widget _buildSignUpButton() {
    return AnimatedContainer(
      duration: AppConstants.animFast,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
        gradient: AppColors.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(_isLoading ? 0 : 60),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
          onTap: _isLoading ? null : () {
            HapticFeedback.mediumImpact();
            _signUp();
          },
          child: Container(
            height: 56,
            alignment: Alignment.center,
            child: _isLoading
                ? const SizedBox(
                    height: 22, width: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                  )
                : const Text(
                    'CREATE ACCOUNT',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Container(
          margin: const EdgeInsets.all(8),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withAlpha(15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withAlpha(30)),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withAlpha(6),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          borderSide: BorderSide(color: Colors.white.withAlpha(12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          borderSide: BorderSide(color: AppColors.primary.withAlpha(80)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          borderSide: BorderSide(color: AppColors.error.withAlpha(80)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
    );
  }
}
