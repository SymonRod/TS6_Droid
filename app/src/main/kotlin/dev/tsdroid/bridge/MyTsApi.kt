package dev.tsdroid.bridge

import com.google.protobuf.InvalidProtocolBufferException
import com.google.protobuf.MessageLite
import com.google.protobuf.Parser
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.AuthTokenLogin
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.AuthTokenReply
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.AuthTokenRequest
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.LoginData
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.LoginSession
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.LoginStatus
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.RenewalTokenLogin
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.Session
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resumeWithException

/**
 * Thin client for the myTeamSpeak cloud API ("ProtobufRPC" over HTTPS).
 *
 * Wire format (docs/myteamspeak-sync-protocol.md §0, confirmed by capture):
 * one `POST` per call to `BASE_URL/<service path>`, `Content-Type:
 * application/ts3cloud`, body = `u8 len` + method name + bare protobuf. On
 * HTTP 200 the whole reply body is the reply message, no envelope; any other
 * status fails the call. Application errors travel inside reply messages.
 *
 * The client never retries on its own: callers pace manual retries.
 */
class MyTsApi(
    private val http: OkHttpClient = defaultClient(),
    private val baseUrl: HttpUrl = BASE_URL.toHttpUrl(),
) {

    /** A cloud service and the URL path it is served on (§0/§1). */
    enum class Service(val path: String) {
        /** `LoginService`. */
        AUTHENTICATION("authentication"),

        /** `SynchronizationService` (M2+). */
        SYNCHRONIZATION("synchronization"),

        /** `UserAccountService`. */
        USER("user"),
    }

    // --- LoginService (/authentication) ---

    suspend fun login(request: LoginData): LoginSession =
        call(Service.AUTHENTICATION, "login", request, LoginSession.parser())

    suspend fun requestAuthToken(request: AuthTokenRequest): AuthTokenReply =
        call(Service.AUTHENTICATION, "requestAuthToken", request, AuthTokenReply.parser())

    suspend fun loginWithAuthToken(request: AuthTokenLogin): LoginSession =
        call(Service.AUTHENTICATION, "loginWithAuthToken", request, LoginSession.parser())

    suspend fun loginWithRenewalToken(request: RenewalTokenLogin): LoginSession =
        call(Service.AUTHENTICATION, "loginWithRenewalToken", request, LoginSession.parser())

    /** Checks that [session] is still valid. */
    suspend fun session(session: String): LoginStatus =
        call(Service.AUTHENTICATION, "session", sessionOf(session), LoginStatus.parser())

    /** Ends [session] on the server (logout). */
    suspend fun deleteSession(session: String): LoginStatus =
        call(Service.AUTHENTICATION, "deleteSession", sessionOf(session), LoginStatus.parser())

    // --- Transport ---

    /** Performs one RPC and parses the reply. Throws [MyTsHttpException] or [IOException]. */
    suspend fun <R : MessageLite> call(
        service: Service,
        method: String,
        request: MessageLite,
        replyParser: Parser<R>,
    ): R {
        val httpRequest = buildRequest(service, method, request)
        val body = http.newCall(httpRequest).await().use { response ->
            if (response.code != 200) throw MyTsHttpException(response.code, method)
            response.body?.bytes() ?: ByteArray(0)
        }
        try {
            return replyParser.parseFrom(body)
        } catch (e: InvalidProtocolBufferException) {
            throw MyTsProtocolException("Malformed $method reply (${body.size} B)", e)
        }
    }

    internal fun buildRequest(service: Service, method: String, request: MessageLite): Request =
        Request.Builder()
            .url(baseUrl.newBuilder().addPathSegment(service.path).build())
            .header("User-Agent", USER_AGENT)
            .post(frame(method, request).toRequestBody(CONTENT_TYPE.toMediaType()))
            .build()

    companion object {
        const val BASE_URL = "https://clientapi.myteamspeak.com"

        /** Sent verbatim; OkHttp must not append a charset. */
        const val CONTENT_TYPE = "application/ts3cloud"

        /** What the desktop client sends (forum captures, §0). */
        const val USER_AGENT = "cpp-httplib/0.11.1"

        /** The desktop client aborts the call when the name is this long or longer. */
        private const val MAX_METHOD_NAME_BYTES = 128

        /**
         * Frames an RPC request body: `u8 n`, `n` bytes of method name (the
         * simple name, e.g. `login`), then the serialized request with no
         * length prefix.
         */
        fun frame(method: String, request: MessageLite): ByteArray {
            val name = method.toByteArray(Charsets.US_ASCII)
            require(name.isNotEmpty() && name.size < MAX_METHOD_NAME_BYTES) {
                "RPC method name must be 1..${MAX_METHOD_NAME_BYTES - 1} bytes: $method"
            }
            val out = ByteArrayOutputStream(1 + name.size + request.serializedSize)
            out.write(name.size)
            out.write(name)
            request.writeTo(out)
            return out.toByteArray()
        }

        private fun sessionOf(session: String): Session =
            Session.newBuilder().setSession(session).build()

        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            // No silent replays: a failed call surfaces to the user, who
            // retries by hand (rate limits, build plan risk 2).
            .retryOnConnectionFailure(false)
            .apply { MyTsHttpLogging.interceptor()?.let(::addInterceptor) }
            .build()
    }
}

/** The server answered with a non-200 status. */
class MyTsHttpException(val code: Int, method: String) :
    IOException("myTeamSpeak $method failed with HTTP $code")

/** The server answered 200 but the body is not the expected message. */
class MyTsProtocolException(message: String, cause: Throwable) : IOException(message, cause)

private suspend fun Call.await(): Response = suspendCancellableCoroutine { cont ->
    enqueue(object : Callback {
        override fun onResponse(call: Call, response: Response) {
            cont.resume(response) { _, value, _ -> value.close() }
        }
        override fun onFailure(call: Call, e: IOException) {
            if (!cont.isCancelled) cont.resumeWithException(e)
        }
    })
    cont.invokeOnCancellation { runCatching { cancel() } }
}
