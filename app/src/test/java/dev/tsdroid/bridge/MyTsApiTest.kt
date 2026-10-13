package dev.tsdroid.bridge

import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.ErrorCommon
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.LoginData
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.LoginSession
import com.teamspeak.myteamspeak.proto.MyteamspeakCommon.Session
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class MyTsApiTest {

    // --- Framing goldens (docs/myteamspeak-sync-protocol.md §0) ---

    @Test
    fun `frame is u8 length, method name, bare protobuf`() {
        val body = MyTsApi.frame("session", Session.newBuilder().setSession("abc").build())

        // 07 "session" | field 1, LEN, 3 bytes "abc"
        assertArrayEquals(hex("07 73657373696f6e 0a03 616263"), body)
    }

    @Test
    fun `login frame matches hand-encoded LoginData`() {
        val request = LoginData.newBuilder()
            .setEmail("a@b")
            .setPassword("pw")
            .setDeviceName("d")
            .build()

        val body = MyTsApi.frame("login", request)

        // 05 "login" | email=1 "a@b" | password=2 "pw" | device_name=9 "d".
        // proto3 defaults (skipSession, origin CLIENT, sync_version DEFAULT,
        // empty strings) are not on the wire.
        assertArrayEquals(hex("05 6c6f67696e 0a03 614062 1202 7077 4a01 64"), body)
    }

    @Test
    fun `frame rejects method names the desktop client would abort on`() {
        val msg = Session.getDefaultInstance()
        assertThrows(IllegalArgumentException::class.java) { MyTsApi.frame("", msg) }
        assertThrows(IllegalArgumentException::class.java) { MyTsApi.frame("x".repeat(128), msg) }
        assertEquals(128, MyTsApi.frame("x".repeat(127), msg).size)
    }

    // --- Round trip through OkHttp, answered in memory (no network) ---

    @Test
    fun `login posts the framed body to authentication and parses a bare reply`() = runBlocking {
        val reply = LoginSession.newBuilder()
            .setSession("sess-1")
            .setUsername("user")
            .setError(ErrorCommon.ERROR_LOGIN_OK)
            .build()
        var seen: Request? = null
        val api = apiAnswering { req -> seen = req; respond(req, 200, reply.toByteArray()) }
        val request = LoginData.newBuilder().setEmail("a@b").setPassword("pw").build()

        val result = api.login(request)

        assertEquals(reply, result)
        val req = seen!!
        assertEquals("POST", req.method)
        assertEquals("https://clientapi.myteamspeak.com/authentication", req.url.toString())
        assertEquals("application/ts3cloud", req.body!!.contentType().toString())
        assertEquals(MyTsApi.USER_AGENT, req.header("User-Agent"))
        val sent = Buffer().also { req.body!!.writeTo(it) }.readByteArray()
        assertArrayEquals(MyTsApi.frame("login", request), sent)
    }

    @Test
    fun `non-200 fails with the status code`() {
        val api = apiAnswering { respond(it, 400, ByteArray(0)) }

        val e = assertThrows(MyTsHttpException::class.java) {
            runBlocking { api.session("s") }
        }
        assertEquals(400, e.code)
    }

    @Test
    fun `a 200 that is not protobuf is a protocol error`() {
        val api = apiAnswering { respond(it, 200, byteArrayOf(0x0a, 0x7f)) }

        assertThrows(MyTsProtocolException::class.java) {
            runBlocking { api.login(LoginData.getDefaultInstance()) }
        }
    }

    private fun apiAnswering(answer: (Request) -> Response): MyTsApi {
        val client = OkHttpClient.Builder()
            .addInterceptor(Interceptor { chain -> answer(chain.request()) })
            .build()
        return MyTsApi(client)
    }

    private fun respond(request: Request, code: Int, body: ByteArray): Response =
        Response.Builder()
            .request(request)
            .protocol(Protocol.HTTP_1_1)
            .code(code)
            .message("test")
            .body(body.toResponseBody("application/ts3cloud".toMediaType()))
            .build()

    private fun hex(s: String): ByteArray =
        s.replace(" ", "").chunked(2).map { it.toInt(16).toByte() }.toByteArray()
}
