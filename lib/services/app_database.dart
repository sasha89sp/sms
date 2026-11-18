import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/operation_record.dart';
import 'app_paths.dart';

class AppDatabase {
  AppDatabase._(this._database);
  final Database _database;

  static Future<AppDatabase> open() async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      AppPaths.instance.dbFile,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async => _createAll(db),
        onUpgrade: (db, oldVersion, newVersion) async {
          await _createAll(db);
          if (oldVersion < 3) {
            try {
              await db.execute(
                  "ALTER TABLE scenario_runs ADD COLUMN fields_json TEXT NOT NULL DEFAULT ''");
            } catch (_) {
              // столбец уже существует
            }
          }
        },
      ),
    );
    return AppDatabase._(database);
  }

  static Future<void> _createAll(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS operations (
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
      CREATE TABLE IF NOT EXISTS logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at TEXT NOT NULL,
        level TEXT NOT NULL,
        message TEXT NOT NULL,
        raw TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scenario_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at TEXT NOT NULL,
        scenario_name TEXT NOT NULL,
        columns_json TEXT NOT NULL,
        cells_json TEXT NOT NULL DEFAULT '[]',
        fields_json TEXT NOT NULL DEFAULT '',
        balance_status TEXT NOT NULL DEFAULT '',
        success INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sims (
        sim_id TEXT PRIMARY KEY,
        phone TEXT NOT NULL DEFAULT '',
        operator TEXT NOT NULL DEFAULT '',
        last_seen TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sms_store (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        hash TEXT NOT NULL UNIQUE,
        sim_id TEXT NOT NULL,
        folder TEXT NOT NULL,
        sender TEXT NOT NULL,
        body TEXT NOT NULL,
        sms_time TEXT NOT NULL,
        saved_at TEXT NOT NULL,
        is_new INTEGER NOT NULL DEFAULT 1,
        modem_refs TEXT NOT NULL DEFAULT '',
        prev_folder TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  // ---- Операции и журнал -------------------------------------------------

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

  // ---- Результаты сценариев (для Excel) ---------------------------------

  Future<int> insertRun({
    required DateTime startedAt,
    required String scenarioName,
    required String fieldsJson,
    required String balanceStatus,
    required bool success,
  }) =>
      _database.insert('scenario_runs', {
        'started_at': startedAt.toIso8601String(),
        'scenario_name': scenarioName,
        'columns_json': '[]',
        'cells_json': '[]',
        'fields_json': fieldsJson,
        'balance_status': balanceStatus,
        'success': success ? 1 : 0,
      });

  Future<List<Map<String, Object?>>> allRuns() =>
      _database.query('scenario_runs', orderBy: 'id ASC');

  Future<int> runCount() async {
    final rows = await _database.rawQuery('SELECT COUNT(*) AS c FROM scenario_runs');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> clearRuns() async => _database.delete('scenario_runs');

  // ---- SIM-карты ---------------------------------------------------------

  Future<void> upsertSim({
    required String simId,
    String phone = '',
    String operator = '',
  }) async {
    final existing = await _database
        .query('sims', where: 'sim_id = ?', whereArgs: [simId], limit: 1);
    final now = DateTime.now().toIso8601String();
    if (existing.isEmpty) {
      await _database.insert('sims', {
        'sim_id': simId,
        'phone': phone,
        'operator': operator,
        'last_seen': now,
      });
    } else {
      final values = <String, Object?>{'last_seen': now};
      if (phone.isNotEmpty) values['phone'] = phone;
      if (operator.isNotEmpty) values['operator'] = operator;
      await _database
          .update('sims', values, where: 'sim_id = ?', whereArgs: [simId]);
    }
  }

  Future<Map<String, String>> simPhones() async {
    final rows = await _database.query('sims');
    return {
      for (final row in rows)
        '${row['sim_id']}': '${row['phone'] ?? ''}',
    };
  }

  // ---- SMS ---------------------------------------------------------------

  Future<bool> smsExists(String hash) async {
    final rows = await _database.query('sms_store',
        columns: ['id'], where: 'hash = ?', whereArgs: [hash], limit: 1);
    return rows.isNotEmpty;
  }

  Future<bool> insertSms({
    required String hash,
    required String simId,
    required String folder,
    required String sender,
    required String body,
    required String smsTime,
    String modemRefs = '',
    bool isNew = true,
  }) async {
    if (await smsExists(hash)) return false;
    await _database.insert('sms_store', {
      'hash': hash,
      'sim_id': simId,
      'folder': folder,
      'sender': sender,
      'body': body,
      'sms_time': smsTime,
      'saved_at': DateTime.now().toIso8601String(),
      'is_new': isNew ? 1 : 0,
      'modem_refs': modemRefs,
    });
    return true;
  }

  /// Входящие SMS, сохранённые после момента [since].
  Future<List<Map<String, Object?>>> incomingSince(DateTime since) =>
      _database.query('sms_store',
          where: "saved_at >= ? AND folder = 'inbox'",
          whereArgs: [since.toIso8601String()],
          orderBy: 'id ASC');

  Future<List<Map<String, Object?>>> smsByFolder(String folder,
          {int limit = 1000}) =>
      _database.query('sms_store',
          where: 'folder = ?',
          whereArgs: [folder],
          orderBy: 'sms_time DESC, id DESC',
          limit: limit);

  Future<Map<String, int>> smsCounts() async {
    final rows = await _database
        .rawQuery('SELECT folder, COUNT(*) AS c FROM sms_store GROUP BY folder');
    return {
      for (final row in rows)
        '${row['folder']}': (row['c'] as num?)?.toInt() ?? 0,
    };
  }

  Future<int> unreadCount() async {
    final rows = await _database.rawQuery(
        "SELECT COUNT(*) AS c FROM sms_store WHERE folder = 'inbox' AND is_new = 1");
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> trashSms(int id) => _database.rawUpdate(
      "UPDATE sms_store SET prev_folder = folder, folder = 'trash' WHERE id = ?",
      [id]);

  Future<void> restoreSms(int id) => _database.rawUpdate(
      "UPDATE sms_store SET folder = CASE WHEN prev_folder = '' THEN 'inbox' ELSE prev_folder END, prev_folder = '' WHERE id = ?",
      [id]);

  Future<void> markSmsRead(int id) => _database.update(
      'sms_store', {'is_new': 0},
      where: 'id = ?', whereArgs: [id]);

  Future<void> markAllSmsRead() => _database.update('sms_store', {'is_new': 0},
      where: "folder = 'inbox'");

  /// Окончательное удаление: текст стирается, а запись-«надгробие» остаётся,
  /// чтобы то же сообщение из памяти модема не вернулось при следующей
  /// синхронизации.
  Future<void> deleteSmsForever(int id) => _database.update(
      'sms_store', {'folder': 'purged', 'body': '', 'sender': ''},
      where: 'id = ?', whereArgs: [id]);

  Future<void> emptyTrash() => _database.update(
      'sms_store', {'folder': 'purged', 'body': '', 'sender': ''},
      where: "folder = 'trash'");

  Future<void> close() => _database.close();
}
