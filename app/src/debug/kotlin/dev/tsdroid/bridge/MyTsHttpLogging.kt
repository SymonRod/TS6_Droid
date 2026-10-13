package dev.tsdroid.bridge

import android.util.Log
import okhttp3.Interceptor
import okhttp3.logging.HttpLoggingInterceptor

/**
 * Debug builds log myTeamSpeak calls at HEADERS level: URL, status, timing.
 * Never raise this to BODY — request bodies carry the password and session
 * tokens, and nothing secret may reach logcat.
 */
internal object MyTsHttpLogging {
    fun interceptor(): Interceptor? =
        HttpLoggingInterceptor { Log.d("MyTsApi", it) }.apply {
            level = HttpLoggingInterceptor.Level.HEADERS
            redactHeader("Authorization")
            redactHeader("Cookie")
            redactHeader("Set-Cookie")
        }
}
