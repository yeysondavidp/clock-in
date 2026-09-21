import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../database/database_helper.dart';
import '../services/backup_service.dart';
import '../services/update_service.dart';
import '../services/work_notification_service.dart';
import '../widgets/update_dialog.dart';

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
  int _roundingMinutes = 0;

  // Switch value
  bool _notificationsEnabled = true;

  bool _isLoading = true;

  String _appVersion = '';
  bool _checkingUpdate = false;
  bool _backupBusy = false;

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
    final rounding = await db.getSetting('time_rounding_minutes') ?? '0';
    final info = await PackageInfo.fromPlatform();

    setState(() {
      _checkinTime  = checkin;
      _checkoutTime = checkout;
      _standardHoursController.text = standardHours;
      _lunchBreakController.text    = lunchBreak;
      _notificationsEnabled         = notifications == 'true';
      _isLoading = false;
      _roundingMinutes = int.parse(rounding);
      _appVersion = info.version;
    });
  }

  // ─── UPDATES ────────────────────────────────────────────

  Future<void> _checkForUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      final update = await UpdateService.instance.checkForUpdate();
      if (!mounted) return;
      if (update == null) {
        _showMessage('You are on the latest version');
      } else {
        await showUpdateDialog(context, update);
      }
    } catch (e) {
      _showMessage('Could not check for updates: $e');
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  // ─── BACKUP ─────────────────────────────────────────────

  Future<void> _exportBackup() async {
    setState(() => _backupBusy = true);
    try {
      await BackupService.instance.exportBackup();
    } catch (e) {
      _showMessage('Backup failed: $e');
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text(
            'All current records, holidays and settings will be replaced '
            'by the ones in the backup file.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _backupBusy = true);
    try {
      final restored = await BackupService.instance.restoreBackup();
      if (!restored) return;
      await WorkNotificationService.instance.scheduleAllNotifications();
      await _loadSettings();
      _showMessage('Backup restored');
    } catch (e) {
      _showMessage('Restore failed: $e');
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _saveSetting(String key, String value) async {
    await db.updateSetting(key, value);
    await WorkNotificationService.instance.scheduleAllNotifications();
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
          // Time Rounding
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Time Rounding',
                          style: TextStyle(fontSize: 16)),
                      Text('Round clock in/out to nearest interval',
                          style: TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                ),
                DropdownButton<int>(
                  value: _roundingMinutes,
                  items: const [
                    DropdownMenuItem(value: 0,  child: Text('Off')),
                    DropdownMenuItem(value: 2, child: Text('2 min')),
                    DropdownMenuItem(value: 3, child: Text('3 min')),
                    DropdownMenuItem(value: 5,  child: Text('5 min')),
                    DropdownMenuItem(value: 10, child: Text('10 min')),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => _roundingMinutes = value);
                    await _saveSetting('time_rounding_minutes', value.toString());

                    // Temporal debug
                    final saved = await db.getSetting('time_rounding_minutes');
                    print('Saved rounding: $saved');
                  },
                ),
              ],
            ),
          ),

          const Divider(),

          // ── BACKUP SECTION ─────────────────────────
          _sectionHeader('Backup'),

          ListTile(
            title: const Text('Export Backup'),
            subtitle: const Text('Save a copy of all your data'),
            trailing: const Icon(Icons.upload_file),
            enabled: !_backupBusy,
            onTap: _exportBackup,
          ),

          ListTile(
            title: const Text('Restore Backup'),
            subtitle: const Text('Replace current data with a backup file'),
            trailing: const Icon(Icons.settings_backup_restore),
            enabled: !_backupBusy,
            onTap: _restoreBackup,
          ),

          const Divider(),

          // ── APP SECTION ────────────────────────────
          _sectionHeader('App'),

          ListTile(
            title: const Text('Version'),
            trailing: Text(_appVersion,
                style: const TextStyle(color: Colors.grey)),
          ),

          ListTile(
            title: const Text('Check for Updates'),
            trailing: _checkingUpdate
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.system_update),
            enabled: !_checkingUpdate,
            onTap: _checkForUpdate,
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}