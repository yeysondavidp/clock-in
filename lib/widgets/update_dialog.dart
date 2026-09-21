import 'package:flutter/material.dart';
import '../services/update_service.dart';

// Asks the user whether to update; if accepted, downloads with progress
// and hands the APK to the Android installer.
Future<void> showUpdateDialog(BuildContext context, AppUpdate update) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Update available: ${update.version}'),
      content: SingleChildScrollView(
        child: Text(update.notes.isEmpty
            ? 'A new version of Clock In is available.'
            : update.notes),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Update'),
        ),
      ],
    ),
  );
  if (accepted != true || !context.mounted) return;

  final progress = ValueNotifier<double>(0);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Downloading update'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value),
              const SizedBox(height: 12),
              Text('${(value * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    ),
  );

  final service = UpdateService.instance;
  String? message;
  try {
    final apk = await service.downloadApk(update,
        onProgress: (value) => progress.value = value);
    final result = await service.installApk(apk);
    if (result == InstallResult.permissionRequired) {
      message = 'Allow "Install unknown apps" for Clock In, then tap Update again.';
    }
  } catch (e) {
    message = 'Update failed: $e';
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
  }

  if (message != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
