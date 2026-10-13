package com.flammedemon.ts6_flutter

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingPerm: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        NativeInit.init(this)
        super.onCreate(savedInstanceState)
    }

    /** Dev only: `am start ... --ez ts6_disconnect true` says goodbye to the server before a reinstall kills us. */
    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        val debuggable = applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
        if (debuggable && intent.getBooleanExtra("ts6_disconnect", false)) {
            try { NativeAudio.disconnectAll() } catch (_: Throwable) {}
            ConnectionService.stop(applicationContext)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ts6/audio")
        channel = ch
        ConnectionService.onDisconnectRequested = {
            runOnUiThread { ch.invokeMethod("disconnectRequested", null) }
        }
        com.cloudwebrtc.webrtc.SystemAudioCapture.onProjectionStopped = Runnable {
            runOnUiThread { ch.invokeMethod("screenShareEnded", null) }
        }
        ConnectionService.onMuteToggleRequested = {
            runOnUiThread { ch.invokeMethod("muteToggleRequested", null) }
        }
        ConnectionService.onVoiceActivity = { v ->
            runOnUiThread { ch.invokeMethod("voiceActivity", v) }
        }
        ConnectionService.onAudioRoute = { d, a, auto ->
            runOnUiThread { ch.invokeMethod("audioRoute", routeMap(d, a, auto)) }
        }
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                // Asks RECORD_AUDIO (+ POST_NOTIFICATIONS on 33+); returns true if mic granted.
                "requestPermissions" -> {
                    val need = mutableListOf(Manifest.permission.RECORD_AUDIO)
                    if (Build.VERSION.SDK_INT >= 33) need += Manifest.permission.POST_NOTIFICATIONS
                    // Needed to see Bluetooth device names and route audio to them.
                    if (Build.VERSION.SDK_INT >= 31) need += Manifest.permission.BLUETOOTH_CONNECT
                    val missing = need.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
                    if (missing.isEmpty()) result.success(true)
                    else {
                        pendingPerm?.success(false)
                        pendingPerm = result
                        requestPermissions(missing.toTypedArray(), 42)
                    }
                }
                "startService" -> {
                    ConnectionService.start(
                        this,
                        call.argument<String>("text") ?: "Connected",
                        call.argument<String>("disconnect") ?: "Disconnect",
                        call.argument<String>("mute") ?: "Mute",
                        call.argument<String>("unmute") ?: "Unmute",
                    )
                    result.success(null)
                }
                "getAudioRoute" -> {
                    val r = ConnectionService.engine?.route?.snapshot()
                    result.success(if (r == null) null else routeMap(r.first, r.second, r.third))
                }
                // id == null selects automatic routing.
                "setAudioDevice" -> {
                    ConnectionService.engine?.route?.select(call.argument<Int>("id"))
                    result.success(null)
                }
                "setScreenShare" -> {
                    ConnectionService.setProjection(this, call.argument<Boolean>("on") ?: false)
                    result.success(null)
                }
                "moveTaskToBack" -> { moveTaskToBack(true); result.success(null) }
                "stopService" -> { ConnectionService.stop(this); result.success(null) }
                "setDeafened" -> {
                    ConnectionService.engine?.deafened = call.argument<Boolean>("deafened") ?: false
                    result.success(null)
                }
                "setMuted" -> {
                    val m = call.argument<Boolean>("muted") ?: true
                    ConnectionService.engine?.muted = m
                    ConnectionService.updateMuted(m)
                    // Mic may have been granted after the service started.
                    if (!m) ConnectionService.engine?.startCapture()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun routeMap(d: List<AudioRoute.Dev>, active: Int?, auto: Boolean) = mapOf(
        "devices" to d.map { mapOf("id" to it.id, "type" to it.type, "name" to it.name) },
        "active" to active,
        "auto" to auto,
    )

    override fun onDestroy() {
        val finishing = isFinishing && !isChangingConfigurations
        super.onDestroy()
        // The Rust client lives in this process (native lib via FFI), not in the Flutter
        // engine, so destroying the engine would leave it orphaned while the foreground
        // service keeps the process alive. If the Activity is really going away with the
        // service running, stop the service and end the process so the client is released.
        if (finishing && ConnectionService.isRunning) {
            // Tell the server we are leaving; a bare kill leaves a ghost client until timeout.
            try { NativeAudio.disconnectAll() } catch (_: Throwable) {}
            ConnectionService.stop(applicationContext)
            android.os.Process.killProcess(android.os.Process.myPid())
        }
    }

    override fun onRequestPermissionsResult(code: Int, perms: Array<out String>, res: IntArray) {
        super.onRequestPermissionsResult(code, perms, res)
        if (code == 42) {
            val mic = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
            pendingPerm?.success(mic)
            pendingPerm = null
        }
    }
}
