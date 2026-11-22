import 'package:flutter_test/flutter_test.dart';
import 'package:safenetic_app/models/device_model.dart';

void main() {
  group('DeviceModel', () {
    test('toMap() returns a valid map', () {
      final now = DateTime.now();
      final device = DeviceModel(
        id: 'd123',
        name: 'My Watch',
        type: 'Smart Watch',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isConnected: true,
        lastSynced: now,
      );

      final map = device.toMap();

      expect(map['id'], 'd123');
      expect(map['name'], 'My Watch');
      expect(map['type'], 'Smart Watch');
      expect(map['macAddress'], 'AA:BB:CC:DD:EE:FF');
      expect(map['isConnected'], true);
      expect(map['lastSynced'], now.millisecondsSinceEpoch);
    });

    test('fromMap() creates a valid object', () {
      final now = DateTime.now();
      final map = {
        'id': 'd123',
        'name': 'My Watch',
        'type': 'Smart Watch',
        'macAddress': 'AA:BB:CC:DD:EE:FF',
        'isConnected': true,
        'lastSynced': now.millisecondsSinceEpoch,
      };

      final device = DeviceModel.fromMap(map);

      expect(device.id, 'd123');
      expect(device.name, 'My Watch');
      expect(device.type, 'Smart Watch');
      expect(device.macAddress, 'AA:BB:CC:DD:EE:FF');
      expect(device.isConnected, true);
      // Since it's recreated from milliseconds, there could be microsecond differences, so compare milliseconds
      expect(device.lastSynced?.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
    });
  });
}
