package dev.tsdroid.viewmodel

import android.app.Application
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.AuthTokenReply
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.AuthTokenRequest
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.ErrorCommon
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.LoginData
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.LoginOrigin
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.LoginSession
import com.teamspeak.myteamspeak.proto.synchronization.SynchronizationCommon.Sync_Version
import dev.tsdroid.bridge.MyTsApi
import dev.tsdroid.bridge.MyTsHttpException
import dev.tsdroid.bridge.MyTsProtocolException
import dev.tsdroid.data.MyTsSession
import dev.tsdroid.data.MyTsSessionStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.IOException

/** Why a myTeamSpeak call failed, as the login screen explains it. */
data class MyTsFailure(val kind: Kind, val code: Int = 0) {

    enum class Kind(val retryable: Boolean) {
        /** `ERROR_LOGIN_FAILED`. */
        WRONG_CREDENTIALS(false),

        /** `ERROR_LOGIN_EMAIL_PENDING`. */
        EMAIL_PENDING(false),

        /** `ERROR_AUTH_REQUIRES_OTP`: not an error so much as the next step. */
        OTP_REQUIRED(false),

        /** `ERROR_2FA_OTP_INVALID`. */
        OTP_INVALID(false),

        /** `ERROR_2FA_OTP_SECRET_MISSING` / `ERROR_2FA_DEVICE_ID_MISSING`. */
        OTP_UNAVAILABLE(false),

        /** `ERROR_LOGIN_OFFLINE` / `ERROR_SESSION_SERVER_OFFLINE`. */
        SERVICE_UNAVAILABLE(true),

        /** HTTP 401. Reported as flaky on the forum, so worth a manual retry. */
        REJECTED(true),

        /** HTTP 400/408/429/5xx. The forum shows spurious 400s: retryable, not fatal. */
        TRANSIENT(true),

        /** No HTTP answer at all. */
        NETWORK(true),

        /** HTTP 200 with a body that is not the expected message. */
        PROTOCOL(false),

        /** Anything else; [code] carries the `ErrorCommon` value or HTTP status. */
        UNKNOWN(false),
    }

    val retryable: Boolean get() = kind.retryable
}

data class MyTsUiState(
    /** True until the stored session has been read. */
    val loading: Boolean = true,
    val session: MyTsSession? = null,
    val busy: Boolean = false,
    /** The account asked for a two-factor code: show the OTP field. */
    val otpRequired: Boolean = false,
    val failure: MyTsFailure? = null,
)

/** The result of one `login` round trip. */
sealed interface MyTsLoginOutcome {
    data class Success(val session: MyTsSession, val deviceId: String) : MyTsLoginOutcome
    data class Failure(val failure: MyTsFailure) : MyTsLoginOutcome
}

/**
 * myTeamSpeak login and session (build plan M1). Login is a single
 * `LoginService.login(LoginData) → LoginSession` call: it is the only login
 * RPC that carries the OTP (docs/myteamspeak-sync-protocol.md §2).
 */
class MyTsViewModel(application: Application) : AndroidViewModel(application) {

    private val store = MyTsSessionStore(application)

    private val _state = MutableStateFlow(MyTsUiState())
    val state: StateFlow<MyTsUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            val session = store.load()
            _state.update { it.copy(loading = false, session = session) }
        }
    }

    fun login(email: String, password: String, otp: String?) {
        if (_state.value.busy) return
        _state.update { it.copy(busy = true, failure = null) }
        viewModelScope.launch {
            pace()
            val trimmedEmail = email.trim()
            // TEMP diagnostic (2026-09-24): find the password encoding the
            // server accepts. Logs only method + encoding label + error code,
            // never the password or any token. Remove once the login works.
            runCatching { diagnose(trimmedEmail, password) }
            val outcome = try {
                val request = buildLoginData(
                    email = trimmedEmail,
                    password = password,
                    otp = otp?.trim().orEmpty(),
                    deviceId = store.deviceId(),
                    deviceName = deviceName(),
                )
                interpretLoginReply(api.login(request), trimmedEmail)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                MyTsLoginOutcome.Failure(classifyFailure(e))
            }
            when (outcome) {
                is MyTsLoginOutcome.Success -> {
                    store.save(outcome.session, outcome.deviceId)
                    _state.update {
                        it.copy(busy = false, session = outcome.session, otpRequired = false)
                    }
                }
                is MyTsLoginOutcome.Failure -> _state.update {
                    val otpStep = outcome.failure.kind in OTP_KINDS
                    it.copy(busy = false, failure = outcome.failure, otpRequired = it.otpRequired || otpStep)
                }
            }
        }
    }

    /** Ends the session on the server when possible; the local tokens go regardless. */
    fun logout() {
        val session = _state.value.session ?: return
        if (_state.value.busy) return
        _state.update { it.copy(busy = true, failure = null) }
        viewModelScope.launch {
            try {
                pace()
                api.deleteSession(session.session)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Offline or already expired: nothing to undo server-side.
            }
            store.clear()
            _state.update { MyTsUiState(loading = false) }
        }
    }

    fun clearFailure() {
        _state.update { it.copy(failure = null) }
    }

    /** Leaving the OTP step (e.g. a different account): hide the code field again. */
    fun resetOtp() {
        _state.update { it.copy(otpRequired = false, failure = null) }
    }

    companion object {
        /** One OkHttp client per process. */
        private val api by lazy { MyTsApi() }

        /** Build plan: at least 4 s between manual replays, no retry storms. */
        private const val MIN_ATTEMPT_SPACING_MS = 4_000L
        private var lastAttemptAt = 0L

        private val OTP_KINDS = setOf(
            MyTsFailure.Kind.OTP_REQUIRED,
            MyTsFailure.Kind.OTP_INVALID,
        )

        private suspend fun pace() {
            val wait = lastAttemptAt + MIN_ATTEMPT_SPACING_MS - SystemClock.elapsedRealtime()
            if (lastAttemptAt != 0L && wait > 0) delay(wait)
            lastAttemptAt = SystemClock.elapsedRealtime()
        }

        private fun deviceName(): String = "TS6 Droid (${Build.MANUFACTURER} ${Build.MODEL})"

        /**
         * `sync_version` for the session. Left at `DEFAULT` (so absent on the
         * wire) until a capture of the desktop client's own `login` shows
         * whether it sends `V1_1`.
         */
        private val LOGIN_SYNC_VERSION = Sync_Version.DEFAULT

        fun buildLoginData(
            email: String,
            password: String,
            otp: String,
            deviceId: String,
            deviceName: String,
            otpRenewalToken: String = "",
        ): LoginData = LoginData.newBuilder()
            .setEmail(email)
            .setPassword(hashPassword(password))
            .setSkipSession(false)
            .setOrigin(LoginOrigin.CLIENT)
            .setSyncVersion(LOGIN_SYNC_VERSION)
            .setOtp(otp)
            .setDeviceId(deviceId)
            .setOtpRenewalToken(otpRenewalToken)
            .setDeviceName(deviceName)
            .build()

        /**
         * The desktop client never sends the plaintext password to
         * `clientapi`: the binary exposes `getAccountHashedPassword` and the
         * sync/crypto layer asserts `plain_hash.size() == sha512_size`, so the
         * login password is a SHA-512 digest. Ghidra (2026-09-24) narrowed it
         * to SHA-512; the exact text encoding (hex case vs base64) is being
         * confirmed empirically against the throwaway account. Lowercase hex
         * is the first candidate.
         */
        /**
         * TEMP diagnostic: try several password encodings against
         * `requestAuthToken` and log the resulting error code for each, so we
         * can tell which transform the server accepts without leaking secrets.
         */
        suspend fun diagnose(email: String, password: String) {
            fun sha512(p: String) =
                java.security.MessageDigest.getInstance("SHA-512").digest(p.toByteArray(Charsets.UTF_8))
            fun sha256(p: String) =
                java.security.MessageDigest.getInstance("SHA-256").digest(p.toByteArray(Charsets.UTF_8))
            fun hex(b: ByteArray, upper: Boolean = false) =
                b.joinToString("") { (if (upper) "%02X" else "%02x").format(it) }
            val b64 = { b: ByteArray -> android.util.Base64.encodeToString(b, android.util.Base64.NO_WRAP) }

            val candidates = linkedMapOf(
                "plain" to password,
                "sha512-hex-lower" to hex(sha512(password)),
                "sha512-hex-upper" to hex(sha512(password), upper = true),
                "sha512-base64" to b64(sha512(password)),
                "sha256-hex-lower" to hex(sha256(password)),
            )
            for ((label, value) in candidates) {
                val reply: AuthTokenReply? = runCatching {
                    api.requestAuthToken(
                        AuthTokenRequest.newBuilder().setEmail(email).setPassword(value).build()
                    )
                }.getOrNull()
                val err = reply?.error?.number
                val tokenLen = reply?.authToken?.length ?: -1
                Log.d("MyTsDiag", "requestAuthToken[$label] error=$err tokenLen=$tokenLen")
                delay(1500)
            }
        }

        fun hashPassword(password: String): String {
            val digest = java.security.MessageDigest.getInstance("SHA-512")
                .digest(password.toByteArray(Charsets.UTF_8))
            return digest.joinToString("") { "%02x".format(it) }
        }

        fun interpretLoginReply(reply: LoginSession, email: String): MyTsLoginOutcome {
            val error = reply.error
            val ok = error == ErrorCommon.ERROR_LOGIN_OK || error == ErrorCommon.UNKNOWN_ERRORCOMMON
            if (ok && reply.session.isNotEmpty()) {
                val alt = reply.alternativeLoginInfo
                return MyTsLoginOutcome.Success(
                    session = MyTsSession(
                        session = reply.session,
                        email = email,
                        username = reply.username,
                        uuid = reply.uuid,
                        renewalToken = alt.renewalToken,
                        otpRenewalToken = alt.otpRenewalToken,
                        expiresAt = reply.purge,
                    ),
                    deviceId = alt.deviceId,
                )
            }
            val kind = when (error) {
                ErrorCommon.ERROR_LOGIN_FAILED -> MyTsFailure.Kind.WRONG_CREDENTIALS
                ErrorCommon.ERROR_LOGIN_EMAIL_PENDING -> MyTsFailure.Kind.EMAIL_PENDING
                ErrorCommon.ERROR_AUTH_REQUIRES_OTP -> MyTsFailure.Kind.OTP_REQUIRED
                ErrorCommon.ERROR_2FA_OTP_INVALID -> MyTsFailure.Kind.OTP_INVALID
                ErrorCommon.ERROR_2FA_OTP_SECRET_MISSING,
                ErrorCommon.ERROR_2FA_DEVICE_ID_MISSING -> MyTsFailure.Kind.OTP_UNAVAILABLE
                ErrorCommon.ERROR_LOGIN_OFFLINE,
                ErrorCommon.ERROR_SESSION_SERVER_OFFLINE -> MyTsFailure.Kind.SERVICE_UNAVAILABLE
                else -> MyTsFailure.Kind.UNKNOWN
            }
            return MyTsLoginOutcome.Failure(MyTsFailure(kind, reply.errorValue))
        }

        fun classifyFailure(e: Throwable): MyTsFailure = when (e) {
            is MyTsHttpException -> when (e.code) {
                401 -> MyTsFailure(MyTsFailure.Kind.REJECTED, e.code)
                400, 408, 429, in 500..599 -> MyTsFailure(MyTsFailure.Kind.TRANSIENT, e.code)
                else -> MyTsFailure(MyTsFailure.Kind.UNKNOWN, e.code)
            }
            is MyTsProtocolException -> MyTsFailure(MyTsFailure.Kind.PROTOCOL)
            is IOException -> MyTsFailure(MyTsFailure.Kind.NETWORK)
            else -> MyTsFailure(MyTsFailure.Kind.UNKNOWN)
        }
    }
}
