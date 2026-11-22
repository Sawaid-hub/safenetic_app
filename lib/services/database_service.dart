import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:safenetic_app/models/user_model.dart';
import 'package:safenetic_app/models/guardian_model.dart';
import 'package:safenetic_app/models/device_model.dart';

class DatabaseService {
  final String uid;
  DatabaseService({required this.uid});

  // Reference to the main users collection
  final CollectionReference userCollection =
      FirebaseFirestore.instance.collection('users');

  // --- USER DATA ---

  // Save or Update User Data
  Future<void> updateUserData(UserModel user) async {
    try {
      return await userCollection.doc(uid).set(user.toMap());
    } catch (e) {
      if (kDebugMode) print('Error updating user data: $e');
      rethrow;
    }
  }

  // Get User Data Stream
  Stream<UserModel> get userData {
    return userCollection.doc(uid).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        return UserModel.fromMap(
            snapshot.data() as Map<String, dynamic>, snapshot.id);
      } else {
        // Return a default empty user if creating for the first time
        return UserModel(
            uid: uid, email: '', name: 'New User', phone: '', sosDelay: 10.0);
      }
    });
  }

  // --- GUARDIANS (Sub-collection) ---

  CollectionReference get guardianCollection =>
      userCollection.doc(uid).collection('guardians');

  // Add or Update Guardian
  Future<void> addGuardian(GuardianModel guardian) async {
    try {
      if (guardian.id.isEmpty) {
        await guardianCollection.add(guardian.toMap());
      } else {
        await guardianCollection.doc(guardian.id).set(guardian.toMap());
      }
    } catch (e) {
      if (kDebugMode) print('Error adding/updating guardian: $e');
      rethrow;
    }
  }

  // Delete Guardian
  Future<void> deleteGuardian(String guardianId) async {
    try {
      await guardianCollection.doc(guardianId).delete();
    } catch (e) {
      if (kDebugMode) print('Error deleting guardian: $e');
      rethrow;
    }
  }

  // Stream List of Guardians
  Stream<List<GuardianModel>> get guardians {
    return guardianCollection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        // Inject the document ID into the map so the model knows its ID
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return GuardianModel.fromMap(data);
      }).toList();
    });
  }

  // --- DEVICES (Sub-collection) ---

  CollectionReference get deviceCollection =>
      userCollection.doc(uid).collection('devices');

  Future<void> addDevice(DeviceModel device) async {
    try {
      if (device.id.isEmpty) {
        await deviceCollection.add(device.toMap());
      } else {
        await deviceCollection.doc(device.id).set(device.toMap());
      }
    } catch (e) {
      if (kDebugMode) print('Error adding device: $e');
      rethrow;
    }
  }

  Future<void> deleteDevice(String deviceId) async {
    try {
      await deviceCollection.doc(deviceId).delete();
    } catch (e) {
      if (kDebugMode) print('Error deleting device: $e');
      rethrow;
    }
  }

  Stream<List<DeviceModel>> get devices {
    return deviceCollection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return DeviceModel.fromMap(data);
      }).toList();
    });
  }
}
