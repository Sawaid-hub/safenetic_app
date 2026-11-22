import 'package:flutter_test/flutter_test.dart';
import 'package:safenetic_app/models/guardian_model.dart';

void main() {
  group('GuardianModel', () {
    test('toMap() returns a valid map', () {
      final guardian = GuardianModel(
        id: 'g123',
        name: 'Guardian Name',
        phone: '+0987654321',
        relationship: 'Parent',
        isActive: false,
        fcmToken: 'token123',
      );

      final map = guardian.toMap();

      expect(map['id'], 'g123');
      expect(map['name'], 'Guardian Name');
      expect(map['phone'], '+0987654321');
      expect(map['relationship'], 'Parent');
      expect(map['isActive'], false);
      expect(map['fcmToken'], 'token123');
    });

    test('fromMap() creates a valid object', () {
      final map = {
        'id': 'g123',
        'name': 'Guardian Name',
        'phone': '+0987654321',
        'relationship': 'Parent',
        'isActive': false,
        'fcmToken': 'token123',
      };

      final guardian = GuardianModel.fromMap(map);

      expect(guardian.id, 'g123');
      expect(guardian.name, 'Guardian Name');
      expect(guardian.phone, '+0987654321');
      expect(guardian.relationship, 'Parent');
      expect(guardian.isActive, false);
      expect(guardian.fcmToken, 'token123');
    });

    test('copyWith() updates correctly', () {
      final guardian = GuardianModel(
        id: 'g123',
        name: 'Guardian Name',
        phone: '+0987654321',
        relationship: 'Parent',
      );

      final updated = guardian.copyWith(
        name: 'New Name',
        isActive: false,
      );

      expect(updated.id, 'g123');
      expect(updated.name, 'New Name');
      expect(updated.isActive, false);
      expect(updated.phone, '+0987654321'); // Unchanged
    });
  });
}
