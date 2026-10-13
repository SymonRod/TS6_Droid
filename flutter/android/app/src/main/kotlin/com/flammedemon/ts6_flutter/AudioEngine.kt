package com.flammedemon.ts6_flutter

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Process

/** Port of AudioBridge.kt: AudioRecord/AudioTrack on plain threads, Opus in Rust. */
class AudioEngine(private val context: Context) {
    companion object {
        const val SAMPLE_RATE = 48000
        private const val FRAME = 960 // 20 ms mono
    }

    @Volatile var muted = true
    @Volatile private var running = false
    private var record: AudioRecord? = null
    private var track: AudioTrack? = null
    private var playThread: Thread? = null
    private var capThread: Thread? = null

    fun start(withCapture: Boolean) {
        if (running) return
        NativeInit.init(context)
        NativeAudio.initAudio()
        running = true
        startPlayback()
        if (withCapture) startCapture()
    }

    @SuppressLint("MissingPermission")
    fun startCapture() {
        if (!running || capThread != null) return
        if (context.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) !=
            android.content.pm.PackageManager.PERMISSION_GRANTED
        ) return
        val min = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val rec = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION, SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
            maxOf(min, FRAME * 2 * 4))
        record = rec
        rec.startRecording()
        capThread = Thread({
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            val buf = ShortArray(FRAME)
            val bytes = ByteArray(FRAME * 2)
            while (running) {
                val n = rec.read(buf, 0, FRAME)
                if (n != FRAME) { if (n < 0) break else continue }
                if (muted) continue
                for (i in 0 until FRAME) {
                    bytes[i * 2] = (buf[i].toInt() and 0xFF).toByte()
                    bytes[i * 2 + 1] = (buf[i].toInt() shr 8).toByte()
                }
                NativeAudio.sendPcm(bytes)
            }
        }, "ts-capture").also { it.start() }
    }

    private fun startPlayback() {
        val min = AudioTrack.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val t = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAudioFormat(AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(SAMPLE_RATE)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setBufferSizeInBytes(maxOf(min, FRAME * 2 * 4))
            .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .build()
        track = t
        t.play()
        playThread = Thread({
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            val mix = ShortArray(FRAME)
            while (running) {
                if (NativeAudio.mixFrame(mix)) t.write(mix, 0, FRAME) else Thread.sleep(5)
            }
        }, "ts-playback").also { it.start() }
    }

    fun stop() {
        if (!running) return
        running = false
        capThread?.join(500); capThread = null
        playThread?.join(500); playThread = null
        record?.let { try { it.stop() } catch (_: Exception) {}; it.release() }; record = null
        track?.let { try { it.stop() } catch (_: Exception) {}; it.release() }; track = null
        NativeAudio.releaseAudio()
    }
}
