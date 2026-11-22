import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:location/location.dart';
import 'package:geolocator/geolocator.dart' as geolocator;
import 'battery_optimization_service.dart';

// Custom timeout exception for location operations
class LocationTimeoutException implements Exception {
  final String message;
  LocationTimeoutException(this.message);

  @override
  String toString() => 'LocationTimeoutException: $message';
}

class LocationService {
  final Location _location = Location();

  Future<bool> checkLocationPermission() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    // Check if location service is enabled
    serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        return false;
      }
    }

    // Check location permission
    permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return false;
      }
    }

    return true;
  }

  Future<LocationData?> getCurrentLocation() async {
    try {
      final hasPermission = await checkLocationPermission();
      if (!hasPermission) {
        return null;
      }

      // Add timeout to prevent hanging operations
      try {
        return await _location.getLocation().timeout(
              const Duration(seconds: 10),
              onTimeout: () =>
                  throw LocationTimeoutException('Location request timed out'),
            );
      } on LocationTimeoutException {
        if (kDebugMode) {
          print('Location request timed out after 10 seconds');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting location: $e');
      }
      return null;
    }
  }

  Future<geolocator.Position?> getCurrentPosition() async {
    try {
      bool serviceEnabled;
      geolocator.LocationPermission permission;

      // Test if location services are enabled.
      serviceEnabled = await geolocator.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Location services are not enabled don't continue
        // accessing the position and request users of the
        // App to enable the location services.
        return null;
      }

      permission = await geolocator.Geolocator.checkPermission();
      if (permission == geolocator.LocationPermission.denied) {
        permission = await geolocator.Geolocator.requestPermission();
        if (permission == geolocator.LocationPermission.denied) {
          // Permissions are denied, next time you could try
          // requesting permissions again (this is also where
          // Android's shouldShowRequestPermissionRationale
          // returned true. According to Android guidelines
          // your App should show an explanatory UI now.
          return null;
        }
      }

      if (permission == geolocator.LocationPermission.deniedForever) {
        // Permissions are denied forever, handle appropriately.
        return null;
      }

      // When we reach here, permissions are granted and we can
      // continue accessing the position of the device.
      return await geolocator.Geolocator.getCurrentPosition();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting position: $e');
      }
      return null;
    }
  }

  Stream<LocationData> getLocationStream() {
    final batteryService = BatteryOptimizationService.instance;
    // Configure location settings for real-time updates
    _location.changeSettings(
      accuracy: batteryService.isLowPowerMode
          ? LocationAccuracy.balanced
          : LocationAccuracy.high,
      interval: batteryService.isLowPowerMode ? 5000 : 1000,
      distanceFilter: batteryService.isLowPowerMode ? 20 : 5,
    );

    return _location.onLocationChanged.handleError((error) {
      if (kDebugMode) {
        print('Location stream error: $error');
      }
    });
  }

  Stream<geolocator.Position> getPositionStream() {
    final batteryService = BatteryOptimizationService.instance;
    return geolocator.Geolocator.getPositionStream(
      locationSettings: geolocator.LocationSettings(
        accuracy: batteryService.isLowPowerMode
            ? geolocator.LocationAccuracy.medium
            : geolocator.LocationAccuracy.high,
        distanceFilter: batteryService.isLowPowerMode ? 20 : 10,
      ),
    );
  }

  /// Change location settings for the location service
  Future<void> changeSettings({
    LocationAccuracy? accuracy,
    int? interval,
    double? distanceFilter,
  }) async {
    await _location.changeSettings(
      accuracy: accuracy ?? LocationAccuracy.high,
      interval: interval ?? 1000,
      distanceFilter: distanceFilter ?? 5,
    );
  }
}
