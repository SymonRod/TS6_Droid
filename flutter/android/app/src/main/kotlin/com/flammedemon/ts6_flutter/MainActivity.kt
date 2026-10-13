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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ts6/audio")
        channel = ch
        ConnectionService.onDisconnectRequested = {
            runOnUiThread { ch.invokeMethod("disconnectRequested", null) }
        }
        ConnectionService.onMuteToggleRequested = {
            runOnUiThread { ch.invokeMethod("muteToggleRequested", null) }
        }
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                // Asks RECORD_AUDIO (+ POST_NOTIFICATIONS on 33+); returns true if mic granted.
                "requestPermissions" -> {
                    val need = mutableListOf(Manifest.permission.RECORD_AUDIO)
                    if (Build.VERSION.SDK_INT >= 33) need += Manifest.permission.POST_NOTIFICATIONS
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

    override fun onRequestPermissionsResult(code: Int, perms: Array<out String>, res: IntArray) {
        super.onRequestPermissionsResult(code, perms, res)
        if (code == 42) {
            val mic = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
            pendingPerm?.success(mic)
            pendingPerm = null
        }
    }
}
