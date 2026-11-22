import 'package:location/location.dart';

class LocationHelper {
  /// Safely fetches the current position using the location package.
  /// Throws specific errors for UI handling, preventing crashes.
  static Future<LocationData> determinePosition() async {
    Location location = Location();
    
    bool serviceEnabled;
    PermissionStatus permission;

    // 1. Check if location services are enabled.
    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the 
      // App to enable the location services.
      return Future.error('Location services are disabled.');
    }

    // 2. Check permission status
    permission = await location.hasPermission();
    
    if (permission == PermissionStatus.denied) {
      // 3. Request permission if currently denied
      permission = await location.requestPermission();
      if (permission == PermissionStatus.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale 
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return Future.error('Location permissions are denied');
      }
    }
    
    if (permission == PermissionStatus.deniedForever) {
      // Permissions are denied forever, handle appropriately. 
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.');
    } 

    // 4. Finally, safe to get position
    // desiredAccuracy: LocationAccuracy.high is good for emergencies
    return await location.getLocation();
  }
}