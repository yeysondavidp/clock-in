import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

class BackupException implements Exception {
  final String message;
  BackupException(this.message);

  @override
  String toString() => message;
}

class BackupService {
  static final BackupService instance = BackupService._init();
  BackupService._init();

  static const _requiredTables = ['records', 'holidays', 'settings'];

  // Copies the database to a timestamped file and opens the share sheet
  // so the user can save it to Drive, Files, email, etc.
  Future<void> exportBackup() async {
    final db = DatabaseHelper.instance;
    final source = File(await db.databaseFilePath);

    final dir = await getTemporaryDirectory();
    final backup = File(join(dir.path, 'clockin_backup_${_stamp()}.db'));

    // Close first so the copy never contains a half-written transaction
    await db.closeConnection();
    await source.copy(backup.path);

    await Share.shareXFiles(
      [XFile(backup.path, mimeType: 'application/octet-stream')],
      subject: 'Clock In backup',
    );
  }

  // Lets the user pick a backup file and replaces the current database with it.
  // Returns false if the user cancelled the picker.
  Future<bool> restoreBackup() async {
    final result = await FilePicker.pickFiles(type: FileType.any);
    final pickedPath = result?.files.single.path;
    if (pickedPath == null) return false;

    // Work on a private copy so the picked file is never modified
    final tempDir = await getTemporaryDirectory();
    final candidate = File(join(tempDir.path, 'restore_candidate.db'));
    await File(pickedPath).copy(candidate.path);

    try {
      await _validate(candidate.path);

      final db = DatabaseHelper.instance;
      final target = File(await db.databaseFilePath);

      // Keep a safety copy of the current data in case the restore was a mistake
      final safetyDir = Directory(
          join((await getApplicationDocumentsDirectory()).path, 'backups'));
      await safetyDir.create(recursive: true);

      await db.closeConnection();
      if (await target.exists()) {
        await target.copy(join(safetyDir.path, 'pre_restore_${_stamp()}.db'));
      }

      // Drop leftover journal files so they aren't replayed onto the new file
      for (final suffix in ['-journal', '-wal', '-shm']) {
        final f = File('${target.path}$suffix');
        if (await f.exists()) await f.delete();
      }
      await candidate.copy(target.path);

      // Reopen now so migrations run and errors surface here, not later
      await db.database;
      return true;
    } finally {
      if (await candidate.exists()) await candidate.delete();
    }
  }

  Future<void> _validate(String path) async {
    Database? db;
    try {
      db = await openDatabase(path, readOnly: true, singleInstance: false);
    } catch (_) {
      throw BackupException('The selected file is not a valid database.');
    }

    try {
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (integrity.first.values.first != 'ok') {
        throw BackupException('The backup file is corrupted.');
      }

      final tables = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((row) => row['name'] as String)
          .toSet();
      if (!_requiredTables.every(tables.contains)) {
        throw BackupException('The selected file is not a Clock In backup.');
      }

      final version = await db.getVersion();
      if (version > DatabaseHelper.schemaVersion) {
        throw BackupException(
            'This backup was made with a newer version of the app. Update the app first.');
      }
    } on DatabaseException {
      throw BackupException('The selected file is not a valid database.');
    } finally {
      await db.close();
    }
  }

  String _stamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
