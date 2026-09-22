import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../database/database_helper.dart';
import '../services/backup_service.dart';
import '../utils/time_calculator.dart';
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

  // Numeric values
  String _standardHours = '8';
  String _lunchBreak = '30';
  Set<int> _workDays = {1, 2, 3, 4, 5};

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

  // ─── DATA ───────────────────────────────────────────────

  Future<void> _loadSettings() async {
    final checkin       = await db.getSetting('checkin_notification_time')  ?? '08:00';
    final checkout      = await db.getSetting('checkout_notification_time') ?? '16:00';
    final standardHours = await db.getSetting('standard_work_hours')        ?? '8';
    final lunchBreak    = await db.getSetting('lunch_break_minutes')        ?? '30';
    final notifications = await db.getSetting('notifications_enabled')      ?? 'true';
    final rounding = await db.getSetting('time_rounding_minutes') ?? '0';
    final workDays = await db.getWorkDays();
    final info = await PackageInfo.fromPlatform();

    setState(() {
      _checkinTime  = checkin;
      _checkoutTime = checkout;
      _standardHours = standardHours;
      _lunchBreak    = lunchBreak;
      _workDays      = workDays;
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

  // ─── NUMBER DIALOG ──────────────────────────────────────

  // Edits a numeric setting in a dialog so the value is only saved on
  // confirmation (inline fields lost edits unless Enter was pressed)
  Future<String?> _editNumber({
    required String title,
    required String initial,
    required String suffix,
    required String? Function(String) validate,
    String? helper,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => _NumberDialog(
        title: title,
        initial: initial,
        suffix: suffix,
        helper: helper,
        validate: validate,
      ),
    );
  }

  Future<void> _editStandardHours() async {
    final value = await _editNumber(
      title: 'Standard work hours',
      initial: _standardHours,
      suffix: 'h',
      helper: 'Time worked beyond this on a workday counts as overtime.',
      validate: (v) {
        final parsed = double.tryParse(v);
        return parsed == null || parsed <= 0 || parsed > 24
            ? 'Enter hours between 0 and 24'
            : null;
      },
    );
    if (value == null) return;
    await _saveSetting('standard_work_hours', value);
    setState(() => _standardHours = value);
  }

  Future<void> _editLunchBreak() async {
    final value = await _editNumber(
      title: 'Lunch break',
      initial: _lunchBreak,
      suffix: 'min',
      helper: 'Deducted from regular shifts longer than 6 hours. Overtime sessions are never deducted.',
      validate: (v) {
        final parsed = int.tryParse(v);
        return parsed == null || parsed < 0 || parsed > 240
            ? 'Enter whole minutes, 0 to 240'
            : null;
      },
    );
    if (value == null) return;
    await _saveSetting('lunch_break_minutes', value);
    setState(() => _lunchBreak = value);
  }

  Future<void> _toggleWorkDay(int day, bool selected) async {
    final updated = {..._workDays};
    selected ? updated.add(day) : updated.remove(day);
    if (updated.isEmpty) {
      _showMessage('Select at least one work day');
      return;
    }
    setState(() => _workDays = updated);
    await _saveSetting('work_days', (updated.toList()..sort()).join(','));
  }

  // ─── UI ─────────────────────────────────────────────────

  static const _roundingOptions = {0: 'Off', 2: '±2 min', 3: '±3 min', 5: '±5 min', 10: '±10 min'};
  static const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // '8' → '8 h', '7.5' → '7h 30m'
  String get _formattedStandardHours {
    final hours = double.tryParse(_standardHours);
    if (hours == null) return '$_standardHours h';
    return hours == hours.roundToDouble()
        ? '${hours.toInt()} h'
        : TimeCalculator.formatHours(hours);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [

          // ── NOTIFICATIONS SECTION ──────────────────
          _sectionHeader('Reminders'),

          // Master switch
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Daily reminders'),
            subtitle: const Text('Clock in/out reminders on work days'),
            value: _notificationsEnabled,
            onChanged: (value) async {
              setState(() => _notificationsEnabled = value);
              await _saveSetting('notifications_enabled', value.toString());
            },
          ),

          _valueTile(
            icon: Icons.login,
            title: 'Clock in reminder',
            value: _checkinTime,
            enabled: _notificationsEnabled,
            onTap: () => _pickTime('checkin_notification_time', _checkinTime),
          ),

          _valueTile(
            icon: Icons.logout,
            title: 'Clock out reminder',
            value: _checkoutTime,
            enabled: _notificationsEnabled,
            onTap: () => _pickTime('checkout_notification_time', _checkoutTime),
          ),

          // ── WORK SCHEDULE SECTION ──────────────────
          _sectionHeader('Work schedule'),

          ListTile(
            leading: const Icon(Icons.date_range_outlined),
            title: const Text('Work days'),
            subtitle: const Text('Time logged on other days counts as overtime'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 24, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var day = 1; day <= 7; day++) _dayToggle(day),
              ],
            ),
          ),

          _valueTile(
            icon: Icons.schedule,
            title: 'Standard work hours',
            subtitle: 'Overtime starts after this',
            value: _formattedStandardHours,
            onTap: _editStandardHours,
          ),

          _valueTile(
            icon: Icons.restaurant_outlined,
            title: 'Lunch break',
            subtitle: 'Deducted from regular shifts over 6h',
            value: '$_lunchBreak min',
            onTap: _editLunchBreak,
          ),

          ListTile(
            leading: const Icon(Icons.timelapse),
            title: const Text('Time rounding'),
            subtitle: const Text('Snap to the nearest 5 min within this margin'),
            trailing: DropdownButton<int>(
              value: _roundingMinutes,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(12),
              style: _valueStyle(context),
              items: [
                for (final entry in _roundingOptions.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) async {
                if (value == null) return;
                setState(() => _roundingMinutes = value);
                await _saveSetting('time_rounding_minutes', value.toString());
              },
            ),
          ),

          // ── BACKUP SECTION ─────────────────────────
          _sectionHeader('Backup'),

          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Export backup'),
            subtitle: const Text('Save a copy of all your data'),
            enabled: !_backupBusy,
            onTap: _exportBackup,
          ),

          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Restore backup'),
            subtitle: const Text('Replace current data with a backup file'),
            enabled: !_backupBusy,
            onTap: _restoreBackup,
          ),

          if (_backupBusy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(),
            ),

          // ── APP SECTION ────────────────────────────
          _sectionHeader('About'),

          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('Check for updates'),
            subtitle: Text('Version $_appVersion'),
            trailing: _checkingUpdate
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            enabled: !_checkingUpdate,
            onTap: _checkForUpdate,
          ),
        ],
      ),
    );
  }

  // Row with its current value on the right, in the accent color
  Widget _valueTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required String value,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: Text(value,
          style: enabled
              ? _valueStyle(context)
              : _valueStyle(context).copyWith(color: Theme.of(context).disabledColor)),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }

  // Round toggle with the weekday's initial, filled when it's a work day
  Widget _dayToggle(int day) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _workDays.contains(day);
    final label = _weekdayLabels[day - 1];

    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: () => _toggleWorkDay(day, !selected),
          radius: 22,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? scheme.primary : Colors.transparent,
              border: Border.all(color: selected ? scheme.primary : scheme.outline),
            ),
            child: Text(label[0],
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                )),
          ),
        ),
      ),
    );
  }

  TextStyle _valueStyle(BuildContext context) => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      );

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
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

// Owns its controller so it's disposed only after the dialog's exit animation
class _NumberDialog extends StatefulWidget {
  final String title;
  final String initial;
  final String suffix;
  final String? helper;
  final String? Function(String) validate;

  const _NumberDialog({
    required this.title,
    required this.initial,
    required this.suffix,
    required this.validate,
    this.helper,
  });

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    // Accept a decimal comma too, as the numeric keyboard offers one
    final value = _controller.text.trim().replaceAll(',', '.');
    final message = widget.validate(value);
    if (message != null) {
      setState(() => _error = message);
    } else {
      Navigator.pop(context, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          suffixText: widget.suffix,
          helperText: widget.helper,
          helperMaxLines: 2,
          errorText: _error,
          errorMaxLines: 2,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
