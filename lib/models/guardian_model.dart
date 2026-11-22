class GuardianModel {
  final String id;
  final String name;
  final String phone;
  final String relationship;
  final bool isActive;
  final String? status; // e.g., "Notified", "Viewing Location"
  final String? fcmToken; // FCM device token for push notifications

  GuardianModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
    this.isActive = true,
    this.status,
    this.fcmToken,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'relationship': relationship,
      'isActive': isActive,
      'status': status,
      'fcmToken': fcmToken,
    };
  }

  factory GuardianModel.fromMap(Map<String, dynamic> map) {
    return GuardianModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      relationship: map['relationship'] ?? 'Contact',
      isActive: map['isActive'] ?? true,
      status: map['status'],
      fcmToken: map['fcmToken'],
    );
  }

  GuardianModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? relationship,
    bool? isActive,
    String? status,
    String? fcmToken,
  }) {
    return GuardianModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      relationship: relationship ?? this.relationship,
      isActive: isActive ?? this.isActive,
      status: status ?? this.status,
      fcmToken: fcmToken ?? this.fcmToken,
    );
  }
}