import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final db = DatabaseHelper.instance;

  // Controllers for numeric fields
  final _standardHoursController = TextEditingController();
  final _lunchBreakController = TextEditingController();

  // Time values
  String _checkinTime  = '08:00';
  String _checkoutTime = '16:00';

  // Switch value
  bool _notificationsEnabled = true;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    // Always dispose controllers to free memory
    _standardHoursController.dispose();
    _lunchBreakController.dispose();
    super.dispose();
  }

  // ─── DATA ───────────────────────────────────────────────

  Future<void> _loadSettings() async {
    final checkin       = await db.getSetting('checkin_notification_time')  ?? '08:00';
    final checkout      = await db.getSetting('checkout_notification_time') ?? '16:00';
    final standardHours = await db.getSetting('standard_work_hours')        ?? '8';
    final lunchBreak    = await db.getSetting('lunch_break_minutes')        ?? '30';
    final notifications = await db.getSetting('notifications_enabled')      ?? 'true';

    setState(() {
      _checkinTime  = checkin;
      _checkoutTime = checkout;
      _standardHoursController.text = standardHours;
      _lunchBreakController.text    = lunchBreak;
      _notificationsEnabled         = notifications == 'true';
      _isLoading = false;
    });
  }

  Future<void> _saveSetting(String key, String value) async {
    await db.updateSetting(key, value);

    // Reschedule notifications whenever any setting changes
    await NotificationService.instance.scheduleAllNotifications();

    _showMessage('Setting saved');
  }

  // ─── TIME PICKER ────────────────────────────────────────

  Future<void> _pickTime(String settingKey, String currentValue) async {
    final parts = currentValue.split(':');
    final initial = TimeOfDay(
      hour:   int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );

    final picked = await showTimePicker(context: context, initialTime: initial);

    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';

      await _saveSetting(settingKey, formatted);

      setState(() {
        if (settingKey == 'checkin_notification_time') {
          _checkinTime = formatted;
        } else {
          _checkoutTime = formatted;
        }
      });
    }
  }

  // ─── UI ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        children: [

          // ── NOTIFICATIONS SECTION ──────────────────
          _sectionHeader('Notifications'),

          // Master switch
          SwitchListTile(
            title: const Text('Enable Notifications'),
            subtitle: const Text('Receive daily clock in/out reminders'),
            value: _notificationsEnabled,
            onChanged: (value) async {
              setState(() => _notificationsEnabled = value);
              await _saveSetting('notifications_enabled', value.toString());
            },
          ),

          // Clock in time
          ListTile(
            title: const Text('Clock In Reminder'),
            subtitle: Text(_checkinTime),
            trailing: const Icon(Icons.access_time),
            enabled: _notificationsEnabled,
            onTap: _notificationsEnabled
                ? () => _pickTime('checkin_notification_time', _checkinTime)
                : null,
          ),

          // Clock out time
          ListTile(
            title: const Text('Clock Out Reminder'),
            subtitle: Text(_checkoutTime),
            trailing: const Icon(Icons.access_time),
            enabled: _notificationsEnabled,
            onTap: _notificationsEnabled
                ? () => _pickTime('checkout_notification_time', _checkoutTime)
                : null,
          ),

          const Divider(),

          // ── WORK HOURS SECTION ─────────────────────
          _sectionHeader('Work Hours'),

          // Standard hours
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Standard Work Hours',
                          style: TextStyle(fontSize: 16)),
                      Text('Hours before overtime kicks in',
                          style: TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: _standardHoursController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      suffix: Text('h'),
                      isDense: true,
                    ),
                    onSubmitted: (value) async {
                      final parsed = double.tryParse(value);
                      if (parsed != null && parsed > 0) {
                        await _saveSetting('standard_work_hours', value);
                      } else {
                        _showMessage('Please enter a valid number');
                        _standardHoursController.text =
                            await db.getSetting('standard_work_hours') ?? '8';
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          // Lunch break
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Lunch Break',
                          style: TextStyle(fontSize: 16)),
                      Text('Deducted when worked more than 6h',
                          style: TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: _lunchBreakController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      suffix: Text('min'),
                      isDense: true,
                    ),
                    onSubmitted: (value) async {
                      final parsed = int.tryParse(value);
                      if (parsed != null && parsed >= 0) {
                        await _saveSetting('lunch_break_minutes', value);
                      } else {
                        _showMessage('Please enter a valid number');
                        _lunchBreakController.text =
                            await db.getSetting('lunch_break_minutes') ?? '30';
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // ── APP SECTION ────────────────────────────
          _sectionHeader('App'),

          ListTile(
            title: const Text('Version'),
            trailing: const Text('1.0.0',
                style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}