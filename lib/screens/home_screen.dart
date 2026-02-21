import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/record.dart';
import '../utils/time_calculator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final db = DatabaseHelper.instance;

  Record? _todayRecord;      // null = no record yet today
  bool _isLoading = true;    // controls the loading spinner

  @override
  void initState() {
    super.initState();
    _loadTodayRecord();      // runs automatically when screen opens
  }

  // ─── DATA ───────────────────────────────────────────────

  Future<void> _loadTodayRecord() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final record = await db.getRecordByDate(today);

    setState(() {
      _todayRecord = record;
      _isLoading = false;
    });
  }

  Future<void> _clockIn() async {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final timeNow = DateFormat('HH:mm').format(now);

    // Check if today is a holiday
    final isHoliday = await db.isHoliday(today);
    if (isHoliday) {
      _showMessage("Today is a holiday. Enjoy your day!");
      return;
    }

    final record = Record(
      date: today,
      startTime: timeNow,
      timestamp: now.toIso8601String(),
    );

    await db.insertRecord(record);
    await _loadTodayRecord();   // refresh UI
  }

  Future<void> _clockOut() async {
    if (_todayRecord == null) return;

    final now = DateTime.now();
    final timeNow = DateFormat('HH:mm').format(now);

    // Get settings for calculation
    final standardHours = double.parse(
        await db.getSetting('standard_work_hours') ?? '8');
    final lunchBreak = int.parse(
        await db.getSetting('lunch_break_minutes') ?? '30');

    // Calculate hours
    final total = TimeCalculator.calculateTotalHours(_todayRecord!.startTime!, timeNow, lunchBreak);
    final overtime = TimeCalculator.calculateOvertimeHours(total, standardHours);

    // Build updated record
    final updatedRecord = Record(
      id: _todayRecord!.id,
      date: _todayRecord!.date,
      startTime: _todayRecord!.startTime,
      endTime: timeNow,
      totalHours: total,
      otimeHours: overtime,
      timestamp: _todayRecord!.timestamp,
    );

    await db.updateRecord(updatedRecord);
    await _loadTodayRecord();   // refresh UI
  }

  // ─── UI ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clock In'),
        actions: [
          // Button to navigate to records screen (we'll build this next)
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () {
              // Navigator.push(context, ...) — coming next
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final today = DateFormat('EEEE, MMMM d').format(DateTime.now());

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            // Date
            Text(today,
                style: const TextStyle(fontSize: 18, color: Colors.grey)),

            const SizedBox(height: 48),

            // Status card
            _buildStatusCard(),

            const SizedBox(height: 48),

            // Action button — changes based on state
            _buildActionButton(),

          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    // No record today yet
    if (_todayRecord == null) {
      return const Text('No record for today yet.',
          style: TextStyle(fontSize: 16));
    }

    // Has clock in but no clock out
    if (_todayRecord!.endTime == null) {
      return Column(
        children: [
          const Text('Clocked in at',
              style: TextStyle(fontSize: 16, color: Colors.grey)),
          Text(_todayRecord!.startTime ?? '',
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
        ],
      );
    }

    // Day completed — show summary
    return Column(
      children: [
        _summaryRow('Clock In',     _todayRecord!.startTime ?? ''),
        _summaryRow('Clock Out',    _todayRecord!.endTime ?? ''),
        const Divider(height: 32),
        _summaryRow('Total Hours',
            TimeCalculator.formatHours(_todayRecord!.totalHours ?? 0)),
        _summaryRow('Overtime',
            TimeCalculator.formatHours(_todayRecord!.otimeHours ?? 0)),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    // Day already completed
    if (_todayRecord?.endTime != null) {
      return const Text('Day completed ✓',
          style: TextStyle(fontSize: 16, color: Colors.green));
    }

    // Clock out button
    if (_todayRecord != null) {
      return ElevatedButton(
        onPressed: _clockOut,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          minimumSize: const Size(200, 60),
        ),
        child: const Text('Clock Out',
            style: TextStyle(fontSize: 18, color: Colors.white)),
      );
    }

    // Clock in button (default)
    return ElevatedButton(
      onPressed: _clockIn,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        minimumSize: const Size(200, 60),
      ),
      child: const Text('Clock In',
          style: TextStyle(fontSize: 18, color: Colors.white)),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}