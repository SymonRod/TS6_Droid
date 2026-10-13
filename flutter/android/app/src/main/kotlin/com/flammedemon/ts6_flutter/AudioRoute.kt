package com.flammedemon.ts6_flutter

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Chooses where voice goes: speaker, earpiece, wired, Bluetooth (SCO / LE Audio).
 * Auto mode prefers the most "personal" device that is connected; a manual pick
 * sticks until that device disappears, then falls back to auto.
 */
class AudioRoute(private val context: Context) {
    data class Dev(val id: Int, val type: Int, val name: String)

    private val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())
    private var selectedId: Int? = null
    private var started = false
    private var prevMode = AudioManager.MODE_NORMAL

    /** (available devices, active id, auto). Always invoked on the main thread. */
    @Volatile var onChanged: ((List<Dev>, Int?, Boolean) -> Unit)? = null

    private val callback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) = apply()
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) = apply()
    }

    fun start() {
        main.post {
            if (started) return@post
            started = true
            prevMode = am.mode
            // Required for the communication device / SCO route to carry both directions.
            am.mode = AudioManager.MODE_IN_COMMUNICATION
            am.registerAudioDeviceCallback(callback, main)
            apply()
        }
    }

    fun stop() {
        main.post {
            if (!started) return@post
            started = false
            am.unregisterAudioDeviceCallback(callback)
            if (Build.VERSION.SDK_INT >= 31) am.clearCommunicationDevice()
            else {
                @Suppress("DEPRECATION") am.stopBluetoothSco()
                @Suppress("DEPRECATION") am.isSpeakerphoneOn = false
            }
            am.mode = prevMode
        }
    }

    /** null = automatic. */
    fun select(id: Int?) {
        main.post { selectedId = id; apply() }
    }

    fun snapshot(): Triple<List<Dev>, Int?, Boolean> {
        val list = candidates()
        val active = pick(list)
        return Triple(list.map { Dev(it.id, it.type, label(it)) }, active?.id, selectedId == null)
    }

    private fun candidates(): List<AudioDeviceInfo> {
        val all = if (Build.VERSION.SDK_INT >= 31) am.availableCommunicationDevices
        else am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList()
        return all.filter { it.type in SUPPORTED }.distinctBy { it.id }
    }

    private fun pick(list: List<AudioDeviceInfo>): AudioDeviceInfo? {
        selectedId?.let { id -> list.firstOrNull { it.id == id }?.let { return it } }
        for (t in AUTO_ORDER) list.firstOrNull { it.type == t }?.let { return it }
        return null
    }

    private fun apply() {
        if (!started) return
        val list = candidates()
        if (selectedId != null && list.none { it.id == selectedId }) selectedId = null
        val target = pick(list)
        if (Build.VERSION.SDK_INT >= 31) {
            if (target != null) am.setCommunicationDevice(target) else am.clearCommunicationDevice()
        } else {
            val sco = target?.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
            @Suppress("DEPRECATION")
            if (sco) am.startBluetoothSco() else am.stopBluetoothSco()
            @Suppress("DEPRECATION")
            am.isSpeakerphoneOn = target?.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
        }
        val s = snapshot()
        onChanged?.invoke(s.first, s.second, s.third)
    }

    private fun label(d: AudioDeviceInfo): String {
        val product = d.productName?.toString()?.takeIf { it.isNotBlank() }
        return when (d.type) {
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
            else -> product ?: "device"
        }
    }

    companion object {
        private val AUTO_ORDER = buildList {
            if (Build.VERSION.SDK_INT >= 31) add(AudioDeviceInfo.TYPE_BLE_HEADSET)
            add(AudioDeviceInfo.TYPE_BLUETOOTH_SCO)
            add(AudioDeviceInfo.TYPE_WIRED_HEADSET)
            add(AudioDeviceInfo.TYPE_WIRED_HEADPHONES)
            add(AudioDeviceInfo.TYPE_USB_HEADSET)
            add(AudioDeviceInfo.TYPE_HEARING_AID)
            add(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
        }
        private val SUPPORTED = AUTO_ORDER.toSet() +
            setOf(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE, AudioDeviceInfo.TYPE_USB_DEVICE) +
            (if (Build.VERSION.SDK_INT >= 31) setOf(AudioDeviceInfo.TYPE_BLE_SPEAKER) else emptySet())
    }
}
