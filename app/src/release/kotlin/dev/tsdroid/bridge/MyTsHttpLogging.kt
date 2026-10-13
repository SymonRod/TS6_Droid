package dev.tsdroid.bridge

import okhttp3.Interceptor

/** Release builds never log myTeamSpeak traffic. */
internal object MyTsHttpLogging {
    fun interceptor(): Interceptor? = null
}
