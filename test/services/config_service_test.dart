import 'package:flutter_test/flutter_test.dart';
import 'package:safenetic_app/services/config_service.dart';

void main() {
  group('ConfigService Tests', () {
    test('apiBaseUrl uses the safe compile-time default', () {
      expect(ConfigService.apiBaseUrl, 'https://alerts.safenetic.online');
    });

    test('apiTimeout returns default 30000', () {
      expect(ConfigService.apiTimeout, 30000);
    });
  });
}
