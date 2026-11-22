import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:safenetic_app/screens/sos_incoming_alert_screen.dart';
import 'package:safenetic_app/services/guardian_invite_service.dart';

/// Global navigator key — set this in main.dart's MaterialApp so we can
/// push full-screen alert routes from anywhere (including FCM handlers).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Manages FCM token registration for guardians and handles incoming SOS push notifications.
///
/// Guardian-side: registers this device's FCM token under the protected user's document.
/// Also configures foreground/background message handlers so SOS alerts pop up immediately.
class GuardianFcmService {
  GuardianFcmService._();
  static final GuardianFcmService instance = GuardianFcmService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _sosChannelId = 'sos_alert_channel';
  static const String _sosChannelName = 'SOS Alerts';
  static const String _sosChannelDesc =
      'High-priority SOS alerts from protected users';

  late final FlutterLocalNotificationsPlugin _localNotifications;
  bool _initialized = false;

  // ───────────────────────────────────────────────
  // Initialization
  // ───────────────────────────────────────────────

  /// Call once during app startup, after Firebase.initializeApp().
  Future<void> initialize(
      FlutterLocalNotificationsPlugin localNotificationsPlugin) async {
    if (_initialized) return;
    _localNotifications = localNotificationsPlugin;

    // Request notification permission (auto-granted on Android < 13)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );

    // Create the high-importance SOS notification channel
    await _createSosChannel();

    // Configure message handlers
    _configureMessageHandlers();

    // Listen for token refresh
    _messaging.onTokenRefresh.listen(_onTokenRefresh);

    _initialized = true;
    if (kDebugMode) print('GuardianFcmService initialized');
  }

  // ───────────────────────────────────────────────
  // Channel Setup
  // ───────────────────────────────────────────────

  Future<void> _createSosChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _sosChannelId,
      _sosChannelName,
      description: _sosChannelDesc,
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      showBadge: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // ───────────────────────────────────────────────
  // Token Registration
  // ───────────────────────────────────────────────

  /// Registers this device's FCM token under the current user's guardian list.
  /// Call after the user logs in.
  Future<void> registerDeviceToken() async {
    if (FirebaseAuth.instance.currentUser == null) return;

    int retries = 3;
    while (retries > 0) {
      try {
        final token = await _messaging.getToken();
        if (token == null) {
          retries--;
          if (retries > 0) await Future.delayed(const Duration(seconds: 2));
          continue;
        }

        await GuardianInviteService.instance.refreshGuardianTokens(token);
        if (kDebugMode) print('Guardian device token refreshed');
        break;
      } catch (e) {
        if (kDebugMode) print('Failed to register FCM token: $e');
        retries--;
        if (retries > 0) await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  /// Registers this device as a guardian for another user (the protected person).
  /// [protectedUserId] is the UID of the person this device's user is guarding.
  Future<void> registerAsGuardian(String inviteCode) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to accept a guardian invite.');
    final token = await _messaging.getToken();
    if (token == null) throw StateError('Could not register this device.');
    await GuardianInviteService.instance.acceptInvite(
      inviteCode: inviteCode,
      fcmToken: token,
    );
  }

  /// Removes this device's guardian token for a protected user.
  Future<void> unregisterAsGuardian(String protectedUserId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _firestore
        .collection('users')
        .doc(protectedUserId)
        .collection('guardian_tokens')
        .doc(uid)
        .delete();
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('protected_links')
        .doc(protectedUserId)
        .delete();
  }

  void _onTokenRefresh(String newToken) async {
    if (kDebugMode) print('FCM token refreshed');
    try {
      await GuardianInviteService.instance.refreshGuardianTokens(newToken);
    } catch (_) {
      if (kDebugMode) print('Could not refresh guardian device registration');
    }
  }

  // ───────────────────────────────────────────────
  // Message Handlers
  // ───────────────────────────────────────────────

  void _configureMessageHandlers() {
    // Foreground messages → launch full-screen emergency alert
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // When user taps a notification while app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // Check if app was opened from a terminated state via notification
    _checkInitialMessage();
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (kDebugMode) {
      print('FCM foreground message: ${message.messageId}');
    }

    // Show the insistent system notification (for the notification shade)
    final notification = message.notification;
    if (notification != null) {
      await _showEmergencyNotification(
        title: notification.title ?? 'SOS Alert',
        body: notification.body ?? 'Emergency alert received!',
        payload: message.data,
      );
    }

    // Launch the full-screen emergency alert overlay
    _launchFullScreenAlert(message.data);
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    if (kDebugMode) print('FCM message opened app: ${message.messageId}');
    // User tapped the notification — show the alert screen
    _launchFullScreenAlert(message.data);
  }

  Future<void> _checkInitialMessage() async {
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _launchFullScreenAlert(initialMessage.data);
    }
  }

  // ───────────────────────────────────────────────
  // Full-Screen Emergency Alert (Earthquake-style)
  // ───────────────────────────────────────────────

  /// Pushes the full-screen emergency alert screen over everything.
  void _launchFullScreenAlert(Map<String, dynamic> data) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      if (kDebugMode) print('Navigator not available for full-screen alert');
      return;
    }

    navigator.push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return SosIncomingAlertScreen(
            userName: data['userName'] ?? 'Someone',
            alertType: data['alertType'] ?? 'manual',
            sosId: data['sosId'],
            userId: data['userId'],
            latitude: data['latitude'],
            longitude: data['longitude'],
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  // ───────────────────────────────────────────────
  // Emergency Notification (insistent alarm-style)
  // ───────────────────────────────────────────────

  /// Shows a high-priority, insistent notification that keeps alarming
  /// until the user interacts with it (like earthquake/tornado warnings).
  Future<void> _showEmergencyNotification({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    // FLAG_INSISTENT (4) = alarm repeats until user interacts
    const int flagInsistent = 4;

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _sosChannelId,
      _sosChannelName,
      channelDescription: _sosChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      ticker: 'EMERGENCY SOS ALERT',
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      ongoing: true,
      autoCancel: false,
      additionalFlags: Int32List.fromList([flagInsistent]),
      colorized: true,
      color: const Color(0xFFFF0000),
      enableLights: true,
      ledColor: const Color(0xFFFF0000),
      ledOnMs: 300,
      ledOffMs: 300,
      timeoutAfter: 120000, // Auto-dismiss after 2 minutes
    );

    final NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      id: 9999, // Fixed ID so it replaces previous SOS notifications
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: payload?['sosId'] ?? '',
    );
  }
}

/// Top-level background message handler — must be a top-level function.
/// Register this in main.dart via FirebaseMessaging.onBackgroundMessage.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    print('FCM background message: ${message.messageId}');
  }
  // The notification will be shown automatically by the system
  // because the message contains a `notification` payload.
  // The full-screen intent will launch the app if configured.
}
