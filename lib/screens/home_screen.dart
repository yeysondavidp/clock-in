import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/day_summary.dart';
import '../models/day_type.dart';
import '../models/record.dart';
import '../services/session_service.dart';
import '../utils/time_calculator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // A session left open yesterday is only picked up (e.g. work past midnight)
  // if it started this recently; older ones are forgotten clock outs.
  static const _maxCarryOver = Duration(hours: 12);

  final db = DatabaseHelper.instance;

  List<Record> _todaySessions = [];
  Record? _openSession;      // session currently running, if any
  DayType _dayType = DayType.workday;
  bool _isLoading = true;    // controls the loading spinner

  @override
  void initState() {
    super.initState();
    _loadToday();            // runs automatically when screen opens
  }

  // ─── DATA ───────────────────────────────────────────────

  Future<void> _loadToday() async {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final sessions = await db.getRecordsByDate(today);
    final dayType = await db.getDayType(today);
    final open = await _findOpenSession(now);

    setState(() {
      _todaySessions = sessions;
      _dayType = dayType;
      _openSession = open;
      _isLoading = false;
    });
  }

  Future<Record?> _findOpenSession(DateTime now) async {
    final today = DateFormat('yyyy-MM-dd').format(now);
    final yesterday =
        DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));

    for (final s in await db.getOpenRecordsSince(yesterday)) {
      if (s.startTime == null) continue;
      if (s.date == today) return s;
      final started = DateTime.parse('${s.date} ${s.startTime}');
      if (now.difference(started) <= _maxCarryOver) return s;
    }
    return null;
  }

  Record? get _regularSession =>
      _todaySessions.where((s) => !s.isExtra).firstOrNull;

  List<Record> get _completedSessions =>
      _todaySessions.where((s) => s.isComplete).toList();

  Future<String> _roundedNow(DateTime now) async {
    final rounding = int.parse(await db.getSetting('time_rounding_minutes') ?? '0');
    return TimeCalculator.roundTime(DateFormat('HH:mm').format(now), rounding);
  }

  // Regular clock in on a workday, or an extra session otherwise
  Future<void> _clockIn({required String type}) async {
    final now = DateTime.now();

    final record = Record(
      date: DateFormat('yyyy-MM-dd').format(now),
      startTime: await _roundedNow(now),
      type: type,
      timestamp: now.toIso8601String(),
    );

    await db.insertRecord(record);
    await _loadToday();
  }

  Future<void> _clockOut() async {
    final session = _openSession;
    if (session == null) return;

    final updated = await SessionService.instance.withTimes(
      session,
      startTime: session.startTime,
      endTime: await _roundedNow(DateTime.now()),
    );

    await db.updateRecord(updated);
    await _loadToday();
  }

  // ─── UI ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final today = DateFormat('EEEE, MMMM d').format(DateTime.now());

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            // Date
            Text(today,
                style: const TextStyle(fontSize: 18, color: Colors.grey)),

            if (!_dayType.isWorkday) ...[
              const SizedBox(height: 12),
              _buildSpecialDayBanner(),
            ],

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

  Widget _buildSpecialDayBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${_dayType.label} — any time you log today counts as overtime',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.purple.shade700),
      ),
    );
  }

  Widget _buildStatusCard() {
    final completed = _completedSessions;

    return Column(
      children: [
        // Session running
        if (_openSession != null) ...[
          Text(_openSession!.isExtra ? 'Overtime session since' : 'Clocked in at',
              style: const TextStyle(fontSize: 16, color: Colors.grey)),
          Text(_openSession!.startTime ?? '',
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
          if (completed.isNotEmpty) const SizedBox(height: 32),
        ],

        // Nothing logged and nothing running
        if (_openSession == null && completed.isEmpty)
          const Text('No record for today yet.',
              style: TextStyle(fontSize: 16)),

        // Summary of what's done so far
        if (completed.isNotEmpty) _buildSummary(completed),
      ],
    );
  }

  Widget _buildSummary(List<Record> completed) {
    final summary = DaySummary.fromSessions(_dayType, completed);

    return Column(
      children: [
        for (final s in completed)
          _summaryRow(s.isExtra ? 'Extra session' : 'Regular session',
              '${s.startTime} – ${s.endTime}'),
        const Divider(height: 32),
        if (_dayType.isWorkday) ...[
          _summaryRow('Regular Hours', TimeCalculator.formatHours(summary.regular)),
          _summaryRow('Overtime', TimeCalculator.formatHours(summary.overtime)),
        ] else ...[
          if (summary.regular > 0)
            _summaryRow('Regular Hours', TimeCalculator.formatHours(summary.regular)),
          _summaryRow('${_dayType.label} Overtime',
              TimeCalculator.formatHours(summary.specialOvertime),
              color: Colors.purple),
        ],
        _summaryRow('Total', TimeCalculator.formatHours(summary.total)),
      ],
    );
  }

  Widget _summaryRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: color ?? Colors.grey)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    // Clock out button
    if (_openSession != null) {
      return _actionButton('Clock Out', Colors.red, _clockOut);
    }

    // Workday without a regular session yet: regular clock in (default)
    if (_dayType.isWorkday && _regularSession == null) {
      return _actionButton('Clock In', Colors.green,
          () => _clockIn(type: Record.typeRegular));
    }

    // Day already completed, or a weekend/holiday: log overtime
    return Column(
      children: [
        if (_dayType.isWorkday)
          const Padding(
            padding: EdgeInsets.only(bottom: 24),
            child: Text('Day completed ✓',
                style: TextStyle(fontSize: 16, color: Colors.green)),
          ),
        _actionButton('Start Overtime', Colors.deepOrange,
            () => _clockIn(type: Record.typeExtra)),
      ],
    );
  }

  Widget _actionButton(String label, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size(200, 60),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 18, color: Colors.white)),
    );
  }
}
