class AlertModel {
  final String id;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final List<String> guardianNames;
  final List<String> guardianPhones;
  final String type; // 'manual' or 'fall'
  final String status; // 'pending', 'sent', 'cancelled'

  AlertModel({
    this.id = '',
    required this.timestamp,
    this.latitude,
    this.longitude,
    required this.guardianNames,
    required this.guardianPhones,
    required this.type,
    this.status = 'pending',
  });

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'guardianNames': guardianNames,
      'guardianPhones': guardianPhones,
      'type': type,
      'status': status,
    };
  }

  factory AlertModel.fromMap(Map<String, dynamic> map, [String id = '']) {
    return AlertModel(
      id: id,
      timestamp: DateTime.parse(map['timestamp']),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      guardianNames: List<String>.from(map['guardianNames'] ?? []),
      guardianPhones: List<String>.from(map['guardianPhones'] ?? []),
      type: map['type'] ?? 'manual',
      status: map['status'] ?? 'pending',
    );
  }
}
