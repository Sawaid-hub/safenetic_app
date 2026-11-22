import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:safenetic_app/firebase_option.dart';

/// Calls the Firebase callable endpoints using the existing HTTP dependency.
/// Authentication is a short-lived Firebase ID token; no shared key is sent.
class GuardianInviteService {
  GuardianInviteService._();
  static final GuardianInviteService instance = GuardianInviteService._();

  Uri _endpoint(String name) {
    final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
    return Uri.https(
      'us-central1-$projectId.cloudfunctions.net',
      name,
    );
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Sign in to manage guardian invites.');
    }

    final response = await http
        .post(
          _endpoint(name),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'data': data}),
        )
        .timeout(const Duration(seconds: 20));

    final payload = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('The invite request could not be completed.');
    }
    if (payload is! Map<String, dynamic>) {
      throw StateError('Invalid response from the invite service.');
    }
    final result = payload['result'] ?? payload['data'];
    if (result is! Map) {
      throw StateError('Invalid response from the invite service.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> createInvite() => _call(
        'createGuardianInvite',
        const <String, dynamic>{},
      );

  Future<void> acceptInvite({
    required String inviteCode,
    required String fcmToken,
  }) async {
    await _call('acceptGuardianInvite', {
      'inviteCode': inviteCode,
      'fcmToken': fcmToken,
    });
  }

  Future<void> refreshGuardianTokens(String fcmToken) async {
    await _call('refreshGuardianTokens', {'fcmToken': fcmToken});
  }
}
