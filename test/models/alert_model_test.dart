import 'package:flutter_test/flutter_test.dart';
import 'package:safenetic_app/models/alert_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  group('AlertModel', () {
    test('toMap() returns a valid map', () {
      final now = DateTime.now();
      final alert = AlertModel(
        id: 'a123',
        type: 'fall',
        timestamp: now,
        latitude: 12.34,
        longitude: 56.78,
        status: 'active',
        guardianNames: ['G1'],
        guardianPhones: ['123'],
      );

      final map = alert.toMap();

      expect(map['type'], 'fall');
      expect(map['latitude'], 12.34);
      expect(map['longitude'], 56.78);
      expect(map['status'], 'active');
      expect(map['guardianNames'], ['G1']);
      expect(map['guardianPhones'], ['123']);
      expect(map['timestamp'], now.toIso8601String());
    });

    test('fromMap() creates a valid object', () {
      final now = DateTime.now();
      final map = {
        'type': 'fall',
        'timestamp': now.toIso8601String(),
        'latitude': 12.34,
        'longitude': 56.78,
        'status': 'active',
        'guardianNames': ['G1'],
        'guardianPhones': ['123'],
      };

      final alert = AlertModel.fromMap(map, 'a123');

      expect(alert.id, 'a123');
      expect(alert.type, 'fall');
      expect(alert.latitude, 12.34);
      expect(alert.longitude, 56.78);
      expect(alert.status, 'active');
      expect(alert.timestamp.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
    });
  });
}
