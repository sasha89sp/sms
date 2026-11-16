import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/operation_record.dart';

class AppDatabase {
  AppDatabase._(this._database);
  final Database _database;

  static Future<AppDatabase> open() async {
    sqfliteFfiInit();
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final dbPath = p.join(directory.path, 'huawei_modem_manager.db');
    final database = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE operations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              started_at TEXT NOT NULL,
              finished_at TEXT NOT NULL,
              phone_response TEXT NOT NULL,
              balance_before TEXT NOT NULL,
              sms_status TEXT NOT NULL,
              balance_after TEXT NOT NULL,
              success INTEGER NOT NULL,
              details TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              created_at TEXT NOT NULL,
              level TEXT NOT NULL,
              message TEXT NOT NULL,
              raw TEXT NOT NULL DEFAULT ''
            )
          ''');
        },
      ),
    );
    return AppDatabase._(database);
  }

  Future<int> insertOperation(OperationRecord record) =>
      _database.insert('operations', record.toMap());

  Future<int> insertLog({
    required DateTime at,
    required String level,
    required String message,
    String raw = '',
  }) =>
      _database.insert('logs', {
        'created_at': at.toIso8601String(),
        'level': level,
        'message': message,
        'raw': raw,
      });

  Future<List<Map<String, Object?>>> recentOperations({int limit = 50}) =>
      _database.query('operations', orderBy: 'id DESC', limit: limit);

  Future<List<Map<String, Object?>>> recentLogs({int limit = 250}) =>
      _database.query('logs', orderBy: 'id DESC', limit: limit);

  Future<void> clearLogs() async => _database.delete('logs');

  Future<void> close() => _database.close();
}
