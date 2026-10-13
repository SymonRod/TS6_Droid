package com.flammedemon.ts6_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.os.PowerManager

/** Foreground service: keeps the process (and the Rust connection) alive and owns the audio engine. */
class ConnectionService : Service() {
    companion object {
        private const val CHANNEL = "connection"
        private const val NOTIF_ID = 1
        const val ACTION_DISCONNECT = "com.flammedemon.ts6_flutter.DISCONNECT"
        const val ACTION_MUTE = "com.flammedemon.ts6_flutter.MUTE"
        @Volatile private var instance: ConnectionService? = null
        val isRunning: Boolean get() = instance != null
        @Volatile var onMuteToggleRequested: (() -> Unit)? = null
        @Volatile private var muted = true

        /** Redraws the notification so the action reads Mute/Unmute. */
        fun updateMuted(m: Boolean) {
            muted = m
            instance?.refreshNotification()
        }
        @Volatile var engine: AudioEngine? = null
        @Volatile var onVoiceActivity: ((Boolean) -> Unit)? = null
        /** Set by MainActivity so the notification button can reach Dart. */
        @Volatile var onDisconnectRequested: (() -> Unit)? = null

        fun start(ctx: Context, text: String, disconnect: String, mute: String, unmute: String) {
            ctx.startForegroundService(
                Intent(ctx, ConnectionService::class.java)
                    .putExtra("text", text).putExtra("disconnect", disconnect)
                    .putExtra("mute", mute).putExtra("unmute", unmute))
        }
        fun stop(ctx: Context) { ctx.stopService(Intent(ctx, ConnectionService::class.java)) }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var text = "Connected"
    private var disconnectLabel = "Disconnect"
    private var muteLabel = "Mute"
    private var unmuteLabel = "Unmute"

    fun refreshNotification() {
        getSystemService(NotificationManager::class.java).notify(NOTIF_ID, buildNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_DISCONNECT) {
            onDisconnectRequested?.invoke()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_MUTE) {
            onMuteToggleRequested?.invoke()
            return START_NOT_STICKY
        }
        intent?.getStringExtra("text")?.let { text = it }
        intent?.getStringExtra("disconnect")?.let { disconnectLabel = it }
        intent?.getStringExtra("mute")?.let { muteLabel = it }
        intent?.getStringExtra("unmute")?.let { unmuteLabel = it }
        instance = this
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Connection", NotificationManager.IMPORTANCE_LOW))
        val hasMic = checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        if (hasMic) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        startForeground(NOTIF_ID, buildNotification(), type)
        if (wakeLock == null) {
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ts6:conn").apply { acquire() }
        }
        val e = engine ?: AudioEngine(applicationContext).also { engine = it }
        e.onVoiceActivity = { v -> android.util.Log.d("ts6-voice", "voice=$v"); onVoiceActivity?.invoke(v) }
        e.start(hasMic)
        return START_NOT_STICKY
    }

    private fun buildNotification(): Notification {
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val disc = PendingIntent.getService(this, 1,
            Intent(this, ConnectionService::class.java).setAction(ACTION_DISCONNECT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val mutePi = PendingIntent.getService(this, 2,
            Intent(this, ConnectionService::class.java).setAction(ACTION_MUTE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, CHANNEL)
            .setContentTitle("TS6 Droid")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, if (muted) unmuteLabel else muteLabel, mutePi).build())
            .addAction(Notification.Action.Builder(null, disconnectLabel, disc).build())
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        instance = null
        engine?.stop(); engine = null
        wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null
        super.onDestroy()
    }
}
