import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/permissions.dart';

/// Deux bases SQLite STRICTEMENT séparées, chacune dans son propre fichier :
/// - `mbb_comptabilite.db`    : comptes, journal et données financières ;
/// - `mbb_cartes_annonces.db` : comptes, journal, membres, présences, annonces.
/// Une session n'accède qu'à la base de son bureau (`AppDatabase.instance`).
/// Fonctionne sans connexion internet.
class AppDatabase {
  AppDatabase._(this.bureau, this.fileName);

  static const schemaVersion = 5;
  static const legacyFileName = 'mbb_database.db';

  final Bureau bureau;
  final String fileName;
  Database? _db;

  static final accounting = AppDatabase._(Bureau.comptabilite, 'mbb_comptabilite.db');
  static final cards = AppDatabase._(Bureau.cartesAnnonces, 'mbb_cartes_annonces.db');

  /// Bureau de la session ouverte (défini à la connexion).
  static Bureau? activeBureau;

  static AppDatabase forBureau(Bureau b) => b == Bureau.comptabilite ? accounting : cards;

  static AppDatabase get instance {
    final b = activeBureau;
    if (b == null) throw StateError('Aucune session ouverte.');
    return forBureau(b);
  }

  /// Texte enregistré dans `users.service_access` pour chaque bureau.
  static String userLabel(Bureau b) =>
      b == Bureau.comptabilite ? 'Comptabilité' : 'Services des cartes et annonces';

  static bool _factoryReady = false;
  static Future<void>? _legacyMigration;

  static Future<void> _prepare() async {
    if (_factoryReady) return;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _factoryReady = true;
  }

  static Future<String> directoryPath() async {
    final dir = await getApplicationSupportDirectory();
    await Directory(dir.path).create(recursive: true);
    return dir.path;
  }

  Future<String> filePath() async => p.join(await directoryPath(), fileName);

  /// Ouvre les deux bases (et migre l'ancienne base unique si elle existe).
  static Future<void> openAll() async {
    await accounting.database;
    await cards.database;
  }

  /// Ancienne installation : une seule base `mbb_database.db`. Elle est mise à
  /// niveau, copiée vers les deux nouveaux fichiers, puis conservée en
  /// `.legacy.bak`. Aucune donnée n'est supprimée de l'original.
  static Future<void> _migrateLegacy() async {
    final dir = await directoryPath();
    final legacy = File(p.join(dir, legacyFileName));
    final accFile = File(p.join(dir, accounting.fileName));
    final cardsFile = File(p.join(dir, cards.fileName));
    if (!await legacy.exists() || await accFile.exists() || await cardsFile.exists()) return;
    final old = await openDatabase(
      legacy.path,
      version: 4,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: _legacyUpgrade,
    );
    await old.close();
    await legacy.copy(accFile.path);
    await legacy.copy(cardsFile.path);
    await legacy.rename(p.join(dir, '$legacyFileName.legacy.bak'));
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    await _prepare();
    _legacyMigration ??= _migrateLegacy();
    await _legacyMigration;
    _db = await openDatabase(
      await filePath(),
      version: schemaVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) => _createSchema(db, bureau),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 5) await _splitUpgrade(db, bureau);
      },
    );
    return _db!;
  }

  // ---------------------------------------------------------------- schéma

  static Future<void> _createCommon(Database db) async {
    await db.execute('''CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL, salt TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'Utilisateur',
      service_access TEXT NOT NULL DEFAULT 'Services des cartes et annonces',
      is_first_admin INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL)''');
    await db.execute('CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await db.execute('''CREATE TABLE audit_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT NOT NULL DEFAULT '',
      action TEXT NOT NULL, details TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)''');
    await db.insert('app_settings', {'key': 'church_name', 'value': 'Mission Baptiste Béraca'});
    await db.insert('app_settings', {'key': 'app_name', 'value': 'MBB'});
    await db.insert('app_settings', {'key': 'language', 'value': 'Français'});
    await db.insert('app_settings', {'key': 'theme_color', 'value': '0xff0A2A66'});
  }

  static Future<void> _createAccounting(Database db) async {
    await db.execute('CREATE TABLE finance_categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, kind TEXT NOT NULL)');
    await db.execute('''CREATE TABLE transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, category TEXT NOT NULL,
      amount REAL NOT NULL, transaction_date TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
      group_id INTEGER, payment_method TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL,
      uid TEXT NOT NULL DEFAULT '', reference TEXT NOT NULL DEFAULT '')''');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_uid ON transactions(uid)');
    for (final c in const [['Dîmes', 'Recette'], ['Offrandes', 'Recette'], ['Dons', 'Recette'], ['Loyer', 'Dépense'], ['Électricité', 'Dépense']]) {
      await db.insert('finance_categories', {'name': c[0], 'kind': c[1]});
    }
  }

  static Future<void> _createCards(Database db) async {
    await db.execute('''CREATE TABLE families (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, address TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE members (
      id INTEGER PRIMARY KEY AUTOINCREMENT, first_name TEXT NOT NULL, last_name TEXT NOT NULL,
      phone TEXT NOT NULL DEFAULT '', email TEXT NOT NULL DEFAULT '', gender TEXT NOT NULL DEFAULT '',
      birth_date TEXT NOT NULL DEFAULT '', address TEXT NOT NULL DEFAULT '', family_id INTEGER,
      photo_path TEXT NOT NULL DEFAULT '', baptized INTEGER NOT NULL DEFAULT 0,
      church_role TEXT NOT NULL DEFAULT '', sunday_school_class_id INTEGER,
      status TEXT NOT NULL DEFAULT 'Actif', notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL,
      FOREIGN KEY(family_id) REFERENCES families(id) ON DELETE SET NULL)''');
    await db.execute('''CREATE TABLE groups_classes (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, item_type TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '', leader_name TEXT NOT NULL DEFAULT '',
      monthly_contribution REAL NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE member_groups (
      member_id INTEGER NOT NULL, group_id INTEGER NOT NULL, PRIMARY KEY(member_id, group_id),
      FOREIGN KEY(member_id) REFERENCES members(id) ON DELETE CASCADE,
      FOREIGN KEY(group_id) REFERENCES groups_classes(id) ON DELETE CASCADE)''');
    await db.execute('''CREATE TABLE announcements (
      id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL,
      target_group TEXT NOT NULL DEFAULT 'Tous les membres', description TEXT NOT NULL,
      announcement_date TEXT NOT NULL, signature TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'Brouillon', created_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE services (
      id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, service_date TEXT NOT NULL,
      notes TEXT NOT NULL DEFAULT '', start_time TEXT NOT NULL DEFAULT '')''');
    await db.execute('''CREATE TABLE attendance (
      id INTEGER PRIMARY KEY AUTOINCREMENT, member_id INTEGER NOT NULL, service_id INTEGER,
      service_date TEXT NOT NULL, status TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
      check_in_time TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL,
      FOREIGN KEY(member_id) REFERENCES members(id) ON DELETE CASCADE,
      FOREIGN KEY(service_id) REFERENCES services(id) ON DELETE SET NULL)''');
    await db.insert('app_settings', {'key': 'late_after_minutes', 'value': '15'});
  }

  static Future<void> _createSchema(Database db, Bureau bureau) async {
    await _createCommon(db);
    if (bureau == Bureau.comptabilite) {
      await _createAccounting(db);
    } else {
      await _createCards(db);
    }
  }

  /// Passage de l'ancienne base unique (v4) à une base par bureau (v5) :
  /// supprime UNIQUEMENT de la copie les tables et comptes de l'autre bureau.
  static Future<void> _splitUpgrade(Database db, Bureau bureau) async {
    final other = bureau == Bureau.comptabilite
        ? const ['attendance', 'member_groups', 'members', 'families', 'groups_classes', 'announcements', 'services']
        : const ['transactions', 'finance_categories'];
    for (final t in other) {
      await db.execute('DROP TABLE IF EXISTS $t');
    }
    await db.delete('users', where: 'service_access <> ?', whereArgs: [userLabel(bureau)]);
    if (bureau == Bureau.cartesAnnonces) {
      Future<void> addColumn(String table, String column, String definition) async {
        final info = await db.rawQuery('PRAGMA table_info($table)');
        if (!info.any((r) => r['name'] == column)) {
          await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
        }
      }
      await addColumn('services', 'start_time', "TEXT NOT NULL DEFAULT ''");
      await addColumn('attendance', 'check_in_time', "TEXT NOT NULL DEFAULT ''");
      // Anciennes présences saisies par date : rattachées au culte de ce jour.
      await db.execute('UPDATE attendance SET service_id = (SELECT s.id FROM services s WHERE s.service_date = attendance.service_date ORDER BY s.id LIMIT 1) WHERE service_id IS NULL');
      final rows = await db.query('app_settings', where: 'key = ?', whereArgs: ['late_after_minutes']);
      if (rows.isEmpty) await db.insert('app_settings', {'key': 'late_after_minutes', 'value': '15'});
    }
  }

  /// Mise à niveau de l'ancienne base unique jusqu'à la v4 (avant séparation).
  static Future<void> _legacyUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
          Future<void> addColumn(String table, String column, String definition) async {
            final info = await db.rawQuery('PRAGMA table_info($table)');
            if (!info.any((row) => row['name'] == column)) {
              await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
            }
          }
          await addColumn('users', 'service_access', "TEXT NOT NULL DEFAULT 'Services des cartes et annonces'");
          await addColumn('users', 'is_first_admin', 'INTEGER NOT NULL DEFAULT 0');
          await addColumn('members', 'photo_path', "TEXT NOT NULL DEFAULT ''");
          await addColumn('members', 'baptized', 'INTEGER NOT NULL DEFAULT 0');
          await addColumn('members', 'church_role', "TEXT NOT NULL DEFAULT ''");
          await addColumn('members', 'sunday_school_class_id', 'INTEGER');
          await addColumn('transactions', 'group_id', 'INTEGER');
          await addColumn('transactions', 'payment_method', "TEXT NOT NULL DEFAULT ''");
          await db.execute('''CREATE TABLE IF NOT EXISTS groups_classes (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, item_type TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '', leader_name TEXT NOT NULL DEFAULT '',
            monthly_contribution REAL NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL)''');
          await db.execute('''CREATE TABLE IF NOT EXISTS member_groups (
            member_id INTEGER NOT NULL, group_id INTEGER NOT NULL, PRIMARY KEY(member_id, group_id),
            FOREIGN KEY(member_id) REFERENCES members(id) ON DELETE CASCADE,
            FOREIGN KEY(group_id) REFERENCES groups_classes(id) ON DELETE CASCADE)''');
          await db.execute('''CREATE TABLE IF NOT EXISTS announcements (
            id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL,
            target_group TEXT NOT NULL DEFAULT 'Tous les membres', description TEXT NOT NULL,
            announcement_date TEXT NOT NULL, signature TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'Brouillon', created_at TEXT NOT NULL)''');
        }
    if (oldVersion < 3) {
          await db.execute('''CREATE TABLE IF NOT EXISTS groups_classes (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, item_type TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '', leader_name TEXT NOT NULL DEFAULT '',
            monthly_contribution REAL NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL)''');
          await db.execute('''CREATE TABLE IF NOT EXISTS member_groups (
            member_id INTEGER NOT NULL, group_id INTEGER NOT NULL,
            PRIMARY KEY(member_id, group_id),
            FOREIGN KEY(member_id) REFERENCES members(id) ON DELETE CASCADE,
            FOREIGN KEY(group_id) REFERENCES groups_classes(id) ON DELETE CASCADE)''');
          await db.execute('''CREATE TABLE IF NOT EXISTS announcements (
            id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL,
            target_group TEXT NOT NULL DEFAULT 'Tous les membres', description TEXT NOT NULL,
            announcement_date TEXT NOT NULL, signature TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'Brouillon', created_at TEXT NOT NULL)''');
          final memberInfo = await db.rawQuery('PRAGMA table_info(members)');
          Future<void> addMemberColumn(String name, String definition) async {
            if (!memberInfo.any((row) => row['name'] == name)) {
              await db.execute('ALTER TABLE members ADD COLUMN $name $definition');
            }
          }
          await addMemberColumn('photo_path', "TEXT NOT NULL DEFAULT ''");
          await addMemberColumn('baptized', 'INTEGER NOT NULL DEFAULT 0');
          await addMemberColumn('church_role', "TEXT NOT NULL DEFAULT ''");
          await addMemberColumn('sunday_school_class_id', 'INTEGER');
          final txInfo = await db.rawQuery('PRAGMA table_info(transactions)');
          if (!txInfo.any((row) => row['name'] == 'group_id')) await db.execute('ALTER TABLE transactions ADD COLUMN group_id INTEGER');
          if (!txInfo.any((row) => row['name'] == 'payment_method')) await db.execute("ALTER TABLE transactions ADD COLUMN payment_method TEXT NOT NULL DEFAULT ''");
        }
    if (oldVersion < 4) {
          // Identité unique de chaque opération, pour l'échange entre appareils.
          final info = await db.rawQuery('PRAGMA table_info(transactions)');
          if (!info.any((row) => row['name'] == 'uid')) await db.execute("ALTER TABLE transactions ADD COLUMN uid TEXT NOT NULL DEFAULT ''");
          if (!info.any((row) => row['name'] == 'reference')) await db.execute("ALTER TABLE transactions ADD COLUMN reference TEXT NOT NULL DEFAULT ''");
          await db.execute("UPDATE transactions SET uid = lower(hex(randomblob(16))) WHERE uid = ''");
          await db.execute("UPDATE transactions SET reference = 'TX-' || upper(substr(uid, 1, 8)) WHERE reference = ''");
          await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_uid ON transactions(uid)');
        }
  }

  // ------------------------------------------------------- outils communs

  /// Ferme la base et oublie le handle : la prochaine requête la rouvre
  /// (nécessaire après le remplacement du fichier lors d'une restauration).
  Future<void> closeAndReset() async {
    final db = _db;
    _db = null;
    if (db != null) await db.close();
  }

  /// Vérifie qu'un fichier est une sauvegarde exploitable POUR CE BUREAU.
  /// Une sauvegarde contenant aussi les tables de l'autre bureau (ancien
  /// format) est refusée afin de ne jamais mélanger les deux bases.
  static Future<String?> validateBackupFile(String path, Bureau bureau) async {
    Database? probe;
    try {
      probe = await openReadOnlyDatabase(path);
      final check = await probe.rawQuery('PRAGMA integrity_check');
      if (check.isEmpty || '${check.first.values.first}' != 'ok') {
        return 'Le fichier est endommagé (contrôle d’intégrité échoué).';
      }
      final tables = (await probe.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((r) => '${r['name']}').toSet();
      final required = bureau == Bureau.comptabilite
          ? const ['users', 'app_settings', 'transactions']
          : const ['users', 'app_settings', 'members', 'attendance'];
      final forbidden = bureau == Bureau.comptabilite
          ? const ['members', 'attendance']
          : const ['transactions'];
      for (final t in required) {
        if (!tables.contains(t)) return 'Ce fichier n’est pas une sauvegarde de ce bureau (table « $t » absente).';
      }
      for (final t in forbidden) {
        if (tables.contains(t)) return 'Cette sauvegarde contient aussi les données de l’autre bureau (ancien format) : elle est refusée pour garder les deux bases séparées.';
      }
      final v = (await probe.rawQuery('PRAGMA user_version')).first.values.first as int;
      if (v != schemaVersion) return 'Version de sauvegarde incompatible ($v ; attendue $schemaVersion).';
      return null;
    } catch (_) {
      return 'Le fichier n’est pas une base SQLite lisible.';
    } finally {
      await probe?.close();
    }
  }

  Future<List<Map<String, Object?>>> query(String table,
      {String? where, List<Object?>? whereArgs, String? orderBy}) async {
    final db = await database;
    return db.query(table, where: where, whereArgs: whereArgs, orderBy: orderBy);
  }

  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? args]) async {
    final db = await database;
    return db.rawQuery(sql, args);
  }

  /// Vrai sur un appareil en consultation : toute écriture métier est refusée ici,
  /// dans la couche données (seuls le journal d'audit et le renouvellement du
  /// hachage d'un mot de passe restent permis).
  static bool readOnly = false;

  void _guardWrite(String table, {bool isUpdate = false}) {
    if (!readOnly) return;
    if (table == 'audit_logs' || (isUpdate && table == 'users')) return;
    throw ReadOnlyDeviceException();
  }

  static String newUid() {
    final r = Random.secure();
    return List<int>.generate(16, (_) => r.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<int> insert(String table, Map<String, Object?> values) async {
    _guardWrite(table);
    final db = await database;
    if (table == 'transactions' && '${values['uid'] ?? ''}'.isEmpty) {
      final uid = newUid();
      values = {...values, 'uid': uid, 'reference': 'TX-${uid.substring(0, 8).toUpperCase()}'};
    }
    return db.insert(table, values, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<int> update(String table, Map<String, Object?> values,
      {required String where, required List<Object?> whereArgs}) async {
    _guardWrite(table, isUpdate: true);
    final db = await database;
    return db.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(String table,
      {required String where, required List<Object?> whereArgs}) async {
    _guardWrite(table);
    final db = await database;
    return db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<int> count(String table) async {
    final db = await database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM $table');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<double> financeTotal(String kind) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM transactions WHERE kind = ?',
      [kind],
    );
    return (rows.first['total'] as num).toDouble();
  }

  Future<String> setting(String key, String fallback) async {
    final rows = await query('app_settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? fallback : '${rows.first['value']}';
  }

  Future<void> log(String action, String details, {String username = 'local'}) async {
    final db = await database;
    await db.insert('audit_logs', {
      'username': username,
      'action': action,
      'details': details,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}

class ReadOnlyDeviceException implements Exception {
  String get message =>
      'Cet appareil est en mode consultation : l’enregistrement de données est réservé à l’appareil principal.';
  @override
  String toString() => message;
}
