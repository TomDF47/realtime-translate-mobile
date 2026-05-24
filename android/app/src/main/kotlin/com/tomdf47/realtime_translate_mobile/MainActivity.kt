package com.tomdf47.realtime_translate_mobile

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val permissionChannelName = "realtime_translate_mobile/microphone_permission"
    private val nativeShareChannelName = "realtime_translate_mobile/native_share"
    private val recordAudioRequestCode = 4701
    private val askedPermissionKey = "asked_record_audio_permission"
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, permissionChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkStatus" -> result.success(microphonePermissionStatus())
                    "request" -> requestMicrophonePermission(result)
                    "openAppSettings" -> {
                        openAppSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, nativeShareChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareMeetingExport" -> shareMeetingExport(call.arguments, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestMicrophonePermission(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            result.success("granted")
            return
        }

        if (pendingPermissionResult != null) {
            result.error("permission_request_active", "A microphone permission request is already active.", null)
            return
        }

        pendingPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), recordAudioRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != recordAudioRequestCode) {
            return
        }

        getPreferences(Context.MODE_PRIVATE)
            .edit()
            .putBoolean(askedPermissionKey, true)
            .apply()

        pendingPermissionResult?.success(microphonePermissionStatus())
        pendingPermissionResult = null
    }

    private fun microphonePermissionStatus(): String {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            return "granted"
        }

        val askedBefore = getPreferences(Context.MODE_PRIVATE).getBoolean(askedPermissionKey, false)
        val canShowRationale = shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)
        return if (askedBefore && !canShowRationale) {
            "permanentlyDenied"
        } else {
            "denied"
        }
    }

    private fun openAppSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
        }
        startActivity(intent)
    }

    private fun shareMeetingExport(arguments: Any?, result: MethodChannel.Result) {
        val values = arguments as? Map<*, *>
        val subject = values?.get("subject") as? String ?: "Live Translate export"
        val body = values?.get("body") as? String ?: ""
        val recipients = (values?.get("recipients") as? List<*>)
            ?.filterIsInstance<String>()
            ?.filter { it.isNotBlank() }
            ?: emptyList()

        if (body.isBlank()) {
            result.error("empty_export", "Export body is empty.", null)
            return
        }

        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, subject)
            putExtra(Intent.EXTRA_TEXT, body)
            if (recipients.isNotEmpty()) {
                putExtra(Intent.EXTRA_EMAIL, recipients.toTypedArray())
            }
        }

        try {
            startActivity(Intent.createChooser(shareIntent, "Share meeting export"))
            result.success("launched")
        } catch (error: ActivityNotFoundException) {
            result.error("share_unavailable", "No local share target is available.", null)
        }
    }
}
