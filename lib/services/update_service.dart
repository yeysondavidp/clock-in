import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdate {
  final String version;
  final String notes;
  final String apkUrl;
  final int apkSize;

  AppUpdate({
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.apkSize,
  });
}

enum InstallResult { started, permissionRequired }

class UpdateService {
  static final UpdateService instance = UpdateService._init();
  UpdateService._init();

  static const _latestReleaseUrl =
      'https://api.github.com/repos/yeysondavidp/clock-in/releases/latest';
  static const _installerChannel =
      MethodChannel('com.polartico.clock_in/installer');

  // Returns the latest GitHub release if it is newer than the installed
  // version and ships an APK, otherwise null.
  Future<AppUpdate?> checkForUpdate() async {
    final response = await http.get(
      Uri.parse(_latestReleaseUrl),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw HttpException('GitHub responded ${response.statusCode}');
    }

    final release = jsonDecode(response.body) as Map<String, dynamic>;
    final latest = _normalize(release['tag_name'] as String);
    final installed = (await PackageInfo.fromPlatform()).version;

    if (compareVersions(latest, installed) <= 0) return null;

    final assets = (release['assets'] as List).cast<Map<String, dynamic>>();
    final apk = assets
        .where((a) => (a['name'] as String).toLowerCase().endsWith('.apk'))
        .firstOrNull;
    if (apk == null) return null;

    return AppUpdate(
      version: latest,
      notes: (release['body'] as String?)?.trim() ?? '',
      apkUrl: apk['browser_download_url'] as String,
      apkSize: apk['size'] as int,
    );
  }

  // Downloads the APK into the cache (reused if already fully downloaded).
  Future<File> downloadApk(AppUpdate update,
      {void Function(double progress)? onProgress}) async {
    final dir = Directory(join((await getTemporaryDirectory()).path, 'updates'));
    await dir.create(recursive: true);
    final file = File(join(dir.path, 'clockin-${update.version}.apk'));

    if (await file.exists() && await file.length() == update.apkSize) {
      onProgress?.call(1);
      return file;
    }

    // Remove APKs from older updates so the cache doesn't grow
    await for (final entry in dir.list()) {
      if (entry is File) await entry.delete();
    }

    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(update.apkUrl)))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('Download failed (${response.statusCode})');
      }

      final total = response.contentLength ?? update.apkSize;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }

      if (await file.length() != update.apkSize) {
        await file.delete();
        throw const HttpException('Download incomplete, please try again');
      }
      return file;
    } finally {
      client.close();
    }
  }

  // Hands the APK to the Android package installer. If the user hasn't allowed
  // installs from this app yet, Android's settings screen for it is opened.
  Future<InstallResult> installApk(File apk) async {
    final result = await _installerChannel
        .invokeMethod<String>('installApk', {'path': apk.path});
    return result == 'permission_required'
        ? InstallResult.permissionRequired
        : InstallResult.started;
  }

  // Tags may be '1.2.0' or 'v1.2.0'; build metadata ('+3') is ignored.
  static String _normalize(String tag) =>
      tag.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;

  // Returns <0, 0 or >0 like compareTo, comparing numeric dot segments.
  static int compareVersions(String a, String b) {
    List<int> parse(String v) =>
        _normalize(v).split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final pa = parse(a), pb = parse(b);
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
