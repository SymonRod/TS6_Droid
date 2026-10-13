package dev.tsdroid.viewmodel

import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.ErrorCommon
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.LoginOrigin
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.LoginSession
import dev.tsdroid.bridge.MyTsHttpException
import dev.tsdroid.bridge.MyTsProtocolException
import dev.tsdroid.data.MyTsSession
import dev.tsdroid.viewmodel.MyTsViewModel.Companion.buildLoginData
import dev.tsdroid.viewmodel.MyTsViewModel.Companion.classifyFailure
import dev.tsdroid.viewmodel.MyTsViewModel.Companion.interpretLoginReply
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

class MyTsLoginTest {

    @Test
    fun `login data carries the OTP and device fields`() {
        val data = buildLoginData(
            email = "a@b", password = "pw", otp = "123456",
            deviceId = "dev-1", deviceName = "phone",
        )

        assertEquals("a@b", data.email)
        assertEquals("123456", data.otp)
        assertEquals("dev-1", data.deviceId)
        assertEquals("phone", data.deviceName)
        assertEquals(LoginOrigin.CLIENT, data.origin)
        assertFalse(data.skipSession)
    }

    @Test
    fun `successful reply becomes a session with its renewal tokens`() {
        val reply = LoginSession.newBuilder()
            .setSession("sess")
            .setUsername("user")
            .setUuid("uuid")
            .setPurge(1_700_000_000L)
            .setError(ErrorCommon.ERROR_LOGIN_OK)
            .setAlternativeLoginInfo(
                LoginSession.AlternativeLoginInformation.newBuilder()
                    .setRenewalToken("renew")
                    .setOtpRenewalToken("otp-renew")
                    .setDeviceId("dev"),
            )
            .build()

        val outcome = interpretLoginReply(reply, "a@b")

        assertEquals(
            MyTsLoginOutcome.Success(
                MyTsSession(
                    session = "sess", email = "a@b", username = "user", uuid = "uuid",
                    renewalToken = "renew", otpRenewalToken = "otp-renew",
                    expiresAt = 1_700_000_000L,
                ),
                deviceId = "dev",
            ),
            outcome,
        )
    }

    @Test
    fun `reply errors map to failure kinds`() {
        val cases = mapOf(
            ErrorCommon.ERROR_LOGIN_FAILED to MyTsFailure.Kind.WRONG_CREDENTIALS,
            ErrorCommon.ERROR_LOGIN_EMAIL_PENDING to MyTsFailure.Kind.EMAIL_PENDING,
            ErrorCommon.ERROR_AUTH_REQUIRES_OTP to MyTsFailure.Kind.OTP_REQUIRED,
            ErrorCommon.ERROR_2FA_OTP_INVALID to MyTsFailure.Kind.OTP_INVALID,
            ErrorCommon.ERROR_2FA_OTP_SECRET_MISSING to MyTsFailure.Kind.OTP_UNAVAILABLE,
            ErrorCommon.ERROR_2FA_DEVICE_ID_MISSING to MyTsFailure.Kind.OTP_UNAVAILABLE,
            ErrorCommon.ERROR_LOGIN_OFFLINE to MyTsFailure.Kind.SERVICE_UNAVAILABLE,
            ErrorCommon.ERROR_FE_UNKNOWN_DATA to MyTsFailure.Kind.UNKNOWN,
        )
        for ((error, kind) in cases) {
            val reply = LoginSession.newBuilder().setError(error).build()
            assertEquals(
                error.name,
                MyTsLoginOutcome.Failure(MyTsFailure(kind, error.number)),
                interpretLoginReply(reply, "a@b"),
            )
        }
    }

    @Test
    fun `OK without a session token is not a login`() {
        val reply = LoginSession.newBuilder().setError(ErrorCommon.ERROR_LOGIN_OK).build()

        val outcome = interpretLoginReply(reply, "a@b")

        assertTrue(outcome is MyTsLoginOutcome.Failure)
    }

    @Test
    fun `flaky HTTP statuses are retryable, not fatal`() {
        assertEquals(MyTsFailure(MyTsFailure.Kind.TRANSIENT, 400), classifyFailure(MyTsHttpException(400, "login")))
        assertEquals(MyTsFailure(MyTsFailure.Kind.REJECTED, 401), classifyFailure(MyTsHttpException(401, "login")))
        assertEquals(MyTsFailure(MyTsFailure.Kind.TRANSIENT, 503), classifyFailure(MyTsHttpException(503, "login")))
        assertTrue(classifyFailure(MyTsHttpException(400, "login")).retryable)
        assertTrue(classifyFailure(MyTsHttpException(401, "login")).retryable)
        assertTrue(classifyFailure(IOException("offline")).retryable)
        assertFalse(classifyFailure(MyTsHttpException(404, "login")).retryable)
        assertEquals(
            MyTsFailure.Kind.PROTOCOL,
            classifyFailure(MyTsProtocolException("bad", RuntimeException())).kind,
        )
    }
}
