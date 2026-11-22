import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'ml_service.dart';
import 'battery_optimization_service.dart';

class BackgroundServiceManager {
  static final BackgroundServiceManager _instance =
      BackgroundServiceManager._internal();

  factory BackgroundServiceManager() => _instance;

  BackgroundServiceManager._internal();

  final FlutterBackgroundService _service = FlutterBackgroundService();

  Future<void> initialize() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'safenetic_bg_service', // id
      'SafeNetic Background Protection', // name
      description:
          'Keeps SafeNetic active to detect falls and distress noises', // description
      importance: Importance
          .low, // low importance prevents sound/vibration for persistent notification
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    // Create the channel on the device
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        // This will be executed when app is in background or foreground
        onStart: onStart,
        autoStart:
            false, // We'll manually start it when permissions are granted
        isForegroundMode: true,
        notificationChannelId: 'safenetic_bg_service',
        initialNotificationTitle: 'SafeNetic Active',
        initialNotificationContent:
            'Monitoring for emergencies in the background',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  Future<void> startService() async {
    final bool isRunning = await _service.isRunning();
    if (!isRunning) {
      await _service.startService();
    }
  }

  Future<void> stopService() async {
    final bool isRunning = await _service.isRunning();
    if (isRunning) {
      _service.invoke("stopService");
    }
  }
}

// =========================================================================
// ENTRY POINTS FOR BACKGROUND ISOLATE
// =========================================================================

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Ensure we can use flutter plugins
  DartPluginRegistrant.ensureInitialized();

  // Initialize Local Notifications to update the ongoing notification

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // 1. Initialize Battery Optimization
  final batteryService = BatteryOptimizationService();
  // Call init implicitly via factory construction and checking properties if needed

  // 2. Initialize ML Service
  final mlService = MLService();
  await mlService.initialize();

  // Dynamic interval based on battery
  Duration getInferenceInterval() {
    return batteryService.isLowPowerMode
        ? const Duration(milliseconds: 1500) // Lower frequency on low power
        : const Duration(milliseconds: 500); // High frequency on normal power
  }

  // 3. Start Monitoring
  void startMonitoring() {
    mlService.startMonitoring(
      inferenceInterval: getInferenceInterval(),
      onMotion: (isAnomaly, confidence) {
        if (isAnomaly) {
          if (kDebugMode) {
            print("Background: MOTION ANOMALY DETECTED! Conf: $confidence");
          }
          // We can send this to the main UI isolate via SendPort, or invoke a method.
          service.invoke('onEmergencyEvent', {
            'type': 'motion',
            'confidence': confidence,
          });
        }
      },
      onNoise: (isDistress, confidence) {
        if (isDistress) {
          if (kDebugMode) {
            print("Background: NOISE DISTRESS DETECTED! Conf: $confidence");
          }
          service.invoke('onEmergencyEvent', {
            'type': 'noise',
            'confidence': confidence,
          });
        }
      },
    );
  }

  // Initial start
  startMonitoring();

  // 4. Listen to Battery Mode changes to adjust frequency
  batteryService.addListener(() {
    // If threshold crossed, restart monitoring with new interval
    mlService.stopMonitoring();
    startMonitoring();

    // Update Notification
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'SafeNetic Active',
        content: batteryService.isLowPowerMode
            ? 'Monitoring (Low Power Mode)'
            : 'Monitoring for emergencies',
      );
    }
  });

  Timer.periodic(const Duration(seconds: 1), (timer) async {
    // Minimal keep-alive tick
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        // Optionally update notification with heartbeat or status
      }
    }
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}
