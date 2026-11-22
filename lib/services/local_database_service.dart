import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:safenetic_app/models/user_model.dart';
import 'package:safenetic_app/models/guardian_model.dart';
import 'package:safenetic_app/models/alert_model.dart';

/// Local SQLite cache for offline support.
///
/// Mirrors Firestore structure: users, guardians, alert_history tables.
/// Syncs upstream when connectivity returns.
class LocalDatabaseService {
  static final LocalDatabaseService instance = LocalDatabaseService._();
  LocalDatabaseService._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'safenetic.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            uid TEXT PRIMARY KEY,
            email TEXT,
            name TEXT,
            phone TEXT,
            profileImageUrl TEXT,
            biometricEnabled INTEGER DEFAULT 1,
            notificationsEnabled INTEGER DEFAULT 1,
            sosDelay REAL DEFAULT 10.0,
            bloodType TEXT,
            medicalConditions TEXT,
            allergies TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE guardians (
            id TEXT PRIMARY KEY,
            name TEXT,
            phone TEXT,
            relationship TEXT,
            isActive INTEGER DEFAULT 1,
            status TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE alert_history (
            id TEXT PRIMARY KEY,
            timestamp TEXT,
            latitude REAL,
            longitude REAL,
            guardianNames TEXT,
            guardianPhones TEXT,
            type TEXT DEFAULT 'manual',
            status TEXT DEFAULT 'pending'
          )
        ''');
      },
    );
  }

  // --- User ---

  Future<void> saveUser(UserModel user) async {
    final db = await database;
    await db.insert(
      'users',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<UserModel?> getUser(String uid) async {
    final db = await database;
    final maps = await db.query('users', where: 'uid = ?', whereArgs: [uid]);
    if (maps.isEmpty) return null;
    return UserModel.fromMap(maps.first, uid);
  }

  // --- Guardians ---

  Future<void> saveGuardians(List<GuardianModel> guardians) async {
    final db = await database;
    final batch = db.batch();
    batch.delete('guardians');
    for (final g in guardians) {
      batch.insert('guardians', g.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<GuardianModel>> getGuardians() async {
    final db = await database;
    final maps = await db.query('guardians');
    return maps.map((m) => GuardianModel.fromMap(m)).toList();
  }

  // --- Alert History ---

  Future<void> saveAlerts(List<AlertModel> alerts) async {
    final db = await database;
    final batch = db.batch();
    batch.delete('alert_history');
    for (final a in alerts) {
      final map = a.toMap();
      map['id'] = a.id;
      // Serialize lists as comma-separated
      map['guardianNames'] = (map['guardianNames'] as List).join(',');
      map['guardianPhones'] = (map['guardianPhones'] as List).join(',');
      batch.insert('alert_history', map);
    }
    await batch.commit(noResult: true);
  }

  Future<List<AlertModel>> getAlerts() async {
    final db = await database;
    final maps = await db.query(
      'alert_history',
      orderBy: 'timestamp DESC',
      limit: 50,
    );
    return maps.map((m) {
      // Deserialize comma-separated lists
      final restored = Map<String, dynamic>.from(m);
      restored['guardianNames'] =
          (m['guardianNames'] as String?)?.split(',') ?? [];
      restored['guardianPhones'] =
          (m['guardianPhones'] as String?)?.split(',') ?? [];
      return AlertModel.fromMap(restored, m['id'] as String? ?? '');
    }).toList();
  }

  /// Sync local cache from Firestore data
  Future<void> syncFromFirestore({
    UserModel? user,
    List<GuardianModel>? guardians,
    List<AlertModel>? alerts,
  }) async {
    if (user != null) await saveUser(user);
    if (guardians != null) await saveGuardians(guardians);
    if (alerts != null) await saveAlerts(alerts);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
