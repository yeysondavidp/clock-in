import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/record.dart';
import '../models/holiday.dart';
import '../models/setting.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('clockin.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE records (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        date        TEXT NOT NULL,
        start_time  TEXT,
        end_time    TEXT,
        total_hours REAL,
        otime_hours REAL,
        timestamp   TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE holidays (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        name      TEXT NOT NULL,
        date      TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        key       TEXT NOT NULL UNIQUE,
        value     TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');

    // Insert default settings on first install
    await _insertDefaultSettings(db);
    await _insertDefaultHolidays(db);
  }

  Future _insertDefaultSettings(Database db) async {
    final now = DateTime.now().toIso8601String();
    final defaults = [
      {'key': 'checkin_notification_time',  'value': '08:00'},
      {'key': 'checkout_notification_time', 'value': '16:00'},
      {'key': 'standard_work_hours',        'value': '8'},
      {'key': 'lunch_break_minutes', 'value': '30'},
      {'key': 'work_days',                  'value': '1,2,3,4,5'},
      {'key': 'notifications_enabled',      'value': 'true'},
    ];

    for (final s in defaults) {
      await db.insert('settings', {
        'key': s['key'],
        'value': s['value'],
        'timestamp': now,
      });
    }
  }

  Future _insertDefaultHolidays (Database db) async {
    final now = DateTime.now().toIso8601String();
    final holidays = [
      // ── 2026 ──────────────────────────────────────────────
      {'name': "New Year's Day",          'date': '2026-01-01'},
      {'name': "Australia Day",           'date': '2026-01-26'},
      {'name': "Good Friday",             'date': '2026-04-03'},
      {'name': "Easter Saturday",         'date': '2026-04-04'},
      {'name': "Easter Sunday",           'date': '2026-04-05'},
      {'name': "Easter Monday",           'date': '2026-04-06'},
      {'name': "Anzac Day",               'date': '2026-04-25'}, // Saturday
      {'name': "Anzac Day (observed)",    'date': '2026-04-27'}, // Monday — trial 2026/2027
      {'name': "King's Birthday",         'date': '2026-06-09'},
      {'name': "Labour Day",              'date': '2026-10-05'},
      {'name': "Christmas Day",           'date': '2026-12-25'},
      {'name': "Boxing Day (observed)",   'date': '2026-12-28'}, // Monday — Boxing Day falls Sunday

      // ── 2027 ──────────────────────────────────────────────
      {'name': "New Year's Day",          'date': '2027-01-01'},
      {'name': "Australia Day",           'date': '2027-01-26'},
      {'name': "Good Friday",             'date': '2027-03-26'},
      {'name': "Easter Saturday",         'date': '2027-03-27'},
      {'name': "Easter Sunday",           'date': '2027-03-28'},
      {'name': "Easter Monday",           'date': '2027-03-29'},
      {'name': "Anzac Day",               'date': '2027-04-25'}, // Sunday
      {'name': "Anzac Day (observed)",    'date': '2027-04-26'}, // Monday — trial 2026/2027
      {'name': "King's Birthday",         'date': '2027-06-14'},
      {'name': "Labour Day",              'date': '2027-10-04'},
      {'name': "Christmas Day",           'date': '2027-12-25'}, // Saturday
      {'name': "Christmas Day (observed)",'date': '2027-12-27'}, // Monday
      {'name': "Boxing Day",              'date': '2027-12-26'}, // Sunday
      {'name': "Boxing Day (observed)",   'date': '2027-12-28'}, // Tuesday
    ];

    for (final h in holidays) {
      await db.insert('holidays', {
        'name': h['name'],
        'date': h['date'],
        'timestamp': now,
      });
    }
  }

  // ─── RECORDS ────────────────────────────────────────────

  Future<int> insertRecord(Record record) async {
    final db = await instance.database;
    return await db.insert('records', record.toMap());
  }

  Future<Record?> getRecordByDate(String date) async {
    final db = await instance.database;
    final maps = await db.query(
      'records',
      where: 'date = ?',
      whereArgs: [date],
    );
    if (maps.isEmpty) return null;
    return Record.fromMap(maps.first);
  }

  Future<List<Record>> getAllRecords() async {
    final db = await instance.database;
    final result = await db.query('records', orderBy: 'date DESC');
    return result.map((map) => Record.fromMap(map)).toList();
  }

  Future<int> updateRecord(Record record) async {
    final db = await instance.database;
    return await db.update(
      'records',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<int> deleteRecord(int id) async {
    final db = await instance.database;
    return await db.delete('records', where: 'id = ?', whereArgs: [id]);
  }

  // ─── HOLIDAYS ───────────────────────────────────────────

  Future<int> insertHoliday(Holiday holiday) async {
    final db = await instance.database;
    return await db.insert('holidays', holiday.toMap());
  }

  Future<List<Holiday>> getAllHolidays() async {
    final db = await instance.database;
    final result = await db.query('holidays', orderBy: 'date ASC');
    return result.map((map) => Holiday.fromMap(map)).toList();
  }

  Future<bool> isHoliday(String date) async {
    final db = await instance.database;
    final maps = await db.query(
      'holidays',
      where: 'date = ?',
      whereArgs: [date],
    );
    return maps.isNotEmpty;
  }

  Future<int> deleteHoliday(int id) async {
    final db = await instance.database;
    return await db.delete('holidays', where: 'id = ?', whereArgs: [id]);
  }

  // ─── SETTINGS ───────────────────────────────────────────

  Future<String?> getSetting(String key) async {
    final db = await instance.database;
    final maps = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isEmpty) return null;
    return maps.first['value'] as String?;
  }

  Future<int> updateSetting(String key, String value) async {
    final db = await instance.database;
    return await db.update(
      'settings',
      {'value': value, 'timestamp': DateTime.now().toIso8601String()},
      where: 'key = ?',
      whereArgs: [key],
    );
  }

  Future<List<Record>> getRecordsByDateRange(String from, String to) async {
    final db = await instance.database;
    final result = await db.query(
      'records',
      where: 'date >= ? AND date <= ?',
      whereArgs: [from, to],
      orderBy: 'date ASC',
    );
    return result.map((map) => Record.fromMap(map)).toList();
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}