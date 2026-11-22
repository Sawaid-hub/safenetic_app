import 'package:background_sms/background_sms.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:safenetic_app/models/alert_model.dart';
import 'package:safenetic_app/models/guardian_model.dart';
import 'package:safenetic_app/services/sos_event_service.dart';

/// Channel-by-channel result shown by the alert screen and stored in history.
class EmergencyAlertResult {
  const EmergencyAlertResult({
    required this.smsStatuses,
    required this.pushDelivery,
  });

  final Map<String, String> smsStatuses;
  final SosDeliveryResult pushDelivery;

  int get confirmedSmsCount =>
      smsStatuses.values.where((status) => status == 'sent').length;

  String get historyStatus {
    if (pushDelivery.hasConfirmedDelivery || confirmedSmsCount > 0) {
      return 'sent';
    }
    if (pushDelivery.isPending ||
        pushDelivery.status == 'unknown' ||
        smsStatuses.values.any((status) => status == 'intent_fallback')) {
      return 'pending';
    }
    return 'failed';
  }

  String get deliverySummary {
    final smsSuffix = confirmedSmsCount > 0
        ? ' SMS sent to $confirmedSmsCount guardian${confirmedSmsCount == 1 ? '' : 's'}.'
        : '';
    final isFallback = pushDelivery.provider == 'alerts_backend';
    final providerLabel = isFallback ? 'Backup push' : 'Primary push';

    switch (pushDelivery.status) {
      case 'delivered':
        return '$providerLabel accepted for ${pushDelivery.successCount} guardian '
            'device${pushDelivery.successCount == 1 ? '' : 's'}'
            '.$smsSuffix';
      case 'partial':
        return '$providerLabel accepted for ${pushDelivery.successCount} of '
            '${pushDelivery.totalCount} guardian devices.$smsSuffix';
      case 'no_guardians':
        return 'No linked guardian devices for push.$smsSuffix';
      case 'pending':
      case 'processing':
        return '$providerLabel confirmation is still pending.$smsSuffix';
      case 'unknown':
        return isFallback
            ? 'Backup push outcome could not be confirmed; no retry was sent '
                'to avoid duplicates.$smsSuffix'
            : 'Primary push outcome could not be confirmed; backup was not '
                'used to avoid duplicates.$smsSuffix';
      default:
        return '$providerLabel delivery failed.$smsSuffix';
    }
  }
}

/// Service for sending emergency notifications to guardians.
///
/// Sends SMS silently via Android's native SmsManager (cellular network)
/// and logs alerts to Firestore.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  late final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Send emergency alerts to all guardians.
  ///
  /// Returns the SMS result per guardian and the server-confirmed push result.
  Future<EmergencyAlertResult> sendEmergencyAlerts({
    required List<GuardianModel> guardians,
    required LocationData? locationData,
    required String userName,
    String alertType = 'manual',
  }) async {
    final results = <String, String>{};

    // Build the SMS message
    final message = buildEmergencyMessage(
      userName: userName,
      latitude: locationData?.latitude,
      longitude: locationData?.longitude,
      alertType: alertType,
    );

    // Check if we have silent SMS permission
    final hasPermission = await _ensureSmsPermission();

    if (hasPermission) {
      // Send SMS silently to each guardian via cellular network
      for (final guardian in guardians) {
        if (guardian.phone.isEmpty) {
          results[guardian.name] = 'no_phone';
          continue;
        }

        try {
          final phone = _formatPhoneNumber(guardian.phone);
          final result = await BackgroundSms.sendMessage(
            phoneNumber: phone,
            message: message,
          );

          if (result == SmsStatus.sent) {
            results[guardian.name] = 'sent';
            if (kDebugMode) print('SMS sent to a guardian');
          } else {
            results[guardian.name] = 'failed';
            if (kDebugMode) {
              print('SMS delivery failed: $result');
            }
          }
        } catch (_) {
          if (kDebugMode) print('SMS send error');
          results[guardian.name] = 'failed';
        }
      }
    } else {
      // SMS permission denied (e.g. Android 17 hard-restricted).
      // Fall back to opening the system SMS app with pre-filled message.
      if (kDebugMode) {
        print('SMS permission denied — falling back to SMS intent');
      }

      for (final guardian in guardians) {
        if (guardian.phone.isEmpty) {
          results[guardian.name] = 'no_phone';
          continue;
        }

        try {
          final phone = _formatPhoneNumber(guardian.phone);
          final launched = await _sendViaIntent(phone, message);
          results[guardian.name] =
              launched ? 'intent_fallback' : 'no_permission';
        } catch (e) {
          if (kDebugMode)
            print('Intent fallback error for ${guardian.name}: $e');
          results[guardian.name] = 'no_permission';
        }
      }
    }

    // Write the history entry before waiting for push delivery so the event is
    // still logged if the app closes or the server receipt is delayed.
    final alertLogRef = await _logAlertToFirestore(
      guardians: guardians,
      locationData: locationData,
      alertType: alertType,
      results: results,
    );

    final pushDelivery = await SosEventService.instance.triggerSos(
      userName: userName,
      locationData: locationData,
      generatedAutomatically: alertType != 'manual',
      alertType: alertType,
    );

    final alertResult = EmergencyAlertResult(
      smsStatuses: Map.unmodifiable(results),
      pushDelivery: pushDelivery,
    );
    await _updateAlertLog(alertLogRef, alertResult);
    return alertResult;
  }

  /// Request SEND_SMS permission at runtime.
  Future<bool> _ensureSmsPermission() async {
    var status = await Permission.sms.status;
    if (status.isGranted) return true;

    // On Android 17+, the permission may be permanently denied / restricted.
    // Don't prompt again if it's permanently denied — go straight to fallback.
    if (status.isPermanentlyDenied || status.isRestricted) {
      if (kDebugMode) print('SMS permission restricted/permanently denied');
      return false;
    }

    status = await Permission.sms.request();
    if (status.isGranted) return true;

    if (kDebugMode) print('SMS permission denied: $status');
    return false;
  }

  /// Open the system SMS app with a pre-filled message as fallback.
  ///
  /// Uses the 'smsto:' scheme with ACTION_SENDTO which is the standard
  /// Android way to open the SMS app with a pre-filled recipient and body.
  /// Returns true if the SMS app was launched successfully.
  Future<bool> _sendViaIntent(String phoneNumber, String message) async {
    try {
      final encodedMessage = Uri.encodeComponent(message);
      final smsUri = Uri.parse('smsto:$phoneNumber?body=$encodedMessage');
      await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      return true;
    } catch (e) {
      if (kDebugMode) print('Could not launch the SMS app');
      return false;
    }
  }

  /// Format phone number for SMS delivery.
  ///
  /// Cleans the number and adds Pakistan country code (+92) as default
  /// if no country code is present.
  String _formatPhoneNumber(String rawPhone) {
    String phone = rawPhone.replaceAll(RegExp(r'[^\d+]'), '');

    // Convert 00 prefix to +
    if (phone.startsWith('00')) {
      phone = '+${phone.substring(2)}';
    }

    // Add Pakistan country code if missing
    if (!phone.startsWith('+')) {
      if (phone.startsWith('0')) {
        phone = '+92${phone.substring(1)}';
      } else if (phone.startsWith('92') && phone.length == 12) {
        phone = '+$phone';
      } else {
        phone = '+92$phone';
      }
    }

    return phone;
  }

  /// Build the emergency SMS message with location link.
  @visibleForTesting
  String buildEmergencyMessage({
    required String userName,
    double? latitude,
    double? longitude,
    required String alertType,
  }) {
    final trigger = alertType == 'fall' ? 'FALL DETECTED' : 'SOS ACTIVATED';
    final buffer = StringBuffer();

    buffer.writeln('🚨 SAFENETIC EMERGENCY ALERT 🚨');
    buffer.writeln();
    buffer.writeln('$trigger for $userName');
    buffer.writeln();

    if (latitude != null && longitude != null) {
      buffer.writeln('📍 Location:');
      buffer.writeln('https://maps.google.com/?q=$latitude,$longitude');
    } else {
      buffer.writeln('📍 Location: Unavailable');
    }

    buffer.writeln();
    buffer.writeln('Please check on them immediately.');
    buffer.writeln('— SafeNetic Alert System');

    return buffer.toString();
  }

  /// Log the alert to Firestore for history tracking.
  Future<DocumentReference<Map<String, dynamic>>?> _logAlertToFirestore({
    required List<GuardianModel> guardians,
    required LocationData? locationData,
    required String alertType,
    required Map<String, String> results,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return null;

      final alert = AlertModel(
        timestamp: DateTime.now(),
        latitude: locationData?.latitude,
        longitude: locationData?.longitude,
        guardianNames: guardians.map((g) => g.name).toList(),
        guardianPhones: guardians.map((g) => g.phone).toList(),
        type: alertType,
        status: 'pending',
      );

      final docRef = await _firestore
          .collection('users')
          .doc(uid)
          .collection('alerts')
          .add({
        ...alert.toMap(),
        'smsResults': results,
        'pushDelivery': const {'status': 'pending'},
      });

      if (kDebugMode) print('Alert logged to Firestore');
      return docRef;
    } catch (e) {
      if (kDebugMode) print('Failed to log alert: $e');
      return null;
    }
  }

  Future<void> _updateAlertLog(
    DocumentReference<Map<String, dynamic>>? alertLogRef,
    EmergencyAlertResult result,
  ) async {
    if (alertLogRef == null) return;

    try {
      await alertLogRef.update({
        'status': result.historyStatus,
        'smsResults': result.smsStatuses,
        'pushDelivery': result.pushDelivery.toMap(),
        'deliveryUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) print('Failed to update alert delivery log: $e');
    }
  }

  /// Get alert history stream for the current user.
  Stream<List<AlertModel>> getAlertHistory() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('alerts')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AlertModel.fromMap(doc.data(), doc.id))
            .toList());
  }
}
