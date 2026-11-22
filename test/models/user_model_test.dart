import 'package:flutter_test/flutter_test.dart';
import 'package:safenetic_app/models/user_model.dart';

void main() {
  group('UserModel', () {
    test('toMap() returns a valid map', () {
      final user = UserModel(
        uid: 'user123',
        email: 'test@example.com',
        name: 'Test User',
        phone: '+1234567890',
        biometricEnabled: true,
        notificationsEnabled: false,
        sosDelay: 15.0,
      );

      final map = user.toMap();

      expect(map['uid'], 'user123');
      expect(map['email'], 'test@example.com');
      expect(map['name'], 'Test User');
      expect(map['phone'], '+1234567890');
      expect(map['biometricEnabled'], true);
      expect(map['notificationsEnabled'], false);
      expect(map['sosDelay'], 15.0);
    });

    test('fromMap() creates a valid object', () {
      final map = {
        'email': 'test@example.com',
        'name': 'Test User',
        'phone': '+1234567890',
        'biometricEnabled': true,
        'notificationsEnabled': false,
        'sosDelay': 15.0,
      };

      final user = UserModel.fromMap(map, 'user123');

      expect(user.uid, 'user123');
      expect(user.email, 'test@example.com');
      expect(user.name, 'Test User');
      expect(user.phone, '+1234567890');
      expect(user.biometricEnabled, true);
      expect(user.notificationsEnabled, false);
      expect(user.sosDelay, 15.0);
    });

    test('copyWith() updates correctly', () {
      final user = UserModel(
        uid: 'user123',
        email: 'test@example.com',
        name: 'Test User',
        phone: '+1234567890',
      );

      final updatedUser = user.copyWith(
        name: 'Updated Name',
        notificationsEnabled: false,
      );

      expect(updatedUser.uid, 'user123');
      expect(updatedUser.name, 'Updated Name');
      expect(updatedUser.notificationsEnabled, false);
      expect(updatedUser.email, 'test@example.com'); // Unchanged
    });
  });
}
