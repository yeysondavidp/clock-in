import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../models/day_type.dart';
import '../models/record.dart';
import 'timesheet_filler.dart';

// A filled copy of the user's timesheet, waiting to be shared
class TimesheetExport {
  final File file;
  final TimesheetResult result;
  const TimesheetExport(this.file, this.result);
}

class TimesheetExportService {
  static final TimesheetExportService instance = TimesheetExportService._init();
  TimesheetExportService._init();

  static const _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  // Asks for the user's timesheet and fills a copy of it with the records
  // in range. Returns null if the user cancelled the picker.
  Future<TimesheetExport?> fill(DateTime fromDate, DateTime toDate) async {
    final entries = await _entries(fromDate, toDate);
    if (entries.isEmpty) {
      throw TimesheetException('No records found for the selected date range.');
    }

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    final pickedPath = picked?.files.single.path;
    if (pickedPath == null) return null;

    final result = TimesheetFiller.fill(await File(pickedPath).readAsBytes(), entries);

    // Same name as the original so it can replace it once saved
    final dir = await getTemporaryDirectory();
    final file = File(join(dir.path, picked!.files.single.name));
    await file.writeAsBytes(result.bytes);
    return TimesheetExport(file, result);
  }

  Future<void> share(TimesheetExport export) async {
    await Share.shareXFiles(
      [XFile(export.file.path, mimeType: _xlsxMime)],
      subject: basenameWithoutExtension(export.file.path),
    );
  }

  Future<List<TimesheetEntry>> _entries(DateTime fromDate, DateTime toDate) async {
    final db = DatabaseHelper.instance;
    final records = await db.getRecordsByDateRange(_key(fromDate), _key(toDate));
    final workDays = await db.getWorkDays();
    final holidays = {for (final h in await db.getAllHolidays()) h.date: h.name};

    final byDate = <String, List<Record>>{};
    for (final r in records) {
      byDate.putIfAbsent(r.date, () => []).add(r);
    }

    final entries = <TimesheetEntry>[];
    for (var day = DateTime(fromDate.year, fromDate.month, fromDate.day);
        !day.isAfter(toDate);
        day = DateTime(day.year, day.month, day.day + 1)) {
      final key = _key(day);
      // Open sessions have no end time yet, so they can't go in the sheet
      final sessions = (byDate[key] ?? []).where((s) => s.isComplete).toList();
      final regular = sessions.where((s) => !s.isExtra).firstOrNull;
      final extras = sessions.where((s) => s.isExtra).toList();

      if (sessions.isNotEmpty) {
        entries.add(TimesheetEntry(
          date: day,
          start: regular?.startTime,
          end: regular?.endTime,
          note: extras.isEmpty
              ? null
              : 'Overtime ${extras.map((s) => '${s.startTime}–${s.endTime}').join(', ')}',
        ));
      } else if (holidays.containsKey(key) &&
          DayType.resolve(day, workDays, const {}).isWorkday) {
        // Holidays on weekends are left blank, like in the template
        entries.add(TimesheetEntry(date: day, holidayName: holidays[key]));
      }
    }

    // A range with only holidays has nothing worth exporting
    return entries.any((e) => e.holidayName == null) ? entries : const [];
  }

  String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
