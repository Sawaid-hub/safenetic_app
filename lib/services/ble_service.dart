import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'battery_optimization_service.dart';

/// BLE wearable service for scanning, connecting, and reading sensor data.
///
/// Reads standard BLE heart rate and accelerometer characteristics from
/// paired wearable devices and exposes streams.
class BleService {
  static final BleService instance = BleService._();
  BleService._();

  BluetoothDevice? _connectedDevice;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  final _deviceController = StreamController<List<ScanResult>>.broadcast();
  final _sensorDataController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _connectionStateController =
      StreamController<BluetoothConnectionState>.broadcast();

  // Standard BLE UUIDs
  static const _heartRateServiceUuid = '0000180d-0000-1000-8000-00805f9b34fb';
  static const _heartRateMeasurementUuid =
      '00002a37-0000-1000-8000-00805f9b34fb';

  // Common accelerometer service (varies by device)
  static const _accelerometerServiceUuid =
      '00001101-0000-1000-8000-00805f9b34fb';
  static const _accelerometerDataUuid = '00002101-0000-1000-8000-00805f9b34fb';

  Stream<List<ScanResult>> get scanResults => _deviceController.stream;
  Stream<Map<String, dynamic>> get sensorData => _sensorDataController.stream;
  Stream<BluetoothConnectionState> get connectionState =>
      _connectionStateController.stream;

  BluetoothDevice? get connectedDevice => _connectedDevice;
  bool get isConnected => _connectedDevice != null;

  /// Start scanning for BLE devices
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
    bool force = false,
  }) async {
    try {
      if (!force && BatteryOptimizationService.instance.isLowPowerMode) {
        if (kDebugMode) {
          print(
              'BLE: Scanning blocked due to low power mode (use force: true to override)');
        }
        return;
      }

      // Check adapter state
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        if (kDebugMode) print('BLE: Bluetooth adapter is not on');
        return;
      }

      await FlutterBluePlus.startScan(timeout: timeout);

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        // Filter to devices with names (skip unnamed)
        final named =
            results.where((r) => r.device.platformName.isNotEmpty).toList();
        _deviceController.add(named);
      });
    } catch (e) {
      if (kDebugMode) print('BLE scan error: $e');
    }
  }

  /// Stop scanning
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  /// Connect to a specific BLE device
  Future<bool> connect(BluetoothDevice device) async {
    try {
      await device.connect(
          autoConnect: false, timeout: const Duration(seconds: 15));
      _connectedDevice = device;

      _connectionSubscription = device.connectionState.listen((state) {
        _connectionStateController.add(state);
        if (state == BluetoothConnectionState.disconnected) {
          _connectedDevice = null;
        }
      });

      // Discover services and subscribe to characteristics
      await _discoverAndSubscribe(device);
      return true;
    } catch (e) {
      if (kDebugMode) print('BLE connect error: $e');
      _connectedDevice = null;
      return false;
    }
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    try {
      await _connectedDevice?.disconnect();
    } catch (e) {
      if (kDebugMode) print('BLE disconnect error: $e');
    }
    _connectedDevice = null;
  }

  /// Discover services and subscribe to sensor characteristics
  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    final services = await device.discoverServices();

    for (final service in services) {
      final serviceUuid = service.uuid.toString().toLowerCase();

      // Heart rate
      if (serviceUuid == _heartRateServiceUuid) {
        for (final char in service.characteristics) {
          if (char.uuid.toString().toLowerCase() == _heartRateMeasurementUuid) {
            await char.setNotifyValue(true);
            char.onValueReceived.listen((value) {
              if (value.length >= 2) {
                int heartRate;
                // BLE heart rate format: bit 0 of flags indicates 8 vs 16-bit
                if ((value[0] & 0x01) != 0 && value.length >= 3) {
                  heartRate = value[1] | (value[2] << 8); // 16-bit
                } else {
                  heartRate = value[1]; // 8-bit
                }
                _sensorDataController.add({
                  'type': 'heart_rate',
                  'value': heartRate,
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                });
              }
            });
          }
        }
      }

      // Accelerometer
      if (serviceUuid == _accelerometerServiceUuid) {
        for (final char in service.characteristics) {
          if (char.uuid.toString().toLowerCase() == _accelerometerDataUuid) {
            await char.setNotifyValue(true);
            char.onValueReceived.listen((value) {
              if (value.length >= 6) {
                // Parse signed 16-bit x, y, z
                final x = _toSigned16(value[0] | (value[1] << 8));
                final y = _toSigned16(value[2] | (value[3] << 8));
                final z = _toSigned16(value[4] | (value[5] << 8));
                _sensorDataController.add({
                  'type': 'accelerometer',
                  'x': x / 1000.0,
                  'y': y / 1000.0,
                  'z': z / 1000.0,
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                });
              }
            });
          }
        }
      }
    }
  }

  int _toSigned16(int val) => val >= 0x8000 ? val - 0x10000 : val;

  /// Get list of bonded (previously paired) devices
  Future<List<BluetoothDevice>> getBondedDevices() async {
    return FlutterBluePlus.bondedDevices;
  }

  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _deviceController.close();
    _sensorDataController.close();
    _connectionStateController.close();
    disconnect();
  }
}
