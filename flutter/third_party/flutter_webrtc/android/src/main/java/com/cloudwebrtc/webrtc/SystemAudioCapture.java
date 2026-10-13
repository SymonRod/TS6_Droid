package com.cloudwebrtc.webrtc;

import android.annotation.SuppressLint;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioPlaybackCaptureConfiguration;
import android.media.AudioRecord;
import android.media.projection.MediaProjection;
import android.util.Log;

import java.nio.ByteBuffer;

/**
 * Device audio (AudioPlaybackCapture) fed into the WebRTC audio device module.
 *
 * The ADM keeps recording from the microphone, but its AudioBufferCallback lets us rewrite
 * every captured buffer before it is encoded: while a capture is active the buffer is
 * fully replaced (with silence on a short read), so the microphone never reaches the stream.
 */
public class SystemAudioCapture {
    private static final String TAG = "SystemAudioCapture";
    /** Called when the user stops the capture from the system (chip/notification). */
    public static volatile Runnable onProjectionStopped;
    private static volatile AudioRecord record;
    private static int recordRate, recordChannels;

    public static synchronized void start(MediaProjection projection) {
        stop();
        AudioPlaybackCaptureConfiguration cfg =
                new AudioPlaybackCaptureConfiguration.Builder(projection)
                        .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                        .addMatchingUsage(AudioAttributes.USAGE_GAME)
                        .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                        .excludeUid(android.os.Process.myUid()) // never our own voices
                        .build();
        // AudioRecord is created lazily on the first buffer, in the ADM's own format.
        pendingConfig = cfg;
        Log.i(TAG, "armed");
    }

    private static AudioPlaybackCaptureConfiguration pendingConfig;

    public static synchronized void stop() {
        pendingConfig = null;
        AudioRecord r = record;
        record = null;
        if (r != null) {
            try {
                r.stop();
            } catch (Exception ignored) {
            }
            r.release();
            Log.i(TAG, "stopped");
        }
    }

    @SuppressLint("MissingPermission")
    private static synchronized AudioRecord ensure(int rate, int channels) {
        if (record != null && recordRate == rate && recordChannels == channels) return record;
        if (pendingConfig == null) return null;
        if (record != null) {
            record.release();
            record = null;
        }
        int mask = channels == 2 ? AudioFormat.CHANNEL_IN_STEREO : AudioFormat.CHANNEL_IN_MONO;
        AudioFormat fmt = new AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(rate)
                .setChannelMask(mask)
                .build();
        int min = AudioRecord.getMinBufferSize(rate, mask, AudioFormat.ENCODING_PCM_16BIT);
        try {
            AudioRecord r = new AudioRecord.Builder()
                    .setAudioPlaybackCaptureConfig(pendingConfig)
                    .setAudioFormat(fmt)
                    .setBufferSizeInBytes(Math.max(min, rate * channels * 2 / 5))
                    .build();
            r.startRecording();
            record = r;
            recordRate = rate;
            recordChannels = channels;
            Log.i(TAG, "capturing " + rate + " Hz x" + channels + " state=" + r.getRecordingState());
        } catch (Exception e) {
            Log.e(TAG, "AudioRecord failed", e);
            pendingConfig = null;
        }
        return record;
    }

    /** JavaAudioDeviceModule.AudioBufferCallback body. Returns the capture timestamp (0 = default). */
    public static long onBuffer(ByteBuffer buf, int format, int channels, int rate, int bytesRead, long ts) {
        if (pendingConfig == null && record == null) return 0; // no device-audio share running
        AudioRecord r = ensure(rate, channels);
        int got = 0;
        if (r != null) {
            byte[] tmp = new byte[bytesRead];
            while (got < bytesRead) {
                int n = r.read(tmp, got, bytesRead - got, AudioRecord.READ_NON_BLOCKING);
                if (n <= 0) break;
                got += n;
            }
            buf.position(0);
            buf.put(tmp, 0, got);
        }
        // Whatever the capture did not fill is silence, never microphone.
        if (got < bytesRead) {
            byte[] zeros = new byte[bytesRead - got];
            buf.position(got);
            buf.put(zeros);
        }
        buf.position(0);
        return 0;
    }
}
