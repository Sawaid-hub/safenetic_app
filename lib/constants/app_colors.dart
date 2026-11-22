import 'package:flutter/material.dart';

/// SafeNetic Design System — Centralized color palette.
///
/// Primary: Emergency Red (#FF5252)
/// Surface: Dark grays for OLED-friendly dark mode
/// Accent: Teal for success/safe states
class AppColors {
  AppColors._();

  // ── Primary ──
  static const Color primary = Color(0xFFFF5252);
  static const Color primaryLight = Color(0xFFFF8A80);
  static const Color primaryDark = Color(0xFFD32F2F);

  // ── Surface & Background ──
  static const Color surface = Color(0xFF1E1E1E);
  static const Color surfaceLight = Color(0xFF2C2C2C);
  static const Color surfaceElevated = Color(0xFF353535);
  static const Color background = Color(0xFF121212);
  static const Color scaffoldDark = Color(0xFF0F0F0F);

  // ── Accents ──
  static const Color accent = Color(0xFF26A69A); // Teal — safe/success
  static const Color accentLight = Color(0xFF80CBC4);
  static const Color warning = Color(0xFFFFB74D); // Amber
  static const Color info = Color(0xFF42A5F5); // Blue

  // ── Text ──
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color textHint = Color(0xFF757575);
  static const Color textOnPrimary = Colors.white;

  // ── Borders & Dividers ──
  static const Color border = Color(0xFF3A3A3A);
  static const Color divider = Color(0xFF2A2A2A);

  // ── States ──
  static const Color success = Color(0xFF66BB6A);
  static const Color error = Color(0xFFEF5350);
  static const Color disabled = Color(0xFF616161);

  // ── Gradients ──
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [surfaceLight, surface],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient emergencyGradient = LinearGradient(
    colors: [Color(0xFFFF5252), Color(0xFFFF1744)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
