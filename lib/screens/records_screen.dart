import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/record.dart';
import '../utils/time_calculator.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final db = DatabaseHelper.instance;
  List<Record> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await db.getAllRecords();
    setState(() {
      _records = records;
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
    // Recalculate hours with updated times
    double? totalHours;
    double? otimeHours;

    if (startTime.isNotEmpty && endTime.isNotEmpty) {
      final standardHours = double.parse(
          await db.getSetting('standard_work_hours') ?? '8');
      final lunchBreak = int.parse(
          await db.getSetting('lunch_break_minutes') ?? '30');

      totalHours = TimeCalculator.calculateTotalHours(startTime, endTime, lunchBreak);
      otimeHours = TimeCalculator.calculateOvertimeHours(startTime, endTime, standardHours);
    }

    final updatedRecord = Record(
      id: record.id,
      date: record.date,
      startTime: startTime.isNotEmpty ? startTime : null,
      endTime: endTime.isNotEmpty ? endTime : null,
      totalHours: totalHours,
      otimeHours: otimeHours,
      timestamp: record.timestamp,
    );

    await db.updateRecord(updatedRecord);
    await _loadRecords();
  }

  // ─── DELETE ─────────────────────────────────────────────

  Future<void> _confirmDelete(Record record) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Record'),
        content: Text(
            'Are you sure you want to delete the record for ${DateFormat('MMM d, yyyy').format(DateTime.parse(record.date))}?'),
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

  // ─── UI ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Records')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
          ? const Center(child: Text('No records yet.'))
          : ListView.builder(
        itemCount: _records.length,
        itemBuilder: (context, index) {
          return _buildRecordCard(_records[index]);
        },
      ),
    );
  }

  Widget _buildRecordCard(Record record) {
    final date = DateFormat('EEE, MMM d yyyy').format(DateTime.parse(record.date));
    final isComplete = record.endTime != null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Date row with action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(date,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                Row(
                  children: [
                    // Edit button
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _showEditDialog(record),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    // Delete button
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                      onPressed: () => _confirmDelete(record),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),

            const Divider(),

            // Times row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _timeChip(Icons.login,  record.startTime ?? '--:--', Colors.green),
                const Icon(Icons.arrow_forward, color: Colors.grey, size: 16),
                _timeChip(Icons.logout, record.endTime   ?? '--:--', Colors.red),
              ],
            ),

            // Hours summary — only if complete
            if (isComplete) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _summaryChip('Total',
                      TimeCalculator.formatHours(record.totalHours ?? 0),
                      Colors.blue),
                  _summaryChip('Overtime',
                      TimeCalculator.formatHours(record.otimeHours ?? 0),
                      record.otimeHours != null && record.otimeHours! > 0
                          ? Colors.orange
                          : Colors.grey),
                ],
              ),
            ],

            // Incomplete badge
            if (!isComplete)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Incomplete — missing clock out',
                    style: TextStyle(fontSize: 12, color: Colors.orange)),
              ),
          ],
        ),
      ),
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