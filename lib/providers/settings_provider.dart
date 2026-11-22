import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  // Emergency Settings
  bool _emergencyNotifications = true;
  bool _emergencySound = true;
  bool _emergencyVibration = true;
  bool _autoSendLocation = true;
  int _emergencyCountdownDuration = 5; // seconds
  bool _sendSMSAlerts = true;
  bool _sendEmailAlerts = false;

  // Notification Settings
  bool _pushNotifications = true;
  bool _locationUpdates = true;
  bool _safetyReminders = true;

  // Privacy & Security
  bool _biometricAuth = false;
  bool _locationTracking = true;
  bool _shareLocationWithContacts = true;

  // Detection Settings
  bool _noiseDetectionEnabled = true;

  // General Settings
  String _language = 'en';
  bool _analyticsEnabled = true;
  bool _crashReporting = true;

  SettingsProvider() {
    _loadSettings();
  }

  // Getters
  bool get emergencyNotifications => _emergencyNotifications;
  bool get emergencySound => _emergencySound;
  bool get emergencyVibration => _emergencyVibration;
  bool get autoSendLocation => _autoSendLocation;
  int get emergencyCountdownDuration => _emergencyCountdownDuration;
  bool get sendSMSAlerts => _sendSMSAlerts;
  bool get sendEmailAlerts => _sendEmailAlerts;

  bool get pushNotifications => _pushNotifications;
  bool get locationUpdates => _locationUpdates;
  bool get safetyReminders => _safetyReminders;

  bool get biometricAuth => _biometricAuth;
  bool get locationTracking => _locationTracking;
  bool get shareLocationWithContacts => _shareLocationWithContacts;

  bool get noiseDetectionEnabled => _noiseDetectionEnabled;

  String get language => _language;
  bool get analyticsEnabled => _analyticsEnabled;
  bool get crashReporting => _crashReporting;

  // Load settings from SharedPreferences
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    _emergencyNotifications = prefs.getBool('emergency_notifications') ?? true;
    _emergencySound = prefs.getBool('emergency_sound') ?? true;
    _emergencyVibration = prefs.getBool('emergency_vibration') ?? true;
    _autoSendLocation = prefs.getBool('auto_send_location') ?? true;
    _emergencyCountdownDuration =
        prefs.getInt('emergency_countdown_duration') ?? 5;
    _sendSMSAlerts = prefs.getBool('send_sms_alerts') ?? true;
    _sendEmailAlerts = prefs.getBool('send_email_alerts') ?? false;

    _pushNotifications = prefs.getBool('push_notifications') ?? true;
    _locationUpdates = prefs.getBool('location_updates') ?? true;
    _safetyReminders = prefs.getBool('safety_reminders') ?? true;

    _biometricAuth = prefs.getBool('biometric_auth') ?? false;
    _locationTracking = prefs.getBool('location_tracking') ?? true;
    _shareLocationWithContacts =
        prefs.getBool('share_location_contacts') ?? true;

    _noiseDetectionEnabled = prefs.getBool('noise_detection_enabled') ?? true;

    _language = prefs.getString('language') ?? 'en';
    _analyticsEnabled = prefs.getBool('analytics_enabled') ?? true;
    _crashReporting = prefs.getBool('crash_reporting') ?? true;

    notifyListeners();
  }

  // Generic setting saver
  Future<void> _saveSetting<T>(
      String key, T value, void Function() updateField) async {
    updateField();
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
    notifyListeners();
  }

  // Emergency Settings
  Future<void> setEmergencyNotifications(bool value) => _saveSetting(
      'emergency_notifications', value, () => _emergencyNotifications = value);
  Future<void> setEmergencySound(bool value) =>
      _saveSetting('emergency_sound', value, () => _emergencySound = value);
  Future<void> setEmergencyVibration(bool value) => _saveSetting(
      'emergency_vibration', value, () => _emergencyVibration = value);
  Future<void> setAutoSendLocation(bool value) => _saveSetting(
      'auto_send_location', value, () => _autoSendLocation = value);
  Future<void> setEmergencyCountdownDuration(int value) => _saveSetting(
      'emergency_countdown_duration',
      value,
      () => _emergencyCountdownDuration = value);
  Future<void> setSendSMSAlerts(bool value) =>
      _saveSetting('send_sms_alerts', value, () => _sendSMSAlerts = value);
  Future<void> setSendEmailAlerts(bool value) =>
      _saveSetting('send_email_alerts', value, () => _sendEmailAlerts = value);

  // Notification Settings
  Future<void> setPushNotifications(bool value) => _saveSetting(
      'push_notifications', value, () => _pushNotifications = value);
  Future<void> setLocationUpdates(bool value) =>
      _saveSetting('location_updates', value, () => _locationUpdates = value);
  Future<void> setSafetyReminders(bool value) =>
      _saveSetting('safety_reminders', value, () => _safetyReminders = value);

  // Privacy & Security
  Future<void> setBiometricAuth(bool value) =>
      _saveSetting('biometric_auth', value, () => _biometricAuth = value);
  Future<void> setLocationTracking(bool value) =>
      _saveSetting('location_tracking', value, () => _locationTracking = value);
  Future<void> setShareLocationWithContacts(bool value) => _saveSetting(
      'share_location_contacts',
      value,
      () => _shareLocationWithContacts = value);

  // Detection
  Future<void> setNoiseDetectionEnabled(bool value) => _saveSetting(
      'noise_detection_enabled', value, () => _noiseDetectionEnabled = value);

  // General Settings
  Future<void> setLanguage(String value) =>
      _saveSetting('language', value, () => _language = value);
  Future<void> setAnalyticsEnabled(bool value) =>
      _saveSetting('analytics_enabled', value, () => _analyticsEnabled = value);
  Future<void> setCrashReporting(bool value) =>
      _saveSetting('crash_reporting', value, () => _crashReporting = value);

  // Reset all settings to defaults
  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _loadSettings();
  }
}
