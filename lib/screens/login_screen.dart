
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:safenetic_app/constants/app_colors.dart';
import 'package:safenetic_app/constants/app_constants.dart';
import 'package:safenetic_app/constants/app_text_styles.dart';
import 'package:safenetic_app/constants/app_routes.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = false;
  
  final _storage = const FlutterSecureStorage();

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
      _clearLegacyPassword();
    });
  }

  Future<void> _clearLegacyPassword() async {
    await _storage.delete(key: 'user_password');
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      await _storage.delete(key: 'user_password');
      if (_rememberMe) {
        await _storage.write(
          key: 'user_email',
          value: _emailController.text.trim(),
        );
      } else {
        await _storage.delete(key: 'user_email');
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg = 'Login failed';
      if (e.code == 'user-not-found') msg = 'No user found for that email.';
      if (e.code == 'wrong-password') msg = 'Wrong password provided.';
      if (e.code == 'invalid-credential') msg = 'Invalid email or password.';
      _showError(msg);
    } catch (e) {
      if (!mounted) return;
      _showError('Login failed. Please check your connection and try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
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
  }

  Widget _staggered(int index, Widget child) {
    final start = (index * 0.08).clamp(0.0, 0.6);
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
                    const SizedBox(height: 60),

                    // Logo with pulse glow
                    _staggered(0, _buildLogo()),
                    const SizedBox(height: 44),

                    // Title
                    _staggered(1, const Text(
                      'Welcome Back',
                      style: AppTextStyles.h1,
                      textAlign: TextAlign.center,
                    )),
                    const SizedBox(height: 8),
                    _staggered(2, Text(
                      'Sign in to continue your safety journey',
                      style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    )),
                    const SizedBox(height: 40),

                    // Glass form card
                    _staggered(3, _buildFormCard()),
                    const SizedBox(height: 28),

                    // Login Button
                    _staggered(4, _buildLoginButton()),
                    const SizedBox(height: 12),
                    
                    const SizedBox(height: 16),

                    // Divider
                    _staggered(5, _buildDivider()),
                    const SizedBox(height: 28),

                    // Sign Up Link
                    _staggered(6, Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Don't have an account?",
                          style: AppTextStyles.bodyMedium,
                        ),
                        TextButton(
                          onPressed: () => context.push(AppRoutes.register),
                          child: const Text(
                            'Sign Up',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    )),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Center(
      child: Container(
        width: 94,
        height: 94,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.emergencyGradient,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withAlpha(70),
              blurRadius: 32,
              spreadRadius: 6,
            ),
          ],
        ),
        child: const Icon(
          Icons.shield_outlined,
          size: 44,
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
              // Email
              _buildGlassField(
                controller: _emailController,
                label: 'Email',
                hint: 'you@example.com',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter your email';
                  if (!v.contains('@')) return 'Invalid email address';
                  return null;
                },
              ),
              const SizedBox(height: 18),

              // Password
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
                  if (v == null || v.isEmpty) return 'Enter your password';
                  if (v.length < 6) return 'At least 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Remember / Forgot
              Row(
                children: [
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: Checkbox(
                      value: _rememberMe,
                      activeColor: AppColors.primary,
                      checkColor: Colors.white,
                      side: const BorderSide(color: AppColors.textHint),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      onChanged: (v) =>
                          setState(() => _rememberMe = v ?? false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('Remember me',
                      style: AppTextStyles.bodyMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () {},
                    child: Text('Forgot?',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.primary)),
                  ),
                ],
              ),
            ],
          ),
    );
  }

  Widget _buildLoginButton() {
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
            _login();
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
                    'LOGIN',
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

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Container(height: 0.5,
            color: Colors.white.withAlpha(15))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('or',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textHint)),
        ),
        Expanded(child: Container(height: 0.5,
            color: Colors.white.withAlpha(15))),
      ],
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
