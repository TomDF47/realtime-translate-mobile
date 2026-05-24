package com.tomdf47.realtime_translate_mobile

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val permissionChannelName = "realtime_translate_mobile/microphone_permission"
    private val microphoneCaptureChannelName = "realtime_translate_mobile/microphone_capture"
    private val microphoneCaptureEventsChannelName = "realtime_translate_mobile/microphone_capture_events"
    private val translatedAudioPlaybackChannelName = "realtime_translate_mobile/translated_audio_playback"
    private val nativeShareChannelName = "realtime_translate_mobile/native_share"
    private val recordAudioRequestCode = 4701
    private val askedPermissionKey = "asked_record_audio_permission"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var microphoneCaptureEventSink: EventChannel.EventSink? = null
    private var microphoneCapture: Pcm16MicrophoneCapture? = null
    private var translatedAudioPlayback: Pcm16TranslatedAudioPlayback? = null

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
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, microphoneCaptureEventsChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    microphoneCaptureEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    microphoneCaptureEventSink = null
                    stopMicrophoneCapture()
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, microphoneCaptureChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> startMicrophoneCapture(call.arguments, result)
                    "stop" -> {
                        stopMicrophoneCapture()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, translatedAudioPlaybackChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> startTranslatedAudioPlayback(call.arguments, result)
                    "enqueuePcm16" -> enqueueTranslatedAudio(call.arguments, result)
                    "stop" -> stopTranslatedAudioPlayback(call.arguments, result)
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

    override fun onDestroy() {
        stopMicrophoneCapture()
        stopTranslatedAudioPlayback(clearQueue = true)
        super.onDestroy()
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

    private fun startMicrophoneCapture(arguments: Any?, result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            result.error("microphone_permission_missing", "Microphone permission is not granted.", null)
            return
        }

        val eventSink = microphoneCaptureEventSink
        if (eventSink == null) {
            result.error("microphone_capture_stream_missing", "Microphone capture stream is not attached.", null)
            return
        }

        val values = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        val sampleRateHz = (values["sampleRateHz"] as? Number)?.toInt() ?: 24000
        val channelCount = (values["channelCount"] as? Number)?.toInt() ?: 1
        val chunkDurationMs = (values["chunkDurationMs"] as? Number)?.toInt() ?: 200

        if (channelCount != 1) {
            result.error("unsupported_channel_count", "Only mono microphone capture is supported.", null)
            return
        }
        if (sampleRateHz <= 0 || chunkDurationMs <= 0) {
            result.error("invalid_capture_config", "Microphone capture config is invalid.", null)
            return
        }

        stopMicrophoneCapture()
        val capture = Pcm16MicrophoneCapture(
            sampleRateHz = sampleRateHz,
            chunkDurationMs = chunkDurationMs,
            eventSink = eventSink,
            mainHandler = mainHandler,
        )
        val startError = capture.start()
        if (startError != null) {
            result.error(startError.code, startError.message, null)
            return
        }

        microphoneCapture = capture
        result.success(null)
    }

    private fun stopMicrophoneCapture() {
        microphoneCapture?.stop()
        microphoneCapture = null
    }

    private fun startTranslatedAudioPlayback(arguments: Any?, result: MethodChannel.Result) {
        val values = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        val sampleRateHz = (values["sampleRateHz"] as? Number)?.toInt() ?: 24000
        val channelCount = (values["channelCount"] as? Number)?.toInt() ?: 1

        if (channelCount != 1) {
            result.error("unsupported_channel_count", "Only mono translated audio playback is supported.", null)
            return
        }
        if (sampleRateHz <= 0) {
            result.error("invalid_playback_config", "Translated audio playback config is invalid.", null)
            return
        }

        stopTranslatedAudioPlayback(clearQueue = true)
        val playback = Pcm16TranslatedAudioPlayback(
            sampleRateHz = sampleRateHz,
            channelCount = channelCount,
        )
        val startError = playback.start()
        if (startError != null) {
            result.error(startError.code, startError.message, null)
            return
        }

        translatedAudioPlayback = playback
        result.success(null)
    }

    private fun enqueueTranslatedAudio(arguments: Any?, result: MethodChannel.Result) {
        val playback = translatedAudioPlayback
        if (playback == null) {
            result.error("translated_audio_playback_closed", "Translated audio playback is not open.", null)
            return
        }

        val values = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        val sampleRateHz = (values["sampleRateHz"] as? Number)?.toInt() ?: playback.sampleRateHz
        val channelCount = (values["channelCount"] as? Number)?.toInt() ?: playback.channelCount
        val bytes = pcm16BytesFromArguments(values["bytes"])
        if (bytes == null) {
            result.error("invalid_playback_chunk", "Translated audio chunk bytes are invalid.", null)
            return
        }
        if (!playback.canAccept(sampleRateHz = sampleRateHz, channelCount = channelCount)) {
            result.error("playback_config_mismatch", "Translated audio chunk format does not match playback config.", null)
            return
        }
        if (bytes.isEmpty()) {
            result.success(null)
            return
        }
        if (!playback.enqueue(bytes)) {
            result.error("translated_audio_playback_closed", "Translated audio playback is not open.", null)
            return
        }

        result.success(null)
    }

    private fun stopTranslatedAudioPlayback(arguments: Any?, result: MethodChannel.Result) {
        val values = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        val clearQueue = values["clearQueue"] as? Boolean ?: true
        stopTranslatedAudioPlayback(clearQueue = clearQueue)
        result.success(null)
    }

    private fun stopTranslatedAudioPlayback(clearQueue: Boolean) {
        translatedAudioPlayback?.stop(clearQueue = clearQueue)
        translatedAudioPlayback = null
    }

    private fun pcm16BytesFromArguments(value: Any?): ByteArray? {
        return when (value) {
            is ByteArray -> value
            is List<*> -> {
                val bytes = ByteArray(value.size)
                for (index in value.indices) {
                    val item = value[index] as? Number ?: return null
                    bytes[index] = item.toByte()
                }
                bytes
            }
            else -> null
        }
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

    private data class CaptureStartError(val code: String, val message: String)

    private data class PlaybackStartError(val code: String, val message: String)

    private class Pcm16MicrophoneCapture(
        private val sampleRateHz: Int,
        private val chunkDurationMs: Int,
        private val eventSink: EventChannel.EventSink,
        private val mainHandler: Handler,
    ) {
        @Volatile
        private var isRecording = false
        private var audioRecord: AudioRecord? = null
        private var captureThread: Thread? = null

        fun start(): CaptureStartError? {
            val chunkByteCount = sampleRateHz * 2 * chunkDurationMs / 1000
            val minBufferSize = AudioRecord.getMinBufferSize(
                sampleRateHz,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            if (chunkByteCount <= 0 || minBufferSize <= 0) {
                return CaptureStartError(
                    "microphone_capture_unavailable",
                    "The device cannot provide the requested PCM16 microphone stream.",
                )
            }

            val bufferSize = maxOf(minBufferSize, chunkByteCount * 2)
            @Suppress("DEPRECATION")
            val record = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                sampleRateHz,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
            )
            if (record.state != AudioRecord.STATE_INITIALIZED) {
                record.release()
                return CaptureStartError(
                    "microphone_capture_unavailable",
                    "The device microphone stream could not be initialized.",
                )
            }

            return try {
                record.startRecording()
                if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                    record.release()
                    CaptureStartError(
                        "microphone_capture_unavailable",
                        "The device microphone stream could not be started.",
                    )
                } else {
                    audioRecord = record
                    isRecording = true
                    captureThread = thread(
                        start = true,
                        isDaemon = true,
                        name = "live-translate-pcm16-capture",
                    ) {
                        Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
                        readLoop(record, chunkByteCount)
                    }
                    null
                }
            } catch (error: SecurityException) {
                record.release()
                CaptureStartError(
                    "microphone_permission_missing",
                    "Microphone permission is not granted.",
                )
            } catch (error: IllegalStateException) {
                record.release()
                CaptureStartError(
                    "microphone_capture_unavailable",
                    "The device microphone stream could not be started.",
                )
            }
        }

        fun stop() {
            isRecording = false
            val record = audioRecord
            audioRecord = null
            try {
                record?.stop()
            } catch (error: IllegalStateException) {
                // The recorder may already be stopped after an input error.
            } finally {
                record?.release()
            }
            captureThread?.join(500)
            captureThread = null
        }

        private fun readLoop(record: AudioRecord, chunkByteCount: Int) {
            val chunk = ByteArray(chunkByteCount)
            var offset = 0
            while (isRecording) {
                val read = record.read(chunk, offset, chunk.size - offset)
                if (read > 0) {
                    offset += read
                    if (offset == chunk.size) {
                        emitChunk(chunk.copyOf())
                        offset = 0
                    }
                    continue
                }

                if (read == AudioRecord.ERROR_INVALID_OPERATION ||
                    read == AudioRecord.ERROR_BAD_VALUE ||
                    read == AudioRecord.ERROR_DEAD_OBJECT
                ) {
                    isRecording = false
                    emitError(
                        "microphone_capture_read_failed",
                        "Microphone capture stopped because the input stream failed.",
                    )
                }
            }
        }

        private fun emitChunk(bytes: ByteArray) {
            mainHandler.post {
                eventSink.success(
                    mapOf(
                        "bytes" to bytes,
                        "sampleRateHz" to sampleRateHz,
                        "channelCount" to 1,
                        "chunkDurationMs" to chunkDurationMs,
                    ),
                )
            }
        }

        private fun emitError(code: String, message: String) {
            mainHandler.post {
                eventSink.error(code, message, null)
            }
        }
    }

    private class Pcm16TranslatedAudioPlayback(
        val sampleRateHz: Int,
        val channelCount: Int,
    ) {
        private val queue = ArrayBlockingQueue<ByteArray>(32)

        @Volatile
        private var isPlaying = false
        private var audioTrack: AudioTrack? = null
        private var playbackThread: Thread? = null

        fun start(): PlaybackStartError? {
            val minBufferSize = AudioTrack.getMinBufferSize(
                sampleRateHz,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            if (minBufferSize <= 0) {
                return PlaybackStartError(
                    "translated_audio_playback_unavailable",
                    "The device cannot provide the requested PCM16 playback stream.",
                )
            }

            val bufferSize = maxOf(minBufferSize, sampleRateHz)
            val format = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRateHz)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            val track = try {
                AudioTrack(
                    attributes,
                    format,
                    bufferSize,
                    AudioTrack.MODE_STREAM,
                    AudioManager.AUDIO_SESSION_ID_GENERATE,
                )
            } catch (error: IllegalArgumentException) {
                return PlaybackStartError(
                    "translated_audio_playback_unavailable",
                    "The device playback stream could not be initialized.",
                )
            } catch (error: UnsupportedOperationException) {
                return PlaybackStartError(
                    "translated_audio_playback_unavailable",
                    "The device playback stream could not be initialized.",
                )
            }

            if (track.state != AudioTrack.STATE_INITIALIZED) {
                track.release()
                return PlaybackStartError(
                    "translated_audio_playback_unavailable",
                    "The device playback stream could not be initialized.",
                )
            }

            return try {
                track.play()
                if (track.playState != AudioTrack.PLAYSTATE_PLAYING) {
                    track.release()
                    PlaybackStartError(
                        "translated_audio_playback_unavailable",
                        "The device playback stream could not be started.",
                    )
                } else {
                    audioTrack = track
                    isPlaying = true
                    playbackThread = thread(
                        start = true,
                        isDaemon = true,
                        name = "live-translate-pcm16-playback",
                    ) {
                        Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
                        writeLoop(track)
                    }
                    null
                }
            } catch (error: IllegalStateException) {
                track.release()
                PlaybackStartError(
                    "translated_audio_playback_unavailable",
                    "The device playback stream could not be started.",
                )
            }
        }

        fun canAccept(sampleRateHz: Int, channelCount: Int): Boolean {
            return this.sampleRateHz == sampleRateHz && this.channelCount == channelCount
        }

        fun enqueue(bytes: ByteArray): Boolean {
            if (!isPlaying) {
                return false
            }

            val copiedBytes = bytes.copyOf()
            if (queue.offer(copiedBytes)) {
                return true
            }

            queue.poll()
            return queue.offer(copiedBytes)
        }

        fun stop(clearQueue: Boolean) {
            isPlaying = false
            if (clearQueue) {
                queue.clear()
            }
            queue.offer(ByteArray(0))

            val track = audioTrack
            audioTrack = null
            try {
                if (clearQueue) {
                    track?.pause()
                    track?.flush()
                }
                track?.stop()
            } catch (error: IllegalStateException) {
                // The playback stream may already be stopped after an output error.
            } finally {
                track?.release()
            }
            playbackThread?.join(500)
            playbackThread = null
        }

        private fun writeLoop(track: AudioTrack) {
            while (isPlaying) {
                val chunk = queue.poll(100, TimeUnit.MILLISECONDS) ?: continue
                var offset = 0
                while (isPlaying && offset < chunk.size) {
                    val written = track.write(chunk, offset, chunk.size - offset)
                    if (written > 0) {
                        offset += written
                    } else {
                        isPlaying = false
                    }
                }
            }
        }
    }
}
