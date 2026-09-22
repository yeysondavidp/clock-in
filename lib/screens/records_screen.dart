import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/day_summary.dart';
import '../models/day_type.dart';
import '../models/record.dart';
import '../services/session_service.dart';
import '../utils/time_calculator.dart';
import '../services/export_service.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final db = DatabaseHelper.instance;
  List<_Day> _days = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await db.getAllRecords();
    final workDays = await db.getWorkDays();
    final holidays = await db.getHolidayDates();

    // Records come sorted by date, so sessions of a day are adjacent
    final days = <_Day>[];
    for (final r in records) {
      if (days.isEmpty || days.last.date != r.date) {
        days.add(_Day(r.date,
            DayType.resolve(DateTime.parse(r.date), workDays, holidays), []));
      }
      days.last.sessions.add(r);
    }

    setState(() {
      _days = days;
      _isLoading = false;
    });
  }

  // ─── EDIT DIALOG ────────────────────────────────────────

  Future<void> _showEditDialog(Record record) async {
    // Controllers pre-filled with existing values
    final startController = TextEditingController(text: record.startTime ?? '');
    final endController = TextEditingController(text: record.endTime ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${DateFormat('MMM d, yyyy').format(DateTime.parse(record.date))}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Start time field
            TextField(
              controller: startController,
              decoration: const InputDecoration(
                labelText: 'Clock In',
                hintText: 'HH:mm',
                prefixIcon: Icon(Icons.login),
              ),
              keyboardType: TextInputType.datetime,
              onTap: () => _pickTime(context, startController),
              readOnly: true,
            ),

            const SizedBox(height: 16),

            // End time field
            TextField(
              controller: endController,
              decoration: const InputDecoration(
                labelText: 'Clock Out',
                hintText: 'HH:mm',
                prefixIcon: Icon(Icons.logout),
              ),
              keyboardType: TextInputType.datetime,
              onTap: () => _pickTime(context, endController),
              readOnly: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _saveEdit(record, startController.text, endController.text);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Opens native time picker and sets value in controller
  Future<void> _pickTime(BuildContext context, TextEditingController controller) async {
    final parts = controller.text.isNotEmpty
        ? controller.text.split(':')
        : ['08', '00'];

    final initial = TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );

    final picked = await showTimePicker(context: context, initialTime: initial);

    if (picked != null) {
      controller.text =
      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _saveEdit(Record record, String startTime, String endTime) async {
    final updatedRecord = await SessionService.instance.withTimes(
      record,
      startTime: startTime.isNotEmpty ? startTime : null,
      endTime: endTime.isNotEmpty ? endTime : null,
    );

    await db.updateRecord(updatedRecord);
    await _loadRecords();
  }

  // ─── ADD SESSION ────────────────────────────────────────

  Future<void> _showAddDialog() async {
    final startController = TextEditingController();
    final endController = TextEditingController();
    DateTime date = DateTime.now();
    String type = Record.typeRegular;
    DayType dayType = DayType.workday;
    bool hasRegular = false;

    // Weekends, holidays and days that already have a regular session
    // can only take extra sessions
    Future<void> loadDay() async {
      final key = DateFormat('yyyy-MM-dd').format(date);
      dayType = await db.getDayType(key);
      hasRegular = (await db.getRecordsByDate(key)).any((s) => !s.isExtra);
      if (!dayType.isWorkday || hasRegular) type = Record.typeExtra;
    }

    await loadDay();
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final canBeRegular = dayType.isWorkday && !hasRegular;
          final crossesMidnight = startController.text.isNotEmpty &&
              endController.text.isNotEmpty &&
              endController.text.compareTo(startController.text) < 0;

          return AlertDialog(
            title: const Text('Add Session'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Date'),
                    subtitle: Text(DateFormat('EEE, MMM d yyyy').format(date)),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2024),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        date = picked;
                        await loadDay();
                        setDialogState(() {});
                      }
                    },
                  ),

                  if (!dayType.isWorkday)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                          '${dayType.label} — the whole session counts as overtime',
                          style: TextStyle(color: Colors.purple.shade700, fontSize: 13)),
                    ),

                  if (canBeRegular)
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: Record.typeRegular, label: Text('Regular')),
                        ButtonSegment(value: Record.typeExtra, label: Text('Extra')),
                      ],
                      selected: {type},
                      onSelectionChanged: (v) => setDialogState(() => type = v.first),
                    ),

                  const SizedBox(height: 8),

                  TextField(
                    controller: startController,
                    decoration: const InputDecoration(
                      labelText: 'Start',
                      hintText: 'HH:mm',
                      prefixIcon: Icon(Icons.login),
                    ),
                    readOnly: true,
                    onTap: () async {
                      await _pickTime(context, startController);
                      setDialogState(() {});
                    },
                  ),

                  const SizedBox(height: 16),

                  TextField(
                    controller: endController,
                    decoration: InputDecoration(
                      labelText: 'End',
                      hintText: 'HH:mm',
                      prefixIcon: const Icon(Icons.logout),
                      helperText: crossesMidnight ? 'Ends the next day' : null,
                    ),
                    readOnly: true,
                    onTap: () async {
                      await _pickTime(context, endController);
                      setDialogState(() {});
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: startController.text.isEmpty ||
                        endController.text.isEmpty ||
                        startController.text == endController.text
                    ? null
                    : () async {
                        await _saveNew(date, type, startController.text, endController.text);
                        if (context.mounted) Navigator.pop(context);
                      },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveNew(DateTime date, String type, String startTime, String endTime) async {
    final session = Record(
      date: DateFormat('yyyy-MM-dd').format(date),
      type: type,
      timestamp: DateTime.now().toIso8601String(),
    );

    await db.insertRecord(await SessionService.instance
        .withTimes(session, startTime: startTime, endTime: endTime));
    await _loadRecords();
  }

  // ─── DELETE ─────────────────────────────────────────────

  Future<void> _confirmDelete(Record record) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Record'),
        content: Text(
            'Are you sure you want to delete the ${record.isExtra ? 'extra' : 'regular'} session '
            '(${record.startTime ?? '--:--'} – ${record.endTime ?? '--:--'}) of '
            '${DateFormat('MMM d, yyyy').format(DateTime.parse(record.date))}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await db.deleteRecord(record.id!);
              await _loadRecords();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showExportDialog() async {
    DateTime fromDate = DateTime.now().subtract(const Duration(days: 30));
    DateTime toDate = DateTime.now();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Export Records'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // From date
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('From'),
                subtitle: Text(
                    '${fromDate.year}-${fromDate.month.toString().padLeft(2, '0')}-${fromDate.day.toString().padLeft(2, '0')}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: fromDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setDialogState(() => fromDate = picked);
                  }
                },
              ),

              // To date
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('To'),
                subtitle: Text(
                    '${toDate.year}-${toDate.month.toString().padLeft(2, '0')}-${toDate.day.toString().padLeft(2, '0')}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: toDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setDialogState(() => toDate = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Export'),
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await ExportService.instance.exportRecordsToCSV(fromDate, toDate);
                } catch (e) {
                  if (mounted) {
                    _showMessage(e.toString().replaceAll('Exception: ', ''));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ─── UI ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Records'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _showExportDialog,
            tooltip: 'Export to CSV',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: 'Add session',
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _days.isEmpty
          ? const Center(child: Text('No records yet.'))
          : ListView.builder(
        padding: const EdgeInsets.only(bottom: 80), // room for the FAB
        itemCount: _days.length,
        itemBuilder: (context, index) {
          return _buildDayCard(_days[index]);
        },
      ),
    );
  }

  // Same card as a single-session day: the main session's times and the
  // day totals. Extra sessions are listed in the details sheet.
  Widget _buildDayCard(_Day day) {
    final date = DateFormat('EEE, MMM d yyyy').format(DateTime.parse(day.date));
    final main = day.main;
    final extras = day.sessions.length - 1;
    final isComplete = day.sessions.every((s) => s.isComplete);
    final summary = DaySummary.fromSessions(
        day.dayType, day.sessions.where((s) => s.isComplete).toList());
    final special = !day.dayType.isWorkday;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: special
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.purple.shade200),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDayDetails(day),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Date row with action buttons
              Row(
                children: [
                  Text(date,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  if (special) ...[
                    const SizedBox(width: 8),
                    _badge(day.dayType.label, Colors.purple),
                  ],
                  const Spacer(),
                  // Edit button
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _showEditDialog(main),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  // Delete button
                  IconButton(
                    icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                    onPressed: () => _confirmDelete(main),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),

              const Divider(),

              // Times row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _timeChip(Icons.login,  main.startTime ?? '--:--', Colors.green),
                  const Icon(Icons.arrow_forward, color: Colors.grey, size: 16),
                  _timeChip(Icons.logout, main.endTime   ?? '--:--', Colors.red),
                ],
              ),

              if (extras > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      '+ $extras more session${extras > 1 ? 's' : ''} · tap for details',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ),

              // Hours summary — only if complete
              if (isComplete) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _summaryChip('Regular',
                        TimeCalculator.formatHours(summary.regular), Colors.blue),
                    special
                        ? _summaryChip('${day.dayType.label} OT',
                            TimeCalculator.formatHours(summary.specialOvertime),
                            Colors.purple)
                        : _summaryChip('Overtime',
                            TimeCalculator.formatHours(summary.overtime),
                            summary.overtime > 0 ? Colors.orange : Colors.grey),
                  ],
                ),
              ],

              // Incomplete badge
              if (!isComplete)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _badge('Incomplete — missing clock out', Colors.orange),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── DAY DETAILS ────────────────────────────────────────

  // Log of every session of the day with its own hours
  Future<void> _showDayDetails(_Day day) async {
    final date = DateFormat('EEEE, MMM d yyyy').format(DateTime.parse(day.date));
    final summary = DaySummary.fromSessions(
        day.dayType, day.sessions.where((s) => s.isComplete).toList());
    final special = !day.dayType.isWorkday;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(date,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                  if (special) ...[
                    const SizedBox(width: 8),
                    _badge(day.dayType.label, Colors.purple),
                  ],
                ],
              ),
              if (special)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Every session counts as overtime',
                      style: TextStyle(fontSize: 13, color: Colors.purple.shade700)),
                ),

              const SizedBox(height: 16),

              for (final session in day.sessions)
                _buildSessionTile(session, sheetContext),

              const Divider(height: 32),

              _detailRow('Regular', TimeCalculator.formatHours(summary.regular)),
              special
                  ? _detailRow('${day.dayType.label} overtime',
                      TimeCalculator.formatHours(summary.specialOvertime),
                      color: Colors.purple)
                  : _detailRow('Overtime', TimeCalculator.formatHours(summary.overtime),
                      color: Colors.orange),
              _detailRow('Total', TimeCalculator.formatHours(summary.total), bold: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionTile(Record session, BuildContext sheetContext) {
    final hours = !session.isComplete
        ? 'In progress'
        : (session.totalHours ?? 0) > 0
            ? '${TimeCalculator.formatHours(session.totalHours!)} + '
              '${TimeCalculator.formatHours(session.otimeHours ?? 0)} OT'
            : '${TimeCalculator.formatHours(session.otimeHours ?? 0)} OT';

    // Close the sheet first so the list behind it refreshes after the change
    void then(Future<void> Function(Record) action) {
      Navigator.pop(sheetContext);
      action(session);
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(session.isExtra ? Icons.more_time : Icons.work_outline,
          color: session.isExtra ? Colors.deepOrange : Colors.blue),
      title: Text('${session.startTime ?? '--:--'} – ${session.endTime ?? '--:--'}',
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text('${session.isExtra ? 'Extra session' : 'Regular session'} · $hours'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            tooltip: 'Edit',
            onPressed: () => then(_showEditDialog),
          ),
          IconButton(
            icon: const Icon(Icons.delete, size: 20, color: Colors.red),
            tooltip: 'Delete',
            onPressed: () => then(_confirmDelete),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: color ?? Colors.grey)),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: bold ? FontWeight.w900 : FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _badge(String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: color.shade800)),
    );
  }

  Widget _timeChip(IconData icon, String time, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(time, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _summaryChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(color: color, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _Day {
  final String date;
  final DayType dayType;
  final List<Record> sessions;

  _Day(this.date, this.dayType, this.sessions);

  // Session shown on the card: the regular one, or the first of the day
  Record get main => sessions.firstWhere((s) => !s.isExtra, orElse: () => sessions.first);
}
