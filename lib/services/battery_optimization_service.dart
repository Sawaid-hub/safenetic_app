import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

class BatteryOptimizationService extends ChangeNotifier {
  static final BatteryOptimizationService _instance =
      BatteryOptimizationService._internal();

  factory BatteryOptimizationService() => _instance;

  static BatteryOptimizationService get instance => _instance;

  BatteryOptimizationService._internal() {
    _init();
  }

  final Battery _battery = Battery();
  int _batteryLevel = 100;
  bool _isLowPowerMode = false;
  StreamSubscription<BatteryState>? _batteryStateSubscription;

  int get batteryLevel => _batteryLevel;
  bool get isLowPowerMode => _isLowPowerMode;

  // Power threshold to trigger low power mode
  static const int _lowPowerThreshold = 20;

  Future<void> _init() async {
    try {
      _batteryLevel = await _battery.batteryLevel;
      _updatePowerMode();

      _batteryStateSubscription =
          _battery.onBatteryStateChanged.listen((state) async {
        // Specifically, check percentage to react.
        _batteryLevel = await _battery.batteryLevel;
        _updatePowerMode();
      });

      // Fallback timer to check every 5 minutes in case state hasn't changed
      // (sometimes discharging state doesn't trigger continuous events)
      Timer.periodic(const Duration(minutes: 5), (_) async {
        _batteryLevel = await _battery.batteryLevel;
        _updatePowerMode();
      });
    } catch (e) {
      if (kDebugMode) {
        print("Error initializing BatteryOptimizationService: $e");
      }
    }
  }

  void _updatePowerMode() {
    final bool newMode = _batteryLevel <= _lowPowerThreshold;
    if (_isLowPowerMode != newMode) {
      _isLowPowerMode = newMode;
      if (kDebugMode) {
        print(
            "Battery Mode Changed: isLowPowerMode = $_isLowPowerMode (Battery: $_batteryLevel%)");
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _batteryStateSubscription?.cancel();
    super.dispose();
  }
}
