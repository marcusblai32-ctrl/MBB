import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite local : fonctionne sans connexion internet.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    await Directory(dir.path).create(recursive: true);
    final path = p.join(dir.path, 'mbb_database.db');
    _db = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            salt TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'Administrateur',
            active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE members (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            first_name TEXT NOT NULL,
            last_name TEXT NOT NULL,
            phone TEXT NOT NULL DEFAULT '',
            email TEXT NOT NULL DEFAULT '',
            gender TEXT NOT NULL DEFAULT '',
            birth_date TEXT NOT NULL DEFAULT '',
            address TEXT NOT NULL DEFAULT '',
            family_id INTEGER,
            status TEXT NOT NULL DEFAULT 'Actif',
            notes TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            FOREIGN KEY(family_id) REFERENCES families(id) ON DELETE SET NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE families (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            address TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE services (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            service_date TEXT NOT NULL,
            notes TEXT NOT NULL DEFAULT ''
          )
        ''');
        await db.execute('''
          CREATE TABLE attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            member_id INTEGER NOT NULL,
            service_id INTEGER,
            service_date TEXT NOT NULL,
            status TEXT NOT NULL,
            notes TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            FOREIGN KEY(member_id) REFERENCES members(id) ON DELETE CASCADE,
            FOREIGN KEY(service_id) REFERENCES services(id) ON DELETE SET NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE finance_categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            kind TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            category TEXT NOT NULL,
            amount REAL NOT NULL,
            transaction_date TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE app_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE audit_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL DEFAULT '',
            action TEXT NOT NULL,
            details TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL
          )
        ''');
        await db.insert('app_settings', {'key': 'church_name', 'value': 'Mission Baptiste Béraca'});
        await db.insert('app_settings', {'key': 'app_name', 'value': 'MBB'});
        await db.insert('app_settings', {'key': 'language', 'value': 'Français'});
        await db.insert('app_settings', {'key': 'theme_color', 'value': '0xff17365D'});
        await db.insert('finance_categories', {'name': 'Dîmes', 'kind': 'Recette'});
        await db.insert('finance_categories', {'name': 'Offrandes', 'kind': 'Recette'});
        await db.insert('finance_categories', {'name': 'Dons', 'kind': 'Recette'});
        await db.insert('finance_categories', {'name': 'Loyer', 'kind': 'Dépense'});
        await db.insert('finance_categories', {'name': 'Électricité', 'kind': 'Dépense'});
      },
    );
    return _db!;
  }

  Future<List<Map<String, Object?>>> query(String table,
      {String? where, List<Object?>? whereArgs, String? orderBy}) async {
    final db = await database;
    return db.query(table, where: where, whereArgs: whereArgs, orderBy: orderBy);
  }

  Future<int> insert(String table, Map<String, Object?> values) async {
    final db = await database;
    return db.insert(table, values, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<int> update(String table, Map<String, Object?> values,
      {required String where, required List<Object?> whereArgs}) async {
    final db = await database;
    return db.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(String table,
      {required String where, required List<Object?> whereArgs}) async {
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

  Future<void> log(String action, String details) async {
    final db = await database;
    await db.insert('audit_logs', {
      'username': 'local',
      'action': action,
      'details': details,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
