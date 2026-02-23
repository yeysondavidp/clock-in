import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../models/record.dart';
import '../utils/time_calculator.dart';

class ExportService {
  static final ExportService instance = ExportService._init();
  ExportService._init();

  Future<void> exportRecordsToCSV(DateTime fromDate, DateTime toDate) async {
    final db = DatabaseHelper.instance;

    // Format dates for query
    final from = '${fromDate.year}-${fromDate.month.toString().padLeft(2, '0')}-${fromDate.day.toString().padLeft(2, '0')}';
    final to = '${toDate.year}-${toDate.month.toString().padLeft(2, '0')}-${toDate.day.toString().padLeft(2, '0')}';

    // Fetch records in range
    final records = await db.getRecordsByDateRange(from, to);

    if (records.isEmpty) {
      throw Exception('No records found for the selected date range.');
    }

    // Build CSV data
    List<List<dynamic>> rows = [];

    // Header row
    rows.add([
      'Date',
      'Clock In',
      'Clock Out',
      'Regular Hours',
      'Overtime Hours',
      'Total Worked',
      'Status',
    ]);

    // Data rows
    for (final record in records) {
      final isComplete = record.endTime != null;
      final totalWorked = isComplete
          ? (record.totalHours ?? 0) + (record.otimeHours ?? 0)
          : 0.0;

      rows.add([
        record.date,
        record.startTime ?? '',
        record.endTime ?? '',
        isComplete ? TimeCalculator.formatHours(record.totalHours ?? 0) : '',
        isComplete ? TimeCalculator.formatHours(record.otimeHours ?? 0) : '',
        isComplete ? TimeCalculator.formatHours(totalWorked) : '',
        isComplete ? 'Complete' : 'Incomplete',
      ]);
    }

    // Add summary row at the bottom
    final totalRegular = records.fold<double>(
        0, (sum, r) => sum + (r.totalHours ?? 0));
    final totalOvertime = records.fold<double>(
        0, (sum, r) => sum + (r.otimeHours ?? 0));

    rows.add([]); // empty row separator
    rows.add([
      'TOTAL',
      '',
      '',
      TimeCalculator.formatHours(totalRegular),
      TimeCalculator.formatHours(totalOvertime),
      TimeCalculator.formatHours(totalRegular + totalOvertime),
      '',
    ]);

    // Convert to CSV string
    final csvString = const ListToCsvConverter().convert(rows);

    // Save to temp directory
    final directory = await getTemporaryDirectory();
    final fileName = 'clock_in_${from}_to_${to}.csv';
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(csvString);

    // Share the file — lets user save to Drive, email, etc.
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Clock In Records $from to $to',
    );
  }
}