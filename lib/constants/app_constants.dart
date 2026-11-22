/// SafeNetic Design System — Spacing, sizing, and animation constants.
class AppConstants {
  AppConstants._();

  // ── App ──
  static const String appName = 'SafeNetic';

  // ── Spacing (8px grid) ──
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing48 = 48.0;

  // ── Border Radius ──
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 24.0;
  static const double radiusCircular = 100.0;

  // ── Touch Targets (Material Design 3 — 48dp minimum) ──
  static const double touchTarget = 48.0;
  static const double buttonHeight = 52.0;
  static const double iconButtonSize = 48.0;

  // ── Elevation ──
  static const double elevationNone = 0.0;
  static const double elevationLow = 2.0;
  static const double elevationMedium = 4.0;
  static const double elevationHigh = 8.0;

  // ── Animation ──
  static const Duration animFast = Duration(milliseconds: 200);
  static const Duration animMedium = Duration(milliseconds: 350);
  static const Duration animSlow = Duration(milliseconds: 500);
  static const Duration animPulse = Duration(milliseconds: 1500);

  // ── Security ──
  static const int minPasswordLength = 6;

  // ── SOS ──
  static const double defaultSosDelay = 10.0;
  static const double sosButtonSize = 140.0;
  static const double sosButtonPulseRadius = 180.0;
}
