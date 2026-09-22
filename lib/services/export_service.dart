import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../models/day_summary.dart';
import '../models/day_type.dart';
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

    final workDays = await db.getWorkDays();
    final holidays = await db.getHolidayDates();

    // Build CSV data
    List<List<dynamic>> rows = [];

    // Header row
    rows.add([
      'Date',
      'Day Type',
      'Session',
      'Clock In',
      'Clock Out',
      'Regular Hours',
      'Overtime Hours',
      'Total Worked',
      'Status',
    ]);

    // Data rows — one per session
    var totals = const DaySummary();
    for (final record in records) {
      final dayType = DayType.resolve(DateTime.parse(record.date), workDays, holidays);
      final isComplete = record.isComplete;
      final totalWorked = isComplete
          ? (record.totalHours ?? 0) + (record.otimeHours ?? 0)
          : 0.0;

      if (isComplete) totals += DaySummary.fromSessions(dayType, [record]);

      rows.add([
        record.date,
        dayType.label,
        record.isExtra ? 'Extra' : 'Regular',
        record.startTime ?? '',
        record.endTime ?? '',
        isComplete ? TimeCalculator.formatHours(record.totalHours ?? 0) : '',
        isComplete ? TimeCalculator.formatHours(record.otimeHours ?? 0) : '',
        isComplete ? TimeCalculator.formatHours(totalWorked) : '',
        isComplete ? 'Complete' : 'Incomplete',
      ]);
    }

    // Summary rows at the bottom, with overtime broken down by source
    List<dynamic> summaryRow(String label, {double? regular, required double overtime, double? total}) => [
          label, '', '', '', '',
          regular != null ? TimeCalculator.formatHours(regular) : '',
          TimeCalculator.formatHours(overtime),
          total != null ? TimeCalculator.formatHours(total) : '',
          '',
        ];

    rows.add([]); // empty row separator
    rows.add(summaryRow('TOTAL',
        regular: totals.regular, overtime: totals.totalOvertime, total: totals.total));
    rows.add(summaryRow('Overtime — workdays', overtime: totals.overtime));
    rows.add(summaryRow('Overtime — weekends & holidays', overtime: totals.specialOvertime));

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