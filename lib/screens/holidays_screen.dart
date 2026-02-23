import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/holiday.dart';

class HolidaysScreen extends StatefulWidget {
  const HolidaysScreen({super.key});

  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  final db = DatabaseHelper.instance;
  List<Holiday> _holidays = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHolidays();
  }

  // ─── DATA ───────────────────────────────────────────────

  Future<void> _loadHolidays() async {
    final holidays = await db.getAllHolidays();
    setState(() {
      _holidays = holidays;
      _isLoading = false;
    });
  }

  Future<void> _showAddDialog() async {
    final nameController = TextEditingController();
    DateTime? selectedDate;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Holiday'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Name field
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Holiday Name',
                  hintText: 'e.g. Easter Monday',
                  prefixIcon: Icon(Icons.celebration),
                ),
                textCapitalization: TextCapitalization.words,
              ),

              const SizedBox(height: 16),

              // Date picker
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(
                  selectedDate != null
                      ? DateFormat('MMM d, yyyy').format(selectedDate!)
                      : 'Tap to select',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
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
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  _showMessage('Please enter a holiday name');
                  return;
                }
                if (selectedDate == null) {
                  _showMessage('Please select a date');
                  return;
                }

                final dateStr =
                    '${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}';

                final holiday = Holiday(
                  name: nameController.text.trim(),
                  date: dateStr,
                  timestamp: DateTime.now().toIso8601String(),
                );

                await db.insertHoliday(holiday);
                await _loadHolidays();
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Holiday holiday) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Holiday'),
        content: Text('Are you sure you want to delete "${holiday.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await db.deleteHoliday(holiday.id!);
              await _loadHolidays();
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ─── UI ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Public Holidays')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _holidays.isEmpty
          ? const Center(child: Text('No holidays added yet.'))
          : ListView.builder(
        itemCount: _holidays.length,
        itemBuilder: (context, index) {
          return _buildHolidayTile(_holidays[index]);
        },
      ),

      // FAB to add new holiday
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: 'Add Holiday',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildHolidayTile(Holiday holiday) {
    final date = DateTime.parse(holiday.date);
    final isPast = date.isBefore(DateTime.now());
    final formattedDate = DateFormat('EEE, MMM d yyyy').format(date);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isPast
            ? Colors.grey.shade200
            : Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          Icons.celebration,
          color: isPast
              ? Colors.grey
              : Theme.of(context).colorScheme.primary,
          size: 20,
        ),
      ),
      title: Text(
        holiday.name,
        style: TextStyle(
          color: isPast ? Colors.grey : null,
          decoration: isPast ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        formattedDate,
        style: TextStyle(color: isPast ? Colors.grey.shade400 : null),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
        onPressed: () => _confirmDelete(holiday),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}