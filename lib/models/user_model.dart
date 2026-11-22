class UserModel {
  final String uid;
  final String email;
  final String name;
  final String phone;
  final String? profileImageUrl;
  final bool biometricEnabled;
  final bool notificationsEnabled;
  final double sosDelay;
  final String? bloodType;
  final String? medicalConditions;
  final String? allergies;

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.phone,
    this.profileImageUrl,
    this.biometricEnabled = true,
    this.notificationsEnabled = true,
    this.sosDelay = 10.0,
    this.bloodType,
    this.medicalConditions,
    this.allergies,
  });

  // Convert a UserModel into a Map (for sending to Firebase)
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'phone': phone,
      'profileImageUrl': profileImageUrl,
      'biometricEnabled': biometricEnabled,
      'notificationsEnabled': notificationsEnabled,
      'sosDelay': sosDelay,
      'bloodType': bloodType,
      'medicalConditions': medicalConditions,
      'allergies': allergies,
    };
  }

  // CopyWith method for easy updates
  UserModel copyWith({
    String? uid,
    String? email,
    String? name,
    String? phone,
    String? profileImageUrl,
    bool? biometricEnabled,
    bool? notificationsEnabled,
    double? sosDelay,
    String? bloodType,
    String? medicalConditions,
    String? allergies,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      sosDelay: sosDelay ?? this.sosDelay,
      bloodType: bloodType ?? this.bloodType,
      medicalConditions: medicalConditions ?? this.medicalConditions,
      allergies: allergies ?? this.allergies,
    );
  }

  // Create a UserModel from a Map (fetching from Firebase)
  factory UserModel.fromMap(Map<String, dynamic> map, String documentId) {
    return UserModel(
      uid: documentId, // Often the doc ID is the UID
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      profileImageUrl: map['profileImageUrl'],
      biometricEnabled: map['biometricEnabled'] ?? true,
      notificationsEnabled: map['notificationsEnabled'] ?? true,
      sosDelay: (map['sosDelay'] ?? 10.0).toDouble(),
      bloodType: map['bloodType'],
      medicalConditions: map['medicalConditions'],
      allergies: map['allergies'],
    );
  }
}
