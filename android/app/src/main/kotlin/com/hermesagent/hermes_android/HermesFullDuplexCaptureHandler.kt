package com.hermesagent.hermes_android

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.max

/**
 * Dedicated PCM capture path for voice-turn barge-in.
 *
 * The normal `record` plugin intentionally remains untouched. This handler owns
 * a fresh VOICE_RECOGNITION AudioRecord for every generation so AEC can be
 * attached to, and truthfully queried from, that recorder's actual session.
 * Every PCM event carries its generation; bounded delivery prevents an old or
 * stalled platform stream from leaking audio into a later voice turn.
 */
internal class HermesFullDuplexCaptureHandler(
    context: Context,
    privateOutputProbe: () -> Boolean = { false },
) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    AutoCloseable {

    private data class Capture(
        val generation: Long,
        val recorder: AudioRecord,
        val aec: AcousticEchoCanceler?,
        val aecEnabled: Boolean,
        val noiseSuppressor: NoiseSuppressor?,
        val noiseSuppressionEnabled: Boolean,
        val stopped: AtomicBoolean = AtomicBoolean(false),
        val started: AtomicBoolean = AtomicBoolean(false),
        val released: AtomicBoolean = AtomicBoolean(false),
        val pendingLock: Any = Any(),
        val pending: ArrayDeque<ByteArray> = ArrayDeque(),
        var drainScheduled: Boolean = false,
        var sink: EventChannel.EventSink? = null,
        var nextSequence: Long = 1,
        var outstandingSequence: Long? = null,
    )

    private val appContext = context.applicationContext
    private val privateOutputProbe = privateOutputProbe
    private val mainHandler = Handler(Looper.getMainLooper())
    private val reader = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "hermes-full-duplex-capture").apply { isDaemon = true }
    }
    private val generationSeed = AtomicLong(0)
    private val startRequestEpoch = AtomicLong(0)
    private val stateLock = Any()

    @Volatile
    private var capture: Capture? = null

    @Volatile
    private var playbackActive = false

    @Volatile
    private var closed = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (closed) {
            result.success(null)
            return
        }
        when (call.method) {
            "hasPermission" -> result.success(hasRecordPermission())
            "start" -> start(result)
            "stop" -> {
                val generation = call.argument<Number>("generation")?.toLong()
                val current = capture
                if (
                    generation == null ||
                    (current != null && generation == current.generation)
                ) {
                    startRequestEpoch.incrementAndGet()
                    stop(generation)
                }
                result.success(null)
            }
            "ack" -> {
                val generation = call.argument<Number>("generation")?.toLong()
                val sequence = call.argument<Number>("sequence")?.toLong()
                acknowledge(generation, sequence)
                result.success(null)
            }
            "setPlaybackActive" -> {
                val active = call.argument<Boolean>("active") ?: false
                playbackActive = active
                val safety = currentSafety()
                if (active && safety["playbackSafe"] != true) {
                    failUnsafeRoute()
                }
                result.success(safety)
            }
            "getPlaybackSafety" -> result.success(currentSafety())
            "dispose" -> {
                startRequestEpoch.incrementAndGet()
                stop(null)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val generation = ((arguments as? Map<*, *>)?.get("generation") as? Number)?.toLong()
        val current = capture
        if (current == null || generation != current.generation || events == null) {
            events?.endOfStream()
            return
        }
        current.sink = events
        if (!current.started.compareAndSet(false, true)) return
        reader.execute {
            try {
                if (current.stopped.get() || closed) return@execute
                current.recorder.startRecording()
                if (current.recorder.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                    throw IllegalStateException("AudioRecord did not enter recording state")
                }
                emitReady(current)
                readLoop(current)
            } catch (error: Throwable) {
                if (!current.stopped.get() && !closed) {
                    failCapture(current, "capture_start_failed", safeMessage(error))
                }
            } finally {
                release(current)
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        val generation = ((arguments as? Map<*, *>)?.get("generation") as? Number)?.toLong()
        val current = capture
        if (current != null && generation == current.generation) {
            current.sink = null
            stop(generation)
        }
    }

    private fun start(result: MethodChannel.Result) {
        if (!hasRecordPermission()) {
            result.error("microphone_permission", "Microphone permission is required", null)
            return
        }
        val request = startRequestEpoch.incrementAndGet()
        stop(null)
        reader.execute { configureOnWorker(request, result) }
    }

    private fun configureOnWorker(
        request: Long,
        result: MethodChannel.Result,
    ) {
        var recorder: AudioRecord? = null
        var aec: AcousticEchoCanceler? = null
        var noiseSuppressor: NoiseSuppressor? = null
        try {
            if (closed || request != startRequestEpoch.get()) {
                throw IllegalStateException("Capture request was superseded")
            }
            // Permission can be revoked after the main-thread start check but
            // before this worker configures AudioRecord. Re-check at the use
            // site; a later platform race is still caught by the error path.
            if (
                ContextCompat.checkSelfPermission(
                    appContext,
                    Manifest.permission.RECORD_AUDIO,
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                mainHandler.post {
                    result.error(
                        "microphone_permission",
                        "Microphone permission is required",
                        null,
                    )
                }
                return
            }
            val minBuffer = AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            if (minBuffer <= 0) {
                throw IllegalStateException("AudioRecord rejected the PCM format")
            }
            recorder = AudioRecord.Builder()
                .setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .build(),
                )
                .setBufferSizeInBytes(max(minBuffer * 2, FRAME_BYTES * 8))
                .build()
            if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                throw IllegalStateException("AudioRecord did not initialize")
            }

            aec = if (AcousticEchoCanceler.isAvailable()) {
                AcousticEchoCanceler.create(recorder.audioSessionId)
            } else {
                null
            }
            val aecEnabled = try {
                aec?.enabled = true
                aec != null && aec.hasControl() && aec.enabled
            } catch (_: Throwable) {
                false
            }

            noiseSuppressor = try {
                if (NoiseSuppressor.isAvailable()) {
                    NoiseSuppressor.create(recorder.audioSessionId)
                } else {
                    null
                }
            } catch (_: Throwable) {
                null
            }
            val noiseSuppressionEnabled = try {
                noiseSuppressor?.enabled = true
                noiseSuppressor != null && noiseSuppressor.hasControl() && noiseSuppressor.enabled
            } catch (_: Throwable) {
                false
            }

            // VOICE_RECOGNITION conserva primary-capture en el Pixel y permite
            // ligar AEC a esta sesión. VOICE_COMMUNICATION seleccionaba
            // voip-capture y deformaba la voz cercana; MIC conservaba la voz,
            // pero su residuo de altavoz superaba el detector y se autoactivaba.
            // Igual que getUserMedia en Desktop, NS se solicita best-effort en
            // la misma sesión; no forma parte de la prueba de seguridad AEC.

            val generation = generationSeed.incrementAndGet()
            val next = Capture(
                generation = generation,
                recorder = recorder,
                aec = aec,
                aecEnabled = aecEnabled,
                noiseSuppressor = noiseSuppressor,
                noiseSuppressionEnabled = noiseSuppressionEnabled,
            )
            synchronized(stateLock) {
                if (closed || request != startRequestEpoch.get()) {
                    throw IllegalStateException("Capture request was superseded")
                }
                capture = next
            }
            val safety = safetyFor(next)
            if (playbackActive && safety["playbackSafe"] != true) {
                Log.w(
                    TAG,
                    "unsafe_playback_route on start: aec=${safety["aecEnabled"]} " +
                        "private=${safety["privateOutput"]} gen=$generation",
                )
                synchronized(stateLock) {
                    if (capture === next) capture = null
                }
                next.stopped.set(true)
                release(next)
                mainHandler.post {
                    result.error(
                        "unsafe_playback_route",
                        "Playback has no proven echo cancellation",
                        null,
                    )
                }
                return
            }
            mainHandler.post {
                result.success(
                    mapOf(
                        "generation" to generation,
                        "aecEnabled" to safety["aecEnabled"],
                        "noiseSuppressionEnabled" to safety["noiseSuppressionEnabled"],
                        "privateOutput" to safety["privateOutput"],
                        "playbackSafe" to safety["playbackSafe"],
                    ),
                )
            }
        } catch (error: Throwable) {
            try {
                noiseSuppressor?.release()
            } catch (_: Throwable) {
            }
            try {
                aec?.release()
            } catch (_: Throwable) {
            }
            try {
                recorder?.release()
            } catch (_: Throwable) {
            }
            mainHandler.post {
                result.error("capture_configure_failed", safeMessage(error), null)
            }
        }
    }

    private fun readLoop(owner: Capture) {
        val buffer = ByteArray(FRAME_BYTES * DELIVERY_FRAMES)
        try {
            while (!owner.stopped.get() && !closed) {
                if (playbackActive && safetyFor(owner)["playbackSafe"] != true) {
                    failCapture(
                        owner,
                        "unsafe_playback_route",
                        "Echo cancellation was lost during playback",
                    )
                    return
                }
                val count = owner.recorder.read(
                    buffer,
                    0,
                    buffer.size,
                    AudioRecord.READ_BLOCKING,
                )
                when {
                    count > 0 -> {
                        val bytes = buffer.copyOf(count)
                        if (!enqueue(owner, bytes)) {
                            failCapture(
                                owner,
                                "capture_backpressure",
                                "PCM delivery could not keep up",
                            )
                            return
                        }
                    }
                    count == 0 -> continue
                    else -> throw IllegalStateException("AudioRecord read failed ($count)")
                }
            }
        } catch (error: Throwable) {
            if (!owner.stopped.get() && !closed) {
                failCapture(owner, "capture_read_failed", safeMessage(error))
            }
        } finally {
            release(owner)
        }
    }

    private fun emitReady(owner: Capture) {
        mainHandler.post {
            val current = capture
            if (
                current !== owner ||
                owner.stopped.get() ||
                owner.released.get() ||
                closed
            ) {
                return@post
            }
            val safety = safetyFor(owner)
            if (playbackActive && safety["playbackSafe"] != true) {
                failCapture(
                    owner,
                    "unsafe_playback_route",
                    "Playback has no proven echo cancellation",
                )
                return@post
            }
            owner.sink?.success(
                mapOf(
                    "type" to "ready",
                    "generation" to owner.generation,
                    "aecEnabled" to safety["aecEnabled"],
                    "noiseSuppressionEnabled" to safety["noiseSuppressionEnabled"],
                    "privateOutput" to safety["privateOutput"],
                    "playbackSafe" to safety["playbackSafe"],
                ),
            )
        }
    }

    private fun enqueue(owner: Capture, bytes: ByteArray): Boolean {
        var schedule = false
        synchronized(owner.pendingLock) {
            if (owner.stopped.get() || owner.released.get()) return false
            if (owner.pending.size >= MAX_PENDING_CHUNKS) return false
            owner.pending.addLast(bytes)
            if (!owner.drainScheduled) {
                owner.drainScheduled = true
                schedule = true
            }
        }
        if (schedule) mainHandler.post { drain(owner) }
        return true
    }

    private fun drain(owner: Capture) {
        val delivery = synchronized(owner.pendingLock) {
            owner.drainScheduled = false
            if (owner.outstandingSequence != null || owner.pending.isEmpty()) {
                null
            } else {
                val sequence = owner.nextSequence++
                owner.outstandingSequence = sequence
                sequence to owner.pending.removeFirst()
            }
        } ?: return
        val current = capture
        if (
            current !== owner ||
            owner.stopped.get() ||
            owner.released.get() ||
            closed
        ) {
            synchronized(owner.pendingLock) {
                owner.pending.clear()
                owner.outstandingSequence = null
            }
            return
        }
        owner.sink?.success(
            mapOf(
                "type" to "pcm",
                "generation" to owner.generation,
                "sequence" to delivery.first,
                "pcm" to delivery.second,
            ),
        )
    }

    private fun acknowledge(generation: Long?, sequence: Long?) {
        val owner = capture
        if (owner == null || generation != owner.generation || sequence == null) return
        var schedule = false
        synchronized(owner.pendingLock) {
            if (owner.outstandingSequence != sequence) return
            owner.outstandingSequence = null
            if (owner.pending.isNotEmpty() && !owner.drainScheduled) {
                owner.drainScheduled = true
                schedule = true
            }
        }
        if (schedule) mainHandler.post { drain(owner) }
    }

    private fun stop(requestedGeneration: Long?) {
        val owner = synchronized(stateLock) {
            val current = capture
            if (
                current == null ||
                (requestedGeneration != null && current.generation != requestedGeneration)
            ) {
                null
            } else {
                capture = null
                current
            }
        } ?: return
        owner.stopped.set(true)
        synchronized(owner.pendingLock) {
            owner.pending.clear()
            owner.outstandingSequence = null
        }
        try {
            if (owner.started.get()) owner.recorder.stop()
        } catch (_: Throwable) {
        }
        if (!owner.started.get()) release(owner)
    }

    private fun failCapture(owner: Capture, code: String, message: String) {
        if (!owner.stopped.compareAndSet(false, true)) return
        synchronized(stateLock) {
            if (capture === owner) capture = null
        }
        synchronized(owner.pendingLock) {
            owner.pending.clear()
            owner.outstandingSequence = null
        }
        val sink = owner.sink
        owner.sink = null
        mainHandler.post {
            sink?.error(code, message, mapOf("generation" to owner.generation))
            sink?.endOfStream()
        }
        try {
            if (owner.started.get()) owner.recorder.stop()
        } catch (_: Throwable) {
        }
        if (!owner.started.get()) release(owner)
    }

    private fun failUnsafeRoute() {
        val owner = capture ?: return
        val safety = safetyFor(owner)
        Log.w(
            TAG,
            "unsafe_playback_route on live capture: aec=${safety["aecEnabled"]} " +
                "private=${safety["privateOutput"]} gen=${owner.generation}",
        )
        failCapture(
            owner,
            "unsafe_playback_route",
            "Playback route has neither proven AEC nor a private output",
        )
    }

    private fun verifyLiveRoute() {
        if (!playbackActive || closed) return
        if (currentSafety()["playbackSafe"] != true) failUnsafeRoute()
    }

    private fun currentSafety(): Map<String, Any> {
        val owner = capture
        return if (owner == null) {
            mapOf(
                "generation" to 0L,
                "aecEnabled" to false,
                "noiseSuppressionEnabled" to false,
                "privateOutput" to false,
                "playbackSafe" to false,
            )
        } else {
            safetyFor(owner)
        }
    }

    private fun safetyFor(owner: Capture): Map<String, Any> {
        val aecLive = try {
            owner.aecEnabled &&
                owner.aec != null &&
                owner.aec.hasControl() &&
                owner.aec.enabled
        } catch (_: Throwable) {
            false
        }
        val noiseSuppressionLive = try {
            owner.noiseSuppressionEnabled &&
                owner.noiseSuppressor != null &&
                owner.noiseSuppressor.hasControl() &&
                owner.noiseSuppressor.enabled
        } catch (_: Throwable) {
            false
        }
        // The probe reads the routedDevice of the exact live TTS AudioTrack.
        // Merely connected devices are never treated as proof of privacy.
        val privateOutput = try {
            privateOutputProbe()
        } catch (_: Throwable) {
            false
        }
        // AcousticEchoCanceler.enabled only reports administrative state. It
        // does not prove that the HAL is attenuating this app's far-end TTS,
        // and the transcript similarity guard runs too late to prevent a false
        // speech_start from cutting playback. Only the routedDevice of the
        // exact live AudioTrack proves a private output and authorizes
        // playback-phase barge-in. AEC/NS remain diagnostic.
        return mapOf(
            "generation" to owner.generation,
            "aecEnabled" to aecLive,
            "noiseSuppressionEnabled" to noiseSuppressionLive,
            "privateOutput" to privateOutput,
            "playbackSafe" to privateOutput,
        )
    }

    private fun release(owner: Capture) {
        if (!owner.released.compareAndSet(false, true)) return
        synchronized(owner.pendingLock) {
            owner.pending.clear()
        }
        try {
            owner.noiseSuppressor?.release()
        } catch (_: Throwable) {
        }
        try {
            owner.aec?.release()
        } catch (_: Throwable) {
        }
        try {
            owner.recorder.release()
        } catch (_: Throwable) {
        }
    }

    private fun hasRecordPermission(): Boolean =
        ContextCompat.checkSelfPermission(appContext, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    override fun close() {
        if (closed) return
        closed = true
        startRequestEpoch.incrementAndGet()
        playbackActive = false
        stop(null)
        reader.shutdown()
    }

    private fun safeMessage(error: Throwable): String =
        error.message?.take(240) ?: error.javaClass.simpleName

    private companion object {
        const val TAG = "HermesVoiceStab"
        const val SAMPLE_RATE = 16_000
        const val FRAME_BYTES = 960 // 30 ms, mono PCM16
        const val DELIVERY_FRAMES = 1 // preserve Hermes' 30 ms VAD cadence
        const val MAX_PENDING_CHUNKS = 34 // ~1 s, plus one ACK-gated message
    }
}
