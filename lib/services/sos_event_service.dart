import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:location/location.dart';
import 'package:safenetic_app/services/config_service.dart';

/// The server-confirmed push delivery result for one SOS event.
class SosDeliveryResult {
  const SosDeliveryResult({
    required this.sosId,
    required this.status,
    required this.provider,
    this.successCount = 0,
    this.failureCount = 0,
    this.totalCount = 0,
    this.error,
  });

  final String sosId;
  final String status;
  final String provider;
  final int successCount;
  final int failureCount;
  final int totalCount;
  final String? error;

  bool get hasConfirmedDelivery => successCount > 0;
  bool get isPending => status == 'pending' || status == 'processing';

  Map<String, dynamic> toMap() => {
        'sosId': sosId,
        'status': status,
        'provider': provider,
        'successCount': successCount,
        'failureCount': failureCount,
        'totalCount': totalCount,
        if (error != null) 'error': error,
      };

  factory SosDeliveryResult.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final delivery = Map<String, dynamic>.from(
      data['delivery'] as Map? ?? const <String, dynamic>{},
    );
    return SosDeliveryResult(
      sosId: snapshot.id,
      status: delivery['status'] as String? ?? 'pending',
      provider: delivery['provider'] as String? ?? 'firestore_cloud_function',
      successCount: (delivery['successCount'] as num?)?.toInt() ?? 0,
      failureCount: (delivery['failureCount'] as num?)?.toInt() ?? 0,
      totalCount: (delivery['totalCount'] as num?)?.toInt() ?? 0,
      error: delivery['error'] as String?,
    );
  }
}

/// Writes SOS events to Firestore, which triggers the Cloud Function
/// to send FCM push notifications to all registered guardians.
class SosEventService {
  SosEventService._();
  static final SosEventService instance = SosEventService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const _backendUrl =
      '${ConfigService.apiBaseUrl}/api/sos/trigger';
  static const _primaryWait = Duration(seconds: 15);
  static const _terminalStatuses = {
    'delivered',
    'partial',
    'failed',
    'no_guardians',
    'unknown',
  };

  /// Writes the event, waits for the primary receipt, and invokes the HTTPS
  /// fallback only after an explicit primary failure.
  Future<SosDeliveryResult> triggerSos({
    required String userName,
    LocationData? locationData,
    required bool generatedAutomatically,
    String alertType = 'manual',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (kDebugMode) print('SosEventService: No authenticated user');
      return const SosDeliveryResult(
        sosId: '',
        status: 'failed',
        provider: 'none',
        error: 'No authenticated user',
      );
    }

    try {
      final sosData = <String, dynamic>{
        'userName': userName,
        'alertType': alertType,
        'generatedAutomatically': generatedAutomatically,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'active',
        // Durable routing metadata and delivery receipt for the alert screen.
        'delivery': <String, dynamic>{
          'status': 'pending',
          'primary': 'firestore_cloud_function',
          'fallback': 'alerts_backend',
          'provider': 'firestore_cloud_function',
          'fallbackEligible': false,
          'successCount': 0,
          'failureCount': 0,
          'totalCount': 0,
        },
      };

      // Include location if available
      if (locationData?.latitude != null && locationData?.longitude != null) {
        sosData['location'] = GeoPoint(
          locationData!.latitude!,
          locationData.longitude!,
        );
        sosData['latitude'] = locationData.latitude;
        sosData['longitude'] = locationData.longitude;
      }

      final docRef = await _firestore
          .collection('users')
          .doc(uid)
          .collection('sos_events')
          .add(sosData);

      if (kDebugMode) {
        print('SOS event created: ${docRef.id} (type: $alertType)');
      }

      final primaryResult = await _waitForPrimary(docRef);
      final latestSnapshot = await docRef.get();
      final latestDelivery = Map<String, dynamic>.from(
        latestSnapshot.data()?['delivery'] as Map? ?? const <String, dynamic>{},
      );
      final latestResult = SosDeliveryResult.fromSnapshot(latestSnapshot);
      final effectiveResult = primaryResult.isPending &&
              _terminalStatuses.contains(latestResult.status)
          ? latestResult
          : primaryResult;

      if (effectiveResult.status == 'failed' &&
          latestDelivery['fallbackEligible'] == true) {
        return await _callFallback(docRef: docRef);
      }

      return effectiveResult;
    } catch (e) {
      if (kDebugMode) print('Failed to create/process SOS event: $e');
      return SosDeliveryResult(
        sosId: '',
        status: 'failed',
        provider: 'none',
        error: e.toString(),
      );
    }
  }

  Future<SosDeliveryResult> _waitForPrimary(
    DocumentReference<Map<String, dynamic>> docRef,
  ) async {
    try {
      final snapshot = await docRef.snapshots().firstWhere((snapshot) {
        final delivery = snapshot.data()?['delivery'] as Map?;
        return _terminalStatuses.contains(delivery?['status']);
      }).timeout(_primaryWait);
      return SosDeliveryResult.fromSnapshot(snapshot);
    } on TimeoutException {
      if (kDebugMode) {
        print('Cloud Function delivery is still pending for ${docRef.id}');
      }
      return SosDeliveryResult(
        sosId: docRef.id,
        status: 'pending',
        provider: 'firestore_cloud_function',
        error: 'Delivery confirmation is still pending',
      );
    }
  }

  Future<SosDeliveryResult> _callFallback({
    required DocumentReference<Map<String, dynamic>> docRef,
  }) async {
    if (kDebugMode) {
      print('Primary push failed; requesting HTTPS fallback for ${docRef.id}');
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      final idToken = await user?.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        return SosDeliveryResult(
          sosId: docRef.id,
          status: 'failed',
          provider: 'alerts_backend',
          error: 'Sign in again to retry emergency delivery.',
        );
      }

      final response = await http
          .post(
            Uri.parse(_backendUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'sosId': docRef.id}),
          )
          .timeout(Duration(milliseconds: ConfigService.apiTimeout));

      if (kDebugMode) {
        print('Fallback response status: ${response.statusCode}');
      }

      // The HTTP response can fail after FCM accepted the send. The Firestore
      // receipt is authoritative for every response, including a 500.
      final snapshot = await docRef.get();
      final receipt = SosDeliveryResult.fromSnapshot(snapshot);
      if (receipt.provider == 'alerts_backend' ||
          response.statusCode == 200 ||
          response.statusCode == 409) {
        return receipt;
      }

      return SosDeliveryResult(
        sosId: docRef.id,
        status: 'failed',
        provider: 'alerts_backend',
        error: 'Fallback rejected the event (${response.statusCode})',
      );
    } catch (e) {
      if (kDebugMode) print('HTTPS fallback failed: $e');
      try {
        // The HTTP response may have been lost after the backend wrote its
        // receipt. Prefer that durable state over assuming the send failed.
        final snapshot = await docRef.get();
        final receipt = SosDeliveryResult.fromSnapshot(snapshot);
        if (receipt.provider == 'alerts_backend') return receipt;
      } catch (_) {
        // Preserve the original network error below.
      }
      return SosDeliveryResult(
        sosId: docRef.id,
        status: 'failed',
        provider: 'alerts_backend',
        error: e.toString(),
      );
    }
  }

  /// Marks an SOS event as resolved.
  Future<void> resolveSos(String sosId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('sos_events')
          .doc(sosId)
          .update({
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) print('SOS event resolved: $sosId');
    } catch (e) {
      if (kDebugMode) print('Failed to resolve SOS event: $e');
    }
  }
}
