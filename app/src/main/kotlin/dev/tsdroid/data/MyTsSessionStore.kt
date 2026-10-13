// security-crypto 1.1.0 deprecates EncryptedSharedPreferences/MasterKey without
// a replacement; they remain the Keystore-backed store the build plan calls for.
@file:Suppress("DEPRECATION")

package dev.tsdroid.data

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * A myTeamSpeak login, as kept between app runs. Fields come from
 * `LoginSession` (docs/myteamspeak-sync-protocol.md §2); the password is
 * never stored.
 */
data class MyTsSession(
    /** `LoginSession.session`: the token every authenticated RPC carries. */
    val session: String,
    val email: String,
    /** `LoginSession.username`. */
    val username: String,
    /** `LoginSession.uuid`: the account id. */
    val uuid: String,
    /** `AlternativeLoginInformation.renewal_token`, for `loginWithRenewalToken` (M4). */
    val renewalToken: String = "",
    /** `AlternativeLoginInformation.otp_renewal_token`: lets a 2FA account skip the OTP next time. */
    val otpRenewalToken: String = "",
    /**
     * `LoginSession.purge`, raw. Assumed to be the session expiry — the unit
     * (seconds or milliseconds since the epoch) is unconfirmed until capture Q6.
     */
    val expiresAt: Long = 0L,
)

/**
 * myTeamSpeak session tokens, encrypted at rest.
 *
 * Unlike [SettingsStore] this does not use DataStore: tokens go into
 * [EncryptedSharedPreferences] under an Android Keystore [MasterKey], and the
 * file is excluded from backups (`res/xml/backup_rules.xml`,
 * `res/xml/data_extraction_rules.xml`) — the Keystore key does not travel with
 * a backup anyway, so a restored file could not be decrypted.
 */
class MyTsSessionStore(context: Context) {

    private val appContext = context.applicationContext
    private val mutex = Mutex()
    private var prefs: SharedPreferences? = null

    private val _session = MutableStateFlow<MyTsSession?>(null)

    /** The stored session, or null when logged out. Valid after [load]. */
    val session: StateFlow<MyTsSession?> = _session.asStateFlow()

    /** Reads the stored session into [session] and returns it. */
    suspend fun load(): MyTsSession? = io {
        read(it).also { s -> _session.value = s }
    }

    /**
     * The server-assigned device id (`AlternativeLoginInformation.device_id`),
     * sent back in `LoginData.device_id`. Kept across logouts: it names this
     * install, not a login, and 2FA accounts need it (`ERROR_2FA_DEVICE_ID_MISSING`).
     */
    suspend fun deviceId(): String = io { it.getString(KEY_DEVICE_ID, null).orEmpty() }

    suspend fun save(session: MyTsSession, deviceId: String?) = io { prefs ->
        prefs.edit().apply {
            putString(KEY_SESSION, session.session)
            putString(KEY_EMAIL, session.email)
            putString(KEY_USERNAME, session.username)
            putString(KEY_UUID, session.uuid)
            putString(KEY_RENEWAL_TOKEN, session.renewalToken)
            putString(KEY_OTP_RENEWAL_TOKEN, session.otpRenewalToken)
            putLong(KEY_EXPIRES_AT, session.expiresAt)
            if (!deviceId.isNullOrEmpty()) putString(KEY_DEVICE_ID, deviceId)
        }.commit()
        _session.value = session
    }

    /** Logout: wipes every token. Only the [deviceId] survives. */
    suspend fun clear() = io { prefs ->
        prefs.edit().apply {
            SESSION_KEYS.forEach(::remove)
        }.commit()
        _session.value = null
    }

    private fun read(prefs: SharedPreferences): MyTsSession? {
        val token = prefs.getString(KEY_SESSION, null)
        if (token.isNullOrEmpty()) return null
        return MyTsSession(
            session = token,
            email = prefs.getString(KEY_EMAIL, null).orEmpty(),
            username = prefs.getString(KEY_USERNAME, null).orEmpty(),
            uuid = prefs.getString(KEY_UUID, null).orEmpty(),
            renewalToken = prefs.getString(KEY_RENEWAL_TOKEN, null).orEmpty(),
            otpRenewalToken = prefs.getString(KEY_OTP_RENEWAL_TOKEN, null).orEmpty(),
            expiresAt = prefs.getLong(KEY_EXPIRES_AT, 0L),
        )
    }

    /** Keystore and file work stays off the main thread, one caller at a time. */
    private suspend fun <T> io(block: (SharedPreferences) -> T): T =
        withContext(Dispatchers.IO) {
            mutex.withLock { block(prefs ?: open().also { prefs = it }) }
        }

    private fun open(): SharedPreferences = try {
        create()
    } catch (e: Exception) {
        // A keyset that no longer matches its Keystore key (e.g. the app data
        // survived a key wipe) cannot be read back. The tokens are only a
        // convenience — start over and let the user log in again.
        Log.w(TAG, "Session store unreadable, resetting it", e)
        appContext.deleteSharedPreferences(FILE_NAME)
        create()
    }

    private fun create(): SharedPreferences {
        val masterKey = MasterKey.Builder(appContext)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        return EncryptedSharedPreferences.create(
            appContext,
            FILE_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    companion object {
        private const val TAG = "MyTsSessionStore"

        /** Must match the backup exclusions in res/xml. */
        const val FILE_NAME = "myts_session"

        private const val KEY_SESSION = "session"
        private const val KEY_EMAIL = "email"
        private const val KEY_USERNAME = "username"
        private const val KEY_UUID = "uuid"
        private const val KEY_RENEWAL_TOKEN = "renewal_token"
        private const val KEY_OTP_RENEWAL_TOKEN = "otp_renewal_token"
        private const val KEY_EXPIRES_AT = "expires_at"
        private const val KEY_DEVICE_ID = "device_id"

        private val SESSION_KEYS = listOf(
            KEY_SESSION, KEY_EMAIL, KEY_USERNAME, KEY_UUID,
            KEY_RENEWAL_TOKEN, KEY_OTP_RENEWAL_TOKEN, KEY_EXPIRES_AT,
        )
    }
}
