class DeviceModel {
  final String id;
  final String name;
  final String type; // e.g., "Smart Watch", "Tag"
  final String? macAddress;
  final bool isConnected;
  final DateTime? lastSynced;

  DeviceModel({
    required this.id,
    required this.name,
    required this.type,
    this.macAddress,
    this.isConnected = false,
    this.lastSynced,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'macAddress': macAddress,
      'isConnected': isConnected,
      'lastSynced': lastSynced?.millisecondsSinceEpoch,
    };
  }

  factory DeviceModel.fromMap(Map<String, dynamic> map) {
    return DeviceModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      type: map['type'] ?? 'Unknown',
      macAddress: map['macAddress'],
      isConnected: map['isConnected'] ?? false,
      lastSynced: map['lastSynced'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastSynced'])
          : null,
    );
  }
}