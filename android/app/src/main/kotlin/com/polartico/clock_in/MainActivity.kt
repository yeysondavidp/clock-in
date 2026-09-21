package com.polartico.clock_in

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "com.polartico.clock_in/battery")
            .setMethodCallHandler { call, result ->
                if (call.method == "isIgnoringBatteryOptimizations") {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(messenger, "com.polartico.clock_in/installer")
            .setMethodCallHandler { call, result ->
                if (call.method == "installApk") {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "Missing APK path", null)
                    } else {
                        result.success(installApk(File(path)))
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun installApk(apk: File): String {
        // Android 8+ requires the user to allow installs from this app first
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
            )
            return "permission_required"
        }

        val uri = FileProvider.getUriForFile(this, "$packageName.update_provider", apk)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
        return "started"
    }
}
