package com.flammedemon.ts6_flutter

/** JNI into tslib-frb (audio.rs). Opus encode/decode + mixing live in Rust; PCM never reaches Dart. */
object NativeAudio {
    external fun initAudio()
    external fun releaseAudio()
    external fun sendPcm(pcm: ByteArray): Boolean
    external fun mixFrame(out: ShortArray): Boolean
}
