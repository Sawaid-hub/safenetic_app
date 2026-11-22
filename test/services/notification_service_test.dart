import 'package:flutter_test/flutter_test.dart';
import 'package:safenetic_app/services/notification_service.dart';
import 'package:safenetic_app/services/sos_event_service.dart';

void main() {
  group('NotificationService', () {
    test('buildEmergencyMessage() constructs correct message with location',
        () {
      final service = NotificationService.instance;

      final message = service.buildEmergencyMessage(
        userName: 'John Doe',
        latitude: 12.34,
        longitude: 56.78,
        alertType: 'fall',
      );

      expect(message, contains('FALL DETECTED for John Doe'));
      expect(message, contains('https://maps.google.com/?q=12.34,56.78'));
    });

    test('buildEmergencyMessage() handles missing location', () {
      final service = NotificationService.instance;

      final message = service.buildEmergencyMessage(
        userName: 'Jane Doe',
        alertType: 'manual',
      );

      expect(message, contains('SOS ACTIVATED for Jane Doe'));
      expect(message, contains('Location: Unavailable'));
    });
  });

  group('EmergencyAlertResult', () {
    test('reports a primary push acceptance and confirmed SMS delivery', () {
      const result = EmergencyAlertResult(
        smsStatuses: {'Alex': 'sent'},
        pushDelivery: SosDeliveryResult(
          sosId: 'sos-1',
          status: 'delivered',
          provider: 'firestore_cloud_function',
          successCount: 2,
          totalCount: 2,
        ),
      );

      expect(result.historyStatus, 'sent');
      expect(result.deliverySummary, contains('Primary push accepted for 2'));
      expect(result.deliverySummary, contains('SMS sent to 1 guardian'));
    });

    test('identifies an accepted fallback without claiming two sends', () {
      const result = EmergencyAlertResult(
        smsStatuses: {'Alex': 'failed'},
        pushDelivery: SosDeliveryResult(
          sosId: 'sos-2',
          status: 'delivered',
          provider: 'alerts_backend',
          successCount: 1,
          totalCount: 1,
        ),
      );

      expect(result.historyStatus, 'sent');
      expect(result.deliverySummary, contains('Backup push accepted'));
    });

    test('keeps an ambiguous push outcome pending and explains deduplication',
        () {
      const result = EmergencyAlertResult(
        smsStatuses: {'Alex': 'failed'},
        pushDelivery: SosDeliveryResult(
          sosId: 'sos-3',
          status: 'unknown',
          provider: 'firestore_cloud_function',
        ),
      );

      expect(result.historyStatus, 'pending');
      expect(result.deliverySummary, contains('backup was not used'));
      expect(result.deliverySummary, contains('avoid duplicates'));
    });

    test('reports a confirmed all-channel failure', () {
      const result = EmergencyAlertResult(
        smsStatuses: {'Alex': 'failed'},
        pushDelivery: SosDeliveryResult(
          sosId: 'sos-4',
          status: 'failed',
          provider: 'alerts_backend',
        ),
      );

      expect(result.historyStatus, 'failed');
      expect(result.deliverySummary, 'Backup push delivery failed.');
    });
  });
}
